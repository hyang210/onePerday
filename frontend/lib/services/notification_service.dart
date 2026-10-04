import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';
import 'package:simcap/routes/app_router.dart';

// 알림 채널 ID 상수
const _doseChannelId = 'simcap_dose';
const _doseChannelName = '복용 알림';
const _stockChannelId = 'simcap_stock';
const _stockChannelName = '재구매 알림';

// 알림 ID 범위
// 복용 알림: 1000 + supplementIndex (0~999)
// 재구매 알림: 2000 + supplementIndex (0~999)
int _doseNotificationId(int idx) => 1000 + idx;
int _stockNotificationId(int idx) => 2000 + idx;

// 알림 시간 데이터 클래스 (flutter_local_notifications Time 대체)
class _NotifTime {
  final int hour;
  final int minute;
  const _NotifTime(this.hour, this.minute);
}

/// 앱 전역 알림 서비스 싱글톤
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _scheduledDoseCount = 0;
  int _lastStockCount = 0;

  /// 알림 서비스 초기화 완료 여부
  bool get isInitialized => _initialized;

  // 초기화
  Future<void> initialize() async {
    if (_initialized) return;

    // flutter_local_notifications는 Android / iOS / macOS / Linux만 지원
    // Windows에서는 스킵
    if (Platform.isWindows) {
      debugPrint('[NotificationService] Windows 미지원 — 알림 비활성화');
      return;
    }

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final result = await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    if (result != true) {
      debugPrint('[NotificationService] 초기화 실패 — result: $result');
      return;
    }

    await _createChannels();

    // FlutterLocalNotificationsPlatform._instance가 설정될 때까지 polling
    // LateInitializationError가 나지 않을 때까지 반복 (최대 5초)
    final ready = await _waitForPlatformInstance();
    if (!ready) {
      debugPrint('[NotificationService] 플랫폼 인스턴스 대기 시간 초과');
      return;
    }

    _initialized = true;
    debugPrint('[NotificationService] 초기화 완료');
  }

  /// show()가 LateInitializationError 없이 성공할 때까지 polling
  /// 최대 50회 × 100ms = 5초 대기
  Future<bool> _waitForPlatformInstance() async {
    for (int i = 0; i < 50; i++) {
      try {
        await _plugin.show(
          99999,
          null,
          null,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _doseChannelId,
              _doseChannelName,
              importance: Importance.min,
              priority: Priority.min,
              playSound: false,
              enableVibration: false,
              silent: true,
            ),
          ),
        );
        await _plugin.cancel(99999);
        debugPrint('[NotificationService] 플랫폼 준비 완료 (${i + 1}회)');
        return true;
      } catch (e) {
        if (e.toString().contains('LateInitializationError')) {
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          debugPrint('[NotificationService] 예상치 못한 에러: ${e.runtimeType}: $e');
          return false;
        }
      }
    }
    return false;
  }

  Future<void> _createChannels() async {
    const doseChannel = AndroidNotificationChannel(
      _doseChannelId,
      _doseChannelName,
      description: '영양제 복용 시간 알림',
      importance: Importance.high,
    );
    const stockChannel = AndroidNotificationChannel(
      _stockChannelId,
      _stockChannelName,
      description: '재구매 임박 알림',
      importance: Importance.defaultImportance,
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(doseChannel);
    await androidPlugin?.createNotificationChannel(stockChannel);
  }

  // 권한 요청
  Future<bool> requestPermission() async {
    // iOS
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final iosGranted =
        await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        true;

    // Android 13+ (API 33)
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidGranted =
        await android?.requestNotificationsPermission() ?? true;

    return iosGranted && androidGranted;
  }

  // 알림 탭 핸들러
  void _onNotificationTap(NotificationResponse response) {
    final id = response.id ?? -1;
    debugPrint('[NotificationService] 알림 탭: id=$id');
    final context = AppRouter.navigatorKey.currentContext;
    if (context == null) return;
    if (id >= 1000 && id < 2000) {
      context.go('/home');
    } else if (id >= 2000 && id < 3000) {
      // 재구매 알림 → '곧 떨어져요' 카드(재구매 버튼)가 있는 홈
      context.go('/home');
    }
  }

  //  복용 알림

  /// 영양제 목록 전체 복용 알림 재스케줄
  /// 영양제 추가/수정/삭제 시 호출
  Future<void> scheduleAllDoseAlarms(List<Supplement> supplements) async {
    if (!_initialized) return;
    await cancelAllDoseAlarms();
    // remaining > 0인 영양제만 알림 등록
    final active = supplements.where((s) => s.remaining > 0).toList();
    for (int i = 0; i < active.length; i++) {
      await scheduleDoseAlarm(active[i], i);
    }
    _scheduledDoseCount = active.length;
    debugPrint('[NotificationService] 복용 알림 \${active.length}개 등록 (소진 제외)');
  }

  /// 개별 영양제 복용 알림 등록 — alarmTimes 기반 (매일 반복)
  Future<void> scheduleDoseAlarm(Supplement supplement, int index) async {
    // 재고 소진 시 알림 등록 안 함
    if (supplement.remaining <= 0) return;
    // alarmTimes가 있으면 각 시간마다 알림, 없으면 기본값 오전 9시
    final times = supplement.alarmTimes.isNotEmpty
        ? supplement.alarmTimes
              .map((t) => _NotifTime(t.hour, t.minute))
              .toList()
        : [const _NotifTime(9, 0)];

    final androidDetails = AndroidNotificationDetails(
      _doseChannelId,
      _doseChannelName,
      channelDescription: '영양제 복용 시간 알림',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    for (int i = 0; i < times.length; i++) {
      final time = times[i];
      // 알림 ID: 기본 ID + 회차 (최대 10회차)
      final id = _doseNotificationId(index * 10 + i);
      final timeLabel = _formatTime(time);

      await _plugin.zonedSchedule(
        id,
        '💊 ${supplement.name} 복용 시간이에요',
        '$timeLabel 복용을 잊지 마세요!',
        _nextInstanceOf(time.hour, time.minute),
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  String _formatTime(_NotifTime t) {
    final isPm = t.hour >= 12;
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    return '\${isPm ? "오후" : "오전"} \$h:\$m';
  }

  /// 특정 영양제 복용 알림 취소
  Future<void> cancelDoseAlarm(int index) async {
    await _plugin.cancel(_doseNotificationId(index));
  }

  /// 모든 복용 알림 취소
  Future<void> cancelAllDoseAlarms() async {
    if (!_initialized) return;
    // _scheduledDoseCount 범위만 취소 (등록된 수량 추적)
    for (int i = 0; i < _scheduledDoseCount; i++) {
      await _plugin.cancel(_doseNotificationId(i));
    }
    _scheduledDoseCount = 0;
  }

  //  재구매 알림

  /// 영양제 목록 전체 재구매 알림 체크 및 표시
  /// 앱 시작 시 또는 복용 토글 후 호출
  Future<void> checkAndNotifyLowStock(List<Supplement> supplements) async {
    if (!_initialized) return;
    await cancelAllStockAlarms();

    final lowStock = supplements
        .asMap()
        .entries
        .where((e) => e.value.isLowStock)
        .toList();

    for (final entry in lowStock) {
      await _showStockAlarm(entry.value, entry.key);
    }
    _lastStockCount = supplements.length; // 전체 인덱스 범위 커버

    if (lowStock.isNotEmpty) {
      debugPrint('[NotificationService] 재구매 알림 ${lowStock.length}개 표시');
    }
  }

  /// 개별 재구매 임박 알림 즉시 표시
  Future<void> _showStockAlarm(Supplement supplement, int index) async {
    if (!_initialized) return;
    try {
      final isCritical = supplement.isCriticalStock;
      final days = supplement.daysLeft ?? 0;
      final runOut = supplement.runOutDate;
      final runOutText = runOut == null
          ? ''
          : ' (${runOut.month}/${runOut.day} 소진 예정)';

      final androidDetails = AndroidNotificationDetails(
        _stockChannelId,
        _stockChannelName,
        channelDescription: '재구매 임박 알림',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
        color: isCritical ? AppColors.danger : AppColors.warning,
      );
      const iosDetails = DarwinNotificationDetails();

      final title = isCritical
          ? '⚠️ ${supplement.name} 재구매 긴급'
          : '🔔 ${supplement.name} 재구매 필요';
      final daysText = days == 0 ? '오늘 다 떨어져요' : '$days일분 남았어요';
      final body = isCritical
          ? '$daysText$runOutText. 눌러서 바로 재구매하세요!'
          : '$daysText$runOutText. 눌러서 재구매할 수 있어요.';

      await _plugin.show(
        _stockNotificationId(index),
        title,
        body,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
      debugPrint('[NotificationService] 재구매 알림 표시 성공: ${supplement.name}');
    } catch (e, stack) {
      debugPrint(
        '[NotificationService] 재구매 알림 표시 실패 [${supplement.name}]: '
        '${e.runtimeType}: $e\n$stack',
      );
    }
  }

  /// 특정 영양제 재구매 알림 취소
  Future<void> cancelStockAlarm(int index) async {
    await _plugin.cancel(_stockNotificationId(index));
  }

  /// 모든 재구매 알림 취소
  Future<void> cancelAllStockAlarms() async {
    if (!_initialized) return;
    // ID 범위(2000~2999) 직접 취소
    for (int i = 0; i < _lastStockCount; i++) {
      await _plugin.cancel(_stockNotificationId(i));
    }
    _lastStockCount = 0;
  }

  // 모든 알림 취소
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    debugPrint('[NotificationService] 모든 알림 취소');
  }

  /// 오늘 또는 내일 기준으로 가장 가까운 [hour:minute] TZDateTime 반환
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // 이미 지난 시간이면 내일로
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
