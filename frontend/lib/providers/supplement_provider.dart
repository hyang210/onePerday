import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';
import 'package:simcap/services/notification_service.dart';
import 'package:simcap/services/auth_service.dart';
import 'package:simcap/services/cabinet_api_service.dart';

// 복용 기록 모델
// 날짜별로 어떤 영양제를 복용했는지 추적
class DoseRecord {
  final String supplementId; // 고유 ID 기반 식별
  final String supplementName; // 표시용
  final DateTime date;
  final int doseIndex;

  const DoseRecord({
    required this.supplementId,
    required this.supplementName,
    required this.date,
    this.doseIndex = 0,
  });

  Map<String, dynamic> toJson() => {
    'supplementId': supplementId,
    'supplementName': supplementName,
    'date': date.toIso8601String(),
    'doseIndex': doseIndex,
  };

  factory DoseRecord.fromJson(Map<String, dynamic> json) {
    final rawId = json['supplementId']?.toString();
    final rawName = json['supplementName']?.toString() ?? '알 수 없는 영양제';
    final parsedDate = json['date'] != null
        ? (DateTime.tryParse(json['date'].toString()) ?? DateTime.now())
        : DateTime.now();
    final index = int.tryParse(json['doseIndex']?.toString() ?? '') ?? 0;

    // id가 null이거나 'null' 문자열이면 빈 문자열 — 이름 폴백 제거
    // 이름이 같은 영양제 간 기록 혼용 방지
    final safeId = (rawId != null && rawId != 'null' && rawId.isNotEmpty)
        ? rawId
        : '';

    return DoseRecord(
      supplementId: safeId,
      supplementName: rawName,
      date: parsedDate,
      doseIndex: index,
    );
  }
}

// 장바구니 아이템 모델
class CartItem {
  final String productId;
  final String name;
  final String brand;
  final int price;
  int count;
  bool checked;

  CartItem({
    required this.productId,
    required this.name,
    required this.brand,
    required this.price,
    this.count = 1,
    this.checked = true,
  });

  int get totalPrice => price * count;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'name': name,
    'brand': brand,
    'price': price,
    'count': count,
    'checked': checked,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    productId: json['productId'] as String,
    name: json['name'] as String,
    brand: json['brand'] as String,
    price: json['price'] as int,
    count: json['count'] as int? ?? 1,
    checked: json['checked'] as bool? ?? true,
  );

  PurchaseItem toPurchaseItem() =>
      PurchaseItem(name: name, brand: brand, price: price, count: count);
}

// 구매 기록 아이템
class PurchaseItem {
  final String name;
  final String brand;
  final int price;
  final int count;

  const PurchaseItem({
    required this.name,
    required this.brand,
    required this.price,
    required this.count,
  });

  int get totalPrice => price * count;

  Map<String, dynamic> toJson() => {
    'name': name,
    'brand': brand,
    'price': price,
    'count': count,
  };

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
    name: json['name'] as String,
    brand: json['brand'] as String,
    price: json['price'] as int,
    count: json['count'] as int,
  );
}

// 구매 기록 모델
enum PurchaseStatus {
  ordered, // 주문 완료
  shipping, // 배송 중
  delivered, // 배송 완료
  cancelled, // 취소
}

extension PurchaseStatusExtension on PurchaseStatus {
  String get label {
    switch (this) {
      case PurchaseStatus.ordered:
        return '주문 완료';
      case PurchaseStatus.shipping:
        return '배송 중';
      case PurchaseStatus.delivered:
        return '배송 완료';
      case PurchaseStatus.cancelled:
        return '취소됨';
    }
  }

  bool get isActive =>
      this == PurchaseStatus.ordered || this == PurchaseStatus.shipping;
}

class PurchaseRecord {
  final String id;
  final List<PurchaseItem> items;
  final int totalPrice;
  final DateTime orderedAt;
  PurchaseStatus status;

  PurchaseRecord({
    required this.id,
    required this.items,
    required this.totalPrice,
    required this.orderedAt,
    this.status = PurchaseStatus.ordered,
  });

