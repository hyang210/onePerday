import { Controller, Get, Post, Body, Query } from '@nestjs/common';
import { AppService } from './app.service';
import { PrismaService } from './prisma/prisma.service';
import { SupplementSearchService } from './supplement-search.service';
import type { LlmExtracted } from './supplement-search.service';
import { Public } from './auth/public.decorator';

@Controller()
export class AppController {
  constructor(
    private readonly appService: AppService,
    private readonly prisma: PrismaService,
    private readonly searchService: SupplementSearchService,
  ) { }

  @Public()
  @Get()
  getHello(): string {
    return this.appService.getHello();
  }

  @Public()
  @Get('supplements')
  async getSupplements(
    @Query('keyword') keyword?: string,
    @Query('record') record?: string,
    @Query('gender') gender?: string,
    @Query('age') age?: string,
    @Query('categories') categoriesStr?: string,
    @Query('ingredients') ingredientsStr?: string,
    @Query('priceRange') priceRange?: string,
  ) {
    if (keyword && keyword.trim().length > 0 && record === 'true') {
      this.appService.recordSearch(keyword);
    }

    const userAge = age ? parseInt(age, 10) : 30;
    let userGender = gender ? gender : '남자';
    if (userGender === '남성' || userGender === 'male') userGender = '남자';
    else if (userGender === '여성' || userGender === 'female') userGender = '여자';

    const categories = categoriesStr ? categoriesStr.split(',').filter(c => c.trim().length > 0) : [];
    const ingredients = ingredientsStr ? ingredientsStr.split(',').filter(i => i.trim().length > 0) : [];

    let minPrice: number | undefined = undefined;
    let maxPrice: number | undefined = undefined;
    if (priceRange) {
      if (priceRange === '1만원 이하') maxPrice = 10000;
      else if (priceRange === '1~3만원') { minPrice = 10000; maxPrice = 30000; }
      else if (priceRange === '3~5만원') { minPrice = 30000; maxPrice = 50000; }
      else if (priceRange === '5만원 이상') minPrice = 50000;
    }

    let mappedNutrients: string[] = [];
    if (categories.length > 0) {
      const guides = await this.prisma.nutrientGuide.findMany();
      for (const guide of guides) {
        const nutrientName = guide.nutrient_name;
        const targetAreas = Array.isArray(guide.target_area) ? guide.target_area : [];
        if (!nutrientName) continue;

        let matchesArea = false;
        for (const cat of categories) {
          const c = cat.replace(/\s/g, '');
          for (const area of targetAreas) {
            const t = String(area).replace(/\s/g, '');
            const keywords = ['눈', '관절', '뼈', '간', '피부', '면역', '혈관', '심혈관', '심장', '뇌', '소화', '장', '근육', '신경', '세포'];
            for (const k of keywords) {
              if (c.includes(k) && t.includes(k)) { matchesArea = true; break; }
            }
            if (c.includes(t) || t.includes(c)) matchesArea = true;
            if (matchesArea) break;
          }
          if (matchesArea) break;
        }
        if (matchesArea) mappedNutrients.push(nutrientName);
      }
    }

    const whereClause: any = { price: { not: null } };

    if (minPrice !== undefined || maxPrice !== undefined) {
      whereClause.price = { ...whereClause.price };
      if (minPrice !== undefined) whereClause.price.gt = minPrice;
      if (maxPrice !== undefined) whereClause.price.lte = maxPrice;
    }

    // ── 핵심 수정: supplementsTemp에 ingredients relation 없음
    // → supplementsIngredients 먼저 조회 후 product_name으로 필터링
    const andConditions: any[] = [];

    if (categories.length > 0) {
      const catNutrients = mappedNutrients.length > 0 ? mappedNutrients : categories;
      const catFilter = catNutrients.map(nut => ({
        ingredient_name: { contains: nut, mode: 'insensitive' as const },
      }));
      const catProductContains = catNutrients.map(nut => ({
        product_name: { contains: nut, mode: 'insensitive' },
      }));

      // supplementsIngredients에서 matching product_name 먼저 조회
      const catMatchedIngs = await this.prisma.supplementsIngredients.findMany({
        where: { OR: catFilter },
        select: { product_name: true },
      });
      const catProductNames = [...new Set(
        catMatchedIngs.map(i => i.product_name).filter(Boolean) as string[]
      )];

      andConditions.push({
        OR: [
          ...(catProductNames.length > 0 ? [{ product_name: { in: catProductNames } }] : []),
          ...catProductContains,
        ],
      });
    }

    if (ingredients.length > 0) {
      const ingFilter = ingredients.map(nut => ({
        ingredient_name: { contains: nut, mode: 'insensitive' as const },
      }));
      const ingProductContains = ingredients.map(nut => ({
        product_name: { contains: nut, mode: 'insensitive' },
      }));

      // supplementsIngredients에서 matching product_name 먼저 조회
      const ingMatchedIngs = await this.prisma.supplementsIngredients.findMany({
        where: { OR: ingFilter },
        select: { product_name: true },
      });
      const ingProductNames = [...new Set(
        ingMatchedIngs.map(i => i.product_name).filter(Boolean) as string[]
      )];

      andConditions.push({
        OR: [
          ...(ingProductNames.length > 0 ? [{ product_name: { in: ingProductNames } }] : []),
          ...ingProductContains,
        ],
      });
    }

    if (keyword && keyword.trim().length > 0) {
      andConditions.push({
        OR: [
          { product_name: { contains: keyword.trim(), mode: 'insensitive' } },
          { brand_name: { contains: keyword.trim(), mode: 'insensitive' } },
        ],
      });
    }

    if (andConditions.length > 0) {
      whereClause.AND = andConditions;
    }

    const dataTemp = await this.prisma.supplementsTemp.findMany({
      take: 20,
      where: whereClause,
    });

    const productNames = dataTemp.map(p => p.product_name).filter(Boolean) as string[];
    const dbIngredients = await this.prisma.supplementsIngredients.findMany({
      where: { product_name: { in: productNames } },
    });

    const data = dataTemp.map(product => ({
      ...product,
      ingredients: dbIngredients.filter(ing => ing.product_name === product.product_name),
    }));

    const standards = await this.prisma.nutrientStandards.findMany({
      where: {
        gender: userGender,
        age_min: { lte: userAge },
        age_max: { gte: userAge },
      },
    });

    const enrichedData = data.map(product => {
      const mappedIngredients = product.ingredients.map(ing => {
        const std = standards.find(s => s.nutrient_name === ing.ingredient_name);
        const dri = std?.recommended_intake || std?.adequate_intake || std?.avg_requirement || null;
        const amount = ing.amount || 0;

        let dailyPercent = 0;
        if (dri && dri > 0) {
          dailyPercent = Number((amount / dri).toFixed(4));
        }

        return { ...ing, dailyPercent };
      });

      return { ...product, ingredients: mappedIngredients };
    });

    return JSON.parse(
      JSON.stringify(enrichedData, (key, value) =>
        typeof value === 'bigint' ? value.toString() : value,
      ),
    );
  }

  @Public()
  @Get('supplements/popular')
  getPopularSupplements() {
    return this.appService.getPopularSearches();
  }

  @Public()
  @Post('supplements/search')
  async searchSupplement(@Body() body: LlmExtracted) {
    const result = await this.searchService.search(body);
    return JSON.parse(
      JSON.stringify(result, (key, value) =>
        typeof value === 'bigint' ? value.toString() : value,
      ),
    );
  }
}
