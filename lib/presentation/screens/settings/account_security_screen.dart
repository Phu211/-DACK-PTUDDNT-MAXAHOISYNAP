import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/services/session_service.dart';
import '../../../data/services/login_history_service.dart';
import '../../../data/services/suspicious_activity_service.dart';
import '../../providers/auth_provider.dart';
import 'change_password_screen.dart';
import 'two_factor_auth_screen.dart';
import 'biometric_auth_screen.dart';
import 'recovery_codes_screen.dart';
import 'ip_whitelisting_screen.dart';
import 'security_questions_screen.dart';

/// Màn hình quản lý bảo mật tài khoản:
/// - Xem danh sách thiết bị đăng nhập
/// - Đăng xuất từ xa
/// - Đổi mật khẩu
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final SessionService _sessionService = SessionService();
  final LoginHistoryService _loginHistoryService = LoginHistoryService();
  final SuspiciousActivityService _suspiciousActivityService =
      SuspiciousActivityService();
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _loginHistory = [];
  List<Map<String, dynamic>> _suspiciousActivities = [];
  bool _isLoading = true;
  bool _isLoadingHistory = false;
  bool _isLoadingActivities = false;
  String? _currentDeviceId;
  int _selectedTab =
      0; // 0: Sessions, 1: Login History, 2: Suspicious Activities

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadLoginHistory();
    _loadSuspiciousActivities();
    _getCurrentDeviceId();
  }

  Future<void> _loadSuspiciousActivities() async {
    setState(() {
      _isLoadingActivities = true;
    });

    try {
      final activities = await _suspiciousActivityService
          .getSuspiciousActivities(limit: 20);
      if (mounted) {
        setState(() {
          _suspiciousActivities = activities;
          _isLoadingActivities = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingActivities = false;
        });
      }
    }
  }

  Future<void> _loadLoginHistory() async {
    setState(() {
      _isLoadingHistory = true;
    });

    try {
      final history = await _loginHistoryService.getLoginHistory(limit: 20);
      if (mounted) {
        setState(() {
          _loginHistory = history;
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  Future<void> _getCurrentDeviceId() async {
    final deviceInfo = await _sessionService.getDeviceInfo();
    if (mounted) {
      setState(() {
        _currentDeviceId = deviceInfo['deviceId'];
      });
    }
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final sessions = await _sessionService.getSessions();
      if (mounted) {
        setState(() {
          _sessions = sessions;
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
            content: Text('Lỗi tải danh sách thiết bị: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _revokeSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất thiết bị'),
        content: const Text(
          'Bạn có chắc chắn muốn đăng xuất khỏi thiết bị này?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _sessionService.revokeSession(sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã đăng xuất khỏi thiết bị'),
            backgroundColor: Colors.green,
          ),
        );
        _loadSessions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _revokeAllSessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất khỏi tất cả thiết bị'),
        content: const Text(
          'Bạn sẽ bị đăng xuất khỏi tất cả thiết bị, bao gồm cả thiết bị hiện tại. '
          'Bạn có chắc chắn?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Đăng xuất tất cả'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _sessionService.revokeAllSessions();
      final authProvider = context.read<AuthProvider>();
      // Chỉ cần gọi signOut, main.dart sẽ tự động navigate đến LoginScreen
      await authProvider.signOut();
      // Không cần manually navigate vì main.dart đã xử lý qua Consumer<AuthProvider>
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Chưa xác định';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays > 0) {
        return '${diff.inDays} ngày trước';
      } else if (diff.inHours > 0) {
        return '${diff.inHours} giờ trước';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes} phút trước';
      } else {
        return 'Vừa xong';
      }
    } catch (_) {
      return dateStr;
    }
  }

  IconData _getPlatformIcon(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'android':
        return Icons.android;
      case 'ios':
        return Icons.phone_iphone;
      default:
        return Icons.devices;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bảo mật tài khoản')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Tab selector
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabButton(
                          'Thiết bị',
                          0,
                          _selectedTab == 0,
                        ),
                      ),
                      Expanded(
                        child: _buildTabButton('Lịch sử', 1, _selectedTab == 1),
                      ),
                      Expanded(
                        child: _buildTabButton(
                          'Cảnh báo',
                          2,
                          _selectedTab == 2,
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: _selectedTab == 0
                      ? _buildSessionsTab()
                      : _selectedTab == 1
                      ? _buildLoginHistoryTab()
                      : _buildSuspiciousActivitiesTab(),
                ),
              ],
            ),
    );
  }

  Widget _buildTabButton(String label, int index, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? Colors.black : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Section: Mật khẩu
        const Text(
          'Mật khẩu',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Đổi mật khẩu'),
            subtitle: const Text('Cập nhật mật khẩu để bảo vệ tài khoản'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // Section: Xác thực bổ sung
        const Text(
          'Xác thực bổ sung',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user),
            title: const Text('Two-Factor Authentication (2FA)'),
            subtitle: const Text('Bảo vệ tài khoản bằng mã xác thực'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TwoFactorAuthScreen()),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Đăng nhập bằng sinh trắc học'),
            subtitle: const Text('Vân tay hoặc Face ID'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BiometricAuthScreen()),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.vpn_key),
            title: const Text('Recovery Codes'),
            subtitle: const Text('Mã khôi phục tài khoản'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecoveryCodesScreen()),
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // Section: Bảo mật nâng cao
        const Text(
          'Bảo mật nâng cao',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.computer),
            title: const Text('IP Whitelisting'),
            subtitle: const Text('Chỉ cho phép đăng nhập từ IP đã đăng ký'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IPWhitelistingScreen()),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Security Questions'),
            subtitle: const Text('Câu hỏi bảo mật để khôi phục tài khoản'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SecurityQuestionsScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // Section: Thiết bị đăng nhập
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Thiết bị đăng nhập',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_sessions.length > 1)
              TextButton(
                onPressed: _revokeAllSessions,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Đăng xuất tất cả'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_sessions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Chưa có thiết bị nào',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          )
        else
          ..._sessions.map((session) {
            final isCurrentDevice = session['deviceId'] == _currentDeviceId;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  _getPlatformIcon(session['platform']),
                  color: isCurrentDevice ? Colors.blue : Colors.grey,
                ),
                title: Text(
                  session['model'] ?? 'Thiết bị không xác định',
                  style: TextStyle(
                    fontWeight: isCurrentDevice
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      session['platform'] ?? 'Không xác định',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hoạt động lần cuối: ${_formatDate(session['lastActiveAt'])}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (isCurrentDevice) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Thiết bị này',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: isCurrentDevice
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.logout, color: Colors.red),
                        onPressed: () =>
                            _revokeSession(session['id'] as String),
                      ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildLoginHistoryTab() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Lịch sử đăng nhập',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_loginHistory.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Chưa có lịch sử đăng nhập',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          )
        else
          ..._loginHistory.map((entry) {
            final isNewDevice = entry['isNewDevice'] == true;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  _getPlatformIcon(entry['platform']),
                  color: isNewDevice ? Colors.orange : Colors.grey,
                ),
                title: Text(
                  entry['model'] ?? 'Thiết bị không xác định',
                  style: TextStyle(
                    fontWeight: isNewDevice
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      entry['platform'] ?? 'Không xác định',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Đăng nhập: ${_formatDate(entry['loginTime'])}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (isNewDevice) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Thiết bị mới',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSuspiciousActivitiesTab() {
    if (_isLoadingActivities) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Hoạt động đáng ngờ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_suspiciousActivities.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Không có hoạt động đáng ngờ nào',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          )
        else
          ..._suspiciousActivities.map((activity) {
            final isResolved = activity['isResolved'] == true;
            final activityType =
                activity['activityType'] as String? ?? 'unknown';
            final details = activity['details'] as String? ?? '';

            IconData icon;
            Color color;
            String title;

            switch (activityType) {
              case 'newDevice':
                icon = Icons.devices;
                color = Colors.orange;
                title = 'Thiết bị mới';
                break;
              case 'multipleFailedLogins':
                icon = Icons.warning;
                color = Colors.red;
                title = 'Nhiều lần đăng nhập sai';
                break;
              case 'passwordChanged':
                icon = Icons.lock;
                color = Colors.blue;
                title = 'Đổi mật khẩu';
                break;
              case 'emailChanged':
                icon = Icons.email;
                color = Colors.purple;
                title = 'Đổi email';
                break;
              default:
                icon = Icons.info;
                color = Colors.grey;
                title = 'Hoạt động khác';
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(icon, color: isResolved ? Colors.grey : color),
                title: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isResolved
                        ? FontWeight.normal
                        : FontWeight.bold,
                    color: isResolved ? Colors.grey : Colors.black,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(details, style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      'Phát hiện: ${_formatDate(activity['detectedAt'])}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (isResolved) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Đã xử lý',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: isResolved
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () async {
                          await _suspiciousActivityService
                              .markActivityAsResolved(activity['id'] as String);
                          _loadSuspiciousActivities();
                        },
                      ),
              ),
            );
          }),
      ],
    );
  }
}
