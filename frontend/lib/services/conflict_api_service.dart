import 'package:simcap/core/constant/app_constants.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ConflictApiService {
  static String get baseUrl => AppConstants.apiBaseUrl;

  Future<List<ConflictCheckResult>> checkConflictsBySupplementIds({
    required List<int> supplementIds,
    List<Map<String, dynamic>>? cabinetSupplements,
    List<String>? userHealth,
    List<String>? userAllergies,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/conflict/check-safety'),
      headers: AppConstants.headers,
      body: jsonEncode({
        'supplementIds': supplementIds,
        if (cabinetSupplements != null)
          'cabinetSupplements': cabinetSupplements,
        if (userHealth != null) 'userHealth': userHealth,
        if (userAllergies != null) 'userAllergies': userAllergies,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('병용금기 검사 실패: ${response.body}');
    }

    final decoded = jsonDecode(response.body);

    // 백엔드는 충돌하는 영양제가 없을 때 { message: "충돌하는 영양제가 없음." } 형태의 Map을 반환함
    if (decoded is Map<String, dynamic>) {
      return [];
    }

    final results = decoded as List<dynamic>? ?? [];
    return results
        .map((e) => ConflictCheckResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class ConflictCheckResult {
  final List<String> conflicts;
  final String reason;
  final List<String> conflictingIngredients;

  ConflictCheckResult({
    required this.conflicts,
    required this.reason,
    required this.conflictingIngredients,
  });

  factory ConflictCheckResult.fromJson(Map<String, dynamic> json) {
    return ConflictCheckResult(
      conflicts: List<String>.from(json['conflicts'] ?? []),
      reason: json['reason'] ?? '',
      conflictingIngredients: List<String>.from(
        json['conflictingIngredients'] ?? [],
      ),
    );
  }
}
