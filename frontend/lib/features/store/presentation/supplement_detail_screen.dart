import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';
import 'package:simcap/routes/app_router.dart';
import 'package:simcap/features/store/presentation/review_screen.dart';
import 'package:simcap/providers/supplement_provider.dart';
import 'package:simcap/services/conflict_api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:portone_flutter/v1.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:simcap/services/review_api_service.dart';
import 'package:simcap/services/intake_api_service.dart';
import 'package:simcap/services/auth_service.dart';

// 스토어 상품 데이터 모델
// TODO: 백엔드 연동 후 API 응답 모델로 교체
class StoreProduct {
  final String id;
  final String name;
  final String brand;
  final int price;
  final String description;
  final List<NutrientInfo> nutrients;
  final List<String> contraindications;
  final List<StoreProduct> similarProducts;
  final String? purchaseUrl;
  final String? imageUrl;
  final int dailyDose; // 1회 복용량
  final int dailyFrequency; // 하루 복용 횟수
  final String? servingWeight;
  final String? totalWeight;

  const StoreProduct({
    required this.id,
    required this.name,
    required this.brand,
    required this.price,
    required this.description,
    required this.nutrients,
    this.contraindications = const [],
    this.similarProducts = const [],
    this.purchaseUrl,
    this.imageUrl,
    this.dailyDose = 1,
    this.dailyFrequency = 1,
    this.servingWeight,
    this.totalWeight,
  });

  factory StoreProduct.fromJson(Map<String, dynamic> json) {
    // 백엔드의 supplements_ingredients 또는 ingredients 파싱
    List<NutrientInfo> parsedNutrients = [];
    final rawIngredients =
        json['supplements_ingredients'] ?? json['ingredients'];
    if (rawIngredients != null && rawIngredients is List) {
      parsedNutrients = rawIngredients.map((item) {
        if (item is Map) {
          return NutrientInfo(
            name: (item['ingredient_name'] ?? item['name'] ?? '').toString(),
            amount:
                double.tryParse(
                  item['amount']?.toString() ??
                      item['value']?.toString() ??
                      '0',
                ) ??
                0.0,
            unit: (item['unit'] ?? '').toString(),
            dailyPercent:
                double.tryParse(
                  item['dailyPercent']?.toString() ??
                      item['percent']?.toString() ??
                      '0',
                ) ??
                0.0,
          );
        } else {
          return NutrientInfo(
            name: item.toString(),
            amount: 0.0,
            unit: '',
            dailyPercent: 0.0,
          );
        }
      }).toList();
    }

    int parsedDose = 1;
    if (json['serving_size'] != null) {
      parsedDose = (double.tryParse(json['serving_size'].toString()) ?? 1.0)
          .round();
    } else if (json['dailyDose'] != null) {
      parsedDose = int.tryParse(json['dailyDose'].toString()) ?? 1;
    }

    int parsedFrequency = 1;
    if (json['daily_servings'] != null) {
      final freqStr = json['daily_servings'].toString().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      parsedFrequency = int.tryParse(freqStr) ?? 1;
    } else if (json['dailyFrequency'] != null) {
      parsedFrequency = int.tryParse(json['dailyFrequency'].toString()) ?? 1;
    }

    return StoreProduct(
      id: json['id']?.toString() ?? '',
      name: json['product_name'] ?? json['name'] ?? '',
      brand: json['brand_name'] ?? json['brand'] ?? '',
      // 가격이 int가 아닐 수도 있으니 안전하게 파싱 (BigInt를 백엔드에서 string으로 처리 중)
      price: json['price'] != null
          ? int.tryParse(json['price'].toString()) ?? 0
          : 0,
      description: json['description'] ?? '',
      nutrients: parsedNutrients,
      contraindications: [],
      similarProducts: [],
      purchaseUrl: json['shop_url'],
      imageUrl: json['image_url'],
      dailyDose: parsedDose,
      dailyFrequency: parsedFrequency,
      servingWeight: json['serving_weight']?.toString(),
      totalWeight: json['total_weight']?.toString(),
    );
  }

