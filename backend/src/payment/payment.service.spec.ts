import {
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  jest,
} from '@jest/globals';
import { PaymentService } from './payment.service';
import { PrismaService } from '../prisma/prisma.service';

type FetchCall = { url: string; init: RequestInit };

/** PortOne API 흉내: 결제 정보(payment)를 돌려주고 호출 기록을 남김 */
function mockPortOne(payment: Record<string, unknown>) {
  const calls: FetchCall[] = [];
  const ok = (response: unknown) =>
    Promise.resolve(
      new Response(JSON.stringify({ code: 0, message: null, response }), {
        status: 200,
      }),
    );
  jest
    .spyOn(globalThis, 'fetch')
    .mockImplementation((input: string | URL | Request, init?: RequestInit) => {
      const url = input instanceof Request ? input.url : input.toString();
      calls.push({ url, init: init ?? {} });
      if (url.endsWith('/users/getToken')) return ok({ access_token: 'tok' });
      if (url.includes('/payments/cancel')) return ok({ status: 'cancelled' });
      return ok(payment);
    });
  return calls;
}

describe('PaymentService.verify', () => {
  let service: PaymentService;

  beforeEach(() => {
    process.env.PORTONE_API_KEY = 'key';
    process.env.PORTONE_API_SECRET = 'secret';
    const prisma = {
      supplementsTemp: {
        findMany: () =>
          Promise.resolve([
            { id: BigInt(1), price: BigInt(12000) },
            { id: BigInt(2), price: BigInt(5000) },
          ]),
      },
    } as unknown as PrismaService;
    service = new PaymentService(prisma);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const dto = {
    impUid: 'imp_123',
    merchantUid: 'order_1',
    items: [
      { productId: '1', count: 2 },
      { productId: '2', count: 1 },
    ],
  };

  it('DB 가격 합계(12000×2 + 5000)와 결제 금액이 같으면 성공', async () => {
    const calls = mockPortOne({
      imp_uid: 'imp_123',
      merchant_uid: 'order_1',
      amount: 29000,
      status: 'paid',
    });

    await expect(service.verify(dto)).resolves.toEqual({
      success: true,
      impUid: 'imp_123',
      merchantUid: 'order_1',
      amount: 29000,
    });
    expect(calls.some((c) => c.url.includes('/payments/cancel'))).toBe(false);
    // 결제 조회에 발급받은 토큰을 사용
    const getPayment = calls.find((c) => c.url.endsWith('/payments/imp_123'));
    expect(getPayment?.init.headers).toMatchObject({ Authorization: 'tok' });
  });

  it('결제 금액이 다르면 결제를 취소하고 400', async () => {
    const calls = mockPortOne({
      imp_uid: 'imp_123',
      merchant_uid: 'order_1',
      amount: 100,
      status: 'paid',
    });

    await expect(service.verify(dto)).rejects.toThrow(BadRequestException);
    const cancel = calls.find((c) => c.url.includes('/payments/cancel'));
    expect(JSON.parse(cancel?.init.body as string)).toMatchObject({
      imp_uid: 'imp_123',
    });
  });

  it('주문번호가 다르면 결제를 취소하고 400', async () => {
    const calls = mockPortOne({
      imp_uid: 'imp_123',
      merchant_uid: 'other_order',
      amount: 29000,
      status: 'paid',
    });

    await expect(service.verify(dto)).rejects.toThrow('주문번호');
    expect(calls.some((c) => c.url.includes('/payments/cancel'))).toBe(true);
  });

  it('결제가 완료(paid) 상태가 아니면 400 (취소 호출 없음)', async () => {
    const calls = mockPortOne({
      imp_uid: 'imp_123',
      merchant_uid: 'order_1',
      amount: 29000,
      status: 'ready',
    });

    await expect(service.verify(dto)).rejects.toThrow('결제가 완료되지');
    expect(calls.some((c) => c.url.includes('/payments/cancel'))).toBe(false);
  });

  it('DB에 없는 상품이면 400 (PortOne 호출 전)', async () => {
    const calls = mockPortOne({});
    await expect(
      service.verify({ ...dto, items: [{ productId: '999', count: 1 }] }),
    ).rejects.toThrow('상품을 찾을 수 없습니다');
    expect(calls).toHaveLength(0);
  });

  it('PortOne API 키가 없으면 503', async () => {
    delete process.env.PORTONE_API_KEY;
    mockPortOne({});
    await expect(service.verify(dto)).rejects.toThrow(
      ServiceUnavailableException,
    );
  });
});
