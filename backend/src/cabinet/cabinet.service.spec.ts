import { BadRequestException, NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, jest } from '@jest/globals';
import { CabinetService } from './cabinet.service';
import { PrismaService } from '../prisma/prisma.service';

const OWNER = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';

describe('CabinetService.update', () => {
  const existing = {
    id: BigInt(7),
    user_uuid: OWNER,
    status: 'active',
    daily_frequency: 2,
  };
  let findUnique: jest.Mock<(args: unknown) => Promise<unknown>>;
  let update: jest.Mock<(args: unknown) => Promise<unknown>>;
  let service: CabinetService;

  beforeEach(() => {
    findUnique = jest.fn(() => Promise.resolve(existing as unknown));
    update = jest.fn((args: unknown) => Promise.resolve(args));
    const prisma = {
      supplementInventory: { findUnique, update },
    } as unknown as PrismaService;
    service = new CabinetService(prisma);
  });

  it('본인 항목의 바뀐 값만 수정한다', async () => {
    await service.update('7', OWNER, {
      stockCount: 10,
      alarmTimes: ['08:00', '20:00'],
    });

    expect(update).toHaveBeenCalledWith({
      where: { id: BigInt(7) },
      data: {
        daily_dose: undefined,
        daily_frequency: undefined,
        stock_count: 10,
        total_count: undefined,
        alarm_times: ['08:00', '20:00'],
      },
    });
  });

  it('다른 사용자의 항목이면 404', async () => {
    await expect(service.update('7', OTHER, { stockCount: 1 })).rejects.toThrow(
      NotFoundException,
    );
    expect(update).not.toHaveBeenCalled();
  });

  it('삭제된 항목이면 404', async () => {
    findUnique.mockResolvedValueOnce({ ...existing, status: 'deleted' });
    await expect(service.update('7', OWNER, { stockCount: 1 })).rejects.toThrow(
      NotFoundException,
    );
  });

  it('알림 시간 개수가 하루 복용 횟수와 다르면 400', async () => {
    // 기존 daily_frequency(2)와 비교
    await expect(
      service.update('7', OWNER, { alarmTimes: ['08:00'] }),
    ).rejects.toThrow(BadRequestException);
    // 함께 바꾸는 dailyFrequency(1)와 비교
    await expect(
      service.update('7', OWNER, { dailyFrequency: 1, alarmTimes: ['08:00'] }),
    ).resolves.toBeDefined();
  });
});