  String get displayTitle {
    if (items.isEmpty) return '상품 없음';
    if (items.length == 1) return items.first.name;
    return '${items.first.name} 외 ${items.length - 1}건';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'items': items.map((i) => i.toJson()).toList(),
    'totalPrice': totalPrice,
    'orderedAt': orderedAt.toIso8601String(),
    'status': status.name,
  };

  factory PurchaseRecord.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'ordered';
    final status = PurchaseStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => PurchaseStatus.ordered,
    );
    return PurchaseRecord(
      id: json['id'] as String,
      items: (json['items'] as List)
          .map((i) => PurchaseItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      totalPrice: json['totalPrice'] as int,
      orderedAt: DateTime.parse(json['orderedAt'] as String),
      status: status,
    );
  }
}

// SupplementProvider — 앱 전역 영양제 상태 관리
// InheritedWidget 기반: 외부 패키지 없이 동작
class SupplementProvider extends InheritedNotifier<SupplementNotifier> {
  const SupplementProvider({
    super.key,
    required SupplementNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// 트리 어디서든 `SupplementProvider.of(context)` 로 접근
  static SupplementNotifier of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<SupplementProvider>();
    assert(provider != null, 'SupplementProvider가 위젯 트리에 없습니다.');
    return provider!.notifier!;
  }
}

// SupplementNotifier — 실제 상태 + 비즈니스 로직
class SupplementNotifier extends ChangeNotifier {
  // SharedPreferences 키
  static const _keySupplements = 'sp_supplements';
  static const _keyDoseHistory = 'sp_dose_history';
  static const _keyCartItems = 'sp_cart_items';
  static const _keyPurchases = 'sp_purchases';

  // 상태 (앱 시작 시 _load()로 초기화)
  List<Supplement> _supplements = [];
  List<DoseRecord> _doseHistory = [];
  List<CartItem> _cartItems = [];
  List<PurchaseRecord> _purchases = [];

  bool _isLoaded = false;

  // ── 저장 / 로드 ──────────────────────────────────────────────────────────

  /// 앱 시작 시 호출 — 저장된 데이터를 SharedPreferences에서 복원
  Future<void> loadFromStorage() async {
    if (_isLoaded) return;
    final prefs = await SharedPreferences.getInstance();

    try {
      // 영양제 목록
      final suppJson = prefs.getString(_keySupplements);
      if (suppJson != null) {
        final list = jsonDecode(suppJson) as List;
        _supplements = list
            .map((e) => Supplement.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 복용 기록
      final doseJson = prefs.getString(_keyDoseHistory);
      if (doseJson != null) {
        final list = jsonDecode(doseJson) as List;
        _doseHistory = list
            .map((e) => DoseRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 장바구니
      final cartJson = prefs.getString(_keyCartItems);
      if (cartJson != null) {
        final list = jsonDecode(cartJson) as List;
        _cartItems = list
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 구매 기록
      final purchaseJson = prefs.getString(_keyPurchases);
      if (purchaseJson != null) {
        final list = jsonDecode(purchaseJson) as List;
        _purchases = list
            .map((e) => PurchaseRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[SupplementNotifier] 데이터 로드 실패: $e');
    }

    _isLoaded = true;
    notifyListeners();
  }

  /// 영양제 목록 저장
  Future<void> _saveSupplements() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keySupplements,
      jsonEncode(_supplements.map((s) => s.toJson()).toList()),
    );
  }

  /// 복용 기록 저장
  Future<void> _saveDoseHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyDoseHistory,
      jsonEncode(_doseHistory.map((d) => d.toJson()).toList()),
    );
  }

  /// 장바구니 저장
  Future<void> _saveCartItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyCartItems,
      jsonEncode(_cartItems.map((c) => c.toJson()).toList()),
    );
  }

  /// 구매 기록 저장
  Future<void> _savePurchases() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyPurchases,
      jsonEncode(_purchases.map((p) => p.toJson()).toList()),
    );
  }

  List<Supplement> get supplements => List.unmodifiable(_supplements);
  List<DoseRecord> get doseHistory => List.unmodifiable(_doseHistory);

