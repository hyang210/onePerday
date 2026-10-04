# Backend Environment Variables

`backend/.env`에 아래 값을 설정하면 챗봇 RAG, 라벨 인식, 과다섭취/병용금기 API를 실행할 수 있습니다.

```env
PORT=3000

# Supabase / Prisma
DATABASE_URL="postgresql://USER:PASSWORD@HOST:PORT/DATABASE"
DIRECT_URL="postgresql://USER:PASSWORD@HOST:PORT/DATABASE"
SUPABASE_URL="https://your-project.supabase.co"
SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"

# 관리자 계정 이메일 (쉼표로 구분). 비어 있으면 /admin API는 아무도 사용할 수 없습니다.
ADMIN_EMAILS="admin@example.com"

# 공공데이터포털 DUR 병용금기 API
DUR_API_KEY="your-dur-api-key"

# Gemini LLM
GEMINI_API_KEY="your-gemini-api-key"
GEMINI_MODEL="gemini-3.5-flash"

# CLOVA OCR
CLOVA_OCR_INVOKE_URL="https://your-clova-ocr-invoke-url"
CLOVA_OCR_SECRET="your-clova-ocr-secret"

# YOLO 라벨 crop
# 미설정 시 backend 실행 위치 기준 ../../onePerday-Feature-YOLO-SJ/weights/best.pt 를 찾습니다.
YOLO_MODEL_PATH="C:\\OPD\\onePerday-Feature-YOLO-SJ\\weights\\best.pt"
PYTHON_BIN="python"
YOLO_CONF=0.35
YOLO_CROP_PADDING=0.06
```

프론트엔드의 백엔드 주소는 `frontend/lib/core/constant/app_constants.dart`의 `AppConstants.apiBaseUrl`에서 관리합니다. (`ApiConfig.baseUrl`도 이 값을 그대로 사용합니다.)
Android 에뮬레이터에서 로컬 백엔드를 쓰려면 이 값을 `http://10.0.2.2:3000`으로 바꿉니다.

영양제 라벨 OCR은 `POST /label-recognition/analyze` 하나로 처리합니다. (YOLO crop → CLOVA OCR → Gemini 구조화 → DB TOP 1 매칭)

YOLO crop 스크립트는 Python에서 실행되므로 서버 환경에 아래 패키지가 필요합니다.

```bash
pip install -r backend/scripts/requirements.txt
```

## 인증

모든 API는 기본적으로 로그인이 필요합니다. 요청 헤더에 Supabase access token을 담아 보내야 합니다.

```
Authorization: Bearer <Supabase access token>
```

- 토큰이 없거나 유효하지 않으면 `401`, 다른 사용자의 데이터(`userUuid`, `userId`)를 요청하면 `403`을 돌려줍니다.
- 로그인 없이 호출할 수 있는 API(`@Public()`): `GET /`, `GET /supplements`, `GET /supplements/popular`, `POST /supplements/search`, `GET /review/:productId`
- `/admin/*` API는 `ADMIN_EMAILS`에 등록된 계정만 호출할 수 있습니다.
- `GET /auth/me`: 로그인한 사용자 정보와 관리자 여부(`isAdmin`)를 돌려줍니다.