  /// StoreProduct → Supplement 변환
  /// 스토어 상품을 캐비닛에 추가할 때 사용
  Supplement toSupplement() {
    int calculatedPills = 0;
    if (totalWeight != null && servingWeight != null) {
      final totalMg = _parseWeightToMg(totalWeight);
      final servingMg = _parseWeightToMg(servingWeight);
      if (totalMg != null && servingMg != null && servingMg > 0) {
        calculatedPills = (totalMg / servingMg).round();
      }
    }

    return Supplement(
      supplementId: id,
      name: name,
      brand: brand,
      remaining: calculatedPills,
      total: calculatedPills,
      dailyDose: dailyDose,
      dailyFrequency: dailyFrequency,
      imageUrl: imageUrl,
      nutrients: nutrients
          .map(
            (n) => Nutrient(
              name: n.name,
              value: n.amount,
              unit: n.unit,
              percent: n.dailyPercent,
            ),
          )
          .toList(),
      analysisGuide: description.isNotEmpty
          ? description
          : '이 영양제는 정해진 시간에 복용하는 것이 좋습니다.',
      aiSummary: '리뷰를 분석 중입니다.',
    );
  }

  static double? _parseWeightToMg(String? weightStr) {
    if (weightStr == null || weightStr.isEmpty) return null;
    final cleaned = weightStr.replaceAll(RegExp(r'\s+'), '').toLowerCase();

    // 정수 및 실수를 파싱하는 정규식
    final regExp = RegExp(r'^([0-9.]+)([a-zμ]+)$');
    final match = regExp.firstMatch(cleaned);

    if (match == null) {
      final fallbackRegExp = RegExp(r'([0-9.]+)\s*([a-zA-Zμ]+)');
      final fallbackMatch = fallbackRegExp.firstMatch(cleaned);
      if (fallbackMatch == null) return null;

      final val = double.tryParse(fallbackMatch.group(1) ?? '');
      final unit = fallbackMatch.group(2) ?? '';
      if (val == null) return null;
      return _convertToMg(val, unit);
    }

    final val = double.tryParse(match.group(1) ?? '');
    final unit = match.group(2) ?? '';
    if (val == null) return null;
    return _convertToMg(val, unit);
  }

  static double _convertToMg(double val, String unit) {
    switch (unit) {
      case 'g':
        return val * 1000.0;
      case 'mg':
        return val;
      case 'mcg':
      case 'μg':
      case 'ug':
        return val / 1000.0;
      case 'kg':
        return val * 1000000.0;
      default:
        return val;
    }
  }
}

class NutrientInfo {
  final String name;
  final double amount;
  final String unit;
  final double dailyPercent; // 일일 권장량 대비 %

  const NutrientInfo({
    required this.name,
    required this.amount,
    required this.unit,
    required this.dailyPercent,
  });
}

// 더미 데이터
// TODO: 실제 API로 교체
final _dummySimilar = <StoreProduct>[
  StoreProduct(
    id: 's1',
    name: '비타민D3 2000IU',
    brand: '네이처메이드',
    price: 18000,
    description: '',
    nutrients: [],
  ),
  StoreProduct(
    id: 's2',
    name: '비타민D+K2',
    brand: '솔가',
    price: 34000,
    description: '',
    nutrients: [],
  ),
  StoreProduct(
    id: 's3',
    name: '선샤인 비타민D',
    brand: '뉴트리코어',
    price: 15000,
    description: '',
    nutrients: [],
  ),
];

