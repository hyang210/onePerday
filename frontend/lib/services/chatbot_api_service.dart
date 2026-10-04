import 'package:simcap/core/constant/app_constants.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';

class ChatbotApiResponse {
  final String answer;
  final List<dynamic> products;
  final List<dynamic> filteredProducts;

  const ChatbotApiResponse({
    required this.answer,
    required this.products,
    required this.filteredProducts,
  });

  factory ChatbotApiResponse.fromJson(Map<String, dynamic> json) {
    return ChatbotApiResponse(
      answer: json['answer'] as String? ?? '응답을 생성하지 못했습니다.',
      products: json['products'] as List<dynamic>? ?? const [],
      filteredProducts: json['filteredProducts'] as List<dynamic>? ?? const [],
    );
  }
}

class ChatbotApiService {
  Future<ChatbotApiResponse> sendMessage({
    required String message,
    required Map<String, dynamic> userProfile,
    required List<Supplement> currentSupplements,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConstants.apiBaseUrl}/chatbot/message'),
      headers: AppConstants.headers,
      body: jsonEncode({
        'message': message,
        'userProfile': userProfile,
        'currentSupplements': currentSupplements.map((item) {
          return {
            'id': item.id,
            'name': item.name,
            'brand': item.brand,
            'nutrients': item.nutrients
                .map(
                  (nutrient) => {
                    'name': nutrient.name,
                    'value': nutrient.value,
                    'unit': nutrient.unit,
                  },
                )
                .toList(),
          };
        }).toList(),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('챗봇 응답 생성 실패: ${response.body}');
    }

    return ChatbotApiResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
