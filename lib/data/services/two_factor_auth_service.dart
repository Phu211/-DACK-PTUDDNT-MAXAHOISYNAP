import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:otp/otp.dart';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import '../../core/constants/app_constants.dart';
import 'recovery_codes_service.dart';
import 'encryption_service.dart';

/// Service quản lý Two-Factor Authentication (2FA) sử dụng TOTP.
///
/// TOTP (Time-based One-Time Password) tương thích với Google Authenticator, Authy, etc.
class TwoFactorAuthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RecoveryCodesService _recoveryCodesService = RecoveryCodesService();
  final EncryptionService _encryptionService = EncryptionService();

  /// Bật 2FA cho user.
  /// Tạo secret key và QR code data.
  /// Trả về secret key và QR code URL để hiển thị.
  /// LƯU Ý: Chỉ tạo secret, KHÔNG set enabled = true cho đến khi user verify code thành công.
  Future<Map<String, String>> enable2FA(String userId, String email) async {
    try {
      // Tạo secret key (32 bytes, base32 encoded)
      final secret = _generateSecret();

      // Lưu secret vào Firestore (encrypted) nhưng CHƯA enable
      // Chỉ enable khi user verify code thành công
      final encryptedSecret = await _encryptSecret(secret);

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('twoFactorAuth')
          .doc('settings')
          .set({
            'enabled': false, // CHƯA enable, chỉ enable sau khi verify
            'secret': encryptedSecret, // Encrypted
            'pendingSetup': true, // Flag để biết đang trong quá trình setup
            'createdAt': DateTime.now().toIso8601String(),
          });

      // Tạo recovery codes (chỉ tạo, chưa lưu vào Firestore)
      final recoveryCodes = await _recoveryCodesService.generateRecoveryCodes(
        userId,
      );

      // Tạo QR code URL
      final qrCodeUrl = _generateQRCodeUrl(email, secret);

      return {
        'secret': secret, // Chỉ hiển thị 1 lần
        'qrCodeUrl': qrCodeUrl,
        'recoveryCodes': recoveryCodes.join('\n'),
      };
    } catch (e) {
      debugPrint('Error enabling 2FA: $e');
      rethrow;
    }
  }

  /// Xác nhận và bật 2FA sau khi user verify code thành công.
  Future<void> confirm2FASetup(String userId) async {
    try {
      debugPrint('TwoFactorAuthService: Confirming 2FA setup for user: $userId');
      
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('twoFactorAuth')
          .doc('settings')
          .update({
            'enabled': true,
            'pendingSetup': false,
            'enabledAt': DateTime.now().toIso8601String(),
          });
      
      debugPrint('TwoFactorAuthService: 2FA setup confirmed successfully for user: $userId');
      
      // Verify lại để đảm bảo đã được lưu
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('twoFactorAuth')
          .doc('settings')
          .get();
      
      if (doc.exists) {
        final data = doc.data();
        debugPrint('TwoFactorAuthService: Verified 2FA settings after confirmation: $data');
      } else {
        debugPrint('TwoFactorAuthService: WARNING - 2FA document not found after confirmation!');
      }
    } catch (e, stackTrace) {
      debugPrint('TwoFactorAuthService: Error confirming 2FA setup: $e');
      debugPrint('TwoFactorAuthService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Tắt 2FA cho user.
  Future<void> disable2FA(String userId) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('twoFactorAuth')
          .doc('settings')
          .update({
            'enabled': false,
            'disabledAt': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      debugPrint('Error disabling 2FA: $e');
      rethrow;
    }
  }

  /// Kiểm tra xem user đã bật 2FA chưa.
  Future<bool> is2FAEnabled(String userId) async {
    try {
      debugPrint('TwoFactorAuthService: Checking 2FA status for user: $userId');
      
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('twoFactorAuth')
          .doc('settings')
          .get();

      if (!doc.exists) {
        debugPrint('TwoFactorAuthService: 2FA document does not exist for user: $userId');
        return false;
      }

      final data = doc.data();
      debugPrint('TwoFactorAuthService: 2FA document data: $data');
      
      final enabled = data?['enabled'] == true;
      final pendingSetup = data?['pendingSetup'] == true;
      
      debugPrint('TwoFactorAuthService: enabled=$enabled, pendingSetup=$pendingSetup');
      
      // Chỉ trả về true nếu enabled = true VÀ không phải đang trong quá trình setup
      final result = enabled && !pendingSetup;
      debugPrint('TwoFactorAuthService: 2FA is enabled: $result');
      
      return result;
    } catch (e, stackTrace) {
      debugPrint('TwoFactorAuthService: Error checking 2FA status: $e');
      debugPrint('TwoFactorAuthService: Stack trace: $stackTrace');
      return false;
    }
  }

  /// Xác thực TOTP code.
  /// Trả về true nếu code hợp lệ.
  /// allowPendingSetup: Cho phép verify code ngay cả khi đang trong quá trình setup (chưa enable)
  Future<bool> verifyTOTPCode(String userId, String code, {bool allowPendingSetup = false}) async {
    try {
      // Lấy secret từ Firestore
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('twoFactorAuth')
          .doc('settings')
          .get();

      if (!doc.exists) return false;

      final data = doc.data();
      // Nếu không cho phép pending setup, chỉ verify khi đã enabled
      if (!allowPendingSetup && data?['enabled'] != true) return false;
      // Nếu cho phép pending setup, chỉ cần có secret
      if (allowPendingSetup && data?['secret'] == null) return false;

      final encryptedSecret = data?['secret'] as String?;
      if (encryptedSecret == null) return false;

      // Decrypt secret
      final secret = await _decryptSecret(encryptedSecret);
      // Trim secret key để loại bỏ khoảng trắng hoặc ký tự đặc biệt
      final cleanSecret = secret.trim().toUpperCase();
      debugPrint('2FA Verify: Decrypted secret: ${cleanSecret.substring(0, 4)}... (length: ${cleanSecret.length})');
      // Debug: In full secret trong debug mode (chỉ để debug, không nên in trong production)
      if (kDebugMode) {
        debugPrint('2FA Verify: Full secret (original): $secret');
        debugPrint('2FA Verify: Full secret (cleaned): $cleanSecret');
      }

      // Generate TOTP code từ secret (sử dụng cleanSecret)
      final expectedCode = await _generateTOTPCode(cleanSecret);
      debugPrint('2FA Verify: Generated code at current time: $expectedCode');
      
      // Debug: Generate codes for ±1 time step và ±2 time steps để tránh timing issues
      final codeMinus2 = await _generateTOTPCode(cleanSecret, timeOffset: -60);
      final codeMinus1 = await _generateTOTPCode(cleanSecret, timeOffset: -30);
      final codePlus1 = await _generateTOTPCode(cleanSecret, timeOffset: 30);
      final codePlus2 = await _generateTOTPCode(cleanSecret, timeOffset: 60);
      debugPrint('2FA Verify: Codes for ±60s: $codeMinus2 $codeMinus1 (current: $expectedCode) $codePlus1 $codePlus2');

      // So sánh (cho phép sai lệch ±2 time steps để tránh timing issues)
      final codeInt = int.tryParse(code.trim());
      if (codeInt == null) {
        debugPrint('2FA Verify: Invalid code format: $code');
        return false;
      }

      // Kiểm tra với current time và ±2 time steps (60 giây)
      final isValid = codeInt == expectedCode ||
          codeInt == codeMinus2 ||
          codeInt == codeMinus1 ||
          codeInt == codePlus1 ||
          codeInt == codePlus2;

      debugPrint('2FA Verify: code=$codeInt, expected=$expectedCode, isValid=$isValid');
      if (!isValid) {
        debugPrint('2FA Verify: All codes checked: [$codeMinus2, $codeMinus1, $expectedCode, $codePlus1, $codePlus2]');
      }
      
      return isValid;
    } catch (e) {
      debugPrint('Error verifying TOTP code: $e');
      return false;
    }
  }

  /// Tạo secret key ngẫu nhiên (base32 encoded).
  String _generateSecret() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; // Base32 alphabet
    final random = Random.secure();
    final buffer = StringBuffer();

    for (int i = 0; i < 16; i++) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }

    return buffer.toString();
  }

  /// Tạo QR code URL cho Google Authenticator.
  String _generateQRCodeUrl(String email, String secret) {
    final issuer = 'Synap';
    final accountName = email.split('@').first;
    final otpAuthUrl =
        'otpauth://totp/$issuer:$accountName?secret=$secret&issuer=$issuer';
    return 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(otpAuthUrl)}';
  }

  /// Generate TOTP code từ secret.
  /// Sử dụng package `otp` để generate code theo RFC 6238.
  /// LƯU Ý: Google Authenticator mặc định dùng SHA1, không phải SHA256
  /// Thử cả package `otp` và manual implementation để đảm bảo tương thích
  Future<int> _generateTOTPCode(String secret, {int timeOffset = 0}) async {
    try {
      final now = DateTime.now().add(Duration(seconds: timeOffset));
      // TOTP sử dụng Unix timestamp (seconds), không phải milliseconds
      final timestamp = now.millisecondsSinceEpoch ~/ 1000;

      // Clean secret key: trim và uppercase
      final cleanSecret = secret.trim().toUpperCase();
      
      // Debug: Log secret key và timestamp
      if (kDebugMode) {
        debugPrint('2FA Generate: secret=$cleanSecret, secretLength=${cleanSecret.length}, timeOffset=$timeOffset, timestamp=$timestamp');
      }

      // Generate TOTP code (6 digits)
      // Sử dụng SHA1 để tương thích với Google Authenticator (mặc định)
      // Thử cả package `otp` và manual implementation
      final code = OTP.generateTOTPCodeString(
        cleanSecret,
        timestamp,
        algorithm: Algorithm.SHA1, // Đổi từ SHA256 sang SHA1
        length: 6,
        interval: 30, // 30 seconds time step
      );

      final codeInt = int.parse(code);
      
      // Thử generate code bằng manual implementation để so sánh
      final manualCode = await _generateTOTPCodeManual(cleanSecret, timestamp);
      
      if (kDebugMode) {
        debugPrint('2FA Generate: Package code=$codeInt, Manual code=$manualCode, timestamp=$timestamp');
        if (codeInt != manualCode) {
          debugPrint('2FA Generate: WARNING - Package and manual codes do not match!');
        }
      }
      
      // Sử dụng manual code nếu có sự khác biệt
      return manualCode;
    } catch (e, stackTrace) {
      debugPrint('Error generating TOTP code: $e');
      debugPrint('Stack trace: $stackTrace');
      return 0;
    }
  }

  /// Generate TOTP code manually để đảm bảo tương thích với Google Authenticator
  /// Implementation theo RFC 6238
  Future<int> _generateTOTPCodeManual(String secret, int timestamp) async {
    try {
      // Base32 decode secret
      final secretBytes = _base32Decode(secret);
      
      // Calculate time step (30 seconds)
      int timeStep = timestamp ~/ 30;
      
      // Convert time step to 8-byte big-endian
      final timeStepBytes = Uint8List(8);
      int tempTimeStep = timeStep;
      for (int i = 7; i >= 0; i--) {
        timeStepBytes[i] = tempTimeStep & 0xFF;
        tempTimeStep >>= 8;
      }
      
      // HMAC-SHA1
      final hmac = Hmac.sha1();
      final secretKey = SecretKey(secretBytes);
      final mac = await hmac.calculateMac(timeStepBytes, secretKey: secretKey);
      
      // Dynamic truncation
      final offset = mac.bytes[19] & 0x0F;
      final binary = ((mac.bytes[offset] & 0x7F) << 24) |
                     ((mac.bytes[offset + 1] & 0xFF) << 16) |
                     ((mac.bytes[offset + 2] & 0xFF) << 8) |
                     (mac.bytes[offset + 3] & 0xFF);
      
      // Generate 6-digit code
      final code = binary % 1000000;
      
      return code;
    } catch (e) {
      debugPrint('Error in manual TOTP generation: $e');
      return 0;
    }
  }

  /// Base32 decode (RFC 4648)
  Uint8List _base32Decode(String input) {
    const base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final inputUpper = input.toUpperCase();
    final buffer = <int>[];
    
    int bits = 0;
    int value = 0;
    
    for (int i = 0; i < inputUpper.length; i++) {
      final char = inputUpper[i];
      if (char == '=') break;
      
      final index = base32Chars.indexOf(char);
      if (index == -1) continue;
      
      value = (value << 5) | index;
      bits += 5;
      
      if (bits >= 8) {
        buffer.add((value >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    
    return Uint8List.fromList(buffer);
  }

  /// Encrypt secret trước khi lưu vào Firestore.
  Future<String> _encryptSecret(String secret) async {
    try {
      // Sử dụng EncryptionService để encrypt secret với keyId cố định cho 2FA
      final encrypted = await _encryptionService.encrypt(
        secret,
        keyId: '2fa_secret_key',
      );
      // Lưu cả encrypted data, nonce, và mac
      return jsonEncode({
        'data': encrypted['cipherText'],
        'nonce': encrypted['nonce'],
        'mac': encrypted['mac'],
      });
    } catch (e) {
      debugPrint('Error encrypting secret: $e');
      // Fallback to base64 nếu encryption fails
      return base64Encode(utf8.encode(secret));
    }
  }

  /// Decrypt secret từ Firestore.
  Future<String> _decryptSecret(dynamic encryptedSecret) async {
    try {
      // Xử lý cả String và Map (Firestore có thể trả về Map)
      Map<String, dynamic> jsonData;
      if (encryptedSecret is String) {
        jsonData = jsonDecode(encryptedSecret) as Map<String, dynamic>;
      } else if (encryptedSecret is Map) {
        jsonData = encryptedSecret as Map<String, dynamic>;
      } else {
        throw Exception('Invalid encrypted secret type: ${encryptedSecret.runtimeType}');
      }

      // Kiểm tra format mới (có mac)
      if (jsonData.containsKey('data') && jsonData.containsKey('nonce') && jsonData.containsKey('mac')) {
        try {
          final decrypted = await _encryptionService.decrypt(
            cipherText: jsonData['data'] as String,
            nonce: jsonData['nonce'] as String,
            mac: jsonData['mac'] as String,
            keyId: '2fa_secret_key',
          );
          debugPrint('2FA: Successfully decrypted secret with MAC');
          return decrypted;
        } catch (e) {
          debugPrint('2FA: Error decrypting with MAC: $e');
          rethrow;
        }
      }
      // Backward compatibility: format cũ không có mac
      else if (jsonData.containsKey('data') && jsonData.containsKey('nonce')) {
        debugPrint('2FA: Old format without MAC detected, attempting decrypt without MAC');
        try {
          final decrypted = await _encryptionService.decrypt(
            cipherText: jsonData['data'] as String,
            nonce: jsonData['nonce'] as String,
            mac: null, // Không có MAC trong format cũ
            keyId: '2fa_secret_key',
          );
          debugPrint('2FA: Successfully decrypted old format secret');
          return decrypted;
        } catch (e) {
          debugPrint('2FA: Error decrypting old format: $e');
          throw Exception('Cannot decrypt old format secret. Please disable and re-enable 2FA to create a new secret.');
        }
      }
    } catch (e) {
      // Nếu không phải JSON, thử base64 decode (backward compatibility)
      if (encryptedSecret is String) {
        try {
          return utf8.decode(base64Decode(encryptedSecret));
        } catch (_) {
          debugPrint('Error decrypting secret: $e');
          rethrow;
        }
      }
      debugPrint('Error decrypting secret: $e');
      rethrow;
    }
    throw Exception('Invalid encrypted secret format');
  }
}
