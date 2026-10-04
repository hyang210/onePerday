import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { SupabaseService } from '../supabase/supabase.service';
import { AdminGuard } from '../auth/admin.guard';

/** 관리자 웹 전용 API. ADMIN_EMAILS에 등록된 계정만 호출할 수 있습니다. */
@UseGuards(AdminGuard)
@Controller('admin')
export class AdminController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly supabaseService: SupabaseService,
  ) {}

  @Get('users')
  async getUsers(@Query('search') search?: string) {
    const usersInfo = await this.prisma.usersInfo.findMany({
      where: search
        ? {
            OR: [
              { name: { contains: search, mode: 'insensitive' } },
              { users: { email: { contains: search, mode: 'insensitive' } } },
            ],
          }
        : undefined,
      select: {
        id: true,
        name: true,
        gender: true,
        birth_year: true,
        created_at: true,
        users: { select: { email: true, created_at: true } },
      },
    });
    return usersInfo;
  }

  @Delete('users/:id')
  async deleteUser(@Param('id') id: string) {
    await this.prisma.usersInfo.delete({ where: { id } });
    const { error } = await this.supabaseService
      .getClient()
      .auth.admin.deleteUser(id);
    if (error) throw new Error(error.message);
    return { success: true };
  }

  // 영양제 추가
  @Post('supplements')
  async addSupplement(@Body() body: any) {
    return JSON.parse(
      JSON.stringify(
        await this.prisma.supplementsTemp.create({
          data: {
            product_name: body.product_name,
            category: body.category,
            brand_name: body.brand_name,
            reference_amount: body.reference_amount,
            serving_size: body.serving_size
              ? parseFloat(body.serving_size)
              : null,
            serving_unit: body.serving_unit,
            serving_weight: body.serving_weight,
            daily_servings: body.daily_servings,
            total_weight: body.total_weight,
            manufacturer: body.manufacturer,
            origin: body.origin,
            image_url: body.image_url,
            shop_url: body.shop_url,
            price: body.price ? BigInt(body.price) : null,
          },
        }),
        (key, value) => (typeof value === 'bigint' ? value.toString() : value),
      ),
    );
  }

  @Delete('supplements/:id')
  async deleteSupplement(@Param('id') id: string) {
    return this.prisma.supplementsTemp.delete({ where: { id: BigInt(id) } });
  }

  @Get('supplements')
  async getAdminSupplements(
    @Query('page') page?: string,
    @Query('keyword') keyword?: string,
  ) {
    const pageNum = page ? parseInt(page, 10) : 1;
    const take = 50;
    const skip = (pageNum - 1) * take;

    const whereClause: any = {};
    if (keyword && keyword.trim().length > 0) {
      whereClause.OR = [
        { product_name: { contains: keyword.trim(), mode: 'insensitive' } },
        { brand_name: { contains: keyword.trim(), mode: 'insensitive' } },
      ];
    }

    const [data, total] = await Promise.all([
      this.prisma.supplementsTemp.findMany({
        take,
        skip,
        where: whereClause,
        orderBy: { id: 'asc' },
      }),
      this.prisma.supplementsTemp.count({ where: whereClause }),
    ]);

    return JSON.parse(
      JSON.stringify(
        {
          data,
          total,
          page: pageNum,
          totalPages: Math.ceil(total / take),
        },
        (key, value) => (typeof value === 'bigint' ? value.toString() : value),
      ),
    );
  }

  // 대시보드
  @Get('dashboard')
  async getDashboard() {
    const [totalUsers, totalSupplements, todayUsers] = await Promise.all([
      this.prisma.usersInfo.count(),
      this.prisma.supplements.count(),
      this.prisma.usersInfo.count({
        where: {
          created_at: {
            gte: new Date(new Date().setHours(0, 0, 0, 0)),
          },
        },
      }),
    ]);

    return { totalUsers, totalSupplements, todayUsers };
  }

  @Patch('users/:id')
  async updateUser(@Param('id') id: string, @Body() body: any) {
    return this.prisma.usersInfo.update({
      where: { id },
      data: {
        name: body.name,
        gender: body.gender,
        birth_year: body.birth_year ? parseInt(body.birth_year) : null,
      },
    });
  }

  @Patch('supplements/:id')
  async updateSupplement(@Param('id') id: string, @Body() body: any) {
    return JSON.parse(
      JSON.stringify(
        await this.prisma.supplementsTemp.update({
          where: { id: BigInt(id) },
          data: {
            product_name: body.product_name,
            category: body.category,
            brand_name: body.brand_name,
            reference_amount: body.reference_amount,
            serving_size: body.serving_size
              ? parseFloat(body.serving_size)
              : null,
            serving_unit: body.serving_unit,
            serving_weight: body.serving_weight,
            daily_servings: body.daily_servings,
            total_weight: body.total_weight,
            manufacturer: body.manufacturer,
            origin: body.origin,
            image_url: body.image_url,
            shop_url: body.shop_url,
            price: body.price ? BigInt(body.price) : null,
          },
        }),
        (key, value) => (typeof value === 'bigint' ? value.toString() : value),
      ),
    );
  }
}
