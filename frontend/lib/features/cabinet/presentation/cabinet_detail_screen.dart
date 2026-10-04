import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';
import 'package:simcap/providers/supplement_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:simcap/features/store/data/store_product_data.dart';
import 'package:simcap/features/store/presentation/supplement_detail_screen.dart';
import 'package:simcap/services/store_api_service.dart';
import 'package:simcap/services/intake_api_service.dart';
import 'package:simcap/services/auth_service.dart';
import 'package:simcap/services/reorder_service.dart';

class CabinetDetailScreen extends StatefulWidget {
  final Supplement item;

  const CabinetDetailScreen({super.key, required this.item});

  @override
  State<CabinetDetailScreen> createState() => _CabinetDetailScreenState();
}

class _CabinetDetailScreenState extends State<CabinetDetailScreen> {
  bool _isLaunching = false;
  StoreProduct? _matchedProduct;
  bool _isLoadingProduct = false;
  List<IntakeResult> _cabinetIntakeResults = [];
  bool _isIntakeLoading = true;


@override
void initState() {
  super.initState();
  _resolveMatchedProduct();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _checkCabinetNutritionSafety();
  });
}

  Future<void> _checkCabinetNutritionSafety() async {
    if (!mounted) return;

    setState(() {
      _isIntakeLoading = true;
    });

    try {
      final notifier = SupplementProvider.of(context);

      final cartItems = notifier.supplements.map((s) {
        return {
          'productId': s.supplementId,
          'name': s.name,
          'brand': s.brand,
          'count': 1,
        };
      }).toList();

      final profile = await AuthService().getIntakeProfile();
      final results = await IntakeApiService().checkOverdoseByCartItems(
        cartItems: cartItems,
        age: profile.age,
        gender: profile.gender,
      );

      if (!mounted) return;

      setState(() {
        _cabinetIntakeResults = results;
        _isIntakeLoading = false;
      });
    } catch (e) {
      debugPrint('[CabinetDetailScreen] 영양성분 검사 실패: $e');
      if (!mounted) return;
      setState(() {
        _isIntakeLoading = false;
      });
    }
  }

  Future<void> _resolveMatchedProduct() async {
    // 1. 로컬 매칭 시도
    StoreProduct? dummyMatched;
    for (final p in allProducts) {
      if (p.name.contains(widget.item.name) || widget.item.name.contains(p.name)) {
        dummyMatched = p;
        break;
      }
    }
    if (dummyMatched != null) {
      if (mounted) {
        setState(() {
          _matchedProduct = dummyMatched;
        });
      }
      return;
    }

    // 2. DB 매칭 시도
    if (mounted) setState(() => _isLoadingProduct = true);
    try {
      final realProducts = await StoreApiService().fetchSupplements();
      StoreProduct? matched;
      for (final p in realProducts) {
        if (p.name.contains(widget.item.name) || widget.item.name.contains(p.name)) {
          matched = p;
          break;
        }
      }
      if (matched != null && mounted) {
        setState(() {
          _matchedProduct = matched;
        });
      }
    } catch (e) {
      debugPrint('DB 상품 매칭 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoadingProduct = false);
    }
  }

  // 구매처 이동 — 상품명으로 네이버 쇼핑 검색
  Future<void> _launchPurchaseUrl() async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);

    final query = Uri.encodeComponent(widget.item.name);
    final uri = Uri.parse(
      'https://search.shopping.naver.com/search/all?query=$query',
    );

    try {
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) {
        if (mounted) _showSnackBar('구매 페이지를 열 수 없습니다.', isError: true);
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) _showSnackBar('구매 페이지 연결에 실패했습니다.', isError: true);
    } finally {
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  /// 편집 화면으로 이동 — 수정 완료 시 updateSupplement() 호출
  Future<void> _navigateToEdit(BuildContext context) async {
    final notifier = SupplementProvider.of(context);
    final idx = notifier.supplements.indexWhere((s) => s.id == item.id);
    if (idx == -1) return;

    final updated = await context.push<Supplement>('/cabinet/add', extra: item);

    if (updated == null || !context.mounted) return;

    notifier.updateSupplement(idx, updated);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${updated.name} 정보가 수정되었습니다.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
      ),
    );

    // 상세 화면을 pop해서 캐비닛 목록으로 돌아감 (최신 데이터 반영)
    if (context.mounted) context.pop();
  }

  /// 영양제 삭제 — 확인 다이얼로그 후 removeSupplement 호출
  Future<void> _deleteSupplement(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '영양제 삭제',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${item.name}을(를) 삭제하시겠습니까?\n복용 기록도 함께 삭제됩니다.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '취소',
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
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '삭제',
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

    if (confirmed != true || !context.mounted) return;

    SupplementProvider.of(context).removeSupplement(item.id);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.name}이(가) 삭제되었습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    }
  }

  void _onWriteReview() {
    if (_matchedProduct != null) {
      context.push('/store/review', extra: _matchedProduct);
    } else {
      _showSnackBar('스토어에 등록되지 않은 영양제는 리뷰를 작성할 수 없습니다.', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AppColors.danger : Colors.black87,
      ),
    );
  }

  // provider에서 최신 데이터 실시간 반영
  Supplement get item {
    final notifier = SupplementProvider.of(context);
    final found = notifier.supplements
        .where((s) => s.id == widget.item.id)
        .toList();
    return found.isNotEmpty ? found.first : widget.item;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '상세 정보',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.black87),
            tooltip: '영양제 수정',
            onPressed: () => _navigateToEdit(context),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.danger,
            ),
            tooltip: '영양제 삭제',
            onPressed: () => _deleteSupplement(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 헤더 영역
            _buildProductHeader(),
            const Divider(height: 1, thickness: 8, color: AppColors.dividerBg),

            // 복용 상태 정보
            _buildStatusSection(),
            const Divider(height: 1, thickness: 8, color: AppColors.dividerBg),

            // 성분 및 함량 분석
            _buildNutrientAnalysisSection(),
            const Divider(height: 1, thickness: 8, color: AppColors.dividerBg),

            // AI 리뷰 요약
            _buildAIReviewSummary(),
          ],
        ),
      ),
      bottomNavigationBar: _buildActionButtons(context),
    );
  }

  Widget _buildProductHeader() {
    final imageSource = item.displayImage ?? _matchedProduct?.imageUrl;
    final isNetwork = imageSource != null && (imageSource.startsWith('http') || imageSource.startsWith('https'));

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: AppColors.primaryFaint,
              borderRadius: BorderRadius.circular(20),
            ),
            child: (imageSource != null && imageSource.isNotEmpty)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: isNetwork
                        ? Image.network(
                            imageSource,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.medication_rounded,
                              size: 45,
                              color: AppColors.primary,
                            ),
                          )
                        : Image.file(
                            File(imageSource),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.medication_rounded,
                              size: 45,
                              color: AppColors.primary,
                            ),
                          ),
                  )
                : const Icon(
                    Icons.medication_rounded,
                    size: 45,
                    color: AppColors.primary,
                  ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.brand.isEmpty ? '브랜드 정보 없음' : item.brand,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.name.isEmpty ? '제품명 없음' : item.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    final int? daysLeft = item.daysUntilEmpty;
    final DateTime? emptyDate = item.emptyDate;

    // 소진 예정일 문자열 포맷
    String emptyDateLabel;
    if (daysLeft == null) {
      emptyDateLabel = '정보 없음';
    } else if (daysLeft <= 0) {
      emptyDateLabel = '오늘 소진';
    } else if (emptyDate != null) {
      emptyDateLabel = '${emptyDate.month}월 ${emptyDate.day}일 (D-$daysLeft)';
    } else {
      emptyDateLabel = 'D-$daysLeft';
    }

    // 소진 임박 여부에 따른 강조 색상
    final Color emptyDateColor = (daysLeft != null && daysLeft <= 7)
        ? AppColors.danger
        : (daysLeft != null && daysLeft <= 30)
        ? AppColors.warning
        : Colors.black87;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '복용 현황',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildRemainingBar(),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.event_outlined,
            '소진 예정일',
            emptyDateLabel,
            valueColor: emptyDateColor,
          ),
          _buildInfoRow(
            Icons.medication_outlined,
            '1일 복용량',
            '${item.dailyDose}정',
          ),
          _buildInfoRow(
            Icons.repeat_rounded,
            '하루 복용 횟수',
            '${item.dailyFrequency}회',
          ),
          _buildInfoRow(
            Icons.inventory_2_outlined,
            '전체 용량',
            item.total == 0 ? '미설정' : '${item.total}정',
          ),
          _buildInfoRow(
            Icons.notifications_active_outlined,
            '알림 설정',
            item.alarmTimes.isEmpty
                ? '기본 시간'
                : item.alarmTimes
                      .map((t) {
                        final h = t.hour;
                        final period = h < 12 ? '오전' : '오후';
                        final hour = h == 0
                            ? 12
                            : h > 12
                            ? h - 12
                            : h;
                        final min = t.minute.toString().padLeft(2, '0');
                        return '$period $hour:$min';
                      })
                      .join(', '),
          ),
        ],
      ),
    );
  }

  Widget _buildRemainingBar() {
    final int total = item.total;
    final int remaining = item.remaining;
    // remaining > total이면 데이터 이상 — total을 remaining으로 보정
    final int displayTotal = total == 0 ? remaining : total;
    final double progress = displayTotal == 0
        ? 0.0
        : (remaining / displayTotal).clamp(0.0, 1.0);
    final Color barColor = progress <= 0.2
        ? AppColors.danger
        : progress <= 0.5
        ? AppColors.warning
        : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '남은 수량',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
              Text(
                '${item.remaining}정 / ${displayTotal}정',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              color: barColor,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${(progress * 100).toInt()}% 남음',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
          if (item.daysLeft != null) ...[
            const Divider(height: 20),
            _buildRunOutRow(),
          ],
        ],
      ),
    );
  }

  /// 소진 예정일과 재구매 버튼
  Widget _buildRunOutRow() {
    final days = item.daysLeft!;
    final runOut = item.runOutDate!;
    final color = item.isCriticalStock
        ? AppColors.danger
        : item.isLowStock
        ? AppColors.warning
        : Colors.black87;

    return Row(
      children: [
        Icon(Icons.event_outlined, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            days == 0
                ? '오늘 다 떨어져요'
                : '$days일분 남음 · ${runOut.month}/${runOut.day} 소진 예정',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        if (item.isLowStock)
          FilledButton(
            onPressed: () => startReorder(context, inventoryId: item.inventoryId),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('재구매'),
          ),
      ],
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.black54)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientAnalysisSection() {
    final List<Nutrient> nutrients = item.nutrients;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '성분 및 함량 분석',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (nutrients.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('등록된 성분 정보가 없습니다.'),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: nutrients.length,
              itemBuilder: (context, index) {
                return _buildNutrientBar(nutrients[index]);
              },
            ),
          const SizedBox(height: 12),
          _buildAnalysisGuide(),
        ],
      ),
    );
  }

