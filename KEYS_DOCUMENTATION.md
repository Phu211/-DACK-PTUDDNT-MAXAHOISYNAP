# Danh sách các API Keys trong Project

## 1. Giphy API Key

**Key:** `YOUR_GIPHY_API_KEY` (placeholder - cần thay thế bằng key thực tế)

**Vị trí:** 
- `lib/presentation/screens/messages/chat_screen.dart`
- `lib/presentation/screens/messages/group_chat_screen.dart`
- `lib/presentation/screens/post/create_post_screen.dart`
- `lib/presentation/screens/groups/create_group_post_screen.dart`

**Mục đích:** Sử dụng để tìm kiếm và hiển thị GIF từ Giphy

**Lưu ý:** Key này được hardcode trong code, nên di chuyển sang environment variables trong production

---

## 2. AI API Keys (AppConstants)

### AI Provider
**Key:** `groq`

**Giá trị có thể:** `groq`, `openrouter`, `gemini`, `openai`

**Vị trí:** `lib/core/constants/app_constants.dart`

**Mục đích:** Chọn provider AI để sử dụng

### AI API Key
**Key:** `YOUR_AI_API_KEY` (placeholder - cần thay thế bằng key thực tế)

**Vị trí:** `lib/core/constants/app_constants.dart`

**Mục đích:** API key cho AI Content Assistant (hiện tại đang dùng Groq)

**Cách lấy key:**
- **Groq:** https://console.groq.com/keys
- **OpenRouter:** https://openrouter.ai/keys
- **Google Gemini:** https://aistudio.google.com/app/apikey
- **OpenAI:** https://platform.openai.com/api-keys

---

## 3. Firebase API Keys

### Android API Key
**Key:** `YOUR_FIREBASE_ANDROID_API_KEY` (placeholder - cần cấu hình qua FlutterFire CLI)

**Vị trí:** `lib/firebase_options.dart` (file này được tạo tự động bởi FlutterFire CLI)

**Mục đích:** Firebase API key cho Android platform

### iOS API Key
**Key:** `YOUR_FIREBASE_IOS_API_KEY` (placeholder - cần cấu hình qua FlutterFire CLI)

**Vị trí:** `lib/firebase_options.dart` (file này được tạo tự động bởi FlutterFire CLI)

**Mục đích:** Firebase API key cho iOS platform

### Web API Key
**Key:** `YOUR_FIREBASE_WEB_API_KEY` (placeholder - cần cấu hình qua FlutterFire CLI)

**Vị trí:** `lib/firebase_options.dart` (file này được tạo tự động bởi FlutterFire CLI)

**Mục đích:** Firebase API key cho Web platform

---

## 4. Agora API Keys

### Agora App ID
**Key:** `YOUR_AGORA_APP_ID` (placeholder - cần thay thế bằng App ID thực tế)

**Vị trí:** `lib/data/services/agora_call_service.dart`

**Mục đích:** Agora App ID cho voice/video calls

**Cách lấy:** https://console.agora.io/

---

## 5. Backend URLs & API Keys

### Backend Base URL
**URL:** `YOUR_BACKEND_URL` (placeholder - cần thay thế bằng URL backend thực tế)

**Vị trí:** `lib/core/constants/app_constants.dart`

**Mục đích:** Backend server cho Agora token generation và push notifications

**Endpoint:** `${backendBaseUrl}/agora/token`

### Google Maps API Key (Tùy chọn)
**Key:** `YOUR_GOOGLE_MAPS_API_KEY` (chưa được cấu hình)

**Vị trí:** `lib/core/constants/app_constants.dart`

**Mục đích:** Google Maps Static API (hiện tại app đang dùng OpenStreetMap miễn phí)

**Cách lấy:** https://console.cloud.google.com/google/maps-apis/credentials

**Lưu ý:** Không bắt buộc, app vẫn hoạt động bình thường nếu không có key này

### Mapbox Access Token (Tùy chọn)
**Key:** `YOUR_MAPBOX_ACCESS_TOKEN` (chưa được cấu hình)

**Vị trí:** `lib/core/constants/app_constants.dart`

**Mục đích:** Mapbox Static Images API

**Cách lấy:** https://www.mapbox.com/

**Lưu ý:** Không bắt buộc, app vẫn hoạt động bình thường nếu không có key này

---

## Tóm tắt

| API Service | Key/Value | Trạng thái | Vị trí |
|------------|-----------|------------|--------|
| Giphy | `YOUR_GIPHY_API_KEY` | ⚠️ Cần cấu hình | 4 file chat/post screens |
| AI (Groq) | `YOUR_AI_API_KEY` | ⚠️ Cần cấu hình | `app_constants.dart` |
| Firebase Android | `YOUR_FIREBASE_ANDROID_API_KEY` | ⚠️ Cần cấu hình | `firebase_options.dart` (FlutterFire CLI) |
| Firebase iOS | `YOUR_FIREBASE_IOS_API_KEY` | ⚠️ Cần cấu hình | `firebase_options.dart` (FlutterFire CLI) |
| Firebase Web | `YOUR_FIREBASE_WEB_API_KEY` | ⚠️ Cần cấu hình | `firebase_options.dart` (FlutterFire CLI) |
| Agora App ID | `YOUR_AGORA_APP_ID` | ⚠️ Cần cấu hình | `agora_call_service.dart` |
| Backend URL | `YOUR_BACKEND_URL` | ⚠️ Cần cấu hình | `app_constants.dart` |
| Google Maps | `YOUR_GOOGLE_MAPS_API_KEY` | ❌ Tùy chọn | `app_constants.dart` |
| Mapbox | `YOUR_MAPBOX_ACCESS_TOKEN` | ❌ Tùy chọn | `app_constants.dart` |

---

## Lưu ý bảo mật

⚠️ **QUAN TRỌNG:** 
- Các API keys hiện tại đang được hardcode trong code
- Trong production, nên di chuyển các keys nhạy cảm sang:
  - Environment variables
  - Secure storage (FlutterSecureStorage)
  - Backend server (không expose keys trong client code)
- Không commit các keys thực tế lên public repositories

