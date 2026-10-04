import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';

class CabinetApiService {
  Future<CabinetItem> createCabinetItem({
    required String userUuid,
    required int supplementId,
    required int dailyDose,
    required int dailyFrequency,
    required int stockCount,
    required int totalCount,
    required List<String> alarmTimes,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/cabinet'),
      headers: AppConstants.headers,
      body: jsonEncode({
        'userUuid': userUuid,
        'supplementId': supplementId,
        'dailyDose': dailyDose,
        'dailyFrequency': dailyFrequency,
        'stockCount': stockCount,
        'totalCount': totalCount,
        'alarmTimes': alarmTimes,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('캐비넷 서버 저장 실패: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'];

    if (data is! Map<String, dynamic>) {
      throw Exception('캐비넷 서버 응답 형식 오류: ${response.body}');
    }

    return CabinetItem.fromJson(data);
  }

  Future<List<CabinetItem>> fetchCabinetItems({
    required String userUuid,
  }) async {
    final response = await http.get(
      Uri.parse('${AppConstants.apiBaseUrl}/cabinet/$userUuid'),
      headers: AppConstants.headers,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('캐비넷 서버 조회 실패: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as List<dynamic>? ?? [];

    return data
        .map((e) => CabinetItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateCabinetItem({
    required String inventoryId,
    required int dailyDose,
    required int dailyFrequency,
    required int stockCount,
    required int totalCount,
    required List<String> alarmTimes,
  }) async {
    final response = await http.patch(
      Uri.parse('${AppConstants.apiBaseUrl}/cabinet/$inventoryId'),
      headers: AppConstants.headers,
      body: jsonEncode({
        'dailyDose': dailyDose,
        'dailyFrequency': dailyFrequency,
        'stockCount': stockCount,
        'totalCount': totalCount,
        'alarmTimes': alarmTimes,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('캐비넷 서버 수정 실패: ${response.body}');
    }
  }

  Future<void> deleteCabinetItem({required String inventoryId}) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.apiBaseUrl}/cabinet/$inventoryId'),
      headers: AppConstants.headers,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('캐비넷 서버 삭제 실패: ${response.body}');
    }
  }
}

class CabinetItem {
  final String id;
  final String userUuid;
  final String supplementId;
  final int dailyDose;
  final int dailyFrequency;
  final int stockCount;
  final int totalCount;
  final List<String> alarmTimes;
  final String status;
  final String? productName;
  final String? brandName;
  final String? imageUrl;
  final List<Nutrient> nutrients;

  CabinetItem({
    required this.id,
    required this.userUuid,
    required this.supplementId,
    required this.dailyDose,
    required this.dailyFrequency,
    required this.stockCount,
    required this.totalCount,
    required this.alarmTimes,
    required this.status,
    required this.productName,
    required this.brandName,
    required this.imageUrl,
    required this.nutrients,
  });

  factory CabinetItem.fromJson(Map<String, dynamic> json) {
    final supplement = json['supplements'] as Map<String, dynamic>?;
    final ingredientsList = supplement?['ingredients'] as List<dynamic>? ?? [];

    return CabinetItem(
      id: json['id']?.toString() ?? '',
      userUuid: json['user_uuid']?.toString() ?? '',
      supplementId: json['supplement_id']?.toString() ?? '',
      dailyDose: int.tryParse(json['daily_dose']?.toString() ?? '') ?? 1,
      dailyFrequency:
          int.tryParse(json['daily_frequency']?.toString() ?? '') ?? 1,
      stockCount: int.tryParse(json['stock_count']?.toString() ?? '') ?? 0,
      totalCount: int.tryParse(json['total_count']?.toString() ?? '') ?? 0,
      alarmTimes: (json['alarm_times'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      status: json['status']?.toString() ?? 'active',
      productName: supplement?['product_name']?.toString(),
      brandName: supplement?['brand_name']?.toString(),
      imageUrl: supplement?['image_url']?.toString(),
      nutrients: ingredientsList
          .map((e) {
            final map = e as Map<String, dynamic>;
            return Nutrient(
              name: map['ingredient_name']?.toString() ?? '',
              value: double.tryParse(map['amount']?.toString() ?? '') ?? 0.0,
              unit: map['unit']?.toString() ?? '',
              percent: double.tryParse(map['dailyPercent']?.toString() ?? '') ?? 0.0,
            );
          })
          .where((n) => n.name.trim().isNotEmpty)
          .toList(),
    );
  }
}
