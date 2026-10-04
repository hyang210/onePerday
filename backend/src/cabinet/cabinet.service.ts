import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCabinetDto } from './dto/create-cabinet.dto';

@Injectable()
export class CabinetService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateCabinetDto) {
    if (dto.alarmTimes.length !== dto.dailyFrequency) {
      throw new BadRequestException(
        'alarmTimes length must match dailyFrequency',
      );
    }

    let supplement: any = null;
    try {
      const tempSupplement = await this.prisma.supplementsTemp.findUnique({
        where: {
          id: BigInt(dto.supplementId),
        },
      });

      if (tempSupplement && tempSupplement.product_name) {
        supplement = await this.prisma.supplements.findUnique({
          where: {
            product_name: tempSupplement.product_name,
          },
        });
      }
    } catch (_) {}

    if (!supplement) {
      try {
        supplement = await this.prisma.supplements.findUnique({
          where: {
            id: BigInt(dto.supplementId),
          },
        });
      } catch (_) {}
    }

    if (!supplement) {
      throw new NotFoundException('Supplement not found');
    }

    const created = await this.prisma.supplementInventory.create({
      data: {
        user_uuid: dto.userUuid,
        supplement_id: supplement.id,
        daily_dose: dto.dailyDose,
        daily_frequency: dto.dailyFrequency,
        stock_count: dto.stockCount ?? 0,
        total_count: dto.totalCount ?? dto.stockCount ?? 0,
        alarm_times: dto.alarmTimes,
        status: 'active',
      },
      include: {
        supplements: {
          include: {
            ingredients: true,
          },
        },
      },
    });

    const userInfo = await this.prisma.usersInfo.findUnique({
      where: { id: dto.userUuid },
    });

    const userAge = userInfo?.birth_year
      ? new Date().getFullYear() - userInfo.birth_year
      : 30;
    let userGender = userInfo?.gender || '남자';
    if (userGender === '남성' || userGender === 'female' || userGender === 'male') {
      if (userGender === '남성' || userGender === 'male') userGender = '남자';
      else userGender = '여자';
    }

    const standards = await this.prisma.nutrientStandards.findMany({
      where: {
        gender: userGender,
        age_min: { lte: userAge },
        age_max: { gte: userAge },
      },
    });

    if (created.supplements && created.supplements.ingredients) {
      const enrichedIngredients = created.supplements.ingredients.map((ing) => {
        const std = standards.find((s) => s.nutrient_name === ing.ingredient_name);
        const dri = std?.recommended_intake || std?.adequate_intake || std?.avg_requirement || null;
        const amount = ing.amount || 0;

        let dailyPercent = 0;
        if (dri && dri > 0) {
          dailyPercent = Number((amount / dri).toFixed(4));
        }

        return {
          ...ing,
          dailyPercent,
        };
      });

      return {
        ...created,
        supplements: {
          ...created.supplements,
          ingredients: enrichedIngredients,
        },
      };
    }

    return created;
  }

  async findByUser(userUuid: string) {
    const userInfo = await this.prisma.usersInfo.findUnique({
      where: { id: userUuid },
    });

    const userAge = userInfo?.birth_year
      ? new Date().getFullYear() - userInfo.birth_year
      : 30;
    let userGender = userInfo?.gender || '남자';
    if (userGender === '남성' || userGender === 'female' || userGender === 'male') {
      if (userGender === '남성' || userGender === 'male') userGender = '남자';
      else userGender = '여자';
    }

    const standards = await this.prisma.nutrientStandards.findMany({
      where: {
        gender: userGender,
        age_min: { lte: userAge },
        age_max: { gte: userAge },
      },
    });

    const items = await this.prisma.supplementInventory.findMany({
      where: {
        user_uuid: userUuid,
        status: 'active',
      },
      include: {
        supplements: {
          include: {
            ingredients: true,
          },
        },
      },
      orderBy: {
        created_at: 'desc',
      },
    });

    const enrichedItems = items.map((item) => {
      if (item.supplements && item.supplements.ingredients) {
        const enrichedIngredients = item.supplements.ingredients.map((ing) => {
          const std = standards.find((s) => s.nutrient_name === ing.ingredient_name);
          const dri = std?.recommended_intake || std?.adequate_intake || std?.avg_requirement || null;
          const amount = ing.amount || 0;

          let dailyPercent = 0;
          if (dri && dri > 0) {
            dailyPercent = Number((amount / dri).toFixed(4));
          }

          return {
            ...ing,
            dailyPercent,
          };
        });

        return {
          ...item,
          supplements: {
            ...item.supplements,
            ingredients: enrichedIngredients,
          },
        };
      }
      return item;
    });

    return enrichedItems;
  }

  async remove(id: string, userUuid: string) {
    const inventoryId = BigInt(id);

    const item = await this.prisma.supplementInventory.findUnique({
      where: {
        id: inventoryId,
      },
    });

    // 다른 사용자의 항목은 존재 여부도 알려주지 않음
    if (!item || item.user_uuid !== userUuid) {
      throw new NotFoundException('Cabinet item not found');
    }

    return this.prisma.supplementInventory.update({
      where: {
        id: inventoryId,
      },
      data: {
        status: 'deleted',
      },
    });
  }
}
