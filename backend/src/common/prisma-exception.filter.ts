import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { Response } from 'express';

/**
 * Prisma 오류 중 요청 값이 원인인 것을 500 대신 알맞은 4xx로 바꿉니다.
 * 그 외 Prisma 오류는 500으로 응답하고 로그를 남깁니다.
 */
@Catch(Prisma.PrismaClientKnownRequestError)
export class PrismaExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(PrismaExceptionFilter.name);

  private static readonly STATUS_BY_CODE: Record<string, [HttpStatus, string]> =
    {
      P2025: [HttpStatus.NOT_FOUND, '대상을 찾을 수 없습니다.'],
      P2023: [HttpStatus.BAD_REQUEST, '올바르지 않은 ID 형식입니다.'],
      P2002: [HttpStatus.CONFLICT, '이미 존재하는 데이터입니다.'],
      P2003: [HttpStatus.BAD_REQUEST, '참조하는 데이터가 없습니다.'],
    };

  catch(exception: Prisma.PrismaClientKnownRequestError, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    const mapped = PrismaExceptionFilter.STATUS_BY_CODE[exception.code];

    if (!mapped) {
      this.logger.error(`Prisma ${exception.code}: ${exception.message}`);
      response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
        statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
        message: 'Internal server error',
      });
      return;
    }

    const [status, message] = mapped;
    response.status(status).json({ statusCode: status, message });
  }
}
