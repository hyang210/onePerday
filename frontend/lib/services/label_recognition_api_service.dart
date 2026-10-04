import 'package:simcap/core/constant/app_constants.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class LabelRecognitionResult {
  final String ocrText;
  final StructuredLabel structured;
  final SupplementMatch? match;
  final double? yoloConfidence;

  const LabelRecognitionResult({
    required this.ocrText,
    required this.structured,
    required this.match,
    required this.yoloConfidence,
  });

  factory LabelRecognitionResult.fromJson(Map<String, dynamic> json) {
    final matchJson = json['match'] as Map<String, dynamic>?;
    final data = matchJson?['data'] as Map<String, dynamic>?;
    final yolo = json['yolo'] as Map<String, dynamic>?;

    return LabelRecognitionResult(
      ocrText: json['ocrText'] as String? ?? '',
      structured: StructuredLabel.fromJson(
        json['structured'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
      match: data == null ? null : SupplementMatch.fromJson(data, matchJson),
      yoloConfidence: (yolo?['confidence'] as num?)?.toDouble(),
    );
  }

  /// DB 매칭 결과를 신뢰할 수 있는 최소 confidence
  static const double minMatchConfidence = 0.7;

  /// 신뢰할 수 있는 DB 매칭 결과 (없으면 null)
  SupplementMatch? get confidentMatch =>
      match != null && match!.confidence >= minMatchConfidence ? match : null;

  String get productName {
    final name = confidentMatch?.productName ?? structured.productName;
    return name.isNotEmpty ? name : '알 수 없는 영양제';
  }

  String get brandName {
    final brand = confidentMatch?.brandName ?? '';
    if (brand.isNotEmpty) return brand;
    return structured.brandName.isNotEmpty
        ? structured.brandName
        : '알 수 없는 브랜드';
  }

  String? get imageUrl => confidentMatch?.imageUrl;

  String? get supplementId {
    final id = confidentMatch?.id;
    return id == null || id.isEmpty ? null : id;
  }

  /// 성분 이름 목록 (DB 매칭 성분 우선, 없으면 라벨에서 추출한 성분)
  List<String> get nutrientNames {
    final fromDb = confidentMatch?.ingredients
            .map((item) => item.name)
            .where((name) => name.isNotEmpty)
            .toList() ??
        const <String>[];
    if (fromDb.isNotEmpty) return fromDb;
    return structured.nutrients
        .map((item) => item.name)
        .where((name) => name.isNotEmpty)
        .toList();
  }
}

class StructuredLabel {
  final String productName;
  final String brandName;
  final List<StructuredNutrient> nutrients;

  const StructuredLabel({
    required this.productName,
    required this.brandName,
    required this.nutrients,
  });

  factory StructuredLabel.fromJson(Map<String, dynamic> json) {
    return StructuredLabel(
      productName: json['productName'] as String? ?? '',
      brandName: json['brandName'] as String? ?? '',
      nutrients: (json['nutrients'] as List<dynamic>? ?? const [])
          .map((item) => StructuredNutrient.fromJson(item))
          .toList(),
    );
  }
}

class StructuredNutrient {
  final String name;
  final double? amount;
  final String unit;

  const StructuredNutrient({
    required this.name,
    required this.amount,
    required this.unit,
  });

  factory StructuredNutrient.fromJson(dynamic json) {
    final data = json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    return StructuredNutrient(
      name: data['name'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble(),
      unit: data['unit'] as String? ?? '',
    );
  }
}

class SupplementMatch {
  final String id;
  final String productName;
  final String brandName;
  final String? imageUrl;
  final int? price;
  final double confidence;
  final List<MatchedIngredient> ingredients;

  const SupplementMatch({
    required this.id,
    required this.productName,
    required this.brandName,
    required this.imageUrl,
    required this.price,
    required this.confidence,
    required this.ingredients,
  });

  factory SupplementMatch.fromJson(
    Map<String, dynamic> json,
    Map<String, dynamic>? matchJson,
  ) {
    final rawIngredients =
        json['supplements_ingredients'] ?? json['ingredients'];
    return SupplementMatch(
      id: json['id']?.toString() ?? '',
      productName: json['product_name'] as String? ?? '',
      brandName: json['brand_name'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      price: int.tryParse(json['price']?.toString() ?? ''),
      confidence: (matchJson?['confidence'] as num?)?.toDouble() ?? 0,
      ingredients: (rawIngredients as List<dynamic>? ?? const [])
          .map((item) => MatchedIngredient.fromJson(item))
          .toList(),
    );
  }
}

class MatchedIngredient {
  final String name;
  final double? amount;
  final String unit;

  const MatchedIngredient({
    required this.name,
    required this.amount,
    required this.unit,
  });

  factory MatchedIngredient.fromJson(dynamic json) {
    if (json is String) {
      return MatchedIngredient(name: json, amount: null, unit: '');
    }
    final data = json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    return MatchedIngredient(
      name: (data['ingredient_name'] ?? data['name'] ?? '').toString(),
      amount:
          (data['amount'] as num?)?.toDouble() ??
          (data['value'] as num?)?.toDouble(),
      unit: (data['unit'] ?? '').toString(),
    );
  }
}

class LabelRecognitionApiService {
  Future<LabelRecognitionResult> analyze(File imageFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConstants.apiBaseUrl}/label-recognition/analyze'),
    );
    request.headers.addAll(AppConstants.headers);
    request.files.add(
      await http.MultipartFile.fromPath('image', imageFile.path),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        '라벨 인식 실패 (${response.statusCode}): ${utf8.decode(response.bodyBytes)}',
      );
    }

    return LabelRecognitionResult.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }
}
