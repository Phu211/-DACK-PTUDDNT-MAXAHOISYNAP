import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/biometric_auth_service.dart';

/// Màn hình quản lý Biometric Authentication
class BiometricAuthScreen extends StatefulWidget {
  const BiometricAuthScreen({super.key});

  @override
  State<BiometricAuthScreen> createState() => _BiometricAuthScreenState();
}

class _BiometricAuthScreenState extends State<BiometricAuthScreen> {
  final BiometricAuthService _biometricService = BiometricAuthService();
  bool _isLoading = false;
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  List<String> _availableBiometrics = [];

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final available = await _biometricService.isBiometricAvailable();
      final biometrics = await _biometricService.getAvailableBiometrics();
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      final enabled = prefs.getBool('biometric_enabled_${user?.uid}') ?? false;

      if (mounted) {
        setState(() {
          _isBiometricAvailable = available;
          _availableBiometrics = biometrics;
          _isBiometricEnabled = enabled;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Test biometric authentication
      final authenticated = await _biometricService.authenticate(
        reason: 'Xác thực để bật đăng nhập bằng vân tay/Face ID',
      );

      if (!authenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Xác thực không thành công'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final user = FirebaseAuth.instance.currentUser;
      await prefs.setBool('biometric_enabled_${user?.uid}', value);

      // Nếu bật biometric và user đã đăng nhập, lưu email ngay
      // (Password sẽ được lưu sau lần đăng nhập tiếp theo)
      if (value && user?.email != null) {
        await _biometricService.saveLoginEmail(user!.email!);
      }

      // Nếu tắt biometric, xóa email đã lưu
      if (!value) {
        await _biometricService.clearSavedLoginInfo();
      }

      if (mounted) {
        setState(() {
          _isBiometricEnabled = value;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Đã bật đăng nhập bằng sinh trắc học. Email sẽ được lưu sau lần đăng nhập tiếp theo.'
                  : 'Đã tắt đăng nhập bằng sinh trắc học',
            ),
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
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getBiometricTypeName(String type) {
    switch (type.toLowerCase()) {
      case 'fingerprint':
        return 'Vân tay';
      case 'face':
        return 'Face ID';
      case 'strong':
        return 'Xác thực mạnh';
      case 'weak':
        return 'Xác thực yếu';
      default:
        return type;
    }
  }

  IconData _getBiometricIcon(String type) {
    switch (type.toLowerCase()) {
      case 'fingerprint':
        return Icons.fingerprint;
      case 'face':
        return Icons.face;
      default:
        return Icons.security;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập bằng sinh trắc học')),
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
                              _isBiometricAvailable
                                  ? Icons.fingerprint
                                  : Icons.fingerprint_outlined,
                              color: _isBiometricAvailable
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isBiometricAvailable
                                  ? 'Hỗ trợ sinh trắc học'
                                  : 'Không hỗ trợ',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _isBiometricAvailable
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isBiometricAvailable
                              ? 'Thiết bị của bạn hỗ trợ đăng nhập bằng vân tay hoặc Face ID.'
                              : 'Thiết bị của bạn không hỗ trợ đăng nhập bằng sinh trắc học.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isBiometricAvailable) ...[
                  const SizedBox(height: 24),
                  if (_availableBiometrics.isNotEmpty) ...[
                    const Text(
                      'Loại xác thực khả dụng:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._availableBiometrics.map(
                      (type) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(_getBiometricIcon(type)),
                          title: Text(_getBiometricTypeName(type)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  SwitchListTile(
                    title: const Text('Đăng nhập bằng sinh trắc học'),
                    subtitle: const Text(
                      'Sử dụng vân tay hoặc Face ID để đăng nhập nhanh',
                    ),
                    value: _isBiometricEnabled,
                    onChanged: _toggleBiometric,
                    secondary: Icon(
                      _isBiometricEnabled
                          ? Icons.fingerprint
                          : Icons.fingerprint_outlined,
                      color: _isBiometricEnabled ? Colors.green : Colors.grey,
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
                            'Lưu ý',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• Đăng nhập bằng sinh trắc học chỉ hoạt động trên thiết bị này\n'
                            '• Bạn vẫn cần nhập mật khẩu khi đăng nhập trên thiết bị khác\n'
                            '• Đảm bảo thiết bị của bạn có khóa màn hình',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
