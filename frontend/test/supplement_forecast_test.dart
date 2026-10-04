import 'package:flutter_test/flutter_test.dart';
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';

Supplement _supplement({
  required int remaining,
  int dailyDose = 1,
  int dailyFrequency = 1,
}) => Supplement(
  name: '비타민D',
  brand: '테스트',
  remaining: remaining,
  total: 60,
  dailyDose: dailyDose,
  dailyFrequency: dailyFrequency,
  nutrients: const [],
);

void main() {
  group('Supplement 소진 예측', () {
    test('하루 복용량(1회량 × 횟수) 기준으로 남은 일수를 계산한다', () {
      expect(_supplement(remaining: 60).daysLeft, 60);
      // 2정씩 하루 3번 = 하루 6정 → 30정이면 5일
      expect(
        _supplement(remaining: 30, dailyDose: 2, dailyFrequency: 3).daysLeft,
        5,
      );
    });

    test('하루치를 채우지 못하는 날은 세지 않고, 복용량이 0이면 null', () {
      expect(_supplement(remaining: 5, dailyDose: 2).daysLeft, 2);
      expect(_supplement(remaining: 1, dailyDose: 2).daysLeft, 0);
      expect(_supplement(remaining: 10, dailyDose: 0).daysLeft, isNull);
    });

    test('소진 예정일은 오늘 + 남은 일수', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(
        _supplement(remaining: 10).runOutDate,
        today.add(const Duration(days: 10)),
      );
    });

    test('7일 이하면 재구매 필요, 3일 이하면 긴급', () {
      final eightDays = _supplement(remaining: 8);
      final sevenDays = _supplement(remaining: 7);
      final threeDays = _supplement(remaining: 6, dailyDose: 2);

      expect(eightDays.isLowStock, isFalse);
      expect(sevenDays.isLowStock, isTrue);
      expect(sevenDays.isCriticalStock, isFalse);
      expect(threeDays.isLowStock, isTrue);
      expect(threeDays.isCriticalStock, isTrue);
    });
  });
}