final dummyProduct = StoreProduct(
  id: 'p1',
  name: '고함량 비타민D 5000IU',
  brand: '심캡푸드',
  price: 28000,
  description:
      '햇빛을 충분히 쬐기 어려운 현대인을 위한 고함량 비타민D입니다. '
      '면역 기능 유지, 뼈 건강, 근육 기능에 도움을 줍니다. '
      '연질캡슐 형태로 흡수율을 높였습니다.',
  nutrients: [
    NutrientInfo(name: '비타민 D3', amount: 5000, unit: 'IU', dailyPercent: 1.25),
    NutrientInfo(name: '비타민 K2', amount: 45, unit: 'mcg', dailyPercent: 0.6),
    NutrientInfo(name: '비타민 E', amount: 10, unit: 'mg', dailyPercent: 0.67),
  ],
  contraindications: [
    '와파린 (항응고제) — 비타민K2와 상호작용',
    '칼슘 보충제 과다 복용 — 고칼슘혈증 위험',
    '티아자이드계 이뇨제 — 칼슘 수치 상승 가능',
  ],
  similarProducts: _dummySimilar,
);

class SupplementDetailScreen extends StatefulWidget {
  final StoreProduct product;

  const SupplementDetailScreen({super.key, required this.product});

  @override
  State<SupplementDetailScreen> createState() => _SupplementDetailScreenState();
}

class _SupplementDetailScreenState extends State<SupplementDetailScreen> {
  bool _contraExpanded = false;
  bool _isPurchaseLoading = false;
  bool _isPaymentLoading = false;
  List<String> _contraindications = [];
  bool _isContraLoading = false;
  List<ProductReview> _reviews = [];
  bool _isReviewsLoading = true;

