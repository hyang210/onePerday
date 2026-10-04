import {
  BadRequestException,
  BadGatewayException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { VerifyPaymentDto } from './dto/verify-payment.dto';

const PORTONE_API = 'https://api.iamport.kr';

interface PortOneResponse<T> {
  code: number;
  message: string | null;
  response: T | null;
}

interface PortOnePayment {
  imp_uid: string;
  merchant_uid: string;
  amount: number;
  status: string; // ready | paid | cancelled | failed
}

/**
 * PortOne(아임포트) V1 결제 검증.
 * 앱이 보낸 금액은 믿지 않고, DB 가격으로 계산한 금액과 PortOne에 실제로 결제된 금액을 비교합니다.
 */
@Injectable()
export class PaymentService {
  private readonly logger = new Logger(PaymentService.name);

  constructor(private readonly prisma: PrismaService) {}

  async verify(dto: VerifyPaymentDto) {
    const expectedAmount = await this.calculateExpectedAmount(dto.items);
    const token = await this.getAccessToken();
    const payment = await this.getPayment(token, dto.impUid);

    if (payment.status !== 'paid') {
      throw new BadRequestException(
        `결제가 완료되지 않았습니다. (상태: ${payment.status})`,
      );
    }

    if (payment.merchant_uid !== dto.merchantUid) {
      await this.cancel(token, dto.impUid, '주문번호 불일치');
      throw new BadRequestException(
        '주문번호가 일치하지 않아 결제를 취소했습니다.',
      );
    }

    if (payment.amount !== expectedAmount) {
      await this.cancel(token, dto.impUid, '결제 금액 불일치');
      throw new BadRequestException(
        `결제 금액(${payment.amount}원)이 상품 금액(${expectedAmount}원)과 달라 결제를 취소했습니다.`,
      );
    }

    return {
      success: true,
      impUid: payment.imp_uid,
      merchantUid: payment.merchant_uid,
      amount: payment.amount,
    };
  }

  /** DB(supplements_temp) 가격 × 수량의 합계 */
  private async calculateExpectedAmount(
    items: VerifyPaymentDto['items'],
  ): Promise<number> {
    const ids = [...new Set(items.map((item) => item.productId))];
    const products = await this.prisma.supplementsTemp.findMany({
      where: { id: { in: ids.map((id) => BigInt(id)) } },
      select: { id: true, price: true },
    });
    const priceById = new Map(
      products.map((product) => [product.id.toString(), product.price]),
    );

    let total = 0;
    for (const item of items) {
      const price = priceById.get(item.productId);
      if (price === undefined) {
        throw new BadRequestException(
          `상품을 찾을 수 없습니다: ${item.productId}`,
        );
      }
      if (price === null || price <= BigInt(0)) {
        throw new BadRequestException(
          `가격 정보가 없는 상품입니다: ${item.productId}`,
        );
      }
      total += Number(price) * item.count;
    }
    return total;
  }

  private async getAccessToken(): Promise<string> {
    const impKey = process.env.PORTONE_API_KEY;
    const impSecret = process.env.PORTONE_API_SECRET;
    if (!impKey || !impSecret) {
      throw new ServiceUnavailableException(
        '결제 검증 설정(PORTONE_API_KEY, PORTONE_API_SECRET)이 없습니다.',
      );
    }

    const data = await this.request<{ access_token: string }>(
      '/users/getToken',
      {
        method: 'POST',
        body: JSON.stringify({ imp_key: impKey, imp_secret: impSecret }),
      },
    );
    return data.access_token;
  }

  private getPayment(token: string, impUid: string) {
    return this.request<PortOnePayment>(
      `/payments/${encodeURIComponent(impUid)}`,
      { method: 'GET', headers: { Authorization: token } },
      '결제 정보를 찾을 수 없습니다.',
    );
  }

  private async cancel(token: string, impUid: string, reason: string) {
    try {
      await this.request('/payments/cancel', {
        method: 'POST',
        headers: { Authorization: token },
        body: JSON.stringify({ imp_uid: impUid, reason }),
      });
    } catch (error) {
      // 취소 실패는 로그로 남기고, 검증 실패 응답은 그대로 돌려줌
      this.logger.error(`결제 취소 실패 (${impUid}): ${String(error)}`);
    }
  }

  private async request<T>(
    path: string,
    init: RequestInit,
    notFoundMessage?: string,
  ): Promise<T> {
    let res: Response;
    try {
      res = await fetch(`${PORTONE_API}${path}`, {
        ...init,
        headers: { 'Content-Type': 'application/json', ...init.headers },
        signal: AbortSignal.timeout(10_000),
      });
    } catch (error) {
      this.logger.error(`PortOne 요청 실패 ${path}: ${String(error)}`);
      throw new BadGatewayException('결제사 서버에 연결하지 못했습니다.');
    }

    const json = (await res
      .json()
      .catch(() => null)) as PortOneResponse<T> | null;
    if (res.status === 404 && notFoundMessage) {
      throw new BadRequestException(notFoundMessage);
    }
    if (!res.ok || !json || json.code !== 0 || !json.response) {
      this.logger.error(
        `PortOne 오류 ${path}: ${res.status} ${json?.message ?? ''}`,
      );
      throw new BadGatewayException(
        json?.message ?? '결제사 서버 응답이 올바르지 않습니다.',
      );
    }
    return json.response;
  }
}
