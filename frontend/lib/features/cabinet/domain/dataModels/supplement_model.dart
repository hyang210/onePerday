import 'package:flutter/material.dart';
import 'package:simcap/core/constant/app_constants.dart';

class Nutrient {
  final String name;
  final double value;
  final String unit;
  final double percent;

  Nutrient({
    required this.name,
    required this.value,
    required this.unit,
    required this.percent,
  });

  factory Nutrient.fromJson(Map<String, dynamic> json) {
    return Nutrient(
      name: json['name'] ?? '',
      value: (json['value'] ?? 0).toDouble(),
      unit: json['unit'] ?? '',
      percent: (json['percent'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'unit': unit,
    'percent': percent,
  };
}

class Supplement {
  final String id; // 프론트 로컬 ID
  final String? supplementId; // 서버 supplements.id
  final String? inventoryId; // 서버 supplement_inventory.id
  final String name;
  final String brand;

  /// 로컬 asset 경로 (기기에 저장된 이미지).
  /// imageUrl과 함께 쓸 경우 imageUrl을 우선 사용하세요.
  final String? imagePath;

  /// 서버/CDN 이미지 URL. null이면 imagePath 또는 기본 아이콘 사용.
  final String? imageUrl;

  final int remaining;
  final int total;

  /// 하루 복용량 (정 수). 기본값 1.
  final int dailyDose;

  /// 하루 복용 횟수. 기본값 1.
  final int dailyFrequency;

  final List<Nutrient> nutrients;
  final String analysisGuide;
  final String aiSummary;

  /// 사용자 지정 알림 시간 목록 (dailyFrequency에 맞게 설정)
  final List<TimeOfDay> alarmTimes;

  /// 하루에 먹는 개수 (1회 복용량 × 하루 횟수)
  int get dailyUsage => dailyDose * dailyFrequency;

  /// 남은 개수로 며칠 더 먹을 수 있는지. 하루치를 못 채우는 날은 세지 않습니다.
  /// 복용량 정보가 없으면 null. (백엔드 calcDaysLeft와 같은 계산)
  int? get daysLeft {
    if (dailyUsage <= 0) return null;
    return (remaining < 0 ? 0 : remaining) ~/ dailyUsage;
  }

  /// 소진 예정일 (오늘 + 남은 일수)
  DateTime? get runOutDate {
    final days = daysLeft;
    if (days == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: days));
  }

  /// 재구매가 필요한 상태 (남은 일수가 AppConstants.lowStockDays 이하)
  bool get isLowStock {
    final days = daysLeft;
    return days != null && days <= AppConstants.lowStockDays;
  }

  /// 긴급 재구매 상태 (남은 일수가 AppConstants.criticalStockDays 이하)
  bool get isCriticalStock {
    final days = daysLeft;
    return days != null && days <= AppConstants.criticalStockDays;
  }

  Supplement({
    String? id,
    this.supplementId,
    this.inventoryId,
    required this.name,
    required this.brand,
    this.imagePath,
    this.imageUrl,
    required this.remaining,
    required this.total,
    this.dailyDose = 1,
    this.dailyFrequency = 1,
    required this.nutrients,
    this.analysisGuide = '이 영양제는 정해진 시간에 복용하는 것이 좋습니다.',
    this.aiSummary = '리뷰를 분석 중입니다.',
    this.alarmTimes = const [],
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  /// 오늘부터 소진까지 남은 일수. dailyDose <= 0이면 null.
  int? get daysUntilEmpty {
    if (dailyDose <= 0) return null;
    return (remaining / dailyDose).ceil();
  }

  /// 소진 예정 날짜 (오늘 + daysUntilEmpty).
  DateTime? get emptyDate {
    final days = daysUntilEmpty;
    if (days == null) return null;
    return DateTime.now().add(Duration(days: days));
  }

  /// 표시할 이미지 소스. imageUrl -> imagePath 순서로 우선 적용.
  String? get displayImage => imageUrl ?? imagePath;

  factory Supplement.fromJson(Map<String, dynamic> json) {
    return Supplement(
      id: json['id'] as String?,
      supplementId: json['supplementId']?.toString(),
      inventoryId: json['inventoryId']?.toString(),
      name: json['name'] ?? '',
      brand: json['brand'] ?? '',
      imagePath: json['imagePath'] as String?,
      imageUrl: json['imageUrl'] as String?,
      remaining: json['remaining'] ?? 0,
      total: json['total'] ?? 0,
      dailyDose: json['dailyDose'] ?? 1,
      dailyFrequency: json['dailyFrequency'] ?? 1,
      nutrients: (json['nutrients'] as List? ?? [])
          .map((n) => Nutrient.fromJson(n as Map<String, dynamic>))
          .toList(),
      analysisGuide: json['analysisGuide'] ?? '이 영양제는 복합 성분 설계로 흡수율을 높였습니다.',
      aiSummary: json['aiSummary'] ?? '리뷰를 분석 중입니다.',
      alarmTimes: (json['alarmTimes'] as List? ?? []).map((t) {
        final parts = (t as String).split(':');
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (supplementId != null) 'supplementId': supplementId,
    if (inventoryId != null) 'inventoryId': inventoryId,
    'name': name,
    'brand': brand,
    if (imagePath != null) 'imagePath': imagePath,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'remaining': remaining,
    'total': total,
    'dailyDose': dailyDose,
    'dailyFrequency': dailyFrequency,
    'nutrients': nutrients.map((n) => n.toJson()).toList(),
    'analysisGuide': analysisGuide,
    'aiSummary': aiSummary,
    'alarmTimes': alarmTimes.map((t) => '${t.hour}:${t.minute}').toList(),
  };

  Supplement copyWith({
    String? id,
    String? supplementId,
    String? inventoryId,
    String? name,
    String? brand,
    String? imagePath,
    String? imageUrl,
    int? remaining,
    int? total,
    int? dailyDose,
    int? dailyFrequency,
    List<Nutrient>? nutrients,
    String? analysisGuide,
    String? aiSummary,
    List<TimeOfDay>? alarmTimes,
  }) {
    return Supplement(
      id: id ?? this.id,
      supplementId: supplementId ?? this.supplementId,
      inventoryId: inventoryId ?? this.inventoryId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      imagePath: imagePath ?? this.imagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      remaining: remaining ?? this.remaining,
      total: total ?? this.total,
      dailyDose: dailyDose ?? this.dailyDose,
      dailyFrequency: dailyFrequency ?? this.dailyFrequency,
      nutrients: nutrients ?? this.nutrients,
      analysisGuide: analysisGuide ?? this.analysisGuide,
      alarmTimes: alarmTimes ?? this.alarmTimes,
      aiSummary: aiSummary ?? this.aiSummary,
    );
  }
}
