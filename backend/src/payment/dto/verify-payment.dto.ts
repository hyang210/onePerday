import {
  ArrayNotEmpty,
  IsArray,
  IsInt,
  IsNotEmpty,
  IsString,
  Matches,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';

class PaymentItemDto {
  @IsString()
  @Matches(/^\d+$/, { message: 'productId는 숫자여야 합니다.' })
  productId!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  count!: number;
}

export class VerifyPaymentDto {
  /** PortOne 결제 고유번호 */
  @IsString()
  @IsNotEmpty()
  impUid!: string;

  /** 앱에서 만든 주문번호 */
  @IsString()
  @IsNotEmpty()
  merchantUid!: string;

  /** 결제한 상품 목록. 서버가 DB 가격으로 결제 금액을 다시 계산합니다. */
  @IsArray()
  @ArrayNotEmpty()
  @ValidateNested({ each: true })
  @Type(() => PaymentItemDto)
  items!: PaymentItemDto[];
}
