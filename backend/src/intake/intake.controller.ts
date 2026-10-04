import { Controller, Post, Body } from '@nestjs/common';
import { IntakeService } from './intake.service';
import { CheckIntakeDto } from './dto/check-intake.dto';
import { CompleteIntakeDto } from './dto/complete-intake.dto';
import { CurrentUser } from '../auth/current-user.decorator';
import { assertSameUser } from '../auth/auth-user';
import type { AuthUser } from '../auth/auth-user';

type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };

function serializeBigInt(value: unknown): JsonValue {
  if (typeof value === 'bigint') return value.toString();
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map((item) => serializeBigInt(item));

  if (value !== null && typeof value === 'object') {
    const result: { [key: string]: JsonValue } = {};

    for (const [key, nestedValue] of Object.entries(
      value as Record<string, unknown>,
    )) {
      result[key] = serializeBigInt(nestedValue);
    }

    return result;
  }

  if (
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean' ||
    value === null
  ) {
    return value;
  }

  return null;
}

@Controller('intake')
export class IntakeController {
  constructor(private readonly intakeService: IntakeService) {}

  @Post('check-safety')
  async checkSafety(@Body() dto: CheckIntakeDto) {
    const analysis = await this.intakeService.checkOverdose(dto);
    const hasWarning = analysis.some(
      (item) =>
        item.status === 'danger' ||
        item.status === 'very_low' ||
        item.status === 'low',
    );
    return {
      success: true,
      hasWarning,
      results: analysis,
    };
  }

  @Post('complete')
  async complete(
    @Body() dto: CompleteIntakeDto,
    @CurrentUser() user: AuthUser,
  ) {
    assertSameUser(user, dto.userUuid);
    const data = await this.intakeService.completeIntake(dto);

    return {
      success: true,
      data: serializeBigInt(data),
    };
  }

  @Post('cancel')
  async cancel(@Body() dto: CompleteIntakeDto, @CurrentUser() user: AuthUser) {
    assertSameUser(user, dto.userUuid);
    const data = await this.intakeService.cancelIntake(dto);

    return {
      success: true,
      data: serializeBigInt(data),
    };
  }
}
