import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:portone_flutter/v1.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/providers/supplement_provider.dart';
import 'package:simcap/routes/app_router.dart';
import 'package:simcap/features/store/presentation/supplement_detail_screen.dart';
import 'package:simcap/features/store/data/store_product_data.dart';

class PurchaseScreen extends StatefulWidget {
  final StoreProduct? product;
  final List<CartItem>? cartItems;

  const PurchaseScreen({super.key, this.product, this.cartItems});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  // 배송지
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _addressDetailController = TextEditingController();

  // 결제수단
  String _selectedPayment = 'card';
  final List<Map<String, dynamic>> _paymentMethods = [
    {'id': 'card', 'label': '신용/체크카드', 'icon': Icons.credit_card_rounded},
    {'id': 'kakao', 'label': '카카오페이', 'icon': Icons.chat_bubble_rounded},
    {'id': 'toss', 'label': '토스페이', 'icon': Icons.payment_rounded},
    {
      'id': 'naver',
      'label': '네이버페이',
      'icon': Icons.account_balance_wallet_rounded,
    },
  ];

  // 배송 요청사항
  String _selectedRequest = '문 앞에 놓아주세요';
  final List<String> _requestOptions = [
    '문 앞에 놓아주세요',
    '경비실에 맡겨주세요',
    '직접 받겠습니다',
    '배송 전 연락 바랍니다',
    '직접 입력',
  ];
  final _customRequestController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _addressDetailController.dispose();
    _customRequestController.dispose();
    super.dispose();
  }

  int get _totalPrice {
    if (widget.product != null) {
      return widget.product!.price;
    }
    if (widget.cartItems != null) {
      return widget.cartItems!.fold(0, (sum, i) => sum + i.totalPrice);
    }
    return 0;
  }

  String get _displayProductName {
    if (widget.product != null) {
      return widget.product!.name;
    }
    if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
      return widget.cartItems!.length == 1
          ? widget.cartItems!.first.name
          : '${widget.cartItems!.first.name} 외 ${widget.cartItems!.length - 1}건';
    }
    return '';
  }

  List<PurchaseItem> get _purchaseItems {
    if (widget.product != null) {
      return [
        PurchaseItem(
          name: widget.product!.name,
          brand: widget.product!.brand,
          price: widget.product!.price,
          count: 1,
        )
      ];
    }
    if (widget.cartItems != null) {
      return widget.cartItems!.map((i) => i.toPurchaseItem()).toList();
    }
    return [];
  }

  String? _getItemImageUrl(String name) {
    final matched = allProducts.where((p) => p.name == name).toList();
    if (matched.isNotEmpty) {
      return matched.first.imageUrl;
    }
    return null;
  }

  Widget _buildOrderItemRow(PurchaseItem item) {
    final imageUrl = _getItemImageUrl(item.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.hardEdge,
            child: imageUrl != null && imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.medication_rounded,
                      color: AppColors.primary,
                      size: 30,
                    ),
                  )
                : const Icon(
                    Icons.medication_rounded,
                    color: AppColors.primary,
                    size: 30,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.brand} · ${item.count}개',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatPrice(item.price * item.count)}원',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(int price) {
    return price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  /// 결제한 상품 목록. 서버가 DB 가격으로 결제 금액을 다시 계산합니다.
  List<Map<String, dynamic>> get _paymentItems {
    if (widget.product != null) {
      return [
        {'productId': widget.product!.id, 'count': 1},
      ];
    }
    return (widget.cartItems ?? [])
        .map((i) => {'productId': i.productId, 'count': i.count})
        .toList();
  }

  /// 서버에서 결제를 검증합니다. 성공하면 null, 실패하면 사용자에게 보여줄 메시지.
  Future<String?> _verifyPayment({
    required String impUid,
    required String merchantUid,
  }) async {
    try {
      final url = Uri.parse('${AppConstants.apiBaseUrl}/api/payment/verify');
      final response = await http
          .post(
            url,
            headers: AppConstants.headers,
            body: jsonEncode({
              'impUid': impUid,
              'merchantUid': merchantUid,
              'items': _paymentItems,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null;
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final message = body is Map ? body['message'] : null;
      return message is String ? message : '결제 검증에 실패했습니다.';
    } catch (e) {
      debugPrint('결제 검증 오류: $e');
      return '결제 검증 중 오류가 발생했습니다. 고객센터에 문의해주세요.';
    }
  }

  void _onPurchase() {
    // 선택된 결제수단에 따라 PG 코드 설정
    String pg;
    String payMethod;
    switch (_selectedPayment) {
      case 'kakao':
        pg = 'kakaopay.TC0ONETIME';
        payMethod = 'kakaopay';
        break;
      case 'toss':
        pg = 'tosspay.tosstest';
        payMethod = 'tosspay';
        break;
      default:
        pg = 'html5_inicis.INIpayTest';
        payMethod = 'card';
    }

    final merchantUid = 'order_${DateTime.now().millisecondsSinceEpoch}';
    final buyerName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : '구매자';
    final buyerTel = _phoneController.text.trim().isNotEmpty
        ? _phoneController.text.trim()
        : '010-0000-0000';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IamportPayment(
          appBar: AppBar(
            title: const Text('결제'),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
          ),
          initialChild: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text('결제창 로딩 중...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          userCode: AppConstants.portoneUserCode,
          data: PaymentData(
            pg: pg,
            payMethod: payMethod,
            name: _displayProductName,
            amount: _totalPrice,
            merchantUid: merchantUid,
            buyerName: buyerName,
            buyerTel: buyerTel,
            appScheme: 'com.example.simcap',
          ),
          callback: (Map<String, String> result) async {
            final navContext = AppRouter.navigatorKey.currentContext;
            if (navContext == null) {
              Navigator.pop(context);
              return;
            }
            final notifier = SupplementProvider.of(navContext);

            final isSuccess =
                result['imp_success'] == 'true' ||
                result['success'] == 'true' ||
                result['imp_uid'] != null;

            if (isSuccess) {
              final impUid = result['imp_uid'] ?? '';
              final errorMessage = await _verifyPayment(
                impUid: impUid,
                merchantUid: merchantUid,
              );

              if (errorMessage == null) {
                notifier.addPurchase(_purchaseItems);
                if (widget.cartItems != null) {
                  notifier.clearCheckedCartItems();
                }
                Navigator.pop(context);
                await Future.delayed(const Duration(milliseconds: 300));
                if (mounted) _showCompleteDialog();
              } else {
                Navigator.pop(context);
                final ctx = AppRouter.navigatorKey.currentContext;
                if (ctx != null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(errorMessage)),
                  );
                }
              }
            } else {
              Navigator.pop(context);
              final errorMsg = result['error_msg'] ?? '결제가 취소되었습니다.';
              final ctx = AppRouter.navigatorKey.currentContext;
              if (ctx != null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(errorMsg),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
        ),
      ),
    );
  }

  void _showCompleteDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '결제가 완료되었습니다!',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _displayProductName,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go('/home');
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '홈으로',
                      style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/profile/purchases');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '구매 기록',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '주문/결제',
          style: TextStyle(
            color: Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── 주문 상품 ──────────────────────────────────────────────
            _buildSection(
              title: '주문 상품',
              child: Column(
                children: _purchaseItems.map((item) => _buildOrderItemRow(item)).toList(),
              ),
            ),

            const SizedBox(height: 8),

            // ── 배송지 ─────────────────────────────────────────────────
            _buildSection(
              title: '배송지',
              trailing: TextButton(
                onPressed: () {},
                child: const Text(
                  '변경',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _inputField('받는 분', _nameController, hint: '홍길동'),
                  const SizedBox(height: 10),
                  _inputField(
                    '연락처',
                    _phoneController,
                    hint: '010-0000-0000',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 10),
                  _inputField('주소', _addressController, hint: '서울시 강남구'),
                  const SizedBox(height: 10),
                  _inputField(
                    '상세 주소',
                    _addressDetailController,
                    hint: '동/호수 입력',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── 배송 요청사항 ───────────────────────────────────────────
            _buildSection(
              title: '배송 요청사항',
              child: Column(
                children: [
                  ..._requestOptions
                      .map(
                        (option) => GestureDetector(
                          onTap: () =>
                              setState(() => _selectedRequest = option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Radio<String>(
                                  value: option,
                                  groupValue: _selectedRequest,
                                  onChanged: (v) =>
                                      setState(() => _selectedRequest = v!),
                                  activeColor: AppColors.primary,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  option,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _selectedRequest == option
                                        ? Colors.black
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  if (_selectedRequest == '직접 입력') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customRequestController,
                      decoration: InputDecoration(
                        hintText: '요청사항을 입력해주세요',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── 결제수단 ───────────────────────────────────────────────
            _buildSection(
              title: '결제수단',
              child: Column(
                children: [
                  ..._paymentMethods
                      .map(
                        (method) => GestureDetector(
                          onTap: () =>
                              setState(() => _selectedPayment = method['id']),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: _selectedPayment == method['id']
                                  ? AppColors.primaryLight
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedPayment == method['id']
                                    ? AppColors.primary
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Radio<String>(
                                  value: method['id'],
                                  groupValue: _selectedPayment,
                                  onChanged: (v) =>
                                      setState(() => _selectedPayment = v!),
                                  activeColor: AppColors.primary,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  method['icon'] as IconData,
                                  size: 20,
                                  color: _selectedPayment == method['id']
                                      ? AppColors.primary
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  method['label'] as String,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: _selectedPayment == method['id']
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _selectedPayment == method['id']
                                        ? AppColors.primary
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── 결제 금액 ──────────────────────────────────────────────
            _buildSection(
              title: '결제 금액',
              child: Column(
                children: [
                  _priceRow(
                    '상품 금액',
                    '${_formatPrice(_totalPrice)}원',
                  ),
                  const SizedBox(height: 8),
                  _priceRow('배송비', '무료', valueColor: AppColors.primary),
                  const Divider(height: 20),
                  _priceRow(
                    '총 결제금액',
                    '${_formatPrice(_totalPrice)}원',
                    isBold: true,
                    valueColor: AppColors.primary,
                  ),
                ],
              ),
            ),

            SizedBox(height: bottomPad + 90),
          ],
        ),
      ),

      // ── 결제하기 버튼 ───────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _onPurchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      '${_formatPrice(_totalPrice)}원 결제하기',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _inputField(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  Widget _priceRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isBold ? Colors.black : Colors.grey[600],
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
