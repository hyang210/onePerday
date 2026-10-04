import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kReleaseMode 사용을 위해 추가
import 'package:supabase_flutter/supabase_flutter.dart';

///
/// 사용법:
///   color: AppColors.primary
///   backgroundColor: AppColors.scaffoldBg
abstract class AppColors {
  // ── 브랜드 색상 (초록 계열) ──────────────────────────────
  /// 앱 메인 컬러 — 버튼, 아이콘, 강조 텍스트 등 전반에 사용 (88회)
  static const Color primary = Color(0xFF4CAF50);

  /// 메인 컬러 진한 버전 — 텍스트, 가이드 설명 배경 내 글자 (6회)
  static const Color primaryDark = Color(0xFF2E7D32);

  /// 메인 컬러 연한 배경 — 카드 배경, 칩 배경 (14회)
  static const Color primaryLight = Color(0xFFE8F5E9);

  /// 메인 컬러 더 연한 배경 — 아이콘 원형 배경, 입력 필드 배경 (8회)
  static const Color primaryFaint = Color(0xFFF1F8E9);

  // ── 상태 색상 ────────────────────────────────────────────
  /// 경고/오류 — 소진 임박, 병용금지, 에러 텍스트 (13회)
  static const Color danger = Color(0xFFFF6B6B);

  /// 주의 — 잔여량 중간, D-Day 30일 이하 배지 (7회)
  static const Color warning = Color(0xFFFFC107);

  // ── 상태 배경 색상 ────────────────────────────────────────
  /// danger 연한 배경 — 경고 카드, 배지 배경 (4회)
  static const Color dangerBg = Color(0xFFFFEBEB);

  /// warning 연한 배경 — 주의 카드 배경 (2회)
  static const Color warningBg = Color(0xFFFFFDE7);

  /// 긴급 알림 배경 (2회)
  static const Color urgentBg = Color(0xFFFFF3F3);

  // ── 배경 색상 ─────────────────────────────────────────────
  /// Scaffold 기본 배경 — 대부분의 화면 배경 (7회)
  static const Color scaffoldBg = Color(0xFFF9FAFB);

  /// 섹션 구분선 배경 — cabinet_detail 두꺼운 Divider (6회)
  static const Color dividerBg = Color(0xFFF5F5F5);

  /// 입력 필드 테두리, 비활성 border (6회)
  static const Color border = Color(0xFFEEEEEE);

  /// 카드 구분용 중간 배경 (1회)
  static const Color cardDivider = Color(0xFFF3F4F6);

  // ── 소셜 로그인 색상 ──────────────────────────────────────
  /// 카카오 브랜드 색상 (1회)
  static const Color kakao = Color(0xFFFEE500);

  // ── 구매 상태 색상 ────────────────────────────────────────
  /// 주문완료 배경 (노란 계열)
  static const Color orderedBg = Color(0xFFFFF3CD);

  /// 주문완료 텍스트
  static const Color orderedFg = Color(0xFF8a6200);

  /// 배송중 배경 (파랑 계열)
  static const Color shippingBg = Color(0xFFE3F2FD);

  /// 배송중 텍스트
  static const Color shippingFg = Color(0xFF1565C0);

  // ── 기타 ──────────────────────────────────────────────────
  /// danger보다 연한 배경 — 검사 패널 배경 등
  static const Color dangerSoftBg = Color(0xFFFFF0F0);

  /// warning보다 연한 배경 — 검사 패널 배경 등
  static const Color warningSoftBg = Color(0xFFFFFDE7);

  // ── 생활 습관 토글 카드 배경 ──────────────────────────────
  /// 흡연 활성 배경 (주황 연한)
  static const Color smokingBg = Color(0xFFFFF3E0);

  /// 음주 활성 배경 (보라 연한)
  static const Color drinkingBg = Color(0xFFF3E5F5);

  /// 임신 활성 배경 (핑크 연한)
  static const Color pregnancyBg = Color(0xFFFCE4EC);

  // ── 배너 / 랭킹 메달 색상 ────────────────────────────────
  /// 배너 파랑 (비타민D 특별전)
  static const Color bannerBlue = Color(0xFF1976D2);

  /// 배너 주황 (쿠폰 배너)
  static const Color bannerOrange = Color(0xFFF57C00);

  /// 랭킹 금메달
  static const Color rankGold = Color(0xFFFFB300);

  /// 랭킹 은메달
  static const Color rankSilver = Color(0xFF9E9E9E);

  /// 랭킹 동메달
  static const Color rankBronze = Color(0xFF8D6E63);

  // ── 바코드 탭 색상 ────────────────────────────────────────
  /// 바코드 탭 테두리 연파랑
  static const Color barcodeBorder = Color(0xFFBBDEFB);
}

/// 앱 전역 텍스트 스타일 상수
abstract class AppTextStyles {
  /// 화면 타이틀 (AppBar, 섹션 헤더)
  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  /// 카드 내 상품명, 영양제명
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  /// 브랜드명, 부제목
  static const TextStyle subtitle = TextStyle(fontSize: 13, color: Colors.grey);

  /// 일반 본문
  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: Colors.black87,
    height: 1.6,
  );

  /// 작은 보조 텍스트 (배지, 캡션)
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: Colors.black54,
  );

  /// 가격 강조
  static const TextStyle price = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppColors.primary,
  );
}

/// 앱 전역 수치 상수
abstract class AppConstants {
  /// 기본 카드 모서리 반지름
  static const double radiusMd = 12.0;

  /// 큰 카드 모서리 반지름
  static const double radiusLg = 20.0;

  /// 기본 화면 좌우 패딩
  static const double horizontalPadding = 16.0;

  /// 재구매 알림 기준 잔여량 (정 수)
  static const int lowStockThreshold = 7;

  /// 긴급 재구매 기준 잔여량 (정 수)
  static const int criticalStockThreshold = 3;

  /// API 기본 주소 (환경에 따라 동적 변경)
  /// 백엔드 공통 헤더. 로그인 상태면 Supabase access token을 함께 보냅니다.
  static Map<String, String> get headers {
    final token = _accessToken;
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String? get _accessToken {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      // Supabase 초기화 전(테스트 등)에는 토큰 없이 요청
      return null;
    }
  }

  static String get apiBaseUrl {
    // 1. 실제 출시(운영) 환경
    if (kReleaseMode) {
      return 'https://arousal-cocoa-bunt.ngrok-free.dev';
    }

    // 2. 개발 환경
    // 에뮬레이터 테스트 시: 아래를 'http://10.0.2.2:3000' 으로 변경
    // 실제 기기 테스트 시: ngrok URL 유지
    return 'https://arousal-cocoa-bunt.ngrok-free.dev';
  }
}
