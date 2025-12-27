import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import '../../../data/services/biometric_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final BiometricAuthService _biometricService = BiometricAuthService();
  bool _obscurePassword = true;
  bool _keepLoggedIn = false;
  bool _isEmailFocused = false;
  bool _isPasswordFocused = false;
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  String? _savedEmail;

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricStatus() async {
    if (kIsWeb) return; // Biometric không hoạt động trên web

    try {
      final available = await _biometricService.isBiometricAvailable();

      // Kiểm tra xem có email đã lưu không
      final savedEmail = await _biometricService.getSavedLoginEmail();

      // Kiểm tra xem có flag biometric_enabled không (tìm trong tất cả keys)
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      bool hasBiometricEnabled = false;
      for (final key in allKeys) {
        if (key.startsWith('biometric_enabled_') && prefs.getBool(key) == true) {
          hasBiometricEnabled = true;
          break;
        }
      }

      // Nếu có savedEmail HOẶC có flag biometric_enabled, thì hiển thị nút
      final enabled = (savedEmail != null && savedEmail.isNotEmpty) || hasBiometricEnabled;

      if (mounted) {
        setState(() {
          _isBiometricAvailable = available;
          _isBiometricEnabled = enabled;
          _savedEmail = savedEmail;
          if (savedEmail != null && savedEmail.isNotEmpty) {
            _emailController.text = savedEmail;
          }
        });
      }
    } catch (e) {
      debugPrint('Error checking biometric status: $e');
    }
  }

  Future<void> _handleBiometricLogin() async {
    if (!_isBiometricAvailable || !_isBiometricEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đăng nhập bằng sinh trắc học chưa được bật hoặc thiết bị không hỗ trợ'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      // Xác thực bằng sinh trắc học
      final authenticated = await _biometricService.authenticate(reason: 'Xác thực để đăng nhập vào tài khoản');

      if (!authenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Xác thực sinh trắc học không thành công'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // Nếu xác thực thành công, tự động đăng nhập nếu có email và password đã lưu
      if (mounted) {
        // Lấy lại savedEmail và password để đảm bảo có dữ liệu mới nhất
        final savedEmail = await _biometricService.getSavedLoginEmail();
        final savedPassword = await _biometricService.getSavedPassword();

        debugPrint('Biometric login - savedEmail: $savedEmail, savedPassword: ${savedPassword != null ? "***" : null}');

        if (savedEmail != null && savedEmail.isNotEmpty && savedPassword != null && savedPassword.isNotEmpty) {
          // Có cả email và password, tự động đăng nhập
          debugPrint('Biometric login - Auto logging in with saved credentials');

          setState(() {
            _emailController.text = savedEmail;
            _passwordController.text = savedPassword;
          });

          // Đợi một chút để UI update
          await Future.delayed(const Duration(milliseconds: 200));

          if (mounted) {
            // Tự động gọi hàm đăng nhập
            await _handleLogin();
          }
        } else if (savedEmail != null && savedEmail.isNotEmpty) {
          debugPrint('Biometric login - Only email found, requesting password');
          // Chỉ có email, tự động điền email và focus vào password
          setState(() {
            _emailController.text = _savedEmail!;
          });

          await Future.delayed(const Duration(milliseconds: 100));

          if (mounted) {
            _passwordFocusNode.requestFocus();

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Xác thực thành công! Vui lòng nhập mật khẩu để hoàn tất đăng nhập.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          // Chưa có email đã lưu, chỉ focus vào email field
          _emailController.selection = TextSelection.fromPosition(TextPosition(offset: _emailController.text.length));
          FocusScope.of(context).requestFocus(FocusNode());
          await Future.delayed(const Duration(milliseconds: 100));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Xác thực thành công! Vui lòng nhập email và mật khẩu để đăng nhập.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi xác thực sinh trắc học: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _handleLogin() async {
    debugPrint('LoginScreen: _handleLogin called');
    if (!_formKey.currentState!.validate()) {
      debugPrint('LoginScreen: Form validation failed');
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final email = _emailController.text.trim();
    debugPrint('LoginScreen: Attempting sign in with email: $email');
    final success = await authProvider.signIn(email: email, password: _passwordController.text);
    debugPrint('LoginScreen: Sign in result: $success, mounted: $mounted');

    if (success) {
      // Lưu email và password nếu user đã bật biometric login
      // Làm ngay sau khi sign in thành công, trước khi kiểm tra mounted
      // để đảm bảo password được lưu ngay cả khi widget bị dispose
      final password = _passwordController.text;
      if (!kIsWeb) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final firebaseUser = FirebaseAuth.instance.currentUser;
          debugPrint('LoginScreen: Checking biometric status - userId: ${firebaseUser?.uid}');
          if (firebaseUser != null) {
            final biometricKey = 'biometric_enabled_${firebaseUser.uid}';
            final biometricEnabled = prefs.getBool(biometricKey) ?? false;
            debugPrint('LoginScreen: biometric_enabled flag: $biometricEnabled (key: $biometricKey)');

            // Kiểm tra tất cả các keys biometric_enabled để debug
            final allKeys = prefs.getKeys();
            final biometricKeys = allKeys.where((k) => k.startsWith('biometric_enabled_')).toList();
            debugPrint('LoginScreen: All biometric_enabled keys: $biometricKeys');

            if (biometricEnabled) {
              debugPrint('LoginScreen: Saving credentials for biometric login');
              await _biometricService.saveLoginCredentials(email, password);
              debugPrint('LoginScreen: Credentials saved successfully');
            } else {
              debugPrint('LoginScreen: Biometric login not enabled, skipping credential save');
            }
          } else {
            debugPrint('LoginScreen: firebaseUser is null, cannot save credentials');
          }
        } catch (e) {
          debugPrint('LoginScreen: Error saving biometric credentials: $e');
        }
      }

      // Kiểm tra mounted sau khi lưu credentials
      if (!mounted) {
        debugPrint('LoginScreen: Widget disposed after saving credentials, skipping navigation');
        return;
      }

      // Không cần kiểm tra 2FA ở đây nữa vì authStateChanges listener trong AuthProvider
      // sẽ tự động kiểm tra và điều hướng đến màn hình 2FA nếu cần
      // Nếu không có 2FA, authStateChanges sẽ tự động load user và chuyển đến MainScreen
      // Nếu có 2FA, authStateChanges sẽ set pending2FAVerification và main.dart sẽ hiển thị TwoFactorVerifyScreen

      // Không cần navigate nữa vì authStateChanges listener sẽ xử lý điều hướng
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Đăng nhập thất bại. Vui lòng thử lại.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1024;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // Left Side: Login Form
          Expanded(
            flex: isDesktop ? 1 : 1,
            child: Container(
              color: Colors.white,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: constraints.maxWidth > 600 ? 64 : 32, vertical: 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header/Logo
                            Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                                  child: Center(
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Synap',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 80),

                            // Form Content
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Chào mừng trở lại',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Đăng nhập để tiếp tục sử dụng Synap.',
                                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                                ),
                                const SizedBox(height: 32),

                                // Form
                                Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Email field
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Email',
                                            style: TextStyle(
                                              color: Colors.grey[800],
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Focus(
                                            onFocusChange: (hasFocus) {
                                              setState(() {
                                                _isEmailFocused = hasFocus;
                                              });
                                            },
                                            child: TextFormField(
                                              controller: _emailController,
                                              keyboardType: TextInputType.emailAddress,
                                              style: const TextStyle(color: Colors.black),
                                              decoration: InputDecoration(
                                                hintText: 'tenban@vidu.com',
                                                hintStyle: TextStyle(color: Colors.grey[500]),
                                                filled: true,
                                                fillColor: Colors.grey[100],
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                                suffixIcon: _isEmailFocused
                                                    ? Icon(Icons.mail_outline, size: 16, color: Colors.grey[600])
                                                    : null,
                                              ),
                                              validator: (value) {
                                                if (value == null || value.isEmpty) {
                                                  return 'Vui lòng nhập email';
                                                }
                                                if (!value.contains('@')) {
                                                  return 'Email không hợp lệ';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Password field
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Mật khẩu',
                                                style: TextStyle(
                                                  color: Colors.grey[800],
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                                                  );
                                                },
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                                child: Text(
                                                  'Quên mật khẩu?',
                                                  style: TextStyle(color: AppColors.primaryDark, fontSize: 12),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Focus(
                                            onFocusChange: (hasFocus) {
                                              setState(() {
                                                _isPasswordFocused = hasFocus;
                                              });
                                            },
                                            child: TextFormField(
                                              controller: _passwordController,
                                              focusNode: _passwordFocusNode,
                                              obscureText: _obscurePassword,
                                              style: const TextStyle(color: Colors.black),
                                              decoration: InputDecoration(
                                                hintText: '••••••••',
                                                hintStyle: TextStyle(color: Colors.grey[500]),
                                                filled: true,
                                                fillColor: Colors.grey[100],
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                                suffixIcon: _isPasswordFocused
                                                    ? Icon(Icons.lock_outline, size: 16, color: Colors.grey[600])
                                                    : IconButton(
                                                        icon: Icon(
                                                          _obscurePassword
                                                              ? Icons.visibility_outlined
                                                              : Icons.visibility_off_outlined,
                                                          size: 16,
                                                          color: Colors.grey[600],
                                                        ),
                                                        onPressed: () {
                                                          setState(() {
                                                            _obscurePassword = !_obscurePassword;
                                                          });
                                                        },
                                                      ),
                                              ),
                                              validator: (value) {
                                                if (value == null || value.isEmpty) {
                                                  return 'Vui lòng nhập mật khẩu';
                                                }
                                                if (value.length < 6) {
                                                  return 'Mật khẩu phải ít nhất 6 ký tự';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Keep me logged in checkbox
                                      Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _keepLoggedIn = !_keepLoggedIn;
                                              });
                                            },
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: _keepLoggedIn ? AppColors.primary : Colors.grey[400]!,
                                                ),
                                                borderRadius: BorderRadius.circular(4),
                                                color: _keepLoggedIn ? AppColors.primary : Colors.white,
                                              ),
                                              child: _keepLoggedIn
                                                  ? const Icon(Icons.check, size: 12, color: Colors.black, weight: 3)
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _keepLoggedIn = !_keepLoggedIn;
                                              });
                                            },
                                            child: Text(
                                              'Ghi nhớ đăng nhập',
                                              style: TextStyle(color: Colors.grey[800], fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Biometric login button (nếu có)
                                      if (!kIsWeb && _isBiometricAvailable && _isBiometricEnabled) ...[
                                        OutlinedButton.icon(
                                          onPressed: _handleBiometricLogin,
                                          icon: const Icon(Icons.fingerprint),
                                          label: const Text('Đăng nhập bằng vân tay/Face ID'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(child: Divider(color: Colors.grey[300])),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16),
                                              child: Text(
                                                'HOẶC',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Expanded(child: Divider(color: Colors.grey[300])),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                      ],

                                      const SizedBox(height: 8),

                                      // Sign in button
                                      Consumer<AuthProvider>(
                                        builder: (context, authProvider, _) {
                                          return ElevatedButton(
                                            onPressed: authProvider.isLoading ? null : _handleLogin,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.primary,
                                              foregroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              elevation: 0,
                                            ),
                                            child: authProvider.isLoading
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.black,
                                                    ),
                                                  )
                                                : Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      const Text(
                                                        'Đăng nhập',
                                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Icon(
                                                        Icons.arrow_forward,
                                                        size: 16,
                                                        color: Colors.black.withOpacity(0.5),
                                                      ),
                                                    ],
                                                  ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 40),

                            // Footer
                            Padding(
                              padding: const EdgeInsets.only(top: 32),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('© 2024 Synap Inc.', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () {},
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'Quyền riêng tư',
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      TextButton(
                                        onPressed: () {},
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'Điều khoản',
                                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Register link
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Center(
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.of(
                                      context,
                                    ).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
                                  },
                                  child: Text(
                                    'Chưa có tài khoản? Đăng ký ngay',
                                    style: TextStyle(
                                      color: AppColors.primaryDark,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Right Side: Visual/Branding (only on desktop)
          if (isDesktop) Expanded(flex: 1, child: _RightSideVisual()),
        ],
      ),
    );
  }
}

class _RightSideVisual extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          // Background gradients
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.5,
                  colors: [AppColors.primary.withOpacity(0.10), Colors.white, Colors.white],
                ),
              ),
            ),
          ),

          // Grid pattern overlay
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),

          // Mock UI Card
          Center(
            child: Transform.rotate(
              angle: -0.035, // -2 degrees
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(0),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[800]!),
                  boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Window controls
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        border: Border(bottom: BorderSide(color: Colors.grey[800]!)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.red.withOpacity(0.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.yellow.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.yellow.withOpacity(0.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.green.withOpacity(0.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Mock content
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Colors.white.withOpacity(0.1), Colors.transparent],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                                ),
                                child: Icon(Icons.smartphone, color: Colors.grey[500], size: 24),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 96,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: 64,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Mock code
                          _CodeLine('class', 'SynapApp', 'extends', 'StatelessWidget', '{'),
                          _CodeLine('', '@override', '', '', ''),
                          _CodeLine('Widget', 'build', '(BuildContext context)', '{', '', indent: 1),
                          _CodeLine('return', 'MaterialApp', '(', '', '', indent: 2),
                          _CodeLine('title:', "'Synap'", ',', '', '', indent: 3, isString: true),
                          _CodeLine('theme:', 'ThemeData', '.dark(),', '', '', indent: 3),
                          _CodeLine('home:', 'Dashboard', '(),', '', '', indent: 3),
                          _CodeLine('', '', ');', '', '', indent: 2),
                          _CodeLine('', '', '}', '', '', indent: 1),
                          _CodeLine('', '', '}', '', '', indent: 0),
                          const SizedBox(height: 16),
                          Divider(color: Colors.grey[800], height: 1),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[700],
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey[900]!, width: 2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[600],
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey[900]!, width: 2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[500],
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey[900]!, width: 2),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '+3',
                                        style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                width: 64,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.grey[800],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Floating decorations
          Positioned(
            bottom: 80,
            right: 80,
            child: Container(
              width: 256,
              height: 256,
              decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
            ),
          ),
          Positioned(
            top: 80,
            left: 80,
            child: Container(
              width: 384,
              height: 384,
              decoration: BoxDecoration(color: Colors.purple.withOpacity(0.05), shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  final String keyword1;
  final String keyword2;
  final String keyword3;
  final String keyword4;
  final String keyword5;
  final int indent;
  final bool isString;

  const _CodeLine(
    this.keyword1,
    this.keyword2,
    this.keyword3,
    this.keyword4,
    this.keyword5, {
    this.indent = 0,
    this.isString = false,
  });

  @override
  Widget build(BuildContext context) {
    Color getColor(String text) {
      if (text.isEmpty) return Colors.transparent;
      if (text == 'class' || text == 'extends' || text == 'return') {
        return const Color(0xFFEC4899); // pink
      }
      if (text == 'Widget' || text == 'MaterialApp' || text == 'ThemeData' || text == 'Dashboard') {
        return const Color(0xFF60A5FA); // blue
      }
      if (text == 'StatelessWidget' || text == 'BuildContext') {
        return const Color(0xFFFCD34D); // yellow
      }
      if (text == '@override') {
        return const Color(0xFFA78BFA); // purple
      }
      if (text == 'title:' || text == 'theme:' || text == 'home:') {
        return const Color(0xFF34D399); // green
      }
      if (isString && text.contains("'")) {
        return const Color(0xFFFB923C); // orange
      }
      return Colors.grey[400]!;
    }

    return Padding(
      padding: EdgeInsets.only(left: indent * 16.0, bottom: 4),
      child: Row(
        children: [
          if (keyword1.isNotEmpty)
            Text(
              keyword1,
              style: TextStyle(color: getColor(keyword1), fontSize: 12, fontFamily: 'monospace'),
            ),
          if (keyword1.isNotEmpty && keyword2.isNotEmpty) const SizedBox(width: 4),
          if (keyword2.isNotEmpty)
            Text(
              keyword2,
              style: TextStyle(color: getColor(keyword2), fontSize: 12, fontFamily: 'monospace'),
            ),
          if (keyword2.isNotEmpty && keyword3.isNotEmpty) const SizedBox(width: 4),
          if (keyword3.isNotEmpty)
            Text(
              keyword3,
              style: TextStyle(color: getColor(keyword3), fontSize: 12, fontFamily: 'monospace'),
            ),
          if (keyword3.isNotEmpty && keyword4.isNotEmpty) const SizedBox(width: 4),
          if (keyword4.isNotEmpty)
            Text(
              keyword4,
              style: TextStyle(color: getColor(keyword4), fontSize: 12, fontFamily: 'monospace'),
            ),
          if (keyword4.isNotEmpty && keyword5.isNotEmpty) const SizedBox(width: 4),
          if (keyword5.isNotEmpty)
            Text(
              keyword5,
              style: TextStyle(color: getColor(keyword5), fontSize: 12, fontFamily: 'monospace'),
            ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[300]!.withOpacity(0.6)
      ..strokeWidth = 1;

    const gridSize = 32.0;

    // Draw vertical lines
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
