import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service quản lý Biometric Authentication (vân tay/Face ID).
///
/// Usage:
/// ```dart
/// final biometricService = BiometricAuthService();
/// final available = await biometricService.isBiometricAvailable();
/// if (available) {
///   final authenticated = await biometricService.authenticate();
///   if (authenticated) {
///     // Proceed with login
///   }
/// }
/// ```
class BiometricAuthService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  /// Kiểm tra xem thiết bị có hỗ trợ biometric không.
  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
    } catch (e) {
      debugPrint('Error checking biometric availability: $e');
      return false;
    }
  }

  /// Xác thực bằng biometric (vân tay/Face ID).
  /// Trả về true nếu xác thực thành công.
  Future<bool> authenticate({String reason = 'Xác thực để tiếp tục'}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return false;
    }
  }

  /// Lấy danh sách các loại biometric được hỗ trợ.
  Future<List<String>> getAvailableBiometrics() async {
    try {
      final available = await _localAuth.getAvailableBiometrics();
      return available.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Error getting available biometrics: $e');
      return [];
    }
  }

  /// Kiểm tra xem user đã bật biometric login chưa.
  Future<bool> isBiometricLoginEnabled() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('biometric_enabled_${user.uid}') ?? false;
    } catch (e) {
      debugPrint('Error checking biometric login enabled: $e');
      return false;
    }
  }

  /// Lưu thông tin đăng nhập để sử dụng với biometric.
  /// Lưu cả email và password (password được lưu trong secure storage).
  Future<void> saveLoginCredentials(String email, String password) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('BiometricAuthService: Cannot save credentials - user is null');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('biometric_email_${user.uid}', email);
      debugPrint('BiometricAuthService: Saved email for userId: ${user.uid}');

      // Lưu password trong secure storage
      try {
        await _secureStorage.write(key: 'biometric_password_${user.uid}', value: password);
        debugPrint('BiometricAuthService: Saved password for userId: ${user.uid}');

        // Verify password was saved
        final verifyPassword = await _secureStorage.read(key: 'biometric_password_${user.uid}');
        if (verifyPassword != null && verifyPassword == password) {
          debugPrint('BiometricAuthService: Password verified successfully after saving');
        } else {
          debugPrint('BiometricAuthService: WARNING - Password verification failed after saving');
        }
      } catch (e) {
        debugPrint('BiometricAuthService: Error saving password to secure storage: $e');
        rethrow;
      }
    } catch (e) {
      debugPrint('BiometricAuthService: Error saving login credentials: $e');
    }
  }

  /// Lưu email (backward compatibility).
  Future<void> saveLoginEmail(String email) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('biometric_email_${user.uid}', email);
    } catch (e) {
      debugPrint('Error saving login email: $e');
    }
  }

  /// Lấy email đã lưu cho biometric login.
  /// Nếu user chưa đăng nhập (currentUser = null), sẽ thử tìm email từ tất cả các keys trong SharedPreferences.
  Future<String?> getSavedLoginEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();

      if (user != null) {
        // Nếu đã đăng nhập, lấy email theo userId
        final email = prefs.getString('biometric_email_${user.uid}');
        debugPrint(
          'BiometricAuthService: Getting email for logged-in user: ${user.uid}, email: ${email != null ? email : "null"}',
        );
        return email;
      } else {
        // Nếu chưa đăng nhập, tìm userId từ biometric_enabled keys (vì email keys có thể đã bị xóa khi logout)
        // Sau đó tìm email theo userId đó
        String? foundUserId;
        final allKeys = prefs.getKeys();

        // Tìm userId từ biometric_enabled keys
        for (final key in allKeys) {
          if (key.startsWith('biometric_enabled_')) {
            final enabled = prefs.getBool(key);
            if (enabled == true) {
              foundUserId = key.replaceFirst('biometric_enabled_', '');
              debugPrint('BiometricAuthService: Found userId from biometric_enabled key: $foundUserId');
              break;
            }
          }
        }

        // Nếu không tìm thấy từ biometric_enabled, thử tìm từ biometric_email keys
        if (foundUserId == null) {
          for (final key in allKeys) {
            if (key.startsWith('biometric_email_')) {
              foundUserId = key.replaceFirst('biometric_email_', '');
              debugPrint('BiometricAuthService: Found userId from biometric_email key: $foundUserId');
              break;
            }
          }
        }

        if (foundUserId != null) {
          final email = prefs.getString('biometric_email_$foundUserId');
          debugPrint(
            'BiometricAuthService: Getting email for userId: $foundUserId, email: ${email != null ? email : "null"}',
          );
          return email;
        }

        debugPrint('BiometricAuthService: No userId found, cannot get email');
        return null;
      }
    } catch (e) {
      debugPrint('BiometricAuthService: Error getting saved login email: $e');
      return null;
    }
  }

  /// Lấy password đã lưu cho biometric login.
  Future<String?> getSavedPassword() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();

      String? userId;
      if (user != null) {
        // Nếu đã đăng nhập, dùng userId hiện tại
        userId = user.uid;
        debugPrint('BiometricAuthService: Getting password for logged-in user: $userId');
      } else {
        // Nếu chưa đăng nhập, tìm userId từ biometric_enabled keys (vì email keys có thể đã bị xóa khi logout)
        final allKeys = prefs.getKeys();

        // Tìm userId từ biometric_enabled keys (ưu tiên vì keys này không bị xóa khi logout)
        for (final key in allKeys) {
          if (key.startsWith('biometric_enabled_')) {
            final enabled = prefs.getBool(key);
            if (enabled == true) {
              userId = key.replaceFirst('biometric_enabled_', '');
              debugPrint('BiometricAuthService: Found userId from biometric_enabled key: $userId');
              break;
            }
          }
        }

        // Nếu không tìm thấy từ biometric_enabled, thử tìm từ biometric_email keys
        if (userId == null) {
          for (final key in allKeys) {
            if (key.startsWith('biometric_email_')) {
              userId = key.replaceFirst('biometric_email_', '');
              debugPrint('BiometricAuthService: Found userId from biometric_email key: $userId');
              break;
            }
          }
        }
      }

      if (userId != null) {
        try {
          final password = await _secureStorage.read(key: 'biometric_password_$userId');
          debugPrint('BiometricAuthService: Password found for userId $userId: ${password != null ? "***" : "null"}');

          // Debug: List all keys in secure storage
          if (password == null) {
            debugPrint('BiometricAuthService: Password is null, checking secure storage keys...');
            // Note: FlutterSecureStorage doesn't have a direct way to list keys,
            // but we can try to read with the expected key format
            debugPrint('BiometricAuthService: Attempted to read key: biometric_password_$userId');
          }

          return password;
        } catch (e) {
          debugPrint('BiometricAuthService: Error reading password from secure storage: $e');
          return null;
        }
      }

      debugPrint('BiometricAuthService: No userId found, cannot get password');
      return null;
    } catch (e) {
      debugPrint('BiometricAuthService: Error getting saved password: $e');
      return null;
    }
  }

  /// Xóa thông tin đăng nhập đã lưu.
  /// [userId] - Optional userId để xóa thông tin của user cụ thể (dùng khi đã logout)
  /// [keepEmail] - Nếu true, giữ lại email (dùng khi logout)
  /// [keepPassword] - Nếu true, giữ lại password (dùng khi logout để có thể đăng nhập lại bằng biometric)
  Future<void> clearSavedLoginInfo({String? userId, bool keepEmail = false, bool keepPassword = false}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();

      // Ưu tiên dùng userId được truyền vào (dùng khi đã logout)
      final targetUserId = userId ?? user?.uid;

      if (targetUserId != null) {
        debugPrint(
          'BiometricAuthService: Clearing info for userId: $targetUserId, keepEmail: $keepEmail, keepPassword: $keepPassword',
        );

        // Xóa email từ SharedPreferences (chỉ nếu keepEmail = false)
        if (!keepEmail) {
          try {
            await prefs.remove('biometric_email_$targetUserId');
            debugPrint('BiometricAuthService: Removed email from SharedPreferences');
          } catch (e) {
            debugPrint('BiometricAuthService: Error removing biometric email: $e');
          }
        } else {
          debugPrint('BiometricAuthService: Keeping email for biometric login');
        }

        // Xóa password từ secure storage (chỉ nếu keepPassword = false)
        if (!keepPassword) {
          try {
            await _secureStorage
                .delete(key: 'biometric_password_$targetUserId')
                .timeout(
                  const Duration(seconds: 2),
                  onTimeout: () {
                    debugPrint('BiometricAuthService: Timeout deleting password, continuing...');
                  },
                );
            debugPrint('BiometricAuthService: Removed password from secure storage');
          } catch (e) {
            debugPrint('BiometricAuthService: Error deleting biometric password from secure storage: $e');
            // Không rethrow, tiếp tục cleanup
          }
        } else {
          debugPrint('BiometricAuthService: Keeping password for biometric login');
        }

        debugPrint('BiometricAuthService: Successfully cleared biometric info for userId: $targetUserId');
      } else {
        // Nếu không có userId, xóa tất cả
        debugPrint('BiometricAuthService: Clearing all biometric info (no userId provided)');
        try {
          final allKeys = prefs.getKeys();
          for (final key in allKeys) {
            if (key.startsWith('biometric_email_')) {
              final foundUserId = key.replaceFirst('biometric_email_', '');
              try {
                await prefs.remove(key);
              } catch (e) {
                debugPrint('BiometricAuthService: Error removing biometric email key $key: $e');
              }
              try {
                await _secureStorage
                    .delete(key: 'biometric_password_$foundUserId')
                    .timeout(
                      const Duration(seconds: 2),
                      onTimeout: () {
                        debugPrint('BiometricAuthService: Timeout deleting password for $foundUserId');
                      },
                    );
              } catch (e) {
                debugPrint('BiometricAuthService: Error deleting biometric password for $foundUserId: $e');
              }
            }
          }
          debugPrint('BiometricAuthService: Successfully cleared all biometric info');
        } catch (e) {
          debugPrint('BiometricAuthService: Error clearing all biometric info: $e');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('BiometricAuthService: Error clearing saved login info: $e');
      debugPrint('BiometricAuthService: Stack trace: $stackTrace');
      // Không rethrow để không làm crash app
    }
  }
}
