import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../../data/services/ip_whitelisting_service.dart';

/// Màn hình quản lý IP Whitelisting
class IPWhitelistingScreen extends StatefulWidget {
  const IPWhitelistingScreen({super.key});

  @override
  State<IPWhitelistingScreen> createState() => _IPWhitelistingScreenState();
}

class _IPWhitelistingScreenState extends State<IPWhitelistingScreen> {
  final IPWhitelistingService _ipWhitelistingService = IPWhitelistingService();
  final TextEditingController _ipController = TextEditingController();
  bool _isLoading = false;
  bool _isEnabled = false;
  List<String> _whitelistedIPs = [];
  String? _currentIP;

  @override
  void initState() {
    super.initState();
    _loadIPWhitelistStatus();
    _getCurrentIP();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentIP() async {
    try {
      final response = await http.get(Uri.parse('https://api.ipify.org'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _currentIP = response.body.trim();
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting current IP: $e');
    }
  }

  Future<void> _loadIPWhitelistStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final enabled = await _ipWhitelistingService.isIPWhitelistingEnabled(
        user.uid,
      );
      final ips = await _ipWhitelistingService.getWhitelistedIPs(user.uid);

      if (mounted) {
        setState(() {
          _isEnabled = enabled;
          // Extract IP addresses from the list of maps
          _whitelistedIPs = ips
              .map((ip) => ip['ipAddress'] as String? ?? '')
              .where((ip) => ip.isNotEmpty)
              .toList();
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

  Future<void> _toggleIPWhitelisting(bool value) async {
    if (value && _whitelistedIPs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vui lòng thêm ít nhất 1 IP vào whitelist trước khi bật',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _ipWhitelistingService.setIPWhitelistingEnabled(user.uid, value);

      if (mounted) {
        setState(() {
          _isEnabled = value;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value ? 'Đã bật IP Whitelisting' : 'Đã tắt IP Whitelisting',
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

  Future<void> _addCurrentIP() async {
    if (_currentIP == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể lấy IP hiện tại'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await _addIP(_currentIP!);
  }

  Future<void> _addIP(String ip) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _ipWhitelistingService.addIPToWhitelist(user.uid, ip);

      if (mounted) {
        _ipController.clear();
        _loadIPWhitelistStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã thêm IP vào whitelist'),
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
            content: Text('Lỗi thêm IP: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeIP(String ip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa IP'),
        content: Text('Bạn có chắc chắn muốn xóa IP $ip khỏi whitelist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
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

      await _ipWhitelistingService.removeIPFromWhitelist(user.uid, ip);

      if (mounted) {
        _loadIPWhitelistStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa IP khỏi whitelist'),
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
            content: Text('Lỗi xóa IP: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _isValidIP(String ip) {
    final ipRegex = RegExp(
      r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
    );
    return ipRegex.hasMatch(ip);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IP Whitelisting')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Colors.orange[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Cảnh báo',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Khi bật IP Whitelisting, bạn chỉ có thể đăng nhập từ các IP đã được thêm vào danh sách. '
                          'Đảm bảo bạn đã thêm IP hiện tại trước khi bật tính năng này.',
                          style: TextStyle(color: Colors.orange[900]),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SwitchListTile(
                  title: const Text('Bật IP Whitelisting'),
                  subtitle: const Text(
                    'Chỉ cho phép đăng nhập từ các IP đã đăng ký',
                  ),
                  value: _isEnabled,
                  onChanged: _toggleIPWhitelisting,
                  secondary: Icon(
                    _isEnabled ? Icons.security : Icons.security_outlined,
                    color: _isEnabled ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(height: 24),
                if (_currentIP != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'IP hiện tại',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _currentIP!,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _addCurrentIP,
                                icon: const Icon(Icons.add),
                                label: const Text('Thêm'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Thêm IP mới',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          hintText: '192.168.1.1',
                          border: OutlineInputBorder(),
                          labelText: 'Địa chỉ IP',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final ip = _ipController.text.trim();
                        if (ip.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Vui lòng nhập địa chỉ IP'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        if (!_isValidIP(ip)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Địa chỉ IP không hợp lệ'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        _addIP(ip);
                      },
                      child: const Text('Thêm'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Danh sách IP được phép',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_whitelistedIPs.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'Chưa có IP nào trong whitelist',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ),
                  )
                else
                  ..._whitelistedIPs.map((ip) {
                    final isCurrent = ip == _currentIP;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          isCurrent ? Icons.location_on : Icons.computer,
                          color: isCurrent ? Colors.blue : Colors.grey,
                        ),
                        title: Text(
                          ip,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: isCurrent
                            ? const Text(
                                'IP hiện tại',
                                style: TextStyle(color: Colors.blue),
                              )
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeIP(ip),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
