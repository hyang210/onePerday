import { Body, Controller, Delete, Get, Param, Post } from '@nestjs/common';
import { CabinetService } from './cabinet.service';
import { CreateCabinetDto } from './dto/create-cabinet.dto';
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
  if (typeof value === 'bigint') {
    return value.toString();
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (Array.isArray(value)) {
    return value.map((item) => serializeBigInt(item));
  }

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

@Controller('cabinet')
export class CabinetController {
  constructor(private readonly cabinetService: CabinetService) {}

  @Post()
  async create(@Body() dto: CreateCabinetDto, @CurrentUser() user: AuthUser) {
    assertSameUser(user, dto.userUuid);
    const data = await this.cabinetService.create(dto);

    return {
      success: true,
      data: serializeBigInt(data),
    };
  }

  @Get(':userUuid')
  async findByUser(
    @Param('userUuid') userUuid: string,
    @CurrentUser() user: AuthUser,
  ) {
    assertSameUser(user, userUuid);
    const data = await this.cabinetService.findByUser(userUuid);

    return {
      success: true,
      data: serializeBigInt(data),
    };
  }

  @Delete(':id')
  async remove(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    const data = await this.cabinetService.remove(id, user.id);

    return {
      success: true,
      data: serializeBigInt(data),
    };
  }
}
