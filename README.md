# 💊 OnePerDay
> **AI 기반 맞춤형 영양제 추천 및 스마트 관리 서비스**  
> 사용자의 건강 상태를 분석하여 최적의 영양제를 추천하고, OCR 기술을 통해 보유 중인 영양제의 성분 충돌(부작용)을 검사하며 섭취 일정을 종합적으로 관리합니다.
> *(본 레포지토리는 2026 AI컴퓨터공학부 심화캡스톤 프로젝트를 기반으로, 개인적인 기능 고도화를 위해 분리한 독립 프로젝트입니다.)*

---

## 📢 프로젝트 소개

기존의 단순 영양제 정보 제공을 넘어, AI 기술(LLM & Vision)을 적극 활용하여 사용자 맞춤형 건강 관리를 돕습니다. 사용자가 복용 중인 영양제 라벨을 촬영하면 자동으로 성분을 인식하고, 성분 간 충돌(부작용)을 검사하며, 개인의 건강 고민에 맞춘 최적의 영양 조합을 추천합니다.

## 주요 기능

*   **AI 맞춤형 영양제 추천 및 챗봇:**
    *   사용자의 연령, 성별, 주요 건강 고민을 바탕으로 최적의 영양제 조합 생성 (Gemini API 연동)
    *   추천 이유 및 각 영양제별 성분/복용 방법 상세 안내
    *   자연어 기반 영양제 상담 챗봇 지원
*   **영양제 라벨 인식 (AI/OCR):**
    *   YOLO 모델을 활용한 영양제 라벨 이미지 크롭 및 전처리
    *   OCR 모듈을 통한 성분표 자동 텍스트 추출 및 데이터화
*   **성분 충돌 및 부작용 검사:**
    *   사용자가 등록한 영양제 간의 상호작용 분석
    *   중복 복용 위험성 및 부작용 경고 알림 제공
*   **스마트 보관함 및 섭취 관리:**
    *   보유 중인 영양제 디지털 보관함 관리 (Cabinet)
    *   일일 섭취 기록 및 리마인더 푸시 알림 기능 제공

---

## 나의 기여도 및 향후 개발 계획 (My Role & Future Plans)

### 원본 프로젝트에서의 내 역할 (My Contributions)
* 프로젝트 초기 목업 피그마 디자인 담당
* 프로젝트 frontend 전담
* ngrok 서버 구축 및 frontend-backend 병합 담당
* backend 로직 일부 담당 - 하루 적정 영양소 체크, 병용 금지 체크

### 향후 추가 개발 계획 (To-Do)
* [ ] 사용자 맞춤형 영양제 섭취 시간 알림(Push Notification) 기능 고도화
* [ ] 추천 알고리즘 로직 개선 및 응답 속도 최적화
* [ ] 영양제 인식(OCR) 정확도 향상을 위한 이미지 전처리 파이프라인 개선
* [ ] 새로운 UI/UX 디자인 적용 및 다크모드 지원

---

## 기술 스택 (Tech Stack)

### Mobile App (Client)
*   **Framework:** Flutter (Dart)
*   **UI/UX:** Pretendard Font 적용, 반응형 모바일 UI

### Web Admin (Backoffice)
*   **Framework:** Next.js, React
*   **Language:** TypeScript

### Backend & Database
*   **Framework:** NestJS
*   **ORM / DB:** Prisma, Supabase
*   **API:** RESTful API 설계

### AI & Data Processing
*   **Language:** Python
*   **Models / Tools:** YOLO (Ultralytics), Pillow, Gemini API

---

## 프로젝트 구조 (Directory Structure)