  List<IntakeResult> _intakeResults = [];
  bool _isIntakeLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkContraindications();
      _checkDetailOverdose();
      _loadReviews();
    });
  }

  Future<void> _loadReviews() async {
    setState(() => _isReviewsLoading = true);
    final list = await ReviewApiService().fetchReviews(widget.product.id);
    if (mounted) {
      setState(() {
        _reviews = list;
        _isReviewsLoading = false;
      });
    }
  }

  Future<void> _checkContraindications() async {
    if (!mounted) return;
    setState(() => _isContraLoading = true);

    try {
      final notifier = SupplementProvider.of(context);
      final currentProductId = int.tryParse(widget.product.id);

      if (currentProductId != null) {
        final cabinetSuppsJson = notifier.supplements
            .map(
              (s) => {
                'name': s.name,
                'ingredients': s.nutrients.map((n) => n.name).toList(),
              },
            )
            .toList();

        final prefs = await SharedPreferences.getInstance();
        final userHealth = prefs.getStringList('selectedHealth') ?? [];
        final userAllergies = prefs.getStringList('selectedAllergies') ?? [];

        final conflictApi = ConflictApiService();
        final backendConflicts = await conflictApi
            .checkConflictsBySupplementIds(
              supplementIds: [currentProductId],
              cabinetSupplements: cabinetSuppsJson,
              userHealth: userHealth,
              userAllergies: userAllergies,
            );

        final List<String> formattedResults = [];
        for (final conflict in backendConflicts) {
          if (conflict.conflicts.length > 1) {
            final cabinetItemName = conflict.conflicts[1];
            formattedResults.add(
              '내 캐비닛 $cabinetItemName 제품과 충돌 유의\n${conflict.reason}',
            );
          } else {
            formattedResults.add(conflict.reason);
          }
        }

        if (mounted) {
          setState(() {
            _contraindications = formattedResults;
          });
        }
      }
    } catch (e) {
      debugPrint('[SupplementDetailScreen] 안전성 검출 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isContraLoading = false);
      }
    }
  }

  Future<void> _checkDetailOverdose() async {
    try {
      if (mounted) {
        setState(() => _isIntakeLoading = true);
      }
      final notifier = SupplementProvider.of(context);

      final cartItems = [
        ...notifier.supplements.map((s) {
          return {
            'productId': s.supplementId,
            'name': s.name,
            'brand': s.brand,
            'count': 1,
          };
        }),
        {
          'productId': widget.product.id,
          'name': widget.product.name,
          'brand': widget.product.brand,
          'count': 1,
        },
      ];

      final profile = await AuthService().getIntakeProfile();
      final results = await IntakeApiService().checkOverdoseByCartItems(
        cartItems: cartItems,
        age: profile.age,
        gender: profile.gender,
      );

      if (mounted) {
        setState(() {
          _intakeResults = results;
          _isIntakeLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[SupplementDetailScreen] 과다복용 검사 실패: $e');
      if (mounted) {
        setState(() => _isIntakeLoading = false);
      }
    }
  }

  /// 이미 캐비닛에 등록된 영양제인지 여부 (이름 기준 비교)
  bool _isAlreadyInCabinet(BuildContext context) {
    final supplements = SupplementProvider.of(context).supplements;
    return supplements.any((s) => s.name == widget.product.name);
  }

  bool _hasOverdoseRiskWithCurrentProduct(BuildContext context) {
    final cabinets = SupplementProvider.of(context).supplements;

    final Map<String, double> totals = {};

    for (final s in cabinets) {
      for (final n in s.nutrients) {
        final key = n.name.trim().toLowerCase();
        totals[key] = (totals[key] ?? 0) + n.percent;
      }
    }

    for (final n in widget.product.nutrients) {
      final key = n.name.trim().toLowerCase();
      final total = (totals[key] ?? 0) + n.dailyPercent;

      if (total > 1.0) {
        return true;
      }
    }

    return false;
  }

  bool _blockIfOverdoseRisk(BuildContext context) {
    if (_hasOverdoseRiskWithCurrentProduct(context)) {
      return true;
    }

    return false;
  }

  /// 이미 장바구니에 있는지 여부
  bool _isInCart(BuildContext context) =>
      SupplementProvider.of(context).isInCart(widget.product.id);

  /// 장바구니에 추가 / 이미 있으면 수량 +1
  void _addToCart(BuildContext context) {
    final notifier = SupplementProvider.of(context);
    final p = widget.product;
    final alreadyInCart = _isInCart(context);

    notifier.addToCart(
      CartItem(productId: p.id, name: p.name, brand: p.brand, price: p.price),
    );

    // 이전 스낵바들을 즉시 지워 연속 클릭 시 버벅임 없앰
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2), // 2초 후 자동으로 사라짐
        content: Text(
          alreadyInCart
              ? '${p.name} 수량을 추가했습니다.'
              : '${p.name}을(를) 장바구니에 담았습니다!',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        action: SnackBarAction(
          label: '장바구니 보기',
          textColor: Colors.white,
          onPressed: () {
            context.push('/store/basket');
          },
        ),
      ),
    );
  }

  /// 캐비닛에 추가
  Future<void> _addToCabinet(BuildContext context) async {
    final notifier = SupplementProvider.of(context);

    // 이미 있으면 추가 안 함
    if (_isAlreadyInCabinet(context)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\${widget.product.name}은(는) 이미 캐비닛에 있습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 영양제 정보 페이지 거쳐서 등록 (복용 알림 설정 위함)
    context.push('/cabinet/info', extra: widget.product.toSupplement());
  }

  // ── 결제 수단 선택 바텀시트 ──────────────────────────────────────────────
  Future<void> _showPaymentMethodSheet(
    BuildContext context,
    StoreProduct product,
  ) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '결제 수단 선택',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatPrice(product.price)}원',
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            // 카카오페이
            _paymentMethodTile(
              context: context,
              product: product,
              label: '카카오페이',
              pg: 'kakaopay.TC0ONETIME',
              color: const Color(0xFFFEE500),
              textColor: Colors.black87,
              icon: Icons.chat_bubble_rounded,
            ),
            const SizedBox(height: 12),
            // 토스페이
            _paymentMethodTile(
              context: context,
              product: product,
              label: '토스페이',
              pg: 'tosspay.tosstest',
              color: const Color(0xFF0064FF),
              textColor: Colors.white,
              icon: Icons.payment_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentMethodTile({
    required BuildContext context,
    required StoreProduct product,
    required String label,
    required String pg,
    required Color color,
    required Color textColor,
    required IconData icon,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context); // 바텀시트 닫기
          _startPayment(context, product, pg: pg);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ── 포트원 결제 ────────────────────────────────────────────────────────
  Future<void> _startPayment(
    BuildContext context,
    StoreProduct product, {
    String pg = 'kakaopay.TC0ONETIME',
  }) async {
    final merchantUid = 'order_\${DateTime.now().millisecondsSinceEpoch}';

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
          userCode: 'imp24258048',
          data: PaymentData(
            pg: pg,
            payMethod: pg.startsWith('kakaopay')
                ? 'kakaopay'
                : pg.startsWith('tosspay')
                ? 'tosspay'
                : 'card',
            name: product.name,
            amount: product.price,
            merchantUid: merchantUid,
            buyerName: '구매자',
            buyerTel: '010-0000-0000',
            appScheme: 'com.example.simcap',
          ),
          callback: (Map<String, String> result) async {
            debugPrint('결제 콜백 수신: $result');
            // 결과 먼저 처리 후 창 닫기
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
              bool verified = false;
              try {
                verified = await _verifyPayment(
                  impUid: impUid,
                  merchantUid: merchantUid,
                  amount: product.price,
                  productId: product.id,
                );
              } catch (e) {
                verified = true; // 백엔드 미연동 시 성공 처리
              }

              if (verified) {
                notifier.addPurchase([
                  PurchaseItem(
                    name: product.name,
                    brand: product.brand,
                    price: product.price,
                    count: 1,
                  ),
                ]);
              }

              // 결제창 닫기
              Navigator.pop(context);

              // 구매 완료 다이얼로그
              if (verified) {
                await Future.delayed(const Duration(milliseconds: 300));
                final ctx = AppRouter.navigatorKey.currentContext;
                if (ctx != null) {
                  showDialog(
                    context: ctx,
                    barrierDismissible: false,
                    builder: (dialogContext) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primary,
                              size: 44,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '구매 완료!',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            product.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatPrice(product.price)}원',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
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
                                  onPressed: () => Navigator.pop(dialogContext),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text(
                                    '닫기',
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
                                    Navigator.pop(dialogContext);
                                    Future.microtask(() {
                                      final c =
                                          AppRouter.navigatorKey.currentContext;
                                      if (c != null)
                                        c.push('/profile/purchases');
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text(
                                    '구매 기록 보기',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
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
              }
            } else {
              Navigator.pop(context);
              final errorMsg = result['error_msg'] ?? '결제가 취소되었습니다.';
              final ctx = AppRouter.navigatorKey.currentContext;
              if (ctx != null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(errorMsg),
                    duration: const Duration(milliseconds: 2000),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
            if (mounted) setState(() => _isPaymentLoading = false);
          },
        ),
      ),
    );
  }

  Future<void> _handlePaymentResult(
    BuildContext context,
    Map<String, String> result,
    StoreProduct product,
    String merchantUid,
    SupplementNotifier notifier,
  ) async {
    // 결제 결과 디버그 출력
    debugPrint('결제 결과: $result');
    debugPrint('imp_success: ${result['imp_success']}');
    debugPrint('imp_uid: ${result['imp_uid']}');

    final isSuccess =
        result['imp_success'] == 'true' ||
        result['success'] == 'true' ||
        result['imp_uid'] != null;

    if (isSuccess) {
      final impUid = result['imp_uid']!;

      try {
        // 백엔드 결제 검증
        final verified = await _verifyPayment(
          impUid: impUid,
          merchantUid: merchantUid,
          amount: product.price,
          productId: product.id,
        );

        if (!mounted) return;

        if (verified) {
          // 구매 기록 추가
          notifier.addPurchase([
            PurchaseItem(
              name: product.name,
              brand: product.brand,
              price: product.price,
              count: 1,
            ),
          ]);

          // 구매 완료 다이얼로그
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primary,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '구매 완료!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.name,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatPrice(product.price)}원',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            '닫기',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            context.push('/profile/purchases');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            '구매 기록 보기',
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
        } else {
          _showErrorSnackBar('결제 검증에 실패했습니다. 고객센터로 문의해주세요.');
        }
      } catch (e) {
        if (mounted) _showErrorSnackBar('결제 처리 중 오류가 발생했습니다.');
      } finally {
        if (mounted) setState(() => _isPaymentLoading = false);
      }
    } else {
      // 결제 실패 or 취소
      final errorMsg = result['error_msg'] ?? '결제가 취소되었습니다.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            duration: const Duration(milliseconds: 2000),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<bool> _verifyPayment({
    required String impUid,
    required String merchantUid,
    required int amount,
    required String productId,
  }) async {
    try {
      // TODO: 실제 서버 주소로 교체
      final url = Uri.parse('${AppConstants.apiBaseUrl}/api/payment/verify');
      final response = await http
          .post(
            url,
            headers: AppConstants.headers,
            body: jsonEncode({
              'imp_uid': impUid,
              'merchant_uid': merchantUid,
              'amount': amount,
              'product_id': productId,
            }),
          )
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('결제 검증 오류: \$e');
      // 백엔드 미연동 시 즉시 true 반환
      return true;
    }
  }

  Future<void> _launchPurchaseUrl(String url) async {
    // URL 파싱
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showErrorSnackBar('올바르지 않은 URL입니다.');
      return;
    }

    setState(() => _isPurchaseLoading = true);

    try {
      // 앱에서 열 수 있는지 먼저 확인
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        if (mounted) _showErrorSnackBar('구매 페이지를 열 수 없습니다.');
        return;
      }
      // 외부 브라우저(기기 기본 브라우저)로 열기
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) _showErrorSnackBar('구매 페이지 연결에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _isPurchaseLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(p),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBasicInfo(p),
                const SizedBox(height: 12),
                _buildNutrientChart(p.nutrients),
                const SizedBox(height: 12),
                _buildContraindications(_contraindications),
                const SizedBox(height: 12),
                _buildReviewSummary(p),
                const SizedBox(height: 12),
                _buildSimilarProducts(p.similarProducts),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, p),
    );
  }

  // AppBar (이미지 영역 포함
  Widget _buildAppBar(StoreProduct p) {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      backgroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: () => context.pop(),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: GestureDetector(
            onTap: () => context.push('/store/basket'),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.shopping_basket_outlined,
                    color: Colors.black,
                  ),
                  if (SupplementProvider.of(context).cartItems.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${SupplementProvider.of(context).cartItems.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: AppColors.primaryFaint,
          // 기존 코드: 아이콘 하드코딩
          // child: const Center(
          //   child: Icon(
          //     Icons.medication_rounded,
          //     size: 100,
          //     color: AppColors.primary,
          //   ),
          // ),
          // API 연동 코드: 실제 이미지 렌더링
          child: p.imageUrl != null && p.imageUrl!.isNotEmpty
              ? Image.network(
                  p.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(
                      Icons.medication_rounded,
                      size: 100,
                      color: AppColors.primary,
                    ),
                  ),
                )
              : const Center(
                  child: Icon(
                    Icons.medication_rounded,
                    size: 100,
                    color: AppColors.primary,
                  ),
                ),
        ),
      ),
    );
  }

  // 기본 정보
  Widget _buildBasicInfo(StoreProduct p) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.brand,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            p.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatPrice(p.price)}원',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            p.description,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // 성분별 함량 도식화
  Widget _buildNutrientChart(List<NutrientInfo> nutrients) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('성분별 함량', icon: Icons.bar_chart_rounded),
          const SizedBox(height: 4),
          Text(
            '일일 권장량(DRI) 대비 함유량',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          ...nutrients.map((n) => _buildNutrientRow(n)),
        ],
      ),
    );
  }

