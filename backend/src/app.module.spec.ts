import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { afterAll, beforeAll, describe, it } from '@jest/globals';
import { AppModule } from './app.module';
import { PrismaService } from './prisma/prisma.service';
import { SupabaseService } from './supabase/supabase.service';

// 실제 AppModule 구성에서 전역 인증 Guard가 적용되는지 확인 (DB/Supabase는 mock)
describe('AppModule 인증 적용', () => {
  let app: INestApplication<App>;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PrismaService)
      .useValue({})
      .overrideProvider(SupabaseService)
      .useValue({
        getClient: () => ({
          auth: {
            getUser: () =>
              Promise.resolve({
                data: { user: null },
                error: new Error('invalid'),
              }),
          },
        }),
      })
      .compile();
    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
  });

  it.each([
    ['get', '/admin/users'],
    ['delete', '/admin/users/some-id'],
    ['get', '/cabinet/11111111-1111-1111-1111-111111111111'],
    ['get', '/reminders/today/11111111-1111-1111-1111-111111111111'],
    ['get', '/recommend?userId=11111111-1111-1111-1111-111111111111'],
    ['post', '/intake/complete'],
    ['post', '/chatbot/message'],
    ['post', '/label-recognition/analyze'],
    ['post', '/review'],
    ['get', '/auth/me'],
  ] as const)('%s %s 는 토큰 없이 401', async (method, path) => {
    await request(app.getHttpServer())[method](path).expect(401);
  });

  it('GET / 는 공개', async () => {
    await request(app.getHttpServer()).get('/').expect(200);
  });
});