  Future<void> loadCabinetFromServer() async {
    final user = AuthService().currentUser;

    if (user == null) {
      debugPrint('[SupplementNotifier] 로그인 사용자 없음: 캐비넷 서버 조회 생략');
      return;
    }
    try {
      final cabinetItems = await CabinetApiService().fetchCabinetItems(
        userUuid: user.id,
      );

      _supplements = cabinetItems.map((item) {
        return Supplement(
          id: item.id,
          supplementId: item.supplementId,
          inventoryId: item.id,
          name: item.productName ?? '알 수 없는 영양제',
          brand: item.brandName ?? '',
          imagePath: item.imageUrl,
          remaining: item.stockCount,
          total: item.totalCount,
          dailyDose: item.dailyDose,
          dailyFrequency: item.dailyFrequency,
          alarmTimes: item.alarmTimes.map(_parseTimeString).toList(),
          nutrients: item.nutrients,
          analysisGuide: '서버에서 불러온 영양제입니다.',
          aiSummary: '분석 데이터 준비 중',
        );
      }).toList();

      NotificationService.instance.scheduleAllDoseAlarms(_supplements);
      NotificationService.instance.checkAndNotifyLowStock(_supplements);

      notifyListeners();
      await _saveSupplements();
    } catch (e) {
      debugPrint('[SupplementNotifier] 서버 캐비넷 조회 실패: $e');
    }
  }

  /// 오늘 복용해야 할 영양제 목록 (전체)
  List<Supplement> get todaySupplements => List.unmodifiable(_supplements);

  /// 구매 기록 목록 (최신순)
  List<PurchaseRecord> get purchases =>
      List.unmodifiable(_purchases.reversed.toList());

  // 복용 여부 조회
  // 오늘 미완료 복용 횟수 (영양제별 전체 회차 기준)
  int get undoneCount {
    int count = 0;
    final today = DateTime.now();
    for (final s in _supplements) {
      if (s.remaining <= 0) continue; // 소진 영양제 제외
      for (int i = 0; i < s.dailyFrequency; i++) {
        if (!isDoneOnIndex(s.id, today, i)) count++;
      }
    }
    return count;
  }

  // 재고가 7정 이하로 남은 영양제 개수
  int get lowStockCount => _supplements.where((s) => s.isLowStock).length;

  // 홈 화면 배지에 표시할 전체 알림 개수
  int get totalNotificationCount => undoneCount + lowStockCount;

  // ── 통계 ─────────────────────────────────────────────────────────────────

  /// 오늘 복용 완료 횟수 (회차 기준)
  int get todayDoneCount {
    if (_supplements.isEmpty) return 0;
    int count = 0;
    final today = DateTime.now();
    for (final s in _supplements) {
      for (int i = 0; i < s.dailyFrequency; i++) {
        if (isDoneOnIndex(s.id, today, i)) count++;
      }
    }
    return count;
  }

  /// 오늘 전체 복용 횟수 (회차 기준)
  int get todayTotalCount {
    if (_supplements.isEmpty) return 0;
    return _supplements.fold(0, (sum, s) => sum + s.dailyFrequency);
  }

  /// 연속 복용 스트릭 (일) — 오늘 포함 연속으로 모든 영양제를 복용한 날 수
  int get currentStreak {
    if (_supplements.isEmpty) return 0;
    int streak = 0;
    final today = _dateOnly(DateTime.now());
    for (int i = 0; i <= 365; i++) {
      final day = today.subtract(Duration(days: i));
      if (isAllDoneOn(day)) {
        streak++;
      } else {
        if (i == 0) continue; // 오늘은 아직 복용 전일 수 있음
        break;
      }
    }
    return streak;
  }

  /// 이번 달 복용률 (0.0 ~ 1.0) — 1일부터 오늘까지 중 완전 복용한 날의 비율
  double get monthlyComplianceRate {
    if (_supplements.isEmpty) return 0.0;
    final now = DateTime.now();
    final daysElapsed = now.day;
    if (daysElapsed == 0) return 0.0;
    int doneDays = 0;
    for (int i = 1; i <= daysElapsed; i++) {
      if (isAllDoneOn(DateTime(now.year, now.month, i))) doneDays++;
    }
    return doneDays / daysElapsed;
  }

