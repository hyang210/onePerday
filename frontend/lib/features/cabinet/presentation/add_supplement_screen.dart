import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';
import 'package:simcap/features/cabinet/presentation/barcode_scan_screen.dart';
import 'package:simcap/features/cabinet/widgets/drum_roll_time_picker.dart';
import 'package:simcap/services/auth_service.dart';
import 'package:simcap/services/cabinet_api_service.dart';
import 'package:simcap/services/label_recognition_api_service.dart';

const int _tabLabel = 0;
const int _tabManual = 1;

class AddSupplementScreen extends StatefulWidget {
  final Supplement? initialItem;

  const AddSupplementScreen({super.key, this.initialItem});

  @override
  State<AddSupplementScreen> createState() => _AddSupplementScreenState();
}

class _AddSupplementScreenState extends State<AddSupplementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _selectedTab = _tabLabel;

  bool _isLoadingOCR = false;
  File? _selectedImage;
  String? _imageUrl; // OCR 또는 기존 아이템에서 가져온 이미지 URL
  final ImagePicker _picker = ImagePicker();

  bool _showNameError = false;

  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _nutrientController = TextEditingController();
  int _dailyDose = 1;
  int _dailyFrequency = 1;
  bool _isEditMode = false;
  List<TimeOfDay> _alarmTimes = [];
  final _remainingController = TextEditingController();
  final _totalController = TextEditingController();

  int? _supplementId;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_tabController.indexIsChanging) return;
        setState(() => _selectedTab = _tabController.index);
      });

    final item = widget.initialItem;
    if (item != null) {
      _isEditMode = true;
      _selectedTab = _tabManual;
      _nameController.text = item.name;
      _brandController.text = item.brand;
      _nutrientController.text = item.nutrients.map((n) => n.name).join(', ');
      _remainingController.text = item.remaining.toString();
      _dailyDose = item.dailyDose;
      _dailyFrequency = item.dailyFrequency;
      _alarmTimes = List.from(item.alarmTimes);
      _totalController.text = item.total.toString();
      _imageUrl = item.imageUrl; // 기존 이미지 URL 보존
      if (item.supplementId != null) {
        _supplementId = int.tryParse(item.supplementId!);
      }
      // 전체 개수 입력 시 잔여 개수 비어있으면 자동 반영
      _totalController.addListener(() {
        if (_remainingController.text.isEmpty) {
          setState(() => _remainingController.text = _totalController.text);
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tabController.animateTo(_tabManual);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    _nutrientController.dispose();
    _remainingController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _processOCR(File imageFile) async {
    setState(() => _isLoadingOCR = true);
    try {
      final result = await LabelRecognitionApiService().analyze(imageFile);
      final nutrients = result.nutrientNames;

      if (!mounted) return;
      setState(() {
        _supplementId = int.tryParse(result.supplementId ?? '');
        _nameController.text = result.productName;
        _brandController.text = result.brandName;
        _nutrientController.text = nutrients.isNotEmpty
            ? nutrients.join(', ')
            : '영양제 성분을 찾을 수 없습니다.';
        _imageUrl = result.imageUrl; // DB에서 매칭된 이미지 URL 저장
        _isLoadingOCR = false;
        _tabController.animateTo(_tabManual);
      });
    } catch (e) {
      debugPrint('OCR Upload Error: $e');
      if (!mounted) return;
      setState(() => _isLoadingOCR = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OCR 분석에 실패했습니다. 내용을 직접 확인해주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      _tabController.animateTo(_tabManual);
    }
  }

  Future<void> _navigateToScan() async {
    final result = await context.push<ScanResult>('/cabinet/scan');
    if (result == null || !mounted) return;

    if (result.isBarcode) {
      // 바코드만으로는 DB 제품을 찾을 수 없어 라벨 촬영으로 안내
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('바코드로 제품을 찾지 못했습니다. 라벨을 촬영해주세요.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (result.isOCR && result.imageFile != null) {
      await _handlePickedImage(result.imageFile!);
    }
  }

  Future<void> _pickFromCamera() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (image != null) {
      await _handlePickedImage(File(image.path));
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await _handlePickedImage(File(image.path));
    }
  }

  Future<void> _handlePickedImage(File imageFile) async {
    setState(() => _selectedImage = imageFile);
    await _processOCR(imageFile);
  }

  String _toTimeString(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _onRegister() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _showNameError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('제품명을 입력해주세요!'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final remainingText = _remainingController.text.trim();
    if (remainingText.isNotEmpty) {
      final parsed = int.tryParse(remainingText);
      if (parsed == null || parsed < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('잔여 수량은 0 이상의 숫자만 입력 가능합니다.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (_alarmTimes.length < _dailyFrequency) {
      final remaining = _dailyFrequency - _alarmTimes.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _alarmTimes.isEmpty
                ? '복용 알림 시간을 설정해주세요!'
                : '알림 시간 ${remaining}개를 더 설정해주세요!',
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final user = AuthService().currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('로그인이 필요합니다.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 신규 등록 시에만 영양제 ID 검사
    if (!_isEditMode && _supplementId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('영양제 ID를 찾을 수 없습니다. 다시 검색해주세요.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final remainingCount = int.tryParse(_remainingController.text) ?? 0;
    final totalCount = int.tryParse(_totalController.text) ?? remainingCount;

    final newSupplement = Supplement(
      id: widget.initialItem?.id,
      supplementId:
          _supplementId?.toString() ?? widget.initialItem?.supplementId,
      inventoryId: widget.initialItem?.inventoryId,
      name: name,
      brand: _brandController.text.trim(),
      imagePath: _selectedImage?.path ?? widget.initialItem?.imagePath,
      imageUrl: _imageUrl ?? widget.initialItem?.imageUrl,
      remaining: remainingCount,
      total: totalCount,
      dailyDose: _dailyDose,
      dailyFrequency: _dailyFrequency,
      alarmTimes: _alarmTimes,
      nutrients: widget.initialItem != null
          ? widget.initialItem!.nutrients
          : _nutrientController.text
                .split(',')
                .where((e) => e.trim().isNotEmpty)
                .map(
                  (e) => Nutrient(
                    name: e.trim(),
                    value: 0,
                    unit: '',
                    percent: 0.7,
                  ),
                )
                .toList(),
      analysisGuide: widget.initialItem?.analysisGuide ?? '방금 등록된 영양제입니다.',
      aiSummary: widget.initialItem?.aiSummary ?? '분석 데이터 준비 중',
    );

    try {
      final alarmTimes = _alarmTimes.map(_toTimeString).toList();
      var savedSupplement = newSupplement;

      if (_isEditMode) {
        final inventoryId = widget.initialItem?.inventoryId;
        if (inventoryId == null) {
          throw Exception('서버에 등록되지 않은 영양제입니다. 삭제 후 다시 등록해주세요.');
        }
        await CabinetApiService().updateCabinetItem(
          inventoryId: inventoryId,
          dailyDose: _dailyDose,
          dailyFrequency: _dailyFrequency,
          stockCount: remainingCount,
          totalCount: totalCount,
          alarmTimes: alarmTimes,
        );
      } else {
        final createdItem = await CabinetApiService().createCabinetItem(
          userUuid: user.id,
          supplementId: _supplementId!,
          dailyDose: _dailyDose,
          dailyFrequency: _dailyFrequency,
          stockCount: remainingCount,
          totalCount: totalCount,
          alarmTimes: alarmTimes,
        );
        // 복용 완료/취소에 서버 보관함 ID가 필요하므로 응답 값으로 맞춤
        savedSupplement = newSupplement.copyWith(
          id: createdItem.id,
          supplementId: createdItem.supplementId,
          inventoryId: createdItem.id,
        );
      }

      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) Navigator.pop(context, savedSupplement);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditMode ? '캐비닛 수정 실패: $e' : '캐비닛 저장 실패: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (!_isEditMode) ...[_buildTabBar(), const Divider(height: 1)],
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildTabContent(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selectedTab == _tabManual
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: _buildRegisterButton(),
              ),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isEditMode = widget.initialItem != null;
    const tabTitles = ['영양제 촬영', '직접 검색'];
    return AppBar(
      title: Text(
        isEditMode ? '영양제 수정' : tabTitles[_selectedTab],
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: Colors.grey,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          fontFamily: 'Pretendard',
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontFamily: 'Pretendard',
        ),
        indicatorColor: AppColors.primary,
        indicatorWeight: 2.5,
        tabs: const [
          Tab(icon: Icon(Icons.camera_alt_rounded, size: 18), text: '영양제 촬영'),
          Tab(icon: Icon(Icons.search_rounded, size: 18), text: '직접 검색'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case _tabLabel:
        return _buildLabelTab();
      case _tabManual:
        return _buildManualTab();
      default:
        return _buildLabelTab();
    }
  }

  Widget _buildLabelTab() {
    return SingleChildScrollView(
      key: const ValueKey('label'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            GestureDetector(
              onTap: _isLoadingOCR ? null : _navigateToScan,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isLoadingOCR
                        ? AppColors.primary
                        : AppColors.primary.withOpacity(0.2),
                    width: _isLoadingOCR ? 2 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: _isLoadingOCR
                    ? _buildOCRLoading()
                    : _selectedImage != null
                    ? _buildImagePreviewInCard()
                    : _buildLabelGuide(),
              ),
            ),
            const SizedBox(height: 24),
            if (!_isLoadingOCR) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildSourceButton(
                      icon: Icons.camera_alt_rounded,
                      label: '카메라 / 바코드',
                      onTap: _navigateToScan,
                      filled: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSourceButton(
                      icon: Icons.photo_library_outlined,
                      label: '갤러리 선택',
                      onTap: _pickFromGallery,
                      filled: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_selectedImage != null)
                TextButton(
                  onPressed: () => setState(() => _selectedImage = null),
                  child: Text(
                    '사진 다시 선택',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLabelGuide() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.camera_alt_rounded,
            size: 52,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '라벨을 촬영해주세요',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '영양제를 촬영하면 데이터를 자동으로 찾아요',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
        const SizedBox(height: 16),
        _buildHintChip('영양제 라벨이 선명하게 보이도록 촬영하세요'),
      ],
    );
  }

  Widget _buildImagePreviewInCard() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.file(_selectedImage!, fit: BoxFit.cover),
        ),
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  '분석 완료 — 직접 입력 탭에서 확인하세요',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOCRLoading() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 20),
        const Text(
          '데이터 찾는 중...',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          '잠시만 기다려 주세요',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _buildSourceButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: filled ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: filled ? Colors.white : Colors.black87),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: filled ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildManualTab() {
    return ListView(
      key: const ValueKey('manual'),
      padding: const EdgeInsets.all(20),
      children: [
        if (_selectedImage != null) _buildSelectedImagePreview(),
        _buildSectionTitle('기본 정보'),
        _buildInputField(
          '제품명',
          _nameController,
          hasError: _showNameError && _nameController.text.isEmpty,
          readOnly: true,
        ),
        _buildInputField('브랜드명', _brandController, readOnly: true),
        _buildInputField(
          '주요 성분',
          _nutrientController,
          isMultiLine: true,
          readOnly: true,
        ),
        const SizedBox(height: 24),
        _buildSectionTitle('복용 및 수량'),
        _buildReadOnlyInfoRow('1회 복용량', '$_dailyDose정'),
        _buildReadOnlyInfoRow('하루 복용 횟수', '${_dailyFrequency}회'),
        const SizedBox(height: 8),
        _buildAlarmTimesSection(),
        const SizedBox(height: 12),
        _buildRemainingQuantitySection(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildReadOnlyInfoRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityStepper(
    String label,
    int value,
    void Function(int) onChanged, {
    bool readOnly = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: readOnly ? Colors.white : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: () {
              if (value > 1) onChanged(value - 1);
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: value > 1 ? Colors.grey : Colors.grey.shade300,
                ),
              ),
              child: Icon(
                Icons.remove,
                size: 16,
                color: value > 1 ? Colors.grey : Colors.grey.shade300,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 44,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$value',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              if (value < 99) onChanged(value + 1);
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary),
              ),
              child: const Icon(Icons.add, size: 16, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmTimesSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alarm, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    text: '복용 알림 시간',
                    style: TextStyle(fontWeight: FontWeight.w600),
                    children: [
                      TextSpan(
                        text: ' *',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_alarmTimes.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _alarmTimes = []),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '초기화',
                    style: TextStyle(fontSize: 12, color: AppColors.danger),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_dailyFrequency, (i) {
              final isSet = _alarmTimes.length > i;
              final label = _dailyFrequency == 1
                  ? (isSet ? _formatTime(_alarmTimes[i]) : '알림 시간 설정하기')
                  : (isSet
                        ? '${i + 1}회차 · ${_formatTime(_alarmTimes[i])}'
                        : '알림 시간${i + 1} 설정하기');

              return GestureDetector(
                onTap: () => _pickAlarmTime(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSet ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: isSet ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSet ? Icons.access_time : Icons.add_alarm_outlined,
                        size: 14,
                        color: isSet ? Colors.white : Colors.grey,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isSet ? Colors.white : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _alarmTimes.isEmpty
                ? '알림 시간을 설정해주세요.'
                : _alarmTimes.length < _dailyFrequency
                ? '나머지 알림 시간도 설정해주세요.'
                : '알림 시간을 탭하면 변경할 수 있습니다.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  List<TimeOfDay> _getDefaultPreviewTimes() {
    switch (_dailyFrequency) {
      case 1:
        return [const TimeOfDay(hour: 9, minute: 0)];
      case 2:
        return [
          const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 19, minute: 0),
        ];
      case 3:
        return [
          const TimeOfDay(hour: 8, minute: 0),
          const TimeOfDay(hour: 13, minute: 0),
          const TimeOfDay(hour: 19, minute: 0),
        ];
      default:
        return List.generate(
          _dailyFrequency,
          (i) => TimeOfDay(hour: (8 + i * 4) % 24, minute: 0),
        );
    }
  }

  Future<void> _pickAlarmTime(int index) async {
    final initial = index < _alarmTimes.length
        ? _alarmTimes[index]
        : const TimeOfDay(hour: 9, minute: 0);

    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => DrumRollTimePicker(initialTime: initial),
    );

    if (picked != null && mounted) {
      setState(() {
        if (index < _alarmTimes.length) {
          _alarmTimes[index] = picked;
        } else {
          _alarmTimes.add(picked);
        }
      });
    }
  }

  String _formatTime(TimeOfDay time) {
    final period = time.hour < 12 ? '오전' : '오후';
    final h = time.hour == 0
        ? 12
        : time.hour <= 12
        ? time.hour
        : time.hour - 12;
    final m = time.minute.toString().padLeft(2, '0');
    return '$period $h:$m';
  }

  Widget _buildRemainingQuantitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInputField(
          '전체 개수 (정/캡슐)',
          _totalController,
          isNumber: true,
          editable: true,
        ),
        const SizedBox(height: 4),
        _buildInputField(
          '영양제 잔여 개수',
          _remainingController,
          isNumber: true,
          editable: true,
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [30, 60, 90, 120, 180].map((val) {
              final isSelected = _remainingController.text == val.toString();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$val정'),
                  selected: isSelected,
                  onSelected: (_) => setState(
                    () => _remainingController.text = val.toString(),
                  ),
                  selectedColor: AppColors.primaryLight,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primary : Colors.black54,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isSelected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedImagePreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _selectedImage!,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '사진 업로드 완료',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '정보가 자동으로 입력되었습니다',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _selectedImage = null),
            icon: const Icon(Icons.close, size: 20, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(
    String hint,
    TextEditingController controller, {
    bool isMultiLine = false,
    bool isNumber = false,
    bool hasError = false,
    bool readOnly = false,
    bool editable = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: readOnly
            ? Colors.white
            : (editable ? Colors.grey.shade100 : Colors.white),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: hasError ? AppColors.danger : AppColors.border,
          width: hasError ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onChanged: (val) {
          if (hasError && val.isNotEmpty) {
            setState(() => _showNameError = false);
          }
        },
        maxLines: isMultiLine ? 3 : 1,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          border: InputBorder.none,
          errorText: hasError ? '제품명을 입력해 주세요' : null,
          errorStyle: const TextStyle(height: 0),
        ),
        style: const TextStyle(fontSize: 15, color: Colors.black87),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.black54,
        ),
      ),
    );
  }

  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _onRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(
          widget.initialItem != null ? '수정 완료' : '캐비닛에 추가하기',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
