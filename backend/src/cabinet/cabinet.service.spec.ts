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

describe('CabinetService.findStoreProduct', () => {
  const inventory = {
    id: BigInt(7),
    user_uuid: OWNER,
    status: 'active',
    supplements: { product_name: '비타민D 2000IU' },
  };

  function createService(storeProduct: unknown) {
    const prisma = {
      supplementInventory: { findUnique: () => Promise.resolve(inventory) },
      supplementsTemp: {
        findFirst: jest.fn<(args: unknown) => Promise<unknown>>(() =>
          Promise.resolve(storeProduct),
        ),
      },
      supplementsIngredients: {
        findMany: () => Promise.resolve([{ ingredient_name: '비타민D' }]),
      },
    };
    return {
      prisma,
      service: new CabinetService(prisma as unknown as PrismaService),
    };
  }

  it('같은 상품명의 스토어 상품을 성분과 함께 돌려준다', async () => {
    const { prisma, service } = createService({
      id: BigInt(42),
      product_name: '비타민D 2000IU',
      price: BigInt(15000),
    });

    await expect(service.findStoreProduct('7', OWNER)).resolves.toEqual({
      id: BigInt(42),
      product_name: '비타민D 2000IU',
      price: BigInt(15000),
      ingredients: [{ ingredient_name: '비타민D' }],
    });
    expect(prisma.supplementsTemp.findFirst).toHaveBeenCalledWith({
      where: { product_name: '비타민D 2000IU' },
    });
  });

  it('스토어에 없는 상품이면 404', async () => {
    const { service } = createService(null);
    await expect(service.findStoreProduct('7', OWNER)).rejects.toThrow(
      '스토어에서 판매하지 않는 상품',
    );
  });

  it('다른 사용자의 항목이면 404', async () => {
    const { service } = createService({ id: BigInt(42) });
    await expect(service.findStoreProduct('7', OTHER)).rejects.toThrow(
      NotFoundException,
    );
  });
});