  /// 총 완전 복용 일수 (누적)
  int get totalDoneDays {
    if (_doseHistory.isEmpty) return 0;
    final uniqueDates = _doseHistory.map((r) => _dateOnly(r.date)).toSet();
    return uniqueDates.where((day) => isAllDoneOn(day)).length;
  }

  /// 역대 최장 연속 복용 일수
  int get bestStreak {
    if (_supplements.isEmpty || _doseHistory.isEmpty) return 0;
    final doneDays =
        _doseHistory
            .map((r) => _dateOnly(r.date))
            .toSet()
            .where((day) => isAllDoneOn(day))
            .toList()
          ..sort();
    if (doneDays.isEmpty) return 0;
    int best = 1, current = 1;
    for (int i = 1; i < doneDays.length; i++) {
      if (doneDays[i].difference(doneDays[i - 1]).inDays == 1) {
        current++;
        if (current > best) best = current;
      } else {
        current = 1;
      }
    }
    return best;
  }

  /// 특정 날짜에 해당 영양제를 복용했는지 여부
  /// 특정 날짜 + 인덱스 복용 여부
  bool isDoneOnIndex(String? supplementId, DateTime date, int doseIndex) {
    if (supplementId == null || supplementId == 'null') return false;
    final day = _dateOnly(date);
    return _doseHistory.any((r) {
      if (r.supplementId == 'null') return false;
      return r.supplementId == supplementId &&
          _dateOnly(r.date) == day &&
          r.doseIndex == doseIndex;
    });
  }

  /// 단일 복용(dailyFrequency <= 1) 전용 체크
  /// 다회 복용은 isDoneOnIndex 사용
  bool isDoneOn(String? supplementId, DateTime date) {
    if (supplementId == null || supplementId == 'null') return false;
    final day = _dateOnly(date);
    final supplement = _supplements.firstWhere(
      (s) => s.id == supplementId,
      orElse: () =>
          _supplements.isNotEmpty ? _supplements.first : _supplements.first,
    );
    // 다회 복용인 경우 모든 회차 완료 여부 반환
    if (supplement.dailyFrequency > 1) {
      for (int i = 0; i < supplement.dailyFrequency; i++) {
        if (!isDoneOnIndex(supplementId, date, i)) return false;
      }
      return true;
    }
    return _doseHistory.any((r) {
      if (r.supplementId == 'null') return false;
      return r.supplementId == supplementId && _dateOnly(r.date) == day;
    });
  }

  /// 오늘 해당 영양제를 복용했는지 여부
  bool isDoneToday(String supplementId) =>
      isDoneOn(supplementId, DateTime.now());

  /// 특정 날짜에 복용 기록이 하나라도 있는지 여부 (캘린더 도트용)
  bool hasDoseRecordOn(DateTime date) {
    final day = _dateOnly(date);
    return _doseHistory.any((r) => _dateOnly(r.date) == day);
  }

  /// 특정 날짜에 모든 영양제의 모든 회차를 완료했는지 여부
  bool isAllDoneOn(DateTime date) {
    if (_supplements.isEmpty) return false;
    return _supplements.every((s) {
      for (int i = 0; i < s.dailyFrequency; i++) {
        if (!isDoneOnIndex(s.id, date, i)) return false;
      }
      return true;
    });
  }

  /// 특정 인덱스 복용 토글 (다회 복용용)
  void toggleDoseIndex(String supplementId, int doseIndex, {DateTime? date}) {
    final targetDate = date ?? DateTime.now();
    final idx = _supplements.indexWhere((s) => s.id == supplementId);
    if (idx == -1) return;

    final supplement = _supplements[idx];
    final alreadyDone = isDoneOnIndex(supplementId, targetDate, doseIndex);

    if (alreadyDone) {
      _doseHistory.removeWhere(
        (r) =>
            r.supplementId == supplementId &&
            _dateOnly(r.date) == _dateOnly(targetDate) &&
            r.doseIndex == doseIndex,
      );
      // 오늘 체크해서 0이 된 경우도 복구 (잘못 체크한 경우 대비 방지)
      final freq = supplement.dailyFrequency > 0
          ? supplement.dailyFrequency
          : 1;
      final dosePerTime = (supplement.dailyDose / freq).ceil();
      _supplements[idx] = supplement.copyWith(
        remaining: (supplement.remaining + dosePerTime).clamp(
          0,
          supplement.total == 0 ? 9999 : supplement.total,
        ),
      );
    } else {
      _doseHistory.add(
        DoseRecord(
          supplementId: supplementId,
          supplementName: supplement.name,
          date: targetDate,
          doseIndex: doseIndex,
        ),
      );
      final freq = supplement.dailyFrequency > 0
          ? supplement.dailyFrequency
          : 1;
      final dosePerTime = (supplement.dailyDose / freq).ceil();
      final newRemaining = (supplement.remaining - dosePerTime).clamp(
        0,
        supplement.total,
      );
      _supplements[idx] = supplement.copyWith(remaining: newRemaining);
    }

    _saveDoseHistory();
    notifyListeners();
  }

