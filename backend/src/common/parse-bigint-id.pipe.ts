import { BadRequestException, PipeTransform } from '@nestjs/common';

/**
 * 숫자 ID(DB BigInt) 경로 파라미터를 검증합니다.
 * 숫자가 아닌 값이 들어오면 BigInt() 변환 오류(500) 대신 400을 돌려줍니다.
 */
export class ParseBigIntIdPipe implements PipeTransform<string, string> {
  transform(value: string): string {
    if (typeof value !== 'string' || !/^\d+$/.test(value)) {
      throw new BadRequestException('올바르지 않은 ID 형식입니다.');
    }
    return value;
  }
}

/** 요청 본문의 숫자 값을 BigInt로 바꿉니다. 비어 있으면 null, 숫자가 아니면 400. */
export function toBigIntOrBadRequest(value: unknown): bigint | null {
  if (value === null || value === undefined || value === '') return null;
  const raw =
    typeof value === 'string' || typeof value === 'number'
      ? String(value).trim()
      : '';
  if (!/^\d+$/.test(raw)) {
    throw new BadRequestException(`숫자가 아닌 값입니다: ${raw}`);
  }
  return BigInt(raw);
}
