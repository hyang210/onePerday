import { Controller, Get, Query, BadRequestException } from '@nestjs/common';
import { RecommendService } from './recommend.service';
import { CurrentUser } from '../auth/current-user.decorator';
import { assertSameUser } from '../auth/auth-user';
import type { AuthUser } from '../auth/auth-user';

@Controller('recommend')
export class RecommendController {
  constructor(private readonly recommendService: RecommendService) {}

  @Get()
  async getRecommendations(
    @Query('userId') userId: string,
    @CurrentUser() user: AuthUser,
  ) {
    if (!userId) {
      throw new BadRequestException('userId 쿼리 파라미터가 필요합니다.');
    }
    assertSameUser(user, userId);
    return this.recommendService.getPersonalizedRecommendations(userId);
  }
}
