import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { PaymentService } from './payment.service';
import { VerifyPaymentDto } from './dto/verify-payment.dto';

@Controller('api/payment')
export class PaymentController {
  constructor(private readonly paymentService: PaymentService) {}

  /** 결제 완료 후 앱이 호출. 검증에 성공하면 200, 실패하면 4xx/5xx */
  @Post('verify')
  @HttpCode(200)
  verify(@Body() dto: VerifyPaymentDto) {
    return this.paymentService.verify(dto);
  }
}
