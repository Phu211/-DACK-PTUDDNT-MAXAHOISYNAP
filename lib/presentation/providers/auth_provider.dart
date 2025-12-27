import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/user_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/presence_service.dart';
import '../../data/services/agora_call_service.dart';
import '../../data/services/call_notification_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/login_history_service.dart';
import '../../data/services/account_lockout_service.dart';
import '../../data/services/suspicious_activity_service.dart';
import '../../data/services/biometric_auth_service.dart';
import '../../data/services/two_factor_auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final PresenceService _presenceService = PresenceService();
  final AgoraCallService _callService = AgoraCallService.instance;
  final CallNotificationService _callNotificationService = CallNotificationService.instance;
  final SessionService _sessionService = SessionService();
  final LoginHistoryService _loginHistoryService = LoginHistoryService();
  final AccountLockoutService _lockoutService = AccountLockoutService();
  final SuspiciousActivityService _suspiciousActivityService = SuspiciousActivityService();
  final BiometricAuthService _biometricService = BiometricAuthService();
  final TwoFactorAuthService _twoFactorService = TwoFactorAuthService();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isSigningOut = false; // Flag để tránh double processing
  bool _pending2FAVerification = false; // Flag để đánh dấu cần verify 2FA
  String? _pending2FAUserId; // User ID cần verify 2FA
  String? _pending2FAEmail; // Email của user cần verify 2FA

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;
  bool get pending2FAVerification => _pending2FAVerification;
  String? get pending2FAUserId => _pending2FAUserId;
  String? get pending2FAEmail => _pending2FAEmail;

  AuthProvider() {
    _init();
    // Khởi tạo call service ngay khi provider được tạo (chỉ trên mobile)
    if (!kIsWeb) {
      try {
        _callService.init();
      } catch (e) {
        debugPrint('Error initializing call service: $e');
      }
    }
  }

  void _init() {
    _authService.authStateChanges.listen(
      (user) async {
        try {
          if (user != null) {
            debugPrint('AuthProvider: authStateChanges - User signed in: ${user.uid}');
            
            // Kiểm tra 2FA trước khi load user
            try {
              final is2FAEnabled = await _twoFactorService.is2FAEnabled(user.uid);
              debugPrint('AuthProvider: 2FA status for ${user.uid}: $is2FAEnabled');
              
              if (is2FAEnabled) {
                // ✅ Kiểm tra xem đã verify 2FA trong session này chưa
                final is2FAVerified = await _is2FAVerifiedInSession(user.uid);
                debugPrint('AuthProvider: 2FA verified in session: $is2FAVerified');
                
                if (!is2FAVerified) {
                  debugPrint('AuthProvider: 2FA is enabled but not verified in session, setting pending verification flag');
                  // Nếu có 2FA nhưng chưa verify trong session này, đánh dấu cần verify
                  _pending2FAVerification = true;
                  _pending2FAUserId = user.uid;
                  // Lấy email từ Firebase user
                  _pending2FAEmail = user.email;
                  _currentUser = null; // Đảm bảo không có currentUser
                  notifyListeners();
                  return; // Không load user, chờ verify 2FA
                } else {
                  debugPrint('AuthProvider: 2FA is enabled and already verified in session, loading user');
                  // Đã verify trong session này, load user bình thường
                  _pending2FAVerification = false;
                  _pending2FAUserId = null;
                  _pending2FAEmail = null;
                }
              } else {
                debugPrint('AuthProvider: 2FA is not enabled, loading user');
                // Không có 2FA, clear flag và load user bình thường
                _pending2FAVerification = false;
                _pending2FAUserId = null;
                _pending2FAEmail = null;
              }
            } catch (e) {
              debugPrint('AuthProvider: Error checking 2FA status: $e');
              // Nếu lỗi kiểm tra 2FA, vẫn load user (fallback)
              _pending2FAVerification = false;
              _pending2FAUserId = null;
              _pending2FAEmail = null;
            }
            
            // Load user chỉ khi không có 2FA hoặc đã verify
            await loadCurrentUser();
            // Khởi tạo Agora engine ngay khi user đăng nhập
            _initCallService();
          } else {
            debugPrint('AuthProvider: authStateChanges - User signed out');
            // ✅ Lưu userId trước khi clear để xóa trạng thái 2FA
            final signedOutUserId = _currentUser?.id ?? _pending2FAUserId;
            
            // Clear 2FA flags khi sign out
            _pending2FAVerification = false;
            _pending2FAUserId = null;
            _pending2FAEmail = null;
            
            // ✅ Xóa trạng thái 2FA verified khi sign out (nếu có userId)
            if (signedOutUserId != null) {
              await _clear2FAVerifiedInSession(signedOutUserId);
            }
            
            // Chỉ clear state nếu không phải đang trong quá trình signOut
            // (signOut() sẽ tự xử lý)
            if (!_isSigningOut) {
              _currentUser = null;
              notifyListeners();
            } else {
              debugPrint('AuthProvider: authStateChanges - Ignoring because signOut in progress');
            }
          }
        } catch (e, stackTrace) {
          debugPrint('AuthProvider: Error in authStateChanges listener: $e');
          debugPrint('AuthProvider: Stack trace: $stackTrace');
          // Không rethrow để tránh crash
        }
      },
      onError: (error) {
        debugPrint('AuthProvider: Error in authStateChanges stream: $error');
        // Không rethrow để tránh crash
      },
    );
  }
  
  /// Gọi sau khi 2FA được verify thành công
  Future<void> complete2FAVerification() async {
    debugPrint('AuthProvider: Completing 2FA verification');
    _pending2FAVerification = false;
    final userId = _pending2FAUserId;
    _pending2FAUserId = null;
    _pending2FAEmail = null;
    
    // ✅ Lưu trạng thái đã verify 2FA trong session
    if (userId != null) {
      await _save2FAVerifiedInSession(userId);
    }
    
    // Load user sau khi 2FA được verify
    if (userId != null) {
      await loadCurrentUser();
      _initCallService();
    }
  }
  
  /// Kiểm tra xem 2FA đã được verify trong session này chưa
  Future<bool> _is2FAVerifiedInSession(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '2fa_verified_$userId';
      final verifiedTimestamp = prefs.getInt(key);
      
      if (verifiedTimestamp == null) {
        debugPrint('AuthProvider: No 2FA verification timestamp found for user $userId');
        return false;
      }
      
      // Kiểm tra xem timestamp có còn hợp lệ không (trong vòng 30 ngày)
      final verifiedTime = DateTime.fromMillisecondsSinceEpoch(verifiedTimestamp);
      final now = DateTime.now();
      final daysSinceVerification = now.difference(verifiedTime).inDays;
      
      if (daysSinceVerification > 30) {
        debugPrint('AuthProvider: 2FA verification expired (${daysSinceVerification} days ago)');
        // Xóa timestamp đã hết hạn
        await prefs.remove(key);
        return false;
      }
      
      debugPrint('AuthProvider: 2FA verified ${daysSinceVerification} days ago, still valid');
      return true;
    } catch (e) {
      debugPrint('AuthProvider: Error checking 2FA verification status: $e');
      return false;
    }
  }
  
  /// Lưu trạng thái đã verify 2FA trong session
  Future<void> _save2FAVerifiedInSession(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '2fa_verified_$userId';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(key, timestamp);
      debugPrint('AuthProvider: Saved 2FA verification timestamp for user $userId');
    } catch (e) {
      debugPrint('AuthProvider: Error saving 2FA verification status: $e');
    }
  }
  
  /// Xóa trạng thái đã verify 2FA (khi sign out)
  Future<void> _clear2FAVerifiedInSession(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '2fa_verified_$userId';
      await prefs.remove(key);
      debugPrint('AuthProvider: Cleared 2FA verification status for user $userId');
    } catch (e) {
      debugPrint('AuthProvider: Error clearing 2FA verification status: $e');
    }
  }

  // Khởi tạo Agora engine để có thể nhận cuộc gọi (chỉ trên mobile)
  Future<void> _initCallService() async {
    if (_currentUser == null || kIsWeb) return;

    try {
      // Với Agora, chỉ cần init engine, không cần connect như Stringee
      // Engine sẽ được sử dụng khi có cuộc gọi
      await _callService.init();
      debugPrint('AuthProvider: Đã khởi tạo Agora engine cho user: ${_currentUser!.id}');
    } catch (e) {
      debugPrint('AuthProvider: Lỗi khởi tạo Agora engine: $e');
      // Thử lại sau 3 giây nếu lỗi
      if (!kIsWeb) {
        Future.delayed(const Duration(seconds: 3), () {
          if (_currentUser != null) {
            _initCallService();
          }
        });
      }
    }
  }

  Future<void> loadCurrentUser() async {
    try {
      _currentUser = await _authService.getCurrentUserData();
      // Set user online when loading
      if (_currentUser != null) {
        await _presenceService.setUserOnline(_currentUser!.id);
        // Khởi tạo Agora engine sau khi load user (chỉ trên mobile)
        if (!kIsWeb) {
          _initCallService();
          // Initialize call notification service (chỉ trên mobile)
          try {
            await _callNotificationService.init(_currentUser!.id);
          } catch (e) {
            debugPrint('Error initializing call notification service: $e');
          }
          // Ghi nhận phiên đăng nhập (session tracking) khi app khởi động lại
          try {
            await _sessionService.registerCurrentSession();
            // Cập nhật lastActiveAt định kỳ
            _sessionService.touchCurrentSession();
          } catch (e) {
            debugPrint('Error registering session: $e');
          }
        }
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String username,
    required String fullName,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.signUpWithEmail(
        email: email,
        password: password,
        username: username,
        fullName: fullName,
      );
      // Set user online after sign up
      if (_currentUser != null) {
        await _presenceService.setUserOnline(_currentUser!.id);
        // Khởi tạo Agora engine sau khi đăng ký (chỉ trên mobile)
        if (!kIsWeb) {
          _initCallService();
          // Initialize call notification service để lưu FCM token
          try {
            await _callNotificationService.init(_currentUser!.id);
          } catch (e) {
            debugPrint('Error initializing call notification service after sign up: $e');
          }
          // Ghi nhận phiên đăng nhập (session tracking)
          try {
            await _sessionService.registerCurrentSession();
          } catch (e) {
            debugPrint('Error registering session: $e');
          }
          // Ghi lại lịch sử đăng nhập (không phát hiện thiết bị mới khi đăng ký)
          try {
            await _loginHistoryService.recordLogin();
          } catch (e) {
            debugPrint('Error recording login history: $e');
          }
        }
      }
      _isLoading = false;
      notifyListeners();
      return _currentUser != null;
    } catch (e) {
      _errorMessage = _getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Kiểm tra xem tài khoản có bị khóa không
      final lockedUntil = await _lockoutService.isAccountLocked(email);
      if (lockedUntil != null) {
        final minutesRemaining = (lockedUntil.difference(DateTime.now()).inMinutes + 1).clamp(
          1,
          AccountLockoutService.lockoutDurationMinutes,
        );
        _errorMessage =
            'Tài khoản đã bị khóa do đăng nhập sai quá nhiều lần. '
            'Vui lòng thử lại sau $minutesRemaining phút.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // ✅ Xóa trạng thái 2FA verified cũ trước khi đăng nhập mới
      // (để đảm bảo user phải verify lại khi đăng nhập mới)
      final oldUserId = _currentUser?.id;
      if (oldUserId != null) {
        await _clear2FAVerifiedInSession(oldUserId);
      }
      
      _currentUser = await _authService.signInWithEmail(email: email, password: password);

      // Nếu đăng nhập thành công, xóa failed attempts
      if (_currentUser != null) {
        // ✅ Xóa trạng thái 2FA verified của user mới (nếu có từ session trước)
        // để đảm bảo user phải verify lại khi đăng nhập mới
        await _clear2FAVerifiedInSession(_currentUser!.id);
        
        await _lockoutService.clearFailedAttempts(email);

        await _presenceService.setUserOnline(_currentUser!.id);
        // Khởi tạo Agora engine sau khi đăng nhập (chỉ trên mobile)
        if (!kIsWeb) {
          _initCallService();
          // ✅ Initialize call notification service NGAY để lưu FCM token
          // Điều này đảm bảo user có thể nhận cuộc gọi ngay cả khi app không mở
          try {
            await _callNotificationService.init(_currentUser!.id);
            debugPrint('AuthProvider: CallNotificationService initialized, FCM token should be saved');
          } catch (e) {
            debugPrint('Error initializing call notification service after sign in: $e');
            // Retry sau 5 giây nếu lỗi
            Future.delayed(const Duration(seconds: 5), () async {
              try {
                await _callNotificationService.init(_currentUser!.id);
                debugPrint('AuthProvider: CallNotificationService initialized on retry');
              } catch (e2) {
                debugPrint('Error retrying call notification service init: $e2');
              }
            });
          }
          // Ghi nhận phiên đăng nhập (session tracking)
          // FCM token sẽ được lưu riêng trong users/{uid}/fcmToken,
          // có thể lấy sau từ Firestore nếu cần
          try {
            await _sessionService.registerCurrentSession();
          } catch (e) {
            debugPrint('Error registering session: $e');
          }
          // Ghi lại lịch sử đăng nhập và phát hiện thiết bị mới
          bool? isNewDevice;
          try {
            isNewDevice = await _loginHistoryService.recordLogin();
            if (isNewDevice) {
              debugPrint('New device detected during login');
            }
          } catch (e) {
            debugPrint('Error recording login history: $e');
          }
          // Phát hiện hoạt động đáng ngờ khi đăng nhập
          // Truyền isNewDevice để tránh gọi recordLogin() lại
          try {
            await _suspiciousActivityService.detectSuspiciousLogin(email, isNewDevice: isNewDevice);
          } catch (e) {
            debugPrint('Error detecting suspicious activity: $e');
          }
        }
      }
      _isLoading = false;
      notifyListeners();
      return _currentUser != null;
    } on FirebaseAuthException catch (e) {
      // Nếu đăng nhập sai, ghi nhận failed attempt
      if (e.code == 'wrong-password' || e.code == 'user-not-found') {
        try {
          final isLocked = await _lockoutService.recordFailedAttempt(email);
          if (isLocked) {
            _errorMessage =
                'Tài khoản đã bị khóa do đăng nhập sai quá nhiều lần. '
                'Vui lòng thử lại sau ${AccountLockoutService.lockoutDurationMinutes} phút.';
          } else {
            final remaining = await _lockoutService.getRemainingAttempts(email);
            _errorMessage = _getErrorMessage(e);
            if (remaining < AccountLockoutService.maxFailedAttempts && remaining > 0) {
              _errorMessage =
                  '${_errorMessage ?? 'Đăng nhập thất bại'}\nCòn $remaining lần thử trước khi tài khoản bị khóa.';
            }
          }
        } catch (_) {
          _errorMessage = _getErrorMessage(e);
        }
      } else {
        _errorMessage = _getErrorMessage(e);
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = _getErrorMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    // Tránh gọi signOut nhiều lần đồng thời
    if (_isSigningOut) {
      debugPrint('AuthProvider: SignOut already in progress, skipping...');
      return;
    }

    debugPrint('AuthProvider: Starting signOut process...');
    _isSigningOut = true;

    try {
      // Lưu userId trước khi signOut để có thể cleanup
      final userId = _currentUser?.id;
      debugPrint('AuthProvider: Current userId before signOut: $userId');

      // Set user offline before signing out (wrap in try-catch để không crash nếu có lỗi)
      if (userId != null) {
        try {
          debugPrint('AuthProvider: Setting user offline...');
          await _presenceService.setUserOffline(userId);
          debugPrint('AuthProvider: User set offline successfully');
        } catch (e) {
          debugPrint('AuthProvider: Error setting user offline during signOut: $e');
          // Continue with signOut even if this fails
        }

        // Cleanup services trước khi signOut từ Firebase
        // Thực hiện cleanup một cách an toàn và không block quá lâu
        if (!kIsWeb) {
          // Cleanup CallNotificationService
          try {
            debugPrint('AuthProvider: Cleaning up CallNotificationService...');
            _callNotificationService.dispose();
            debugPrint('AuthProvider: CallNotificationService cleaned up successfully');
          } catch (e, stackTrace) {
            debugPrint('AuthProvider: Error cleaning up CallNotificationService: $e');
            debugPrint('AuthProvider: Stack trace: $stackTrace');
            // Continue with signOut even if this fails
          }

          // Đợi một chút giữa các cleanup operations
          await Future.delayed(const Duration(milliseconds: 50));

          // Cleanup Agora engine
          try {
            debugPrint('AuthProvider: Cleaning up Agora engine...');
            _callService.dispose();
            debugPrint('AuthProvider: Agora engine cleaned up successfully');
          } catch (e, stackTrace) {
            debugPrint('AuthProvider: Error cleaning up Agora engine: $e');
            debugPrint('AuthProvider: Stack trace: $stackTrace');
            // Continue with signOut even if this fails
          }
        }
      }

      // Sign out from Firebase Auth
      // Điều này sẽ trigger authStateChanges listener, nhưng chúng ta đã set _isSigningOut = true
      // nên listener sẽ không xử lý lại
      debugPrint('AuthProvider: Calling Firebase Auth signOut...');
      try {
        await _authService.signOut();
        debugPrint('AuthProvider: Firebase Auth signOut completed');
      } catch (e, stackTrace) {
        debugPrint('AuthProvider: Error during Firebase Auth signOut: $e');
        debugPrint('AuthProvider: Stack trace: $stackTrace');
        // Continue even if Firebase signOut fails - we still want to clear local state
      }

      // Xóa thông tin biometric đã lưu (sau khi Firebase signOut để đảm bảo userId vẫn còn)
      // Làm sau Firebase signOut nhưng trước khi clear _currentUser
      // Sử dụng unawaited để không block signOut process
      if (userId != null) {
        // KHÔNG xóa biometric info khi logout (giữ lại email và password để có thể đăng nhập lại bằng biometric)
        // Chỉ xóa khi user tắt biometric login hoặc đổi mật khẩu
        debugPrint('AuthProvider: Keeping biometric credentials for future login');
        debugPrint('AuthProvider: Biometric cleanup initiated (non-blocking)');
      }

      // ✅ Xóa trạng thái 2FA verified khi sign out
      if (userId != null) {
        await _clear2FAVerifiedInSession(userId);
      }
      
      // Clear current user state (luôn thực hiện dù có lỗi hay không)
      debugPrint('AuthProvider: Clearing user state...');
      _currentUser = null;
      _isLoading = false;
      _errorMessage = null;

      // Wrap notifyListeners in try-catch để tránh crash nếu có lỗi
      try {
        notifyListeners();
        debugPrint('AuthProvider: notifyListeners called successfully');
      } catch (e, stackTrace) {
        debugPrint('AuthProvider: Error in notifyListeners after signOut: $e');
        debugPrint('AuthProvider: Stack trace: $stackTrace');
      }

      debugPrint('AuthProvider: SignOut completed successfully');
      debugPrint('AuthProvider: isAuthenticated after signOut: $isAuthenticated');

      // Đợi một chút để đảm bảo mọi thứ được cleanup và UI có thời gian update
      // Tăng delay để đảm bảo tất cả các operations đã hoàn thành
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e, stackTrace) {
      debugPrint('AuthProvider: Unexpected error during signOut: $e');
      debugPrint('AuthProvider: Stack trace: $stackTrace');
      // Even if there's an error, clear the user state
      _currentUser = null;
      _isLoading = false;
      _errorMessage = null;

      // Wrap notifyListeners in try-catch để tránh crash nếu có lỗi
      try {
        notifyListeners();
      } catch (e) {
        debugPrint('AuthProvider: Error in notifyListeners during signOut error handling: $e');
      }

      // Không rethrow để tránh crash - chỉ log error
    } finally {
      _isSigningOut = false;
      debugPrint('AuthProvider: SignOut process finished, flag reset');
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  String _getErrorMessage(dynamic error) {
    // Handle FirebaseAuthException
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'Email này đã được sử dụng. Vui lòng đăng nhập hoặc xóa tài khoản cũ trong Firebase Console.';
        case 'weak-password':
          return 'Mật khẩu quá yếu. Vui lòng chọn mật khẩu mạnh hơn (ít nhất 6 ký tự).';
        case 'invalid-email':
          return 'Email không hợp lệ. Vui lòng kiểm tra lại.';
        case 'user-not-found':
          return 'Không tìm thấy tài khoản với email này.';
        case 'wrong-password':
          return 'Mật khẩu không đúng. Vui lòng thử lại.';
        case 'too-many-requests':
          return 'Quá nhiều yêu cầu. Vui lòng thử lại sau.';
        case 'network-request-failed':
          return 'Lỗi kết nối mạng. Vui lòng kiểm tra internet.';
        case 'configuration-not-found':
          return 'Firebase chưa được cấu hình. Vui lòng kiểm tra lại.';
        default:
          return 'Lỗi: ${error.message ?? error.code}';
      }
    }

    // Handle string errors
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('email-already-in-use')) {
      return 'Email này đã được sử dụng. Vui lòng đăng nhập hoặc xóa tài khoản cũ trong Firebase Console.';
    } else if (errorString.contains('weak-password')) {
      return 'Mật khẩu quá yếu. Vui lòng chọn mật khẩu mạnh hơn.';
    } else if (errorString.contains('invalid-email')) {
      return 'Email không hợp lệ. Vui lòng kiểm tra lại.';
    } else if (errorString.contains('user-not-found')) {
      return 'Không tìm thấy tài khoản với email này.';
    } else if (errorString.contains('wrong-password')) {
      return 'Mật khẩu không đúng. Vui lòng thử lại.';
    }

    // Default error message
    return 'Đã xảy ra lỗi: ${error.toString()}';
  }
}
