import { Injectable, Logger } from '@nestjs/common';
import { Conflict } from './entities/conflict.entity';
import { HttpService } from '@nestjs/axios';
import { ConfigService } from '@nestjs/config';
import { firstValueFrom } from 'rxjs';
import { PrismaService } from '../prisma/prisma.service';

interface UserConflictRecord {
  piilName: string;
  ingredients: string[];
  dailyDosage: number;
}

interface FilterResult {
  status: 'SAFE' | 'CAUTION' | 'DANGER';
  reasons: string[];
}

@Injectable()
export class ConflictService {
  private readonly logger = new Logger(ConflictService.name);
  private durApiKey: string;
  private readonly baseUrl = 'https://api.odcloud.kr/api/15089525/v1/uddi:3f2efdac-942b-494e-919f-8bdc583f65ea';

  // 두 성분간 병용금기 캐싱 (중복 API 요청 방지 - 성분 간 금기 사유 저장)
  private pairCache = new Map<string, string | null>();

  constructor(
    private readonly httpService: HttpService,
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    this.durApiKey = this.configService.get<string>('DUR_API_KEY') || '';
  }

  // 1) 한국어 질환명을 recommend.service와 대치되는 ID로 변환하는 맵핑
  private readonly diseaseToIdMap: Record<string, string> = {
    '고혈압': '1', '당뇨': '2', '고지혈증': '3', '심장질환': '4', '심장 질환': '4',
    '신장질환': '5', '신장 질환': '5', '간질환': '6', '간 질환': '6',
    '갑상선 질환': '7', '갑상선질환': '7', '골다공증': '8', '관절염': '9', '빈혈': '10'
  };

  // 2) recommend.service 와 100% 동기화된 질환별 주의 성분 목록
  private readonly contraindicationMap: Record<string, string[]> = {
    '1': ['나트륨', '감초'],
    '2': ['당류'],
    '3': ['콜레스테롤', '포화지방산'],
    '4': ['나트륨'],
    '5': ['칼륨', '인'],
    '6': ['비타민 A', '철'],
    '7': ['요오드'],
    '8': ['인'],
    '9': ['당류', '포화지방산'],
    '10': ['아연'],
  };

  // 3) 각 질환별 성분 충돌 시 화면에 출력될 상세한 원인 및 설명
  private readonly diseaseReasonMap: Record<string, Record<string, string>> = {
    '1': { '나트륨': '혈압 상승 가능', '감초': '혈압 상승 가능' },
    '2': { '당류': '혈당 수치 급상승 위험' },
    '3': { '콜레스테롤': '지질 수치 악화 위험', '포화지방산': '콜레스테롤 상승 위험' },
    '4': { '나트륨': '심장 부담 증가' },
    '5': { '칼륨': '고칼륨혈증 위험', '인': '신장 배설 기능 저하 시 부작용' },
    '6': { '비타민 A': '간 독성 위험', '철': '간 철 축적 위험' },
    '7': { '요오드': '갑상선 기능 악화 가능' },
    '8': { '인': '칼슘 흡수 저해' },
    '9': { '당류': '염증 악화 위험', '포화지방산': '염증 수치 상승 위험' },
    '10': { '아연': '철분 흡수 저해' },
  };

  // 4) 모바일 설문 알레르기 명칭 -> 실제 DB(allergies_list)의 label_ko 맵핑
  private readonly surveyAllergyToDbMap: Record<string, string> = {
    '갑각류': '갑각류',
    '대두': '대두',
    '우유': '유제품',
    '견과류': '견과류',
    '밀': '글루텐',
    '메밀': '글루텐',
    '달걀': '달걀',
    '고등어': '생선',
  };

  // 5) 실제 DB 알레르기 기준(총 7가지) 유발 유의 성분 키워드 목록
  private readonly allergyMap: Record<string, string[]> = {
    '견과류': ['아몬드', '호두', '캐슈', '견과', 'nuts', 'almond', 'walnut'],
    '갑각류': ['크릴', '크릴오일', 'krill', '새우', '게', 'shellfish', 'shrimp', 'crab'],
    '생선': ['고등어', '어유', 'fish oil', '오메가3', '오메가-3', 'fish'],
    '유제품': ['우유', '유청', 'whey', '카세인', '유단백', 'dairy', 'milk'],
    '달걀': ['달걀', '계란', 'egg'],
    '글루텐': ['밀', '글루텐', '메밀', 'gluten', 'wheat', 'buckwheat'],
    '대두': ['대두', '콩', 'soy', '이소플라본'],
  };

