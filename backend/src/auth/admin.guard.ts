import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { isAdminEmail } from './auth-user';
import type { AuthRequest } from './auth-user';

/** SupabaseAuthGuard 다음에 실행되며, ADMIN_EMAILS에 등록된 계정만 통과시킵니다. */
@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const { user } = context.switchToHttp().getRequest<AuthRequest>();
    if (!isAdminEmail(user?.email)) {
      throw new ForbiddenException('관리자만 접근할 수 있습니다.');
    }
    return true;
  }
}