  /// 복용 체크/해제 토글.
  /// - 체크 시: 복용 기록 추가 + remaining -= dailyDose
  /// - 해제 시: 복용 기록 삭제 + remaining += dailyDose (되돌리기)
  void toggleDose(String supplementId, {DateTime? date}) {
    final targetDate = date ?? DateTime.now();
    final idx = _supplements.indexWhere((s) => s.id == supplementId);
    if (idx == -1) return;

    final supplement = _supplements[idx];
    final alreadyDone = isDoneOn(supplementId, targetDate);

    if (alreadyDone) {
      // 복용 해제: 기록 삭제 + remaining 복구
      // 오늘 체크해서 0이 된 경우도 복구 (잘못 체크한 경우 대비)
      _doseHistory.removeWhere(
        (r) =>
            r.supplementId == supplementId &&
            _dateOnly(r.date) == _dateOnly(targetDate),
      );
      _supplements[idx] = supplement.copyWith(
        remaining: (supplement.remaining + supplement.dailyDose).clamp(
          0,
          supplement.total == 0 ? 9999 : supplement.total,
        ),
      );
    } else {
      // 복용 완료: 기록 추가 + remaining 차감
      _doseHistory.add(
        DoseRecord(
          supplementId: supplementId,
          supplementName: supplement.name,
          date: targetDate,
        ),
      );
      final newRemaining = (supplement.remaining - supplement.dailyDose).clamp(
        0,
        supplement.total,
      );
      _supplements[idx] = supplement.copyWith(remaining: newRemaining);
    }

    notifyListeners();
    _saveSupplements();
    _saveDoseHistory();

    // 복용 후 재고 임박 여부 재확인 → 알림 트리거
    NotificationService.instance.checkAndNotifyLowStock(_supplements);
  }

  // 캐비닛 CRUD

  Future<Supplement> addSupplement(
    Supplement supplement, {
    String? backendSupplementId,
  }) async {
    _supplements.add(supplement);

    NotificationService.instance.scheduleAllDoseAlarms(_supplements);
    NotificationService.instance.checkAndNotifyLowStock(_supplements);

    notifyListeners();
    await _saveSupplements();

    return supplement;
  }

  void updateSupplement(int index, Supplement updated) {
    if (index < 0 || index >= _supplements.length) return;
    _supplements[index] = updated;
    // 복용 시점이 바뀔 수 있으므로 복용 알림 재스케줄
    NotificationService.instance.scheduleAllDoseAlarms(_supplements);
    NotificationService.instance.checkAndNotifyLowStock(_supplements);
    notifyListeners();
    _saveSupplements();
  }

  Future<void> removeSupplement(String id) async {
    _supplements.removeWhere((s) => s.id == id);
    _doseHistory.removeWhere((r) => r.supplementId == id);
    NotificationService.instance.scheduleAllDoseAlarms(_supplements);
    notifyListeners();
    await _saveSupplements();
    await _saveDoseHistory();

    try {
      await CabinetApiService().deleteCabinetItem(inventoryId: id);
      debugPrint('[SupplementNotifier] 서버 캐비넷 삭제 성공: $id');
    } catch (e) {
      debugPrint('[SupplementNotifier] 서버 캐비넷 삭제 실패: $e');
    }
  }

  // ── 구매 기록 CRUD ────────────────────────────────────────────────────