  // 6) 한글 -> 영문 (DUR API 성분명) 표준 매핑 사전
  private readonly ingredientTranslationMap: Record<string, string> = {
    // 주요 미네랄 및 영양소 (한글 DB명 -> 영문 DUR 표준명)
    '비타민 k': 'phytomenadione',  // DUR API의 비타민 K 공식 성분명 (피토나디온)
    '비타민 k1': 'phytomenadione',
    '비타민k': 'phytomenadione',
    '비타민k1': 'phytomenadione',
    '칼슘': 'calcium',
    '철': 'iron',
    '철분': 'iron',
    '아연': 'zinc',
    '마그네슘': 'magnesium',
    '칼륨': 'potassium',
    '나트륨': 'sodium',
    
    // 주요 다빈도 한글 약물명 -> 영문 DUR 표준명
    '아스피린': 'aspirin',
    '와파린': 'warfarin',
    '세레콕시브': 'celecoxib',
    '이부프로펜': 'ibuprofen',
    '나프록센': 'naproxen',
    '아세트아미노펜': 'acetaminophen',
    '케토롤락': 'ketorolac',
    '케토롤락트로메타민': 'ketorolac tromethamine',
  };

  private normalizeIngredientName(ing: string): string {
    if (!ing) return '';
    
    // 1. 소문자화 및 양끝 공백 정제
    let normalized = ing.trim().toLowerCase();
    
    // 2. 한글 -> 영문 사전에 등록되어 있다면 영문 표준명으로 매핑 치환
    if (this.ingredientTranslationMap[normalized]) {
      return this.ingredientTranslationMap[normalized];
    }
    
    // 3. 띄어쓰기 무관한 세밀 대조 (예: '비타민 k' -> '비타민k' 매칭)
    const noSpace = normalized.replace(/\s+/g, '');
    for (const [key, value] of Object.entries(this.ingredientTranslationMap)) {
      const keyNoSpace = key.replace(/\s+/g, '');
      if (noSpace === keyNoSpace) {
        return value;
      }
    }
    
    // 4. 사전 매핑이 없을 경우 소문자로 통일된 원래 성분명 반환 (영문 성분은 그대로 소문자로 유지)
    return normalized;
  }

  async checkConflictsByIds(
    supplementIds: number[],
    cabinetSupplements: { name: string; ingredients: string[] }[] = [],
    userHealth: string[] = [],
    userAllergies: string[] = [],
  ) {
    const conflicts: Conflict[] = [];

    // 1. DB에서 장바구니 영양제 조회 및 Conflict 객체 변환
    if (supplementIds && supplementIds.length > 0) {
      const supplementBigIntIds = supplementIds
        // 숫자가 아닌 ID는 BigInt 변환 오류(500)가 나므로 제외
        .filter((id) => /^\d+$/.test(String(id)))
        .map((id) => BigInt(id))
        .filter((id) => id <= BigInt(2147483647));

      const selectedSupplementsTemp = await this.prisma.supplementsTemp.findMany({
        where: {
          id: {
            in: supplementBigIntIds,
          },
        },
      });

      const productNames = selectedSupplementsTemp.map((s) => s.product_name).filter(Boolean) as string[];
      const ingredients = await this.prisma.supplementsIngredients.findMany({
        where: { product_name: { in: productNames } },
      });

      const selectedSupplements = selectedSupplementsTemp.map((product) => ({
        ...product,
        ingredients: ingredients.filter((ing) => ing.product_name === product.product_name),
      }));

      const dbConflicts: Conflict[] = selectedSupplements.map((s) => ({
        name: s.product_name || '',
        ingredients: s.ingredients
          .map((si) => si.ingredient_name?.trim())
          .filter(Boolean) as string[],
      }));

      conflicts.push(...dbConflicts);
    }

    // 2. 프론트엔드에서 전달받은 캐비넷 영양제 추가
    if (cabinetSupplements && cabinetSupplements.length > 0) {
      conflicts.push(...cabinetSupplements);
    }

    if (conflicts.length === 0) {
      return [];
    }

    // 3. 약물-약물 간 DUR 병용금기 분석 실행
    const durResults = await this.checkConflicts(conflicts);
    const finalResults: any[] = [];
    if (Array.isArray(durResults)) {
      finalResults.push(...durResults);
    }

    // 4. 약물-만성질환 / 약물-알레르기 실시간 매핑 검사 수행
    for (const s of conflicts) {
      const sIngredients = s.ingredients || [];

      // A) 만성질환 검사
      for (const disease of userHealth) {
        const id = this.diseaseToIdMap[disease];
        if (!id) continue;

        const avoidIngs = this.contraindicationMap[id] || [];
        for (const avoidIng of avoidIngs) {
          const matched = sIngredients.find((ing) =>
            ing.toLowerCase().includes(avoidIng.toLowerCase())
          );
          if (matched) {
            const reasonDetail = this.diseaseReasonMap[id]?.[avoidIng] || '섭취 유의 성분 포함';
            finalResults.push({
              conflicts: [s.name, `[${disease} 보유]`],
              reason: `주의 성분 : ${avoidIng}\n질환 병용금기 사유: ${reasonDetail}`,
              conflictingIngredients: [avoidIng],
            });
          }
        }
      }

      // B) 알레르기 검사 (실제 DB allergies_list 에 정의된 7가지 기준만 적용)
      for (const surveyAllergy of userAllergies) {
        const dbAllergyLabel = this.surveyAllergyToDbMap[surveyAllergy];
        if (!dbAllergyLabel) continue; // DB 테이블 범위를 벗어나는 알레르기는 스킵

        const avoidKeywords = this.allergyMap[dbAllergyLabel] || [];
        for (const keyword of avoidKeywords) {
          const matched = sIngredients.find((ing) =>
            ing.toLowerCase().includes(keyword.toLowerCase())
          );
          if (matched) {
            finalResults.push({
              conflicts: [s.name, `[${dbAllergyLabel} 알레르기]`],
              reason: `알레르기 성분 : ${keyword}\n알레르기 유발 사유: ${dbAllergyLabel} 알레르기 유발 성분 포함 가능 — 섭취 전 전문의 상담 권장`,
              conflictingIngredients: [keyword],
            });
          }
        }
      }
    }

    return finalResults.length > 0 ? finalResults : { message: '충돌하는 영양제가 없음.' };
  }

