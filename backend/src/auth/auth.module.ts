import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { AdminGuard } from './admin.guard';
import { SupabaseAuthGuard } from './supabase-auth.guard';

@Module({
  controllers: [AuthController],
  providers: [
    AuthService,
    AdminGuard,
    // 모든 엔드포인트에 로그인 검증 적용 (예외는 @Public())
    { provide: APP_GUARD, useClass: SupabaseAuthGuard },
  ],
  exports: [AdminGuard],
})
export class AuthModule {}
