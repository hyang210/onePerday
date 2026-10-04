import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { Prisma } from '@prisma/client';
import request from 'supertest';
import { App } from 'supertest/types';
import { afterAll, beforeAll, describe, expect, it } from '@jest/globals';
import { AppModule } from '../app.module';
import { PrismaService } from '../prisma/prisma.service';
import { SupabaseService } from '../supabase/supabase.service';
import { toBigIntOrBadRequest } from './parse-bigint-id.pipe';

const ADMIN = {
  id: '22222222-2222-2222-2222-222222222222',
  email: 'admin@example.com',
};

const notFound = () =>
  new Prisma.PrismaClientKnownRequestError('Record not found', {
    code: 'P2025',
    clientVersion: Prisma.prismaVersion.client,
  });

// 잘못된 ID나 없는 대상이 500이 아니라 4xx로 응답하는지 확인
describe('잘못된 ID 처리', () => {
  let app: INestApplication<App>;

  beforeAll(async () => {
    process.env.ADMIN_EMAILS = ADMIN.email;

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(SupabaseService)
      .useValue({
        getClient: () => ({
          auth: {
            getUser: () =>
              Promise.resolve({ data: { user: ADMIN }, error: null }),
          },
        }),
      })
      .overrideProvider(PrismaService)
      .useValue({
        supplementsTemp: { delete: () => Promise.reject(notFound()) },
      })
      .compile();

    app = moduleRef.createNestApplication();
    // main.ts와 같은 전역 ValidationPipe
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true }),
    );
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
  });

  const auth = { Authorization: 'Bearer token' };

  it.each([
    ['get', '/review/abc'],
    ['delete', '/cabinet/abc'],
    ['patch', '/cabinet/1.5'],
    ['delete', '/admin/supplements/abc'],
    ['delete', '/admin/users/not-a-uuid'],
  ] as const)('%s %s 는 400', async (method, path) => {
    await request(app.getHttpServer())[method](path).set(auth).expect(400);
  });

  it('리뷰 작성 시 productId가 숫자가 아니면 400', async () => {
    await request(app.getHttpServer())
      .post('/review')
      .set(auth)
      .send({ productId: 'abc', userId: ADMIN.id, score: 5, content: '좋아요' })
      .expect(400);
  });

  it('없는 대상을 삭제하면 (Prisma P2025) 404', async () => {
    const res = await request(app.getHttpServer())
      .delete('/admin/supplements/999')
      .set(auth)
      .expect(404);
    expect(res.body).toEqual({
      statusCode: 404,
      message: '대상을 찾을 수 없습니다.',
    });
  });
});

describe('toBigIntOrBadRequest', () => {
  it('숫자는 BigInt, 빈 값은 null, 그 외는 400', () => {
    expect(toBigIntOrBadRequest('12000')).toBe(BigInt(12000));
    expect(toBigIntOrBadRequest(3000)).toBe(BigInt(3000));
    expect(toBigIntOrBadRequest('')).toBeNull();
    expect(toBigIntOrBadRequest(undefined)).toBeNull();
    expect(() => toBigIntOrBadRequest('12,000')).toThrow(
      '숫자가 아닌 값입니다',
    );
  });
});
