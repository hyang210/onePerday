import { IsArray, IsInt, IsOptional, IsString, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class UpdateCabinetDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  dailyDose?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  dailyFrequency?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  stockCount?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  totalCount?: number;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  alarmTimes?: string[];
}
