/** 남은 일수가 이 값 이하이면 재구매 알림 */
export const LOW_STOCK_DAYS = 7;
/** 남은 일수가 이 값 이하이면 긴급 재구매 알림 */
export const CRITICAL_STOCK_DAYS = 3;

/**
 * 남은 개수로 며칠 더 복용할 수 있는지 계산합니다. (하루 복용량 = 1회 복용량 × 하루 횟수)
 * 하루치를 다 채우지 못하는 날은 세지 않습니다. 복용량 정보가 없으면 null.
 */
export function calcDaysLeft(
  stockCount: number,
  dailyDose: number,
  dailyFrequency: number,
): number | null {
  const perDay = dailyDose * dailyFrequency;
  if (!Number.isFinite(perDay) || perDay <= 0) return null;
  return Math.floor(Math.max(0, stockCount) / perDay);
}
