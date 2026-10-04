import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { AuthRequest, AuthUser } from './auth-user';

/** SupabaseAuthGuard가 검증한 로그인 사용자를 주입합니다. */
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthUser =>
    ctx.switchToHttp().getRequest<AuthRequest>().user as AuthUser,
);
