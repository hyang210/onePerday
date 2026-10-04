# onePERday - Frontend

영양제 관리 및 AI 추천 앱 프론트엔드입니다.

## 실행 전제 조건

- Flutter SDK가 설치되어 있어야 합니다.
- flutter 명령어가 터미널에서 실행 가능하도록 **Path**에 등록되어 있어야 합니다.
  - ex: Windows 검색창에 환경 변수 입력 → 시스템 환경 변수 편집 클릭 → 아래쪽 환경 변수 버튼 클릭 → 시스템 변수 목록에서 Path 찾아서 편집 → C:\flutter\bin
- Windows에서 빌드 오류(symlink support)가 발생하면 **개발자 모드**를 켜주세요.
  - Windows 설정 → "개발자 모드" 검색 → On으로 변경

## 실행 방법

프로젝트를 받은 후 아래 명령어를 **순서대로** 실행해주세요.

```bash
# 1. 이전 빌드 캐시 완전 삭제 (문제 발생 시 필수)
flutter clean

# 2. 필요한 패키지 설치
flutter pub get

# 3. 앱 실행 (백엔드 주소를 바꾸려면 --dart-define=API_BASE_URL=http://10.0.2.2:3000)
flutter run