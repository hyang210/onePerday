import { ForbiddenException } from '@nestjs/common';
import type { Request } from 'express';

export interface AuthUser {
  id: string;
  email: string | null;
}

/** SupabaseAuthGuard를 통과한 요청 */
export type AuthRequest = Request & { user?: AuthUser };

/** 요청에 담긴 사용자 ID가 로그인한 사용자 본인인지 확인합니다. */
export function assertSameUser(user: AuthUser, userId: string | undefined) {
  if (!userId || userId !== user.id) {
    throw new ForbiddenException('본인의 데이터만 접근할 수 있습니다.');
  }
}

/** ADMIN_EMAILS 환경변수(쉼표 구분)에 포함된 이메일인지 확인합니다. */
export function isAdminEmail(email: string | null | undefined): boolean {
  if (!email) return false;
  const admins = (process.env.ADMIN_EMAILS ?? '')
    .split(',')
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);
  return admins.includes(email.toLowerCase());
}
