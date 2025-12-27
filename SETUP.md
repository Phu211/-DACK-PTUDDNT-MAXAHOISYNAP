# Hướng dẫn Cấu hình API Keys

Trước khi chạy project, bạn cần cấu hình các API keys sau:

## 1. Firebase Configuration

### Cách 1: Sử dụng FlutterFire CLI (Khuyến nghị)
```bash
flutter pub global activate flutterfire_cli
flutterfire configure
```

Lệnh này sẽ tự động tạo file `lib/firebase_options.dart` với các API keys của bạn.

### Cách 2: Tạo thủ công
1. Vào [Firebase Console](https://console.firebase.google.com/)
2. Tạo project mới hoặc chọn project hiện có
3. Thêm Android/iOS app vào project
4. Tải file `google-services.json` (Android) và `GoogleService-Info.plist` (iOS)
5. Tạo file `lib/firebase_options.dart` với cấu hình Firebase của bạn

**Lưu ý:** File `firebase_options.dart` đã được thêm vào `.gitignore` để bảo mật.

## 2. Giphy API Key

1. Đăng ký tài khoản tại [Giphy Developers](https://developers.giphy.com/)
2. Tạo app mới và lấy API key
3. Thay thế `YOUR_GIPHY_API_KEY` trong các file sau:
   - `lib/presentation/screens/messages/chat_screen.dart`
   - `lib/presentation/screens/messages/group_chat_screen.dart`
   - `lib/presentation/screens/post/create_post_screen.dart`
   - `lib/presentation/screens/groups/create_group_post_screen.dart`

```dart
static const String _giphyApiKey = 'YOUR_GIPHY_API_KEY'; // Thay bằng key thực tế
```

## 3. AI API Key

1. Chọn một trong các provider sau:
   - **Groq** (Miễn phí, khuyến nghị): https://console.groq.com/keys
   - **OpenRouter**: https://openrouter.ai/keys
   - **Google Gemini**: https://aistudio.google.com/app/apikey
   - **OpenAI**: https://platform.openai.com/api-keys

2. Cập nhật trong `lib/core/constants/app_constants.dart`:
```dart
static const String aiProvider = 'groq'; // hoặc 'openrouter', 'gemini', 'openai'
static const String aiApiKey = 'YOUR_AI_API_KEY'; // Thay bằng key thực tế
```

## 4. Agora App ID

1. Đăng ký tại [Agora Console](https://console.agora.io/)
2. Tạo project mới và lấy App ID
3. Cập nhật trong `lib/data/services/agora_call_service.dart`:
```dart
static const String appId = 'YOUR_AGORA_APP_ID'; // Thay bằng App ID thực tế
```

## 5. Backend URL

1. Deploy backend server (xem thư mục `agora-backend/`)
2. Cập nhật trong `lib/core/constants/app_constants.dart`:
```dart
static const String backendBaseUrl = 'YOUR_BACKEND_URL'; // Thay bằng URL backend thực tế
```

## 6. Google Maps API Key (Tùy chọn)

Nếu muốn sử dụng Google Maps thay vì OpenStreetMap:

1. Lấy API key tại [Google Cloud Console](https://console.cloud.google.com/google/maps-apis/credentials)
2. Enable "Maps Static API"
3. Cập nhật trong `lib/core/constants/app_constants.dart`:
```dart
static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
```

## 7. Mapbox Access Token (Tùy chọn)

Nếu muốn sử dụng Mapbox:

1. Đăng ký tại [Mapbox](https://www.mapbox.com/)
2. Lấy Access Token
3. Cập nhật trong `lib/core/constants/app_constants.dart`:
```dart
static const String mapboxAccessToken = 'YOUR_MAPBOX_ACCESS_TOKEN';
```

## Checklist

- [ ] Firebase đã được cấu hình (`firebase_options.dart`)
- [ ] Giphy API key đã được thêm vào 4 file
- [ ] AI API key đã được cấu hình
- [ ] Agora App ID đã được cấu hình
- [ ] Backend URL đã được cấu hình
- [ ] (Tùy chọn) Google Maps API key
- [ ] (Tùy chọn) Mapbox Access Token

## Lưu ý Bảo mật

⚠️ **QUAN TRỌNG:**
- Không commit các API keys thực tế lên GitHub
- File `firebase_options.dart` đã được thêm vào `.gitignore`
- Các placeholder `YOUR_*` phải được thay thế trước khi chạy app
- Sử dụng environment variables hoặc secure storage cho production

## Troubleshooting

### Lỗi "API key not found"
- Kiểm tra lại xem đã thay thế tất cả `YOUR_*` placeholder chưa
- Kiểm tra API key có hợp lệ không

### Lỗi Firebase
- Chạy lại `flutterfire configure`
- Kiểm tra file `google-services.json` và `GoogleService-Info.plist` đã được thêm vào project chưa

### Lỗi Agora calls
- Kiểm tra Agora App ID đã đúng chưa
- Kiểm tra backend server đã được deploy và hoạt động chưa