  async checkConflicts(conflicts: Conflict[]) {
    const results: {
      conflicts: string[];
      reason: string;
      conflictingIngredients: string[]
    }[] = [];

    // 영양제간 병용금기 대조
    for (let i = 0; i < conflicts.length; i++) {
      for (let j = i + 1; j < conflicts.length; j++) {
        const conflictA = conflicts[i];
        const conflictB = conflicts[j];
        const exactConflicts = new Set<string>();
        const details: string[] = [];

        // 두 약의 성분 쌍을 하나씩 대조
        for (const ingA of conflictA.ingredients) {
          for (const ingB of conflictB.ingredients) {
            const reason = await this.checkPairConflict(ingA, ingB);
            if (reason) {
              exactConflicts.add(ingA);
              exactConflicts.add(ingB);
              details.push(`성분 충돌 : ${ingA} - ${ingB}\n병용금기 사유: ${reason}`);
            }
          }
        }

        if (exactConflicts.size > 0) {
          results.push({
            conflicts: [conflictA.name, conflictB.name],
            reason: details.join('\n\n'),
            conflictingIngredients: Array.from(exactConflicts)
          });
        }
      }
    }

    return results.length > 0 ? results : { message: '충돌하는 영양제가 없음.' };
  }

  private async checkPairConflict(ingA: string, ingB: string): Promise<string | null> {
    const normalizedA = this.normalizeIngredientName(ingA);
    const normalizedB = this.normalizeIngredientName(ingB);

    const cacheKey1 = `${normalizedA}-${normalizedB}`;
    const cacheKey2 = `${normalizedB}-${normalizedA}`;

    // 이미 조회된 성분 조합은 캐시에서 바로 반환
    if (this.pairCache.has(cacheKey1)) return this.pairCache.get(cacheKey1)!;
    if (this.pairCache.has(cacheKey2)) return this.pairCache.get(cacheKey2)!;

    try {
      const url1 = `${this.baseUrl}?page=1&perPage=1&serviceKey=${this.durApiKey}&cond[성분명1::EQ]=${encodeURIComponent(normalizedA)}&cond[성분명2::EQ]=${encodeURIComponent(normalizedB)}`;
      const url2 = `${this.baseUrl}?page=1&perPage=1&serviceKey=${this.durApiKey}&cond[성분명1::EQ]=${encodeURIComponent(normalizedB)}&cond[성분명2::EQ]=${encodeURIComponent(normalizedA)}`;

      const [res1, res2] = await Promise.all([
        firstValueFrom(this.httpService.get(url1)),
        firstValueFrom(this.httpService.get(url2))
      ]);

      let reason: string | null = null;
      if (res1.data?.matchCount > 0 && res1.data?.data?.[0]?.금기사유) {
        reason = res1.data.data[0].금기사유;
      } else if (res2.data?.matchCount > 0 && res2.data?.data?.[0]?.금기사유) {
        reason = res2.data.data[0].금기사유;
      } else if (res1.data?.matchCount > 0 || res2.data?.matchCount > 0) {
        reason = '병용금기 성분';
      }

      this.pairCache.set(cacheKey1, reason);
      return reason;
    } catch (error) {
      this.logger.error(`Failed to check pair conflict for: ${ingA} (normalized: ${normalizedA}) and ${ingB} (normalized: ${normalizedB})`, error);
      return null; // 방어
    }
  }

}
