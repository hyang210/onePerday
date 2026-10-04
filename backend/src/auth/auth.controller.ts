import { Controller, Get } from '@nestjs/common';
import { CurrentUser } from './current-user.decorator';
import { isAdminEmail } from './auth-user';
import type { AuthUser } from './auth-user';

@Controller('auth')
export class AuthController {
  /** 로그인한 사용자 정보와 관리자 여부 (관리자 웹 로그인 확인용) */
  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return { ...user, isAdmin: isAdminEmail(user.email) };
  }
}