```text
onePerday/
├── backend/                  # NestJS 기반 메인 API 서버
│   ├── src/auth/             # 사용자 인증 및 관리
│   ├── src/cabinet/          # 영양제 보관함 및 섭취 알림 로직
│   ├── src/recommend/        # AI 맞춤형 추천 및 충돌 검사 로직
│   └── scripts/crop_label.py # YOLO 기반 라벨 이미지 전처리 스크립트
├── frontend/                 # Flutter 기반 모바일 애플리케이션
│   ├── lib/                  # Dart UI 및 비즈니스 로직
│   └── assets/fonts/         # 폰트 리소스
└── admin/                    # Next.js 기반 관리자 웹 대시보드
    ├── app/                  # Next.js App 라우터 구조
    └── pages/                # 회원 및 영양제 DB 관리 페이지
```

---

## 실행 방법 (How to Run)

백엔드 서버와 Flutter 앱은 **각각 다른 터미널**에서 켜야 합니다. (둘 다 실행 중인 상태로 유지됩니다)

### 0. 처음 한 번만: 설치 및 설정
```bash
# 백엔드 패키지 설치
cd backend
npm install
npx prisma generate

# 라벨 인식(YOLO crop)용 Python 패키지
pip install -r scripts/requirements.txt

# 앱 패키지 설치
cd ../frontend
flutter pub get
```
- `backend/.env` 파일을 만들어야 합니다. 필요한 값과 설명은 [`backend/ENVIRONMENT.md`](backend/ENVIRONMENT.md)를 참고하세요.
- `.env`는 비밀키가 들어 있어 git에 올라가지 않습니다. 실행하는 PC마다 직접 만들어야 합니다.

### 1. 터미널 1: 백엔드 서버 (NestJS)
```bash
cd backend
npm run start:dev
```
- 반드시 `backend` 폴더에서 실행하세요. (`.env`와 `scripts/crop_label.py`를 이 위치 기준으로 찾습니다)
- `http://localhost:3000`으로 켜지며, 브라우저에서 열었을 때 `OnePerDay!`가 보이면 정상입니다.
- 코드를 수정하면 자동으로 다시 시작됩니다.

### 2. 터미널 2: Flutter 앱
앱이 백엔드를 찾아갈 주소에 따라 실행 명령이 다릅니다.

| 실행 환경 | 명령 |
|---|---|
| Android 에뮬레이터 + 내 PC 서버 | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` |
| 실제 휴대폰 + 같은 Wi-Fi의 PC | `flutter run --dart-define=API_BASE_URL=http://<PC의 IP>:3000` |
| ngrok 주소 사용 (기본값) | `flutter run` (아래 3번의 ngrok 실행 필요) |

```bash
cd frontend
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```
- `10.0.2.2`는 Android 에뮬레이터 안에서 "내 PC"를 가리키는 주소입니다.
- PC의 IP는 Windows에서 `ipconfig`로 확인합니다. (예: `192.168.0.12`) 방화벽이 3000번 포트를 막으면 연결되지 않습니다.
- 주소 설정은 `frontend/lib/core/constant/app_constants.dart`의 `AppConstants.apiBaseUrl` 한 곳에서 관리합니다.

### 3. (선택) 터미널 3: ngrok
`--dart-define` 없이 `flutter run`으로 실행하면 앱은 기본값인 ngrok 주소로 접속합니다. 이때는 ngrok으로 로컬 서버를 외부에 연결해야 합니다.
```bash
ngrok http --url=arousal-cocoa-bunt.ngrok-free.dev 3000
```
- 이 고정 주소를 소유한 ngrok 계정으로 로그인되어 있어야 합니다.
- 구버전 ngrok은 `--url` 대신 `--domain`을 사용합니다.

### 4. (선택) 관리자 웹 (Next.js)
```bash
cd admin
npm install
npm run dev -- -p 3001
```
- 관리자 웹의 기본 포트도 3000이라 백엔드와 겹치므로 **`-p 3001`을 꼭 붙여야 합니다.** 접속 주소는 `http://localhost:3001`입니다.
- `admin/.env.local` 설정과 관리자 계정 등록 방법은 [`admin/README.md`](admin/README.md)를 참고하세요.

### 요약: 에뮬레이터로 개발할 때
```bash
# 터미널 1
cd backend && npm run start:dev

# 터미널 2
cd frontend && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```
