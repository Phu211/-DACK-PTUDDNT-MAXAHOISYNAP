import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../data/services/two_factor_auth_service.dart';

/// Màn hình quản lý Two-Factor Authentication (2FA)
class TwoFactorAuthScreen extends StatefulWidget {
  const TwoFactorAuthScreen({super.key});

  @override
  State<TwoFactorAuthScreen> createState() => _TwoFactorAuthScreenState();
}

class _TwoFactorAuthScreenState extends State<TwoFactorAuthScreen> {
  final TwoFactorAuthService _twoFactorService = TwoFactorAuthService();
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  bool _is2FAEnabled = false;
  bool _isVerifying = false;
  String? _secretKey;
  String? _recoveryCodes;
  bool _showSecret = false;

  @override
  void initState() {
    super.initState();
    _check2FAStatus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _check2FAStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final isEnabled = await _twoFactorService.is2FAEnabled(user.uid);
      if (mounted) {
        setState(() {
          _is2FAEnabled = isEnabled;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi kiểm tra trạng thái 2FA: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _enable2FA() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không tìm thấy thông tin người dùng'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _twoFactorService.enable2FA(user.uid, user.email!);

      if (mounted) {
        setState(() {
          _secretKey = result['secret'];
          _recoveryCodes = result['recoveryCodes'];
          _isLoading = false;
        });

        // Hiển thị dialog với QR code và recovery codes
        _showSetupDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi bật 2FA: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _verifyAndEnable() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập mã xác thực 6 số'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Verify code với allowPendingSetup = true (vì đang trong quá trình setup)
      final isValid = await _twoFactorService.verifyTOTPCode(
        user.uid, 
        code,
        allowPendingSetup: true, // Cho phép verify khi đang setup
      );

      if (mounted) {
        setState(() {
          _isVerifying = false;
        });

        if (isValid) {
          // Xác nhận và bật 2FA
          await _twoFactorService.confirm2FASetup(user.uid);
          
          Navigator.pop(context); // Đóng dialog
          _codeController.clear();
          _secretKey = null; // Clear secret sau khi đã enable
          _recoveryCodes = null;
          _check2FAStatus();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã bật 2FA thành công'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // Hiển thị dialog với hướng dẫn chi tiết
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Mã xác thực không đúng'),
              content: const SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mã xác thực không khớp. Có thể do:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('1. Secret key trong Google Authenticator không khớp với secret key mới'),
                    SizedBox(height: 4),
                    Text('2. Bạn đã quét QR code cũ hoặc nhập secret key cũ'),
                    SizedBox(height: 16),
                    Text(
                      'Giải pháp:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('1. Xóa entry cũ trong Google Authenticator (nếu có)'),
                    SizedBox(height: 4),
                    Text('2. Quét lại QR code mới hoặc nhập secret key mới'),
                    SizedBox(height: 4),
                    Text('3. Nhập mã 6 số mới từ Google Authenticator'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Đã hiểu'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xác thực: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disable2FA() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tắt 2FA'),
        content: const Text(
          'Bạn có chắc chắn muốn tắt Two-Factor Authentication? '
          'Tài khoản của bạn sẽ kém an toàn hơn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Tắt'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _twoFactorService.disable2FA(user.uid);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _is2FAEnabled = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tắt 2FA'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tắt 2FA: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSetupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Thiết lập 2FA'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[300]!),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'QUAN TRỌNG: Nếu bạn đã có entry cũ trong ứng dụng xác thực, vui lòng XÓA entry cũ trước khi thêm mới!',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '1. Quét QR code bằng ứng dụng xác thực (Google Authenticator, Authy, etc.)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[300]!),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'KHUYẾN NGHỊ: Sử dụng quét QR code thay vì nhập secret key thủ công để đảm bảo secret key được nhận đúng.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user?.email == null || _secretKey == null) {
                        return const SizedBox.shrink();
                      }
                      final issuer = 'Synap';
                      final accountName = user!.email!.split('@').first;
                      // Tạo otpauth URL từ secret key
                      final otpAuthUrl =
                          'otpauth://totp/$issuer:$accountName?secret=$_secretKey&issuer=$issuer';
                      // Debug: Log secret key và QR URL
                      debugPrint('2FA Setup: Secret key: $_secretKey');
                      debugPrint('2FA Setup: QR URL: $otpAuthUrl');
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: QrImageView(
                          data: otpAuthUrl,
                          version: QrVersions.auto,
                          size: 200.0,
                          backgroundColor: Colors.white,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '2. Hoặc nhập mã secret thủ công (KHÔNG KHUYẾN NGHỊ):',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'CẢNH BÁO: Nhập secret key thủ công có thể không hoạt động đúng. Vui lòng quét QR code để đảm bảo secret key được nhận đúng.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '2. Hoặc nhập mã secret thủ công:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      setDialogState(() {
                        _showSecret = !_showSecret;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _showSecret ? (_secretKey?.trim().toUpperCase() ?? '') : '••••••••••••',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(
                            _showSecret ? Icons.visibility_off : Icons.visibility,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '3. Lưu Recovery Codes (chỉ hiển thị 1 lần):',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: SelectableText(
                      _recoveryCodes ?? '',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '4. Nhập mã 6 số từ ứng dụng để xác thực:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      hintText: '000000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  // Xóa pending setup nếu user hủy
                  try {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      await _twoFactorService.disable2FA(user.uid);
                    }
                  } catch (e) {
                    debugPrint('Error cleaning up pending 2FA setup: $e');
                  }
                  
                  Navigator.pop(ctx);
                  _codeController.clear();
                  // Xóa secret và recovery codes nếu user hủy
                  setState(() {
                    _secretKey = null;
                    _recoveryCodes = null;
                  });
                  // Refresh status
                  _check2FAStatus();
                },
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: _isVerifying ? null : _verifyAndEnable,
                child: _isVerifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Xác thực'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-Factor Authentication')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.security,
                              color: _is2FAEnabled ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _is2FAEnabled ? '2FA đã bật' : '2FA chưa bật',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _is2FAEnabled
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _is2FAEnabled
                              ? 'Tài khoản của bạn được bảo vệ bằng Two-Factor Authentication. '
                                    'Bạn sẽ cần mã từ ứng dụng xác thực khi đăng nhập.'
                              : 'Bật 2FA để tăng cường bảo mật cho tài khoản. '
                                    'Bạn sẽ cần mã từ ứng dụng xác thực khi đăng nhập.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_is2FAEnabled)
                  ElevatedButton.icon(
                    onPressed: _disable2FA,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Tắt 2FA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _enable2FA,
                    icon: const Icon(Icons.lock),
                    label: const Text('Bật 2FA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hướng dẫn',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '1. Tải ứng dụng xác thực như Google Authenticator hoặc Authy\n'
                          '2. Quét QR code hoặc nhập mã secret\n'
                          '3. Lưu Recovery Codes ở nơi an toàn\n'
                          '4. Nhập mã 6 số để xác thực và hoàn tất',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
