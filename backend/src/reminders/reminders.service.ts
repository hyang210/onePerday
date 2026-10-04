import { Injectable } from '@nestjs/common';
import {
  calcDaysLeft,
  CRITICAL_STOCK_DAYS,
  LOW_STOCK_DAYS,
} from '../cabinet/stock-forecast';
import { PrismaService } from '../prisma/prisma.service';

type ReminderStatus = 'UPCOMING' | 'DUE' | 'MISSED' | 'TAKEN';

@Injectable()
export class RemindersService {
  constructor(private readonly prisma: PrismaService) {}

  async getTodayReminders(userUuid: string) {
    const today = this.getDateOnly(new Date());

    const inventories = await this.prisma.supplementInventory.findMany({
      where: {
        user_uuid: userUuid,
        status: 'active',
      },
      include: {
        supplements: true,
        daily_supplements: {
          where: {
            date: today,
          },
        },
      },
      orderBy: {
        created_at: 'desc',
      },
    });

    const doseReminders = inventories
      .flatMap((item) => {
        const dailyFrequency = item.daily_frequency ?? 1;
        const alarmTimes = this.getAlarmTimesOrDefault(
          item.alarm_times,
          dailyFrequency,
        );

        return alarmTimes.map((time, index) => {
          const log = item.daily_supplements.find(
            (daily) => daily.dose_index === index,
          );

          const isTaken = log?.is_taken === true;
          const status = this.getReminderStatus(time, isTaken);

          return {
            inventoryId: item.id.toString(),
            supplementId: item.supplement_id.toString(),
            supplementName: item.supplements.product_name,
            brandName: item.supplements.brand_name,
            imageUrl: item.supplements.image_url,
            doseIndex: index,
            supplementTime: time,
            date: today.toISOString().slice(0, 10),
            isTaken,
            status,
          };
        });
      })
      .filter((item) => item.status !== 'TAKEN');

    const stockReminders = inventories
      .map((item) => {
        const dailyDose = item.daily_dose ?? 1;
        const dailyFrequency = item.daily_frequency ?? 1;
        const stockCount = item.stock_count ?? 0;
        const daysLeft = calcDaysLeft(stockCount, dailyDose, dailyFrequency);

        return {
          inventoryId: item.id.toString(),
          supplementId: item.supplement_id.toString(),
          supplementName: item.supplements.product_name,
          brandName: item.supplements.brand_name,
          imageUrl: item.supplements.image_url,
          stockCount,
          totalCount: item.total_count ?? 0,
          dailyDose,
          dailyFrequency,
          daysLeft,
          status:
            daysLeft !== null && daysLeft <= CRITICAL_STOCK_DAYS
              ? 'CRITICAL_STOCK'
              : 'LOW_STOCK',
        };
      })
      .filter(
        (item) => item.daysLeft !== null && item.daysLeft <= LOW_STOCK_DAYS,
      );

    doseReminders.sort((a, b) => {
      const priority: Record<ReminderStatus, number> = {
        DUE: 1,
        MISSED: 2,
        UPCOMING: 3,
        TAKEN: 4,
      };

      if (priority[a.status] !== priority[b.status]) {
        return priority[a.status] - priority[b.status];
      }

      return a.supplementTime.localeCompare(b.supplementTime);
    });

    stockReminders.sort((a, b) => (a.daysLeft ?? 0) - (b.daysLeft ?? 0));

    return {
      doseReminders,
      stockReminders,
    };
  }

  private parseAlarmTimes(value: unknown): string[] {
    if (!Array.isArray(value)) {
      return [];
    }

    const alarmTimes: string[] = [];

    for (const item of value) {
      if (typeof item === 'string' && item.length > 0) {
        alarmTimes.push(item);
      }
    }

    return alarmTimes;
  }

  private getAlarmTimesOrDefault(
    value: unknown,
    dailyFrequency: number,
  ): string[] {
    const parsed = this.parseAlarmTimes(value);

    if (parsed.length >= dailyFrequency) {
      return parsed.slice(0, dailyFrequency);
    }

    const defaults = this.getDefaultAlarmTimes(dailyFrequency);

    return Array.from({ length: dailyFrequency }, (_, index) => {
      return parsed[index] ?? defaults[index] ?? '09:00';
    });
  }

  private getDefaultAlarmTimes(dailyFrequency: number): string[] {
    if (dailyFrequency <= 1) return ['09:00'];
    if (dailyFrequency === 2) return ['09:00', '19:00'];
    if (dailyFrequency === 3) return ['08:00', '13:00', '19:00'];

    return Array.from({ length: dailyFrequency }, (_, index) => {
      const hour = (8 + index * 4) % 24;
      return `${hour.toString().padStart(2, '0')}:00`;
    });
  }

  private getDateOnly(date: Date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }

  private getReminderStatus(
    supplementTime: string,
    isTaken: boolean,
  ): ReminderStatus {
    if (isTaken) return 'TAKEN';

    const now = new Date();
    const [hour, minute] = supplementTime.split(':').map(Number);

    if (Number.isNaN(hour) || Number.isNaN(minute)) {
      return 'UPCOMING';
    }

    const target = new Date(now);
    target.setHours(hour, minute, 0, 0);

    const dueEnd = new Date(target.getTime() + 60 * 60 * 1000);

    if (now < target) return 'UPCOMING';
    if (now <= dueEnd) return 'DUE';
    return 'MISSED';
  }
}
