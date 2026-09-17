# 💊 OnePerDay (하루한알)

> **AI 기반 맞춤형 영양제 추천 및 스마트 관리 서비스**  
> 사용자의 건강 상태를 분석하여 최적의 영양제를 추천하고, OCR 기술을 통해 보유 중인 영양제의 성분 충돌(부작용)을 검사하며 섭취 일정을 종합적으로 관리합니다.
> *(본 레포지토리는 2026 AI컴퓨터공학부 심화캡스톤 프로젝트를 기반으로, 개인적인 기능 고도화를 위해 분리한 독립 프로젝트입니다.)*

---

## 📢 프로젝트 소개

기존의 단순 영양제 정보 제공을 넘어, AI 기술(LLM & Vision)을 적극 활용하여 사용자 맞춤형 건강 관리를 돕습니다. 사용자가 복용 중인 영양제 라벨을 촬영하면 자동으로 성분을 인식하고, 성분 간 충돌(부작용)을 검사하며, 개인의 건강 고민에 맞춘 최적의 영양 조합을 추천합니다.

## ✨ 주요 기능

*   **🤖 AI 맞춤형 영양제 추천 및 챗봇:**
    *   사용자의 연령, 성별, 주요 건강 고민을 바탕으로 최적의 영양제 조합 생성 (Gemini API 연동)
    *   추천 이유 및 각 영양제별 성분/복용 방법 상세 안내
    *   자연어 기반 영양제 상담 챗봇 지원
*   **📸 영양제 라벨 인식 (AI/OCR):**
    *   YOLO 모델을 활용한 영양제 라벨 이미지 크롭 및 전처리
    *   OCR 모듈을 통한 성분표 자동 텍스트 추출 및 데이터화
*   **⚠️ 성분 충돌 및 부작용 검사:**
    *   사용자가 등록한 영양제 간의 상호작용 분석
    *   중복 복용 위험성 및 부작용 경고 알림 제공
*   **🗂️ 스마트 보관함 및 섭취 관리:**
    *   보유 중인 영양제 디지털 보관함 관리 (Cabinet)
    *   일일 섭취 기록 및 리마인더 푸시 알림 기능 제공

---

## 👨‍💻 나의 기여도 및 향후 개발 계획 (My Role & Future Plans)

### 🎯 원본 프로젝트에서의 내 역할 (My Contributions)
* *(예시) NestJS를 활용한 백엔드 API 설계 및 DB(Prisma, Supabase) 연동*
* *(예시) Gemini API를 활용한 맞춤형 추천 시스템 프롬프트 엔지니어링 및 로직 구현*
* *(예시) 영양제 성분 데이터베이스 구축 및 성분 충돌/부작용 검사 알고리즘 개발*
*(※ 괄호 친 부분은 질문자님이 실제로 담당하셨던 역할로 알맞게 수정해 주세요!)*

### 🚀 향후 추가 개발 계획 (To-Do)
* [ ] 사용자 맞춤형 영양제 섭취 시간 알림(Push Notification) 기능 고도화
* [ ] 추천 알고리즘 로직 개선 및 응답 속도 최적화
* [ ] 영양제 인식(OCR) 정확도 향상을 위한 이미지 전처리 파이프라인 개선
* [ ] 새로운 UI/UX 디자인 적용 및 다크모드 지원

---

## 🛠 기술 스택 (Tech Stack)

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

## 📂 프로젝트 구조 (Directory Structure)

\`\`\`text
onePerday/
├── backend/                  # NestJS 기반 메인 API 서버
│   ├── src/auth/             # 사용자 인증 및 관리
│   ├── src/cabinet/          # 영양제 보관함 및 섭취 알림 로직
│   ├── src/recommend/        # AI 맞춤형 추천 및 충돌 검사 로직
│   └── scripts/crop_label.py # YOLO 기반 라벨 이미지 전처리 스크립트
├── frontend/                 # Flutter 기반 모바일 애플리케이션
│   ├── lib/                  # Dart UI 및 비즈니스 로직
│   └── assets/fonts/         # 폰트 리소스
├── admin/                    # Next.js 기반 관리자 웹 대시보드
│   ├── app/                  # Next.js App 라우터 구조
│   └── pages/                # 회원 및 영양제 DB 관리 페이지
└── LLM_OCR_DEPLOY_KIT/       # AI 추천 및 OCR 기능 독립 배포 모듈
\`\`\`

---

## 🚀 실행 방법 (How to Run)

각 모듈별로 독립적인 실행 환경이 필요합니다. 아래 가이드를 참고하여 실행해 주세요.

### 1. Backend (NestJS API 서버)
\`\`\`bash
cd backend
npm install
# .env 파일 설정 필수 (Supabase URL, DB URL, Gemini API Key 등)
npm run start:dev
\`\`\`

### 2. Python 스크립트 환경 설정 (OCR 및 이미지 처리)
\`\`\`bash
cd backend/scripts
pip install -r requirements.txt
\`\`\`

### 3. Frontend (Flutter 모바일 앱)
\`\`\`bash
cd frontend
flutter pub get
flutter run
\`\`\`

### 4. Admin Web (Next.js 관리자 페이지)
\`\`\`bash
cd admin
npm install
npm run dev
\`\`\`
