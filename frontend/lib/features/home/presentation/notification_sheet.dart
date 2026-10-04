import 'package:flutter/material.dart';
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/services/auth_service.dart';
import 'package:simcap/services/reminder_api_service.dart';
import 'package:simcap/routes/app_router.dart';
import 'package:simcap/services/reorder_service.dart';

class NotificationSheet extends StatelessWidget {
  const NotificationSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      isScrollControlled: true,
      builder: (context) => const NotificationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;

    final remindersFuture = user == null
        ? Future<ReminderData>.value(
            ReminderData(doseReminders: [], stockReminders: []),
          )
        : ReminderApiService().fetchTodayReminders(userUuid: user.id);

    return Container(
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.6,
      child: FutureBuilder<ReminderData>(
        future: remindersFuture,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final doseList = data?.doseReminders ?? [];
          final stockList = data?.stockReminders ?? [];
          final bool isEmpty = doseList.isEmpty && stockList.isEmpty;
          final int count = doseList.length + stockList.length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        '알림',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!isEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 30),

              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : snapshot.hasError
                        ? const Center(
                            child: Text(
                              '알림을 불러오지 못했어요.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black54,
                              ),
                            ),
                          )
                        : isEmpty
                            ? _buildEmptyState()
                            : ListView(
                                children: [
                                  // 섹션 1: 오늘 미복용 알림
                                  if (doseList.isNotEmpty) ...[
                                    _buildSectionLabel(
                                      '오늘 복용 알림',
                                      Icons.medication_liquid,
                                    ),
                                    ...doseList.map(
                                      (item) => _buildPillItem(item),
                                    ),
                                    const SizedBox(height: 8),
                                  ],

                                  // 섹션 2: 재구매 필요 알림
                                  if (stockList.isNotEmpty) ...[
                                    _buildSectionLabel(
                                      '재구매 알림',
                                      Icons.shopping_bag_outlined,
                                    ),
                                    ...stockList.map(
                                      (item) =>
                                          _buildStockItem(context, item),
                                    ),
                                  ],
                                ],
                              ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 섹션 라벨
  Widget _buildSectionLabel(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // 미복용 알림 카드
  Widget _buildPillItem(DoseReminder item) {
    final timeLabel = _formatTimeString(item.supplementTime);
    final doseLabel =
        ' (${item.doseIndex + 1}회차${timeLabel.isNotEmpty ? " · $timeLabel" : ""})';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F3),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.medication_liquid,
            color: Colors.redAccent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '복용 알림$doseLabel',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '[${item.supplementName}]을(를) 아직 복용하지 않으셨어요!',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 재구매 알림 카드
  Widget _buildStockItem(BuildContext context, StockReminder item) {
    final bool isCritical = item.status == 'CRITICAL_STOCK';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCritical ? const Color(0xFFFFF3F3) : const Color(0xFFFFFDE7),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            color: isCritical ? Colors.redAccent : const Color(0xFFFFC107),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '재고 부족',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    // D-Day 배지
                    if (item.daysLeft != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isCritical
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFFFFC107),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.daysLeft! <= 0
                              ? '오늘 소진'
                              : 'D-${item.daysLeft}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.daysLeft == null
                      ? '[${item.supplementName}]이(가) ${item.stockCount}정 남았습니다.'
                      : '[${item.supplementName}]이(가) ${item.stockCount}정(${item.daysLeft}일분) 남았습니다.',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                // 스토어 이동 버튼
                GestureDetector(
                  onTap: () {
                    // 시트가 닫혀도 유지되는 앱 루트 context로 재구매 진행
                    final rootContext = AppRouter.navigatorKey.currentContext;
                    Navigator.pop(context);
                    if (rootContext != null) {
                      startReorder(rootContext, inventoryId: item.inventoryId);
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '바로 재구매',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isCritical
                              ? Colors.redAccent
                              : const Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 11,
                        color: isCritical
                            ? Colors.redAccent
                            : const Color(0xFF4CAF50),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeString(String value) {
    if (value.isEmpty) return '';

    final parts = value.split(':');
    if (parts.length < 2) return value;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) return value;

    final isPm = hour >= 12;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');

    return '${isPm ? "오후" : "오전"} $displayHour:$displayMinute';
  }

  // 알림 없음 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              size: 44,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '모든 알림을 확인했어요!',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '오늘 복용을 모두 완료하면 알림이 사라집니다 🎉',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // 복용 시점 배지
}