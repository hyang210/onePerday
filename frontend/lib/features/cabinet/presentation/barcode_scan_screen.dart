import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simcap/core/constant/app_constants.dart';
import 'package:simcap/features/cabinet/domain/dataModels/supplement_model.dart';
import 'package:simcap/features/store/data/store_product_data.dart';
import 'package:simcap/features/store/presentation/supplement_detail_screen.dart';
import 'package:simcap/features/cabinet/presentation/supplement_info_screen.dart';
import 'dart:async';
import 'package:simcap/services/store_api_service.dart';
import 'package:simcap/services/label_recognition_api_service.dart';

/// 통합 스캔 결과
class ScanResult {
  final String? barcodeValue;
  final BarcodeFormat? barcodeFormat;
  final File? imageFile;

  const ScanResult({this.barcodeValue, this.barcodeFormat, this.imageFile});

  bool get isBarcode => barcodeValue != null;
  bool get isOCR => imageFile != null;
}

typedef BarcodeScanResult = ScanResult;

class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  CameraController? _cameraController;
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  final ImagePicker _picker = ImagePicker();

  bool _isInitialized = false;
  bool _isScanning = false;
  bool _hasScanned = false;
  bool _isTorchOn = false;
  bool _isCapturing = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _isInitialized = true;
      });

      // 바코드 실시간 감지 시작
      _startBarcodeScanning();
    } catch (e) {
      debugPrint('카메라 초기화 실패: $e');
    }
  }

  // ── 실시간 바코드 스캔 ────────────────────────────────────────────────────
  void _startBarcodeScanning() {
    _cameraController?.startImageStream((CameraImage image) async {
      if (_isScanning || _hasScanned || !mounted) return;
      _isScanning = true;

      try {
        final inputImage = _convertCameraImage(image);
        if (inputImage == null) {
          _isScanning = false;
          return;
        }

        final barcodes = await _barcodeScanner.processImage(inputImage);
        if (barcodes.isNotEmpty && !_hasScanned && mounted) {
          final barcode = barcodes.first;
          if (barcode.rawValue != null) {
            setState(() => _hasScanned = true);
            await _cameraController?.stopImageStream();
            if (mounted) _showBarcodeResultSheet(barcode);
          }
        }
      } catch (e) {
        debugPrint('바코드 스캔 오류: $e');
      }

      _isScanning = false;
    });
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  // ── 라벨 촬영 버튼 ────────────────────────────────────────────────────────
  Future<void> _captureForOCR() async {
    if (_cameraController == null || !_isInitialized || _isCapturing) return;
    setState(() {
      _isCapturing = true;
      _isProcessing = true;
    });

    try {
      await _cameraController!.stopImageStream();
      final XFile photo = await _cameraController!.takePicture();
      if (!mounted) return;

      final File imageFile = File(photo.path);
      await _uploadAndProcessOCR(imageFile);
    } catch (e) {
      debugPrint('촬영 실패: $e');
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isProcessing = false;
          _hasScanned = false;
        });
        _startBarcodeScanning();
      }
    }
  }

  Future<void> _pickGalleryForOCR() async {
    await _cameraController?.stopImageStream();
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      if (mounted) _startBarcodeScanning();
      return;
    }
    if (!mounted) return;
    setState(() {
      _isProcessing = true;
    });

    final File imageFile = File(image.path);
    await _uploadAndProcessOCR(imageFile);
  }

  Future<void> _uploadAndProcessOCR(File imageFile) async {
    try {
      final result = await LabelRecognitionApiService().analyze(imageFile);

      if (!mounted) return;

      final List<Nutrient> nutrientsList = result.nutrientNames
          .map(
            (name) => Nutrient(name: name, value: 0, unit: '', percent: 0.0),
          )
          .toList();

      final supplement = Supplement(
        supplementId: result.supplementId,
        name: result.productName,
        brand: result.brandName,
        imagePath: imageFile.path,
        imageUrl: result.imageUrl,
        remaining: 0,
        total: 90,
        dailyDose: 1,
        dailyFrequency: 1,
        nutrients: nutrientsList,
        analysisGuide: 'OCR 분석 완료: 백엔드에서 성분 정보를 가져왔습니다.',
        aiSummary: '',
      );

      await context.push('/cabinet/info', extra: supplement);

      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isProcessing = false;
          _hasScanned = false;
        });
        _startBarcodeScanning();
      }
    } catch (e) {
      debugPrint('OCR Upload Error: $e');
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _isProcessing = false;
        _hasScanned = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OCR 분석에 실패했습니다. 내용을 직접 확인해주세요.'),
          duration: Duration(seconds: 2),
        ),
      );
      _startBarcodeScanning();
    }
  }

  // ── 바코드 결과 바텀시트 ─────────────────────────────────────────────────
  void _showBarcodeResultSheet(Barcode barcode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
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
                Icons.check_circle_rounded,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '바코드 인식 완료',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.scaffoldBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '바코드',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    barcode.rawValue ?? '-',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '이 바코드로 영양제 정보를 불러올게요',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _hasScanned = false);
                      _startBarcodeScanning();
                    },
                    child: const Text(
                      '다시 스캔',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      context.pop(ScanResult(barcodeValue: barcode.rawValue!));
                    },
                    child: const Text(
                      '이 바코드 사용',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isTorchOn ? Icons.flash_on : Icons.flash_off,
              color: _isTorchOn ? Colors.yellow : Colors.white,
            ),
            onPressed: () async {
              await _cameraController?.setFlashMode(
                _isTorchOn ? FlashMode.off : FlashMode.torch,
              );
              setState(() => _isTorchOn = !_isTorchOn);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 카메라 뷰
          Positioned.fill(
            child: _isInitialized && _cameraController != null
                ? CameraPreview(_cameraController!)
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),

          // 하단 버튼
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),

          // 로딩 오버레이
          if (_isProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.7),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      '데이터 찾는 중...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSearchSheet() {
    final searchController = TextEditingController();
    List<StoreProduct> results = [];
    bool sheetLoading = false;
    bool isInit = false;
    Timer? debounce;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // 최초 시트 진입 시 전체 영양제 목록 API 조회
          if (!isInit) {
            isInit = true;
            sheetLoading = true;
            StoreApiService()
                .fetchSupplements()
                .then((apiResults) {
                  if (ctx.mounted) {
                    setSheetState(() {
                      results = apiResults;
                      sheetLoading = false;
                    });
                  }
                })
                .catchError((e) {
                  if (ctx.mounted) {
                    setSheetState(() {
                      results = List.from(allProducts);
                      sheetLoading = false;
                    });
                  }
                });
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) => Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '영양제 검색',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: '제품명 또는 브랜드명 검색',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                        onChanged: (val) {
                          if (debounce?.isActive ?? false) debounce?.cancel();
                          debounce = Timer(
                            const Duration(milliseconds: 300),
                            () async {
                              if (!ctx.mounted) return;
                              setSheetState(() {
                                sheetLoading = true;
                              });
                              try {
                                final apiResults = await StoreApiService()
                                    .fetchSupplements(keyword: val);
                                if (ctx.mounted) {
                                  setSheetState(() {
                                    results = apiResults;
                                    sheetLoading = false;
                                  });
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  setSheetState(() {
                                    // 에러 발생 시 로컬 하드코딩 리스트로 Fallback
                                    results = val.isEmpty
                                        ? List.from(allProducts)
                                        : allProducts
                                              .where(
                                                (p) =>
                                                    p.name
                                                        .toLowerCase()
                                                        .contains(
                                                          val.toLowerCase(),
                                                        ) ||
                                                    p.brand
                                                        .toLowerCase()
                                                        .contains(
                                                          val.toLowerCase(),
                                                        ),
                                              )
                                              .toList();
                                    sheetLoading = false;
                                  });
                                }
                              }
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: sheetLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : results.isEmpty
                      ? const Center(
                          child: Text(
                            '검색 결과가 없습니다',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = results[i];
                            return ListTile(
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryLight,
                                  shape: BoxShape.circle,
                                ),
                                child:
                                    p.imageUrl != null && p.imageUrl!.isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          p.imageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Icon(
                                                    Icons.medication_rounded,
                                                    color: AppColors.primary,
                                                    size: 22,
                                                  ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.medication_rounded,
                                        color: AppColors.primary,
                                        size: 22,
                                      ),
                              ),
                              title: Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                p.brand,
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(sheetCtx);
                                context.push(
                                  '/cabinet/info',
                                  extra: p.toSupplement(),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(
        bottom: bottomPad + 24,
        top: 20,
        left: 40,
        right: 40,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.8), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _bottomButton(
                icon: Icons.photo_library_outlined,
                label: '갤러리',
                size: 48,
                onTap: _pickGalleryForOCR,
              ),
              const SizedBox(width: 24),
              _bottomButton(
                icon: _isCapturing
                    ? Icons.hourglass_top_rounded
                    : Icons.camera_alt_rounded,
                label: '라벨 촬영',
                size: 72,
                onTap: _isCapturing ? () {} : _captureForOCR,
                primary: true,
              ),
              const SizedBox(width: 24),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _showSearchSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '직접 검색',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomButton({
    required IconData icon,
    required String label,
    required double size,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary ? Colors.white : Colors.white.withOpacity(0.2),
              border: Border.all(color: Colors.white, width: primary ? 0 : 1.5),
            ),
            child: Icon(
              icon,
              color: primary ? Colors.black87 : Colors.white,
              size: primary ? 32 : 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 11,
              fontWeight: primary ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
