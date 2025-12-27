import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'data/services/push_notification_service.dart';
import 'data/services/notification_tap_service.dart';
import 'data/services/break_reminder_service.dart';
import 'data/services/daily_usage_service.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/language_provider.dart';
import 'presentation/localizations/translated_localizations_delegate.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/two_factor_verify_screen.dart';
import 'presentation/screens/main/main_screen.dart';
import 'flutter_gen/gen_l10n/app_localizations.dart';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // When app is background/terminated:
  // - If FCM includes notification payload -> Android will show it automatically.
  // - If it's data-only -> we can show local notification here (optional).
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}

  // Xử lý incoming call notifications khi app ở background/terminated
  if (message.data['type'] == 'incoming_call') {
    try {
      // ✅ Khi app terminated, FCM sẽ tự động hiển thị notification nếu có notification payload
      // Nhưng ta vẫn cần show local notification để đảm bảo hiển thị
      await PushNotificationService.instance.init(forBackground: true);
      
      // Hiển thị notification với priority cao và sound
      final callerName = message.data['callerName'] as String? ?? 'Người gọi';
      final isVideo = message.data['isVideo'] == 'true' || message.data['isVideo'] == true;
      final title = callerName;
      final body = isVideo ? 'Cuộc gọi video đến' : 'Cuộc gọi thoại đến';
      
      // Đảm bảo data có đầy đủ thông tin để mở màn hình cuộc gọi khi user tap
      final notificationData = Map<String, dynamic>.from(message.data);
      notificationData['type'] = 'incoming_call';
      
      // Đảm bảo các field cần thiết có trong data
      if (!notificationData.containsKey('callerId') || notificationData['callerId'] == null) {
        debugPrint('WARNING: Missing callerId in incoming call notification');
      }
      if (!notificationData.containsKey('callId') || notificationData['callId'] == null) {
        debugPrint('WARNING: Missing callId in incoming call notification');
      }
      if (!notificationData.containsKey('channelName') || notificationData['channelName'] == null) {
        debugPrint('WARNING: Missing channelName in incoming call notification');
      }

      // ✅ Show local notification để đảm bảo hiển thị ngay cả khi app terminated
      // FCM notification payload sẽ tự hiển thị, nhưng local notification đảm bảo chắc chắn
      await PushNotificationService.instance.showCallNotification(
        title: title, 
        body: body, 
        data: notificationData,
      );
      debugPrint('Background call notification shown: $title - $body (data: $notificationData)');
    } catch (e) {
      debugPrint('Error handling background call notification: $e');
      // Không throw để không làm crash app
    }
    return;
  }

  // ✅ Luôn hiển thị local notification khi app ở background/terminated
  // để đảm bảo notification luôn được hiển thị, ngay cả khi FCM có notification payload
  // (FCM notification payload có thể không hiển thị trong một số trường hợp)
  try {
    await PushNotificationService.instance.init(forBackground: true);
    
    // Nếu có notification payload, sử dụng nó; nếu không, tạo từ data
    if (message.notification != null) {
      // Có notification payload: vẫn hiển thị local notification để đảm bảo
      await PushNotificationService.instance.showFromRemoteMessage(message);
    } else {
      // Chỉ có data payload: hiển thị local notification từ data
      await PushNotificationService.instance.showFromRemoteMessage(message);
    }
  } catch (e) {
    debugPrint('Error showing background notification: $e');
  }
}