Widget _buildNutrientBar(Nutrient n) {
  final matched = _cabinetIntakeResults
      .where(
        (r) =>
            r.nutrientName.trim().toLowerCase() ==
            n.name.trim().toLowerCase(),
      )
      .toList();

  final result = matched.isNotEmpty ? matched.first : null;

  final ratio = result?.ratio ?? n.percent;
  final status = result?.status ?? 'none';
  final targetType = result?.targetType ?? 'none';

  final barColor = result == null ? AppColors.warning : _statusColor(status);
  final statusLabel = result == null ? '분석 전' : _statusText(status, targetType);

  final percentLabel = _isIntakeLoading
      ? '계산중'
      : result != null
          ? '${(ratio * 100).toInt()}% $statusLabel'
          : '-';

  return Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  n.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${n.value.toInt()}${n.unit}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
            Text(
              percentLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Stack(
          children: [
            Container(
              height: 10,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.dividerBg,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            FractionallySizedBox(
              widthFactor: ratio.clamp(0.0, 1.0),
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

  Widget _buildAnalysisGuide() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryFaint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lightbulb_outline,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.analysisGuide.isEmpty
                  ? '이 영양제는 정해진 시간에 꾸준히 복용하는 것이 좋습니다.'
                  : item.analysisGuide,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIReviewSummary() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'AI 리뷰 분석 요약',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Spacer(),
              Icon(Icons.auto_awesome, size: 16, color: Colors.blueAccent),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.scaffoldBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              item.aiSummary.isEmpty ? '아직 분석된 리뷰 데이터가 없습니다.' : item.aiSummary,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: const BoxDecoration(color: Colors.white),
      child: Row(
        children: [
          // 리뷰 작성하기 — 백엔드 연동 전 TODO 스낵바
          Expanded(
            child: OutlinedButton(
              onPressed: _onWriteReview,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '리뷰 작성하기',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 스토어 이동 — 앱 내 스토어 상세 페이지
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                if (_matchedProduct != null) {
                  context.push('/store/detail', extra: _matchedProduct);
                } else {
                  context.push('/store/search');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '스토어 이동',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
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
