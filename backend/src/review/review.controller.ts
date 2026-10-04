import { Controller, Get, Post, Body, Param } from '@nestjs/common';
import { ReviewService } from './review.service';
import { CreateReviewDto } from './dto/create-review.dto';
import { Public } from '../auth/public.decorator';
import { ParseBigIntIdPipe } from '../common/parse-bigint-id.pipe';
import { CurrentUser } from '../auth/current-user.decorator';
import { assertSameUser } from '../auth/auth-user';
import type { AuthUser } from '../auth/auth-user';

@Controller('review')
export class ReviewController {
  constructor(private readonly reviewService: ReviewService) {}

  @Post()
  async createReview(
    @Body() dto: CreateReviewDto,
    @CurrentUser() user: AuthUser,
  ) {
    assertSameUser(user, dto.userId);
    return this.reviewService.createReview(dto);
  }

  @Public()
  @Get(':productId')
  async getReviewsByProduct(@Param('productId', ParseBigIntIdPipe) productId: string) {
    return this.reviewService.getReviewsByProduct(productId);
  }

  @Get('user/:userId')
  async getReviewsByUser(
    @Param('userId') userId: string,
    @CurrentUser() user: AuthUser,
  ) {
    assertSameUser(user, userId);
    return this.reviewService.getReviewsByUser(userId);
  }
}
