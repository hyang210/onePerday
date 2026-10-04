import {
  IsNotEmpty,
  IsNumber,
  IsString,
  Matches,
  Max,
  Min,
} from 'class-validator';

export class CreateReviewDto {
  @IsNotEmpty()
  @IsString()
  @Matches(/^\d+$/, { message: 'productId는 숫자여야 합니다.' })
  productId!: string;

  @IsNotEmpty()
  @IsString()
  userId!: string;

  @IsNotEmpty()
  @IsNumber()
  @Min(1)
  @Max(5)
  score!: number;

  @IsNotEmpty()
  @IsString()
  content!: string;
}
