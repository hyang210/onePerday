import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';

/** 로그인 없이 호출할 수 있는 엔드포인트에 붙입니다. */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
