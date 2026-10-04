import { describe, expect, it } from '@jest/globals';
import { calcDaysLeft } from './stock-forecast';

describe('calcDaysLeft', () => {
  it('하루 복용량(1회량 × 횟수) 기준으로 남은 일수를 계산한다', () => {
    expect(calcDaysLeft(60, 1, 1)).toBe(60);
    // 2정씩 하루 3번 = 하루 6정 → 30정이면 5일
    expect(calcDaysLeft(30, 2, 3)).toBe(5);
  });

  it('하루치를 채우지 못하는 날은 세지 않는다', () => {
    expect(calcDaysLeft(5, 2, 1)).toBe(2);
    expect(calcDaysLeft(1, 2, 1)).toBe(0);
  });

  it('재고가 음수면 0, 복용량 정보가 없으면 null', () => {
    expect(calcDaysLeft(-3, 1, 1)).toBe(0);
    expect(calcDaysLeft(10, 0, 1)).toBeNull();
    expect(calcDaysLeft(10, 1, 0)).toBeNull();
  });
});