Widget _buildNutrientRow(NutrientInfo n) {
  final matched = _intakeResults
      .where(
        (r) =>
            r.nutrientName.trim().toLowerCase() ==
            n.name.trim().toLowerCase(),
      )
      .toList();

  final result = matched.isNotEmpty ? matched.first : null;

  final ratio = result?.ratio ?? 0.0;
  final clampedPercent = ratio.clamp(0.0, 1.5);

  final status = result?.status ?? 'none';
  final targetType = result?.targetType ?? 'none';

  final Color barColor = _statusColor(status);

  final Color badgeBg = status == 'danger' || status == 'very_low'
      ? AppColors.dangerBg
      : status == 'low'
          ? const Color(0xFFFFF3E0)
          : AppColors.primaryLight;

  final percentLabel = _isIntakeLoading
      ? '계산중'
      : result != null
          ? '${(ratio * 100).toStringAsFixed(0)}%'
          : '-';

  final statusLabel = result == null ? '' : _statusText(status, targetType);

  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              n.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                Text(
                  '${n.amount}${n.unit}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel.isEmpty
                        ? percentLabel
                        : '$percentLabel $statusLabel',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: barColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  height: 8,
                  width:
                      constraints.maxWidth *
                      (clampedPercent / 1.5).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Positioned(
                  left: constraints.maxWidth * (1.0 / 1.5),
                  child: Container(
                    width: 1.5,
                    height: 8,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

  // 병용 금지 정보
  void _showConsultPopup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.local_hospital_outlined, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              '전문의 상담 안내',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          '영양제 복용에 관한 정확한 판단은 전문의와 상담하는 것이 가장 안전합니다.\n\n'
          '특히 만성질환, 임신, 약물 복용 중인 경우 반드시 전문의와 상의 후 복용하세요.',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      '닫기',
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
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      '확인',
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

  Widget _buildContraindications(List<String> items) {
    final cabinets = SupplementProvider.of(context).supplements;

    // 캐비닛 영양제 성분 목록
    final cabinetNutrients = cabinets
        .expand((s) => s.nutrients.map((n) => n.name.toLowerCase()))
        .toSet();

    // 이 제품의 성분 중 병용금지 항목과 겹치는 것
    final productNutrientNames = widget.product.nutrients
        .map((n) => n.name.toLowerCase())
        .toSet();

    // 병용금지 충돌 (캐비닛 성분 vs 이 제품 병용금지 목록)
    final conflictItems = items.where((item) {
      final lower = item.toLowerCase();
      return cabinetNutrients.any(
        (n) => lower.contains(n) || n.contains(lower),
      );
    }).toList();

    // 과다복용 위험 성분 (캐비닛에 동일 성분 있는 경우)
    final overdoseRisks = widget.product.nutrients.where((n) {
      final lower = n.name.toLowerCase();
      return cabinetNutrients.any(
        (cn) => lower.contains(cn) || cn.contains(lower),
      );
    }).toList();

    final hasOverdose = overdoseRisks.isNotEmpty;
    final hasInteraction = conflictItems.isNotEmpty;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '병용금지 · 과다복용',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (!hasOverdose && !hasInteraction)
                GestureDetector(
                  onTap: _showConsultPopup,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.info_outline,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 과다복용 섹션 ─────────────────────────────────────────────
          Row(
            children: [
              const Icon(
                Icons.monitor_heart_outlined,
                size: 16,
                color: Colors.orange,
              ),
              const SizedBox(width: 6),
              const Text(
                '과다복용 위험',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (overdoseRisks.isEmpty)
            _buildSafeItem('중복 성분 없음')
          else
            ...overdoseRisks
                .map(
                  (n) =>
                      _buildContraItem('${n.name} — 캐비닛 영양제와 중복, 합산 섭취량 확인 필요'),
                )
                .toList(),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // ── 병용금지 섹션 ─────────────────────────────────────────────
          Row(
            children: [
              const Icon(
                Icons.block_outlined,
                size: 16,
                color: AppColors.danger,
              ),
              const SizedBox(width: 6),
              const Text(
                '병용 금지 약물·성분',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 전체 병용금지 목록
          if (items.isEmpty)
            _buildSafeItem('등록된 병용 금지 정보가 없습니다')
          else ...[
            _buildContraItem(items.first),
            if (items.length > 1) ...[
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: _contraindications
                      .skip(1)
                      .map(_buildContraItem)
                      .toList(),
                ),
                crossFadeState: _contraExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _contraExpanded = !_contraExpanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _contraExpanded
                          ? '접기'
                          : '${_contraindications.length - 1}개 더 보기',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      _contraExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _safeChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildContraItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.error_outline, size: 15, color: AppColors.danger),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // 문제 없는 경우 — 체크 아이콘
  Widget _buildSafeItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(
              Icons.check_circle_outline,
              size: 15,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 리뷰 요약 섹션 ────────────────────────────────────────────────────
  Widget _buildReviewSummary(StoreProduct product) {
    final reviews = _reviews;
    final avg = reviews.isEmpty
        ? 0.0
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
    final preview = reviews.take(2).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                const Text(
                  '리뷰',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                // 평균 별점
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      avg.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warning,
                      ),
                    ),
                    Text(
                      ' (${reviews.length})',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await context.push('/store/review', extra: product);
                    _loadReviews();
                  },
                  child: const Text(
                    '전체보기',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          // 리뷰 미리보기 2개
          if (reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '아직 리뷰가 없습니다',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
            )
          else
            ...preview.map((r) => _buildReviewPreviewRow(r)),
        ],
      ),
    );
  }

  Widget _buildReviewPreviewRow(ProductReview review) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 13,
                    color: i < review.rating
                        ? AppColors.warning
                        : Colors.grey[300],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                review.userName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${review.createdAt.month}/${review.createdAt.day}',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            review.content,
            style: const TextStyle(fontSize: 13, height: 1.4),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarProducts(List<StoreProduct> products) {
    if (products.isEmpty) return const SizedBox.shrink();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('유사 제품 추천', icon: Icons.recommend_rounded),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final sp = products[index];
                return GestureDetector(
                  onTap: () => context.push('/store/detail', extra: sp),
                  child: Container(
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryFaint,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.medication_rounded,
                            color: AppColors.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            sp.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatPrice(sp.price)}원',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, StoreProduct p) {
    final bool alreadyAdded = _isAlreadyInCabinet(context);

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 장바구니
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _isInCart(context)
                    ? AppColors.primaryLight
                    : Colors.white,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _addToCart(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isInCart(context)
                        ? Icons.shopping_cart_rounded
                        : Icons.shopping_cart_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isInCart(context) ? '담김' : '장바구니',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 캐비닛 추가
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: alreadyAdded
                    ? AppColors.primaryLight
                    : Colors.white,
                side: BorderSide(
                  color: alreadyAdded
                      ? AppColors.primary
                      : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _addToCabinet(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    alreadyAdded
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 16,
                    color: alreadyAdded
                        ? AppColors.primary
                        : Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    alreadyAdded ? '추가됨' : '내 캐비닛',
                    style: TextStyle(
                      color: alreadyAdded
                          ? AppColors.primary
                          : Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: _isPaymentLoading
                  ? null
                  : () => context.push('/store/purchase', extra: p),
              child: _isPaymentLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '바로 구매',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String _formatPrice(int price) {
    return price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'very_low':
      return AppColors.danger;
    case 'low':
      return AppColors.warning;
    case 'normal':
    case 'enough':
      return AppColors.primary;
    case 'danger':
      return AppColors.danger;
    default:
      return Colors.grey;
  }
}

String _statusText(String status, String targetType) {
  if (targetType == 'upper') {
    return status == 'danger' ? '위험' : '정상';
  }

  switch (status) {
    case 'very_low':
      return '매우 부족';
    case 'low':
      return '부족';
    case 'normal':
      return '적정';
    case 'enough':
      return '충분';
    case 'danger':
      return '위험';
    default:
      return '-';
  }
}