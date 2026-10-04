import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';
import 'package:simcap/providers/supplement_provider.dart';
import 'notification_sheet.dart';
import 'package:simcap/services/intake_api_service.dart';
import 'package:simcap/services/auth_service.dart';
import 'package:simcap/services/reorder_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedDate = DateTime.now();

  bool _isNutritionChecking = false;
  bool _hasNutritionWarning = false;
  bool _hasNutritionDanger = false;
  List<IntakeResult> _homeIntakeResults = [];

  Future<void> _handleRefresh() async {
    if (!mounted) return;
    final notifier = SupplementProvider.of(context);
    await notifier.loadCabinetFromServer();
    if (!mounted) return;
    await _checkHomeNutritionSafety();
    if (mounted) setState(() {});
  }

  Future<void> _checkHomeNutritionSafety() async {
    if (_isNutritionChecking) return;
    if (!mounted) return;

    final notifier = SupplementProvider.of(context);
    final supplements = notifier.supplements;

    // 실제 사용자 정보 조회
    final profile = await AuthService().getIntakeProfile();
    if (!mounted) return;

    final List<Map<String, dynamic>> takenCartItems = [];
    for (final s in supplements) {
      if (s.supplementId == null) continue;
      int takenCount = 0;
      if (s.dailyFrequency <= 1) {
        if (notifier.isDoneOn(s.id, _selectedDate)) takenCount = 1;
      } else {
        for (int i = 0; i < s.dailyFrequency; i++) {
          if (notifier.isDoneOnIndex(s.id, _selectedDate, i)) takenCount++;
        }
      }
      takenCartItems.add({
        'productId': s.supplementId,
        'name': s.name,
        'brand': s.brand,
        'count': takenCount > 0 ? takenCount : 1,
      });
    }

    if (takenCartItems.isEmpty) return;

    setState(() => _isNutritionChecking = true);

    try {
      final results = await IntakeApiService().checkOverdoseByCartItems(
        cartItems: takenCartItems,
        age: profile.age,
        gender: profile.gender,
      );

      if (!mounted) return;

      debugPrint('===== HOME INTAKE RESULT =====');
      for (final r in results) {
        debugPrint(
          '${r.nutrientName} current=${r.currentTotal} '
          'recommended=${r.recommendedIntake} upper=${r.upperLimit} status=${r.status}',
        );
      }

      setState(() {
        _hasNutritionDanger = results.any(
          (r) => r.status == 'danger' || r.status == 'very_low',
        );
        _hasNutritionWarning = results.any(
          (r) => r.status == 'low' || r.status == 'enough',
        );
        _homeIntakeResults = results;
        _isNutritionChecking = false;
      });
    } catch (e) {
      debugPrint('[HomeScreen] 영양 검사 실패: \$e');
      if (!mounted) return;
      setState(() {
        _isNutritionChecking = false;
        _hasNutritionWarning = false;
        _hasNutritionDanger = false;
        _homeIntakeResults = [];
      });
    }
  }

  String _formatDateForApi(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _formatTimeForApi(TimeOfDay? time) {
    final t = time ?? const TimeOfDay(hour: 9, minute: 0);
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _completeDose({
    required Supplement supplement,
    required int doseIndex,
    required TimeOfDay? supplementTime,
    required VoidCallback onLocalComplete,
  }) async {
    final user = AuthService().currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인이 필요합니다.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final inventoryId = supplement.inventoryId ?? supplement.id;

    try {
      await IntakeApiService().completeIntake(
        userUuid: user.id,
        inventoryId: inventoryId,
        doseIndex: doseIndex,
        date: _formatDateForApi(_selectedDate),
        supplementTime: _formatTimeForApi(supplementTime),
      );

      onLocalComplete();
      // setState 완료 후 검사 실행 (레이스 컨디션 방지)
      if (mounted) setState(() {});
      await Future.microtask(() {});
      if (mounted) await _checkHomeNutritionSafety();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('복용 완료 저장 실패: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _cancelDose({
    required Supplement supplement,
    required int doseIndex,
    required TimeOfDay? supplementTime,
    required VoidCallback onLocalCancel,
  }) async {
    final user = AuthService().currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인이 필요합니다.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final inventoryId = supplement.inventoryId ?? supplement.id;

    try {
      await IntakeApiService().cancelIntake(
        userUuid: user.id,
        inventoryId: inventoryId,
        doseIndex: doseIndex,
        date: _formatDateForApi(_selectedDate),
        supplementTime: _formatTimeForApi(supplementTime),
      );

      onLocalCancel();
      // setState 완료 후 검사 실행 (레이스 컨디션 방지)
      if (mounted) setState(() {});
      await Future.microtask(() {});
      if (mounted) await _checkHomeNutritionSafety();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('복용 취소 실패: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final notifier = SupplementProvider.of(context);
      await notifier.loadCabinetFromServer();
      if (!mounted) return;
      _checkHomeNutritionSafety();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildWeeklyCalendar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                color: AppColors.primary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStreakCard(),
                        _buildReorderCard(),
                        const SizedBox(height: 24),
                        Text(
                          _isSelectedToday ? '오늘의 영양 성분 분석' : '영양 성분 분석',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildNutritionCard(),
                        const SizedBox(height: 32),
                        Text(
                          _isSelectedToday
                              ? '오늘 남은 복용'
                              : '${_selectedDate.month}월 ${_selectedDate.day}일 복용 현황',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildMedicationList(),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomCalendar(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  // ── 월간 복용 달력 바텀시트 ──────────────────────────────────────────────
  void _showMonthlyCalendar(BuildContext context, SupplementNotifier notifier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MonthlyCalendarSheet(notifier: notifier),
    );
  }

  // ── 주간 캘린더 ──────────────────────────────────────────────────────────
  int _weekOffset = 0;

  Widget _buildWeeklyCalendar() {
    final notifier = SupplementProvider.of(context);
    final notificationCount = notifier.totalNotificationCount;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => _showCustomCalendar(context),
                  child: Row(
                    children: [
                      Text(
                        "${_selectedDate.month}. ${_selectedDate.day} "
                        "${DateFormat('E', 'ko_KR').format(_selectedDate)}요일",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
                Badge(
                  label: Text('$notificationCount'),
                  isLabelVisible: notificationCount > 0,
                  backgroundColor: Colors.redAccent,
                  offset: const Offset(-2, 2),
                  child: IconButton(
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.primary,
                      size: 26,
                    ),
                    onPressed: () => NotificationSheet.show(context),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                ),
              ],
            ),
          ),
          // 주 이동 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => setState(() => _weekOffset--),
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: AppColors.primary,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                if (_weekOffset != 0)
                  GestureDetector(
                    onTap: () => setState(() {
                      _weekOffset = 0;
                      _selectedDate = DateTime.now();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        '오늘로',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                IconButton(
                  onPressed: _weekOffset < 0
                      ? () => setState(() => _weekOffset++)
                      : null,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: _weekOffset < 0
                        ? AppColors.primary
                        : Colors.grey[300],
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (index) {
              final DateTime now = DateTime.now();
              final DateTime firstDayOfWeek = now
                  .subtract(Duration(days: now.weekday - 1))
                  .add(Duration(days: _weekOffset * 7));
              final DateTime date = firstDayOfWeek.add(Duration(days: index));

              final bool isSelected =
                  date.day == _selectedDate.day &&
                  date.month == _selectedDate.month;
              final bool isFuture = date.isAfter(now);

              final notifier = SupplementProvider.of(context);
              final bool allDone = !isFuture && notifier.isAllDoneOn(date);
              final bool partialDone =
                  !isFuture && !allDone && notifier.hasDoseRecordOn(date);

              return Column(
                children: [
                  Text(
                    ["월", "화", "수", "목", "금", "토", "일"][index],
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? AppColors.primary : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => setState(() => _selectedDate = date),
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        "${date.day}",
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: allDone ? AppColors.primary : Colors.transparent,
                      border: partialDone
                          ? Border.all(color: AppColors.primary, width: 1)
                          : null,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── 복용 스트릭 & 통계 카드 ──────────────────────────────────────────────
  /// 7일 안에 떨어지는 영양제와 바로 재구매 버튼
  Widget _buildReorderCard() {
    final lowStock =
        SupplementProvider.of(context).supplements
            .where((s) => s.isLowStock)
            .toList()
          ..sort((a, b) => a.daysLeft!.compareTo(b.daysLeft!));
    if (lowStock.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.warning),
              SizedBox(width: 6),
              Text(
                '곧 떨어져요',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...lowStock.map(_buildReorderRow),
        ],
      ),
    );
  }

  Widget _buildReorderRow(Supplement supplement) {
    final days = supplement.daysLeft!;
    final runOut = supplement.runOutDate!;
    final color = supplement.isCriticalStock ? AppColors.danger : AppColors.warning;
    final status = days == 0 ? '오늘 소진' : '$days일분 남음';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplement.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '$status · ${runOut.month}/${runOut.day} 소진 예정',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () =>
                startReorder(context, inventoryId: supplement.inventoryId),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('재구매'),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakCard() {
    final notifier = SupplementProvider.of(context);
    final streak = notifier.currentStreak;
    final best = notifier.bestStreak;
    final monthly = notifier.monthlyComplianceRate;
    final total = notifier.totalDoneDays;
    final done = notifier.todayDoneCount;
    final supplementTotal = notifier.todayTotalCount;

    // 영양제 미등록 시 안내 카드
    if (supplementTotal == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          children: [
            Icon(Icons.add_circle_outline, color: Colors.white70, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '캐비닛에 영양제를 추가하면\n복용 통계를 확인할 수 있어요!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final todayRate = supplementTotal > 0 ? done / supplementTotal : 0.0;
    final streakMsg = streak == 0
        ? '오늘 복용을 시작해보세요!'
        : streak < 3
        ? '좋은 시작이에요! 계속해봐요 💪'
        : streak < 7
        ? '습관이 만들어지고 있어요 🌱'
        : streak < 30
        ? '대단해요! ${streak}일 연속 복용 중 🔥'
        : '믿기 어려운 기록이에요! 🏆';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 스트릭 + 오늘 진행도
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$streak',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Text(
                            '일 연속',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      streakMsg,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              _buildCircularProgress(done, supplementTotal, todayRate),
            ],
          ),
          const SizedBox(height: 20),
          // 하단: 3개 통계 칩
          Row(
            children: [
              _buildStatChip(
                icon: Icons.calendar_month_outlined,
                label: '이번 달',
                value: '${(monthly * 100).round()}%',
                onTap: () => _showMonthlyCalendar(context, notifier),
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                icon: Icons.emoji_events_outlined,
                label: '최고 기록',
                value: '$best일',
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                icon: Icons.check_circle_outline,
                label: '총 복용',
                value: '$total일',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 원형 진행도 ──────────────────────────────────────────────────────────
  Widget _buildCircularProgress(int done, int total, double rate) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 6,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: rate,
              strokeWidth: 6,
              color: Colors.white,
              backgroundColor: Colors.transparent,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$done/$total',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                '복용',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 통계 칩 ──────────────────────────────────────────────────────────────
  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(onTap != null ? 0.22 : 0.15),
            borderRadius: BorderRadius.circular(14),
            border: onTap != null
                ? Border.all(color: Colors.white.withOpacity(0.3))
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white70, size: 16),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white60, fontSize: 10),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right,
                      size: 10,
                      color: Colors.white60,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 영양 성분 카드 ────────────────────────────────────────────────────────
  Widget _buildNutritionCard() {
    final nutrients = [..._homeIntakeResults]
      ..sort((a, b) => b.ratio.compareTo(a.ratio));

    final boxDeco = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 15,
          offset: const Offset(0, 4),
        ),
      ],
    );

    if (nutrients.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: boxDeco,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 64, color: Colors.grey[200]),
            const SizedBox(height: 16),
            Text(
              '등록된 영양제가 없습니다',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '캐비닛에 영양제를 추가하면\n성분별 섭취량을 분석해 드려요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[400],
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => context.go('/cabinet'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              icon: const Icon(Icons.add, size: 16, color: AppColors.primary),
              label: const Text(
                '영양제 추가하기',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: boxDeco,
      child: Column(
        children: [
          ...nutrients.map((r) => _buildBarGraph(r)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryFaint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: AppColors.primary,
                ),
                SizedBox(width: 8),
                Text(
                  '권장/충분 섭취량과 상한 섭취량 기준으로 분석합니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 바 그래프 ─────────────────────────────────────────────────────────────
  Widget _buildBarGraph(IntakeResult result) {
    final ratio = result.ratio;
    final status = result.status;
    final targetType = result.targetType;

    final barColor = _statusColor(status);
    final pct = '${(ratio * 100).round()}%';
    final statusNote = _statusText(status, targetType);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  result.nutrientName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                pct,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              backgroundColor: Colors.grey[100],
              color: barColor,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(statusNote, style: TextStyle(fontSize: 10, color: barColor)),
        ],
      ),
    );
  }

  // ── 복용 목록 ─────────────────────────────────────────────────────────────
  Widget _buildMedicationList() {
    try {
      final notifier = SupplementProvider.of(context);
      final supplements = notifier.todaySupplements;

      if (supplements.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: Text(
              '등록된 영양제가 없습니다.\n캐비닛에서 영양제를 추가해보세요!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.6),
            ),
          ),
        );
      }

      // 알림 시간 기준 정렬 (첫 번째 알림 시간, 없으면 맨 뒤)
      final sorted = [...supplements]
        ..sort((a, b) {
          final aTime = a.alarmTimes.isNotEmpty
              ? a.alarmTimes.first.hour * 60 + a.alarmTimes.first.minute
              : 9999;
          final bTime = b.alarmTimes.isNotEmpty
              ? b.alarmTimes.first.hour * 60 + b.alarmTimes.first.minute
              : 9999;
          return aTime.compareTo(bTime);
        });

      // 오전/오후 구분 헤더 추가
      final List<Widget> items = [];
      String? lastPeriod;

      for (final s in sorted) {
        final firstAlarm = s.alarmTimes.isNotEmpty ? s.alarmTimes.first : null;
        String? period;
        if (firstAlarm != null) {
          final isPm = firstAlarm.hour >= 12;
          final h = firstAlarm.hour == 0
              ? 12
              : firstAlarm.hour > 12
              ? firstAlarm.hour - 12
              : firstAlarm.hour;
          final m = firstAlarm.minute.toString().padLeft(2, '0');
          period = '${isPm ? "오후" : "오전"} $h:$m';
        }

        if (period != null && period != lastPeriod) {
          if (lastPeriod != null) {
            items.add(const SizedBox(height: 4));
          }
          items.add(
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      period,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Divider(color: Colors.grey.shade200, height: 1),
                  ),
                ],
              ),
            ),
          );
          lastPeriod = period;
        }

        items.add(_buildMedicationToggleCard(s, notifier));
      }

      return Column(children: items);
    } catch (e, stack) {
      debugPrint('ERROR IN _buildMedicationList: $e\n$stack');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '오류가 발생했습니다:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              e.toString(),
              style: TextStyle(color: Colors.red.shade900, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              stack.toString(),
              style: TextStyle(color: Colors.red.shade700, fontSize: 10),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildMedicationToggleCard(
    Supplement supplement,
    SupplementNotifier notifier,
  ) {
    final isToday = _dateOnly(_selectedDate) == _dateOnly(DateTime.now());
    final freq = supplement.dailyFrequency;

    // 1회 복용 — 기존 방식
    if (freq <= 1) {
      final isDone = notifier.isDoneOn(supplement.id, _selectedDate);
      final isEmpty = supplement.remaining <= 0 && !isDone;
      return GestureDetector(
        onTap: isToday
            ? () {
                if (isDone) {
                  _cancelDose(
                    supplement: supplement,
                    doseIndex: 0,
                    supplementTime: supplement.alarmTimes.isNotEmpty
                        ? supplement.alarmTimes.first
                        : null,
                    onLocalCancel: () {
                      notifier.toggleDose(supplement.id, date: _selectedDate);
                    },
                  );
                } else if (!isEmpty) {
                  _completeDose(
                    supplement: supplement,
                    doseIndex: 0,
                    supplementTime: supplement.alarmTimes.isNotEmpty
                        ? supplement.alarmTimes.first
                        : null,
                    onLocalComplete: () {
                      notifier.toggleDose(supplement.id, date: _selectedDate);
                    },
                  );
                }
              }
            : null,

        child: _buildMedicationCard(
          supplement,
          isDone,
          isToday,
          doseLabel: null,
          isEmpty: isEmpty,
        ),
      );
    }

    // 2회 이상 — 시간대 헤더 + 카드
    final alarmTimes = supplement.alarmTimes.isNotEmpty
        ? supplement.alarmTimes
        : List.generate(freq, (i) {
            const defaults = [
              TimeOfDay(hour: 8, minute: 0),
              TimeOfDay(hour: 13, minute: 0),
              TimeOfDay(hour: 19, minute: 0),
              TimeOfDay(hour: 22, minute: 0),
            ];
            return i < defaults.length
                ? defaults[i]
                : TimeOfDay(hour: (8 + i * 4) % 24, minute: 0);
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(freq, (i) {
        final isDone = notifier.isDoneOnIndex(supplement.id, _selectedDate, i);
        final t = i < alarmTimes.length
            ? alarmTimes[i]
            : TimeOfDay(hour: (8 + i * 4) % 24, minute: 0);
        final isPm = t.hour >= 12;
        final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
        final m = t.minute.toString().padLeft(2, '0');
        final timeLabel = '${isPm ? "오후" : "오전"} $h:$m';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 시간대 헤더
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Divider(color: Colors.grey.shade200, height: 1),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6, top: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 13,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    timeLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            // 카드
            Builder(
              builder: (ctx) {
                final isEmpty = supplement.remaining <= 0 && !isDone;
                return GestureDetector(
                  onTap: isToday
                      ? () {
                          if (isDone) {
                            _cancelDose(
                              supplement: supplement,
                              doseIndex: i,
                              supplementTime: t,
                              onLocalCancel: () {
                                notifier.toggleDoseIndex(
                                  supplement.id,
                                  i,
                                  date: _selectedDate,
                                );
                              },
                            );
                          } else if (!isEmpty) {
                            _completeDose(
                              supplement: supplement,
                              doseIndex: i,
                              supplementTime: t,
                              onLocalComplete: () {
                                notifier.toggleDoseIndex(
                                  supplement.id,
                                  i,
                                  date: _selectedDate,
                                );
                              },
                            );
                          }
                        }
                      : null,

                  child: _buildMedicationCard(
                    supplement,
                    isDone,
                    isToday,
                    doseLabel: null,
                    doseIndex: i,
                    totalDose: freq,
                    isEmpty: isEmpty,
                  ),
                );
              },
            ),
          ],
        );
      }),
    );
  }

  Widget _buildMedicationCard(
    Supplement supplement,
    bool isDone,
    bool isToday, {
    String? doseLabel,
    int doseIndex = 0,
    int totalDose = 1,
    bool isEmpty = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isEmpty
            ? Colors.grey.shade50
            : isDone
            ? AppColors.primary.withOpacity(0.12)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isEmpty
              ? Colors.grey.shade300
              : isDone
              ? AppColors.primary.withOpacity(0.4)
              : Colors.grey.withOpacity(0.1),
          width: isDone ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isEmpty
                ? Colors.grey.shade200
                : isDone
                ? AppColors.primary
                : isToday
                ? AppColors.dangerBg
                : Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isEmpty
                ? Icons.warning_amber_rounded
                : isDone
                ? Icons.check_rounded
                : Icons.medication_rounded,
            color: isEmpty
                ? Colors.orange
                : isDone
                ? Colors.white
                : isToday
                ? AppColors.danger
                : Colors.grey[400],
            size: 22,
          ),
        ),
        title: Text(
          supplement.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isEmpty
                ? Colors.grey[400]
                : isDone
                ? Colors.grey[500]
                : Colors.black87,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isEmpty
              ? '재고 소진 · 구매가 필요해요'
              : isDone
              ? '복용 완료 · ${supplement.remaining}정 남음'
              : '${supplement.remaining}정 남음',
          style: TextStyle(
            fontSize: 12,
            color: isEmpty
                ? Colors.orange
                : isDone
                ? Colors.grey[400]
                : Colors.grey[600],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: const Text(
                  '구매 필요',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else if (!isDone && supplement.isLowStock)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'D-${supplement.daysLeft}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool get _isSelectedToday =>
      _dateOnly(_selectedDate) == _dateOnly(DateTime.now());
}

// ── 월간 복용 달력 바텀시트 ──────────────────────────────────────────────────
class _MonthlyCalendarSheet extends StatefulWidget {
  final SupplementNotifier notifier;
  const _MonthlyCalendarSheet({required this.notifier});

  @override
  State<_MonthlyCalendarSheet> createState() => _MonthlyCalendarSheetState();
}

class _MonthlyCalendarSheetState extends State<_MonthlyCalendarSheet> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(DateTime.now().year, DateTime.now().month);
  }

  DateTime get _today => DateTime.now();

  List<DateTime?> get _calendarDays {
    final firstDay = DateTime(_month.year, _month.month, 1);
    final lastDay = DateTime(_month.year, _month.month + 1, 0);
    final leadingBlanks = (firstDay.weekday - 1) % 7;
    return [
      ...List.filled(leadingBlanks, null),
      ...List.generate(
        lastDay.day,
        (i) => DateTime(_month.year, _month.month, i + 1),
      ),
    ];
  }

  String _dayStatus(DateTime day) {
    final n = widget.notifier;
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final d = DateTime(day.year, day.month, day.day);
    if (d.isAfter(today)) return 'future';
    // 현재 등록된 영양제가 없으면 복용 기록만으로 판단
    if (n.supplements.isEmpty) {
      return n.hasDoseRecordOn(d) ? 'partial' : 'none';
    }
    // 현재 영양제 기준으로 모두 복용했으면 allDone
    if (n.isAllDoneOn(d)) return 'allDone';
    // 일부라도 복용 기록이 있으면 partial
    if (n.hasDoseRecordOn(d)) return 'partial';
    return 'none';
  }

  Future<void> _handleRefresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = _today;
    final days = _calendarDays;
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;
    final lastDayOfMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final countDays = isCurrentMonth ? now.day : lastDayOfMonth;

    // 해당 월 복용 일수 계산
    // - 현재 영양제 모두 복용한 날: allDone (완전 복용)
    // - 일부라도 복용 기록 있는 날: partial (부분 복용)
    // 복용률은 완전 복용 기준으로 계산
    int doneDays = 0;
    int partialDays = 0;
    for (int i = 1; i <= countDays; i++) {
      final d = DateTime(_month.year, _month.month, i);
      if (widget.notifier.isAllDoneOn(d)) {
        doneDays++;
      } else if (widget.notifier.hasDoseRecordOn(d)) {
        partialDays++;
      }
    }
    final rate = countDays > 0 ? doneDays / countDays : 0.0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),

          // 헤더: 월 이동
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month - 1);
                }),
              ),
              Expanded(
                child: Text(
                  '${_month.year}년 ${_month.month}월',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _month.year == now.year && _month.month == now.month
                    ? null
                    : () => setState(() {
                        _month = DateTime(_month.year, _month.month + 1);
                      }),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 월간 요약
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem('완전 복용', '$doneDays일', AppColors.primary),
                _summaryItem('부분 복용', '$partialDays일', AppColors.warning),
                _summaryItem(
                  '미복용',
                  '${countDays - doneDays - partialDays}일',
                  Colors.grey,
                ),
                _summaryItem(
                  isCurrentMonth ? '이번 달' : '${_month.month}월',
                  '${(rate * 100).round()}%',
                  AppColors.primaryDark,
                ),
              ],
            ),
          ),

          // 요일 헤더
          Row(
            children: ['월', '화', '수', '목', '금', '토', '일']
                .map(
                  (d) => Expanded(
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),

          // 날짜 그리드
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: days.length,
            itemBuilder: (_, i) {
              final day = days[i];
              if (day == null) return const SizedBox.shrink();
              final status = _dayStatus(day);
              final isToday =
                  day.year == now.year &&
                  day.month == now.month &&
                  day.day == now.day;
              return _buildDayCell(day, status, isToday);
            },
          ),
          const SizedBox(height: 20),

          // 범례
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendItem(AppColors.primary, '전체 복용'),
              const SizedBox(width: 16),
              _legendItem(AppColors.warning, '일부 복용'),
              const SizedBox(width: 16),
              _legendItem(Colors.grey[200]!, '미복용'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(DateTime day, String status, bool isToday) {
    Color bg;
    Color textColor;
    Widget? badge;

    switch (status) {
      case 'allDone':
        bg = AppColors.primary;
        textColor = Colors.white;
        badge = const Positioned(
          top: 2,
          right: 2,
          child: Icon(Icons.check_circle, size: 10, color: Colors.white70),
        );
        break;
      case 'partial':
        bg = AppColors.warning.withOpacity(0.25);
        textColor = Colors.orange.shade800;
        badge = Positioned(
          top: 2,
          right: 2,
          child: Icon(
            Icons.remove_circle,
            size: 10,
            color: Colors.orange.shade400,
          ),
        );
        break;
      case 'future':
        bg = Colors.transparent;
        textColor = Colors.grey[300]!;
        break;
      default:
        bg = Colors.grey[100]!;
        textColor = Colors.grey[500]!;
    }

    return Stack(
      children: [
        Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: isToday
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
          ),
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              color: isToday && status != 'allDone'
                  ? AppColors.primary
                  : textColor,
            ),
          ),
        ),
        if (badge != null) badge,
      ],
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
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
