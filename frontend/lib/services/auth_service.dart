import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:simcap/core/supabase/supabase_client.dart';

class AuthService {
  Future<void> signInWithGoogle() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'com.example.simcap://login-callback/',
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  Future<void> signInWithKakao() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.kakao,
      scopes: 'profile_nickname,profile_image',
      redirectTo: kIsWeb ? null : 'com.example.simcap://login-callback/',
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  }

  bool isLoggedIn() {
    return supabase.auth.currentSession != null;
  }

  User? get currentUser => supabase.auth.currentUser;

  Future<Map<String, dynamic>?> getUserInfo() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    try {
      final data = await supabase
          .from('users_info')
          .select('name, gender, birth_year')
          .eq('id', user.id)
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('[AuthService] getUserInfo 실패: \$e');
      return null;
    }
  }

  /// 과다섭취 검사용 나이/성별 ('male' | 'female').
  /// DB(users_info) → 온보딩 때 기기에 저장한 값 → 기본값(24세 여성) 순서로 사용합니다.
  Future<({int age, String gender})> getIntakeProfile() async {
    final info = await getUserInfo();
    final prefs = await SharedPreferences.getInstance();

    final birthYear = info?['birth_year'];
    final int age = birthYear is int
        ? DateTime.now().year - birthYear
        : int.tryParse(prefs.getString('userAge') ?? '') ?? 24;

    final rawGender =
        ((info?['gender'] as String?) ?? prefs.getString('userGender') ?? '')
            .toLowerCase();
    final gender = const ['male', '남성', '남자', 'm'].contains(rawGender)
        ? 'male'
        : 'female';

    return (age: age, gender: gender);
  }

  Future<bool> hasUserInfo() async {
    final user = supabase.auth.currentUser;

    if (user == null) return false;

    final data = await supabase
        .from('users_info')
        .select('name, gender, birth_year')
        .eq('id', user.id)
        .maybeSingle();

    if (data == null) return false;

    return (data['name'] as String?)?.isNotEmpty == true &&
        (data['gender'] as String?)?.isNotEmpty == true &&
        data['birth_year'] != null;
  }

  // Mapping lists matching database BigInt IDs
  static const Map<String, int> goalMap = {
    '눈 건강': 1,
    '관절 건강': 2,
    '면역력 증진': 3,
    '피로 회복': 4,
    '장 건강': 5,
    '피부 개선': 6,
    '뼈/치아 건강': 7,
    '혈행 개선': 8,
    '두뇌/기억력 개선': 9,
    '다이어트': 10,
    '스트레스 케어': 11,
    '모발/손톱 영양': 12,
    '간 건강': 13,
  };

  static const Map<String, int> conditionMap = {
    '고혈압': 1,
    '당뇨': 2,
    '고지혈증': 3,
    '심장 질환': 4,
    '신장 질환': 5,
    '간 질환': 6,
    '갑상선 질환': 7,
    '골다공증': 8,
    '관절염': 9,
    '빈혈': 10,
  };

  static const Map<String, int> allergyMap = {
    '견과류': 1,
    '갑각류': 2,
    '고등어': 3,
    '우유': 4,
    '달걀': 5,
    '밀': 6,
    '메밀': 6,
    '대두': 7,
  };

  Future<void> completeOnboarding({
    required String name,
    required String gender,
    required int birthYear,
    required List<String> conditions,
    required List<String> allergies,
    required List<String> healthGoals,
  }) async {
    var user = supabase.auth.currentUser;

    if (user == null) {
      await supabase.auth.refreshSession();
      user = supabase.auth.currentUser;
    }

    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }

    final conditionIds = conditions
        .map((label) => conditionMap[label])
        .whereType<int>()
        .toList();

    final allergyIds = allergies
        .map((label) => allergyMap[label])
        .whereType<int>()
        .toList();

    final goalIds = healthGoals
        .map((label) => goalMap[label])
        .whereType<int>()
        .toList();

    await supabase.from('users_info').upsert({
      'id': user.id,
      'name': name,
      'gender': gender,
      'birth_year': birthYear,
      'conditions': conditionIds,
      'allergies': allergyIds,
      'health_goals': goalIds,
      'special_notes': <int>[],
    });
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }
}
