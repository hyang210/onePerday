import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:simcap/services/cabinet_api_service.dart';

/// 보관함 영양제를 스토어에서 바로 재구매합니다.
/// 서버에서 같은 상품을 찾아 결제 화면(/store/purchase)으로 이동합니다.
Future<void> startReorder(
  BuildContext context, {
  required String? inventoryId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void showMessage(String message) {
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  if (inventoryId == null) {
    showMessage('서버에 등록되지 않은 영양제라 재구매할 수 없습니다.');
    return;
  }

  try {
    final product = await CabinetApiService().fetchStoreProduct(
      inventoryId: inventoryId,
    );
    if (!context.mounted) return;

    if (product == null) {
      showMessage('스토어에서 판매하지 않는 상품입니다.');
      return;
    }
    if (product.price <= 0) {
      showMessage('가격 정보가 없어 지금은 구매할 수 없는 상품입니다.');
      return;
    }

    context.push('/store/purchase', extra: product);
  } catch (e) {
    debugPrint('재구매 상품 조회 실패: $e');
    showMessage('상품 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
  }
}