void main() async {
  // Error handling - catch all unhandled errors
  FlutterError.onError = (FlutterErrorDetails details) {
    // Log error but don't crash
    debugPrint('Flutter Error: ${details.exception}');
    debugPrint('Stack trace: ${details.stack}');
    // Suppress error presentation in release mode to avoid crash
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  // Handle async errors from zones
  PlatformDispatcher.instance.onError = (error, stack) {
    // Log error but don't crash
    debugPrint('Platform Error: $error');
    debugPrint('Stack trace: $stack');
    // Return true to indicate error was handled
    return true;
  };

  // Run app in a zone to catch all unhandled errors
  runZonedGuarded(
    () async {
      // Initialize Flutter bindings inside the zone to avoid zone mismatch
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize Firebase
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      // Setup Firebase Messaging background handler (chỉ trên mobile)
      if (!kIsWeb) {
        try {
          FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        } catch (e) {
          debugPrint('Error setting up Firebase Messaging background handler: $e');
        }
      }

      // Init local/system notifications for foreground messages
      if (!kIsWeb) {
        try {
          await PushNotificationService.instance.init();
        } catch (e) {
          debugPrint('PushNotificationService init error: $e');
        }
      }

      // Khởi động dịch vụ nhắc nhở nghỉ giải lao (dùng local notification)
      try {
        await BreakReminderService.instance.ensureInitialized();
      } catch (e) {
        debugPrint('BreakReminderService init error: $e');
      }

      // Khởi động dịch vụ ghi lại thời gian sử dụng hàng ngày
      try {
        await DailyUsageService.instance.init();
      } catch (e) {
        debugPrint('DailyUsageService init error: $e');
      }

      // Capture notification taps (open app -> navigate later in MainScreen)
      if (!kIsWeb) {
        try {
          await NotificationTapService.instance.init();
        } catch (e) {
          debugPrint('NotificationTapService init error: $e');
        }
      }

      runApp(const MyApp());
    },
    (error, stack) {
      // Catch all unhandled errors in the zone
      debugPrint('Unhandled error in zone: $error');
      debugPrint('Stack trace: $stack');
      // Don't rethrow to prevent app crash
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, themeProvider, languageProvider, _) {
          // Force rebuild MaterialApp when theme or locale changes
          final appKey = ValueKey('${themeProvider.themeMode}_${languageProvider.locale.languageCode}');

          debugPrint(
            'MaterialApp rebuilding with themeMode: ${themeProvider.themeMode}, locale: ${languageProvider.locale.languageCode}',
          );

          return MaterialApp(
            key: appKey,
            onGenerateTitle: (context) => AppLocalizations.of(context)?.appTitle ?? 'Synap',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            locale: languageProvider.locale,
            // Hỗ trợ tất cả các ngôn ngữ (LibreTranslate sẽ dịch nếu cần)
            supportedLocales: const [
              Locale('vi'),
              Locale('en'),
              Locale('zh'),
              Locale('ja'),
              Locale('ko'),
              Locale('th'),
              Locale('fr'),
              Locale('es'),
              Locale('de'),
              Locale('it'),
              Locale('pt'),
              Locale('ru'),
              Locale('ar'),
              // Thêm các ngôn ngữ khác nếu cần
            ],
            localizationsDelegates: [
              // Sử dụng TranslatedLocalizationsDelegate để tự động dịch
              TranslatedLocalizationsDelegate(),
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Consumer<AuthProvider>(
              builder: (context, authProvider, _) {
                debugPrint('MyApp: Building home - isAuthenticated: ${authProvider.isAuthenticated}, pending2FA: ${authProvider.pending2FAVerification}');
                
                // Nếu cần verify 2FA, hiển thị màn hình 2FA
                if (authProvider.pending2FAVerification && 
                    authProvider.pending2FAUserId != null && 
                    authProvider.pending2FAEmail != null) {
                  debugPrint('MyApp: Returning TwoFactorVerifyScreen');
                  return TwoFactorVerifyScreen(
                    userId: authProvider.pending2FAUserId!,
                    email: authProvider.pending2FAEmail!,
                  );
                }
                
                if (authProvider.isAuthenticated) {
                  debugPrint('MyApp: Returning MainScreen');
                  return const MainScreen();
                }
                debugPrint('MyApp: Returning LoginScreen');
                return const LoginScreen();
              },
            ),
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: MediaQuery.of(context).textScaler.clamp(minScaleFactor: 0.8, maxScaleFactor: 1.2),
                ),
                child: child ?? const SizedBox(),
              );
            },
          );
        },
      ),
    );
  }
}
