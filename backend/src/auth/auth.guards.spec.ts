import { Controller, Get, INestApplication, Param } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { afterAll, beforeAll, describe, expect, it } from '@jest/globals';
import { AuthModule } from './auth.module';
import { Public } from './public.decorator';
import { CurrentUser } from './current-user.decorator';
import { assertSameUser, isAdminEmail } from './auth-user';
import type { AuthUser } from './auth-user';
import { AdminController } from '../admin/admin.controller';
import { PrismaService } from '../prisma/prisma.service';
import { SupabaseService } from '../supabase/supabase.service';
import { SupabaseModule } from '../supabase/supabase.module';
import { PrismaModule } from '../prisma/prisma.module';

const USER_TOKEN = 'user-token';
const ADMIN_TOKEN = 'admin-token';
const USER = {
  id: '11111111-1111-1111-1111-111111111111',
  email: 'user@example.com',
};
const ADMIN = {
  id: '22222222-2222-2222-2222-222222222222',
  email: 'Admin@Example.com',
};

@Controller('test')
class TestController {
  @Public()
  @Get('public')
  open() {
    return { ok: true };
  }

  @Get('mine/:userUuid')
  mine(@Param('userUuid') userUuid: string, @CurrentUser() user: AuthUser) {
    assertSameUser(user, userUuid);
    return { ok: true };
  }
}

describe('인증 Guard', () => {
  let app: INestApplication<App>;

  beforeAll(async () => {
    process.env.ADMIN_EMAILS = ' admin@example.com , other@example.com ';

    const supabaseMock = {
      getClient: () => ({
        auth: {
          getUser: (token: string) => {
            const users: Record<string, typeof USER> = {
              [USER_TOKEN]: USER,
              [ADMIN_TOKEN]: ADMIN,
            };
            const user = users[token] ?? null;
            return Promise.resolve({
              data: { user },
              error: user ? null : new Error('invalid'),
            });
          },
        },
      }),
    };

    const moduleRef = await Test.createTestingModule({
      imports: [SupabaseModule, PrismaModule, AuthModule],
      controllers: [TestController, AdminController],
    })
      .overrideProvider(SupabaseService)
      .useValue(supabaseMock)
      .overrideProvider(PrismaService)
      .useValue({
        usersInfo: { count: () => Promise.resolve(3) },
        supplements: { count: () => Promise.resolve(5) },
      })
      .compile();

    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
  });

  it('@Public() 엔드포인트는 토큰 없이 호출된다', async () => {
    await request(app.getHttpServer()).get('/test/public').expect(200);
  });

  it('토큰이 없으면 401', async () => {
    await request(app.getHttpServer()).get(`/test/mine/${USER.id}`).expect(401);
  });

  it('유효하지 않은 토큰이면 401', async () => {
    await request(app.getHttpServer())
      .get(`/test/mine/${USER.id}`)
      .set('Authorization', 'Bearer wrong')
      .expect(401);
  });

  it('본인 데이터는 접근할 수 있다', async () => {
    await request(app.getHttpServer())
      .get(`/test/mine/${USER.id}`)
      .set('Authorization', `Bearer ${USER_TOKEN}`)
      .expect(200);
  });

  it('다른 사용자의 데이터는 403', async () => {
    await request(app.getHttpServer())
      .get(`/test/mine/${ADMIN.id}`)
      .set('Authorization', `Bearer ${USER_TOKEN}`)
      .expect(403);
  });

  it('관리자 API: 토큰 없으면 401, 일반 사용자는 403', async () => {
    await request(app.getHttpServer()).get('/admin/dashboard').expect(401);
    await request(app.getHttpServer())
      .get('/admin/dashboard')
      .set('Authorization', `Bearer ${USER_TOKEN}`)
      .expect(403);
  });

  it('관리자 API: ADMIN_EMAILS 계정은 통과 (대소문자 무시)', async () => {
    const res = await request(app.getHttpServer())
      .get('/admin/dashboard')
      .set('Authorization', `Bearer ${ADMIN_TOKEN}`)
      .expect(200);
    expect(res.body).toEqual({
      totalUsers: 3,
      totalSupplements: 5,
      todayUsers: 3,
    });
  });

  it('GET /auth/me 는 관리자 여부를 알려준다', async () => {
    const res = await request(app.getHttpServer())
      .get('/auth/me')
      .set('Authorization', `Bearer ${USER_TOKEN}`)
      .expect(200);
    expect(res.body).toEqual({ ...USER, isAdmin: false });
  });
});

describe('isAdminEmail', () => {
  it('ADMIN_EMAILS가 비어 있으면 아무도 관리자가 아니다', () => {
    process.env.ADMIN_EMAILS = '';
    expect(isAdminEmail('admin@example.com')).toBe(false);
    expect(isAdminEmail(null)).toBe(false);
  });
});
