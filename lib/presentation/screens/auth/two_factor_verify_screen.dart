import 'package:flutter/material.dart';
import '../../../data/services/two_factor_auth_service.dart';
import '../../../data/services/recovery_codes_service.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';

/// Màn hình xác thực 2FA sau khi đăng nhập
class TwoFactorVerifyScreen extends StatefulWidget {
  final String userId;
  final String email;

  const TwoFactorVerifyScreen({
    super.key,
    required this.userId,
    required this.email,
  });

  @override
  State<TwoFactorVerifyScreen> createState() => _TwoFactorVerifyScreenState();
}

class _TwoFactorVerifyScreenState extends State<TwoFactorVerifyScreen> {
  final TwoFactorAuthService _twoFactorService = TwoFactorAuthService();
  final RecoveryCodesService _recoveryCodesService = RecoveryCodesService();
  final TextEditingController _codeController = TextEditingController();
  bool _isVerifying = false;
  String? _errorMessage;
  bool _showRecoveryCodeInput = false;
  final TextEditingController _recoveryCodeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _recoveryCodeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length != 6) {
      setState(() {
        _errorMessage = 'Vui lòng nhập mã 6 số';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final isValid = await _twoFactorService.verifyTOTPCode(
        widget.userId,
        code,
      );

      if (mounted) {
        if (isValid) {
          // Xác thực thành công, tiếp tục đăng nhập
          final authProvider = context.read<AuthProvider>();
          await authProvider.complete2FAVerification();
          // Không cần navigate, main.dart sẽ tự động chuyển đến MainScreen
        } else {
          setState(() {
            _isVerifying = false;
            _errorMessage = 'Mã xác thực không đúng. Vui lòng thử lại.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMessage = 'Lỗi xác thực: $e';
        });
      }
    }
  }

  Future<void> _verifyRecoveryCode() async {
    final code = _recoveryCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập mã khôi phục';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final isValid = await _recoveryCodesService.verifyRecoveryCode(
        widget.userId,
        code,
      );

      if (mounted) {
        if (isValid) {
          // Xác thực thành công, tiếp tục đăng nhập
          final authProvider = context.read<AuthProvider>();
          await authProvider.complete2FAVerification();
          // Không cần navigate, main.dart sẽ tự động chuyển đến MainScreen
        } else {
          setState(() {
            _isVerifying = false;
            _errorMessage = 'Mã khôi phục không đúng. Vui lòng thử lại.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorMessage = 'Lỗi xác thực: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác thực 2 yếu tố'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.security,
                  size: 40,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Xác thực 2 yếu tố',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tài khoản của bạn đã bật xác thực 2 yếu tố.\n'
                'Vui lòng nhập mã 6 số từ ứng dụng xác thực (Google Authenticator, Authy, v.v.) để tiếp tục.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (!_showRecoveryCodeInput) ...[
                // Mã 6 số input với UI đẹp hơn
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 32,
                    letterSpacing: 12,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: '000000',
                    hintStyle: TextStyle(
                      fontSize: 32,
                      letterSpacing: 12,
                      color: Colors.grey[300],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    counterText: '', // Ẩn counter
                    contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  ),
                  onChanged: (value) {
                    // Xóa error message khi user bắt đầu nhập lại
                    if (_errorMessage != null && value.isNotEmpty) {
                      setState(() {
                        _errorMessage = null;
                      });
                    }
                    // Tự động verify khi nhập đủ 6 số
                    if (value.length == 6) {
                      _verifyCode();
                    }
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isVerifying ? null : _verifyCode,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Xác thực',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isVerifying ? null : () {
                    setState(() {
                      _showRecoveryCodeInput = true;
                      _errorMessage = null;
                    });
                  },
                  child: const Text(
                    'Sử dụng mã khôi phục',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ] else ...[
                // Recovery code input
                Text(
                  'Mã khôi phục',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _recoveryCodeController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Nhập mã khôi phục 8 ký tự',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  ),
                  onChanged: (value) {
                    // Xóa error message khi user bắt đầu nhập lại
                    if (_errorMessage != null && value.isNotEmpty) {
                      setState(() {
                        _errorMessage = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Mã khôi phục là mã 8 ký tự bạn đã lưu khi bật 2FA',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isVerifying ? null : _verifyRecoveryCode,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Xác thực',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isVerifying ? null : () {
                    setState(() {
                      _showRecoveryCodeInput = false;
                      _errorMessage = null;
                      _recoveryCodeController.clear();
                    });
                  },
                  child: const Text(
                    'Quay lại nhập mã 6 số',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextButton(
                onPressed: () async {
                  // Đăng xuất và quay lại màn hình đăng nhập
                  final authProvider = context.read<AuthProvider>();
                  await authProvider.signOut();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
                child: const Text('Đăng xuất'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

