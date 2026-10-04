import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { SupabaseService } from '../supabase/supabase.service';
import { IS_PUBLIC_KEY } from './public.decorator';
import type { AuthRequest } from './auth-user';

/**
 * 모든 요청에 적용되는 전역 Guard.
 * Authorization: Bearer <Supabase access token>을 검증하고 request.user에 사용자를 담습니다.
 */
@Injectable()
export class SupabaseAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly supabaseService: SupabaseService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<AuthRequest>();
    const header = request.headers.authorization;
    const [scheme, token] = header?.split(' ') ?? [];
    if (scheme?.toLowerCase() !== 'bearer' || !token) {
      throw new UnauthorizedException('로그인이 필요합니다.');
    }

    const { data, error } = await this.supabaseService
      .getClient()
      .auth.getUser(token);
    if (error || !data?.user) {
      throw new UnauthorizedException('로그인 정보가 유효하지 않습니다.');
    }

    request.user = { id: data.user.id, email: data.user.email ?? null };
    return true;
  }
}