  // ── 장바구니 상태 ─────────────────────────────────────────────────────

  /// 장바구니 아이템 목록 (불변)
  List<CartItem> get cartItems => List.unmodifiable(_cartItems);

  /// 선택된 아이템 수
  int get cartCheckedCount => _cartItems.where((i) => i.checked).length;

  /// 선택된 아이템 총액
  int get cartTotalPrice => _cartItems
      .where((i) => i.checked)
      .fold(0, (sum, i) => sum + i.totalPrice);

  /// 이미 장바구니에 있는지 여부 (productId 기준)
  bool isInCart(String productId) =>
      _cartItems.any((i) => i.productId == productId);

  /// 장바구니에 추가. 이미 있으면 수량만 +1
  void addToCart(CartItem item) {
    final idx = _cartItems.indexWhere((i) => i.productId == item.productId);
    if (idx != -1) {
      _cartItems[idx].count++;
    } else {
      _cartItems.add(item);
    }
    notifyListeners();
    _saveCartItems();
  }

  /// 장바구니에서 제거 (productId 기준)
  void removeFromCart(String productId) {
    _cartItems.removeWhere((i) => i.productId == productId);
    notifyListeners();
    _saveCartItems();
  }

  /// 수량 변경 (0 이하면 자동 제거)
  void updateCartCount(String productId, int delta) {
    final idx = _cartItems.indexWhere((i) => i.productId == productId);
    if (idx == -1) return;
    final newCount = _cartItems[idx].count + delta;
    if (newCount <= 0) {
      _cartItems.removeAt(idx);
    } else {
      _cartItems[idx].count = newCount;
    }
    notifyListeners();
    _saveCartItems();
  }

  /// 선택 토글 (체크박스)
  void toggleCartChecked(String productId) {
    final idx = _cartItems.indexWhere((i) => i.productId == productId);
    if (idx == -1) return;
    _cartItems[idx].checked = !_cartItems[idx].checked;
    notifyListeners();
  }

  /// 전체 선택 / 해제
  void setAllCartChecked(bool checked) {
    for (final item in _cartItems) {
      item.checked = checked;
    }
    notifyListeners();
  }

  /// 주문 완료 후 선택된 항목 장바구니에서 제거
  void clearCheckedCartItems() {
    _cartItems.removeWhere((i) => i.checked);
    notifyListeners();
    _saveCartItems();
  }

  /// 장바구니 전체 비우기
  void clearCart() {
    _cartItems.clear();
    notifyListeners();
    _saveCartItems();
  }

  /// 장바구니 아이템으로 구매 기록 생성 및 저장
  /// basket_screen의 "주문하기" 버튼에서 호출
  PurchaseRecord addPurchase(List<PurchaseItem> items) {
    final record = PurchaseRecord(
      id: 'ORD-${DateTime.now().millisecondsSinceEpoch}',
      items: items,
      totalPrice: items.fold(0, (sum, i) => sum + i.totalPrice),
      orderedAt: DateTime.now(),
      status: PurchaseStatus.ordered,
    );
    _purchases.add(record);
    notifyListeners();
    _savePurchases();
    return record;
  }

  /// 구매 상태 업데이트 (백엔드 연동 후 폴링/웹소켓으로 교체)
  void updatePurchaseStatus(String orderId, PurchaseStatus status) {
    final idx = _purchases.indexWhere((p) => p.id == orderId);
    if (idx == -1) return;
    _purchases[idx].status = status;
    notifyListeners();
    _savePurchases();
  }

  TimeOfDay _parseTimeString(String value) {
    final parts = value.split(':');

    if (parts.length < 2) {
      return const TimeOfDay(hour: 9, minute: 0);
    }

    final hour = int.tryParse(parts[0]) ?? 9;
    final minute = int.tryParse(parts[1]) ?? 0;

    return TimeOfDay(hour: hour, minute: minute);
  }

  /// 시간을 제거하고 날짜만 반환 (날짜 비교용)
  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// 로그아웃 시 메모리 상태 전체 초기화
  void clearAll() {
    _supplements.clear();
    _doseHistory.clear();
    _cartItems.clear();
    _purchases.clear();
    _isLoaded = false;
    notifyListeners();
  }
}
