import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../../providers/auth_provider.dart';
import '../../../data/services/translation_cache_service.dart';
import 'account_security_screen.dart';
import 'account_management_screen.dart';
import '../profile/blocked_users_screen.dart';
import 'hidden_content_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _autoplayKey = 'settings_autoplay_videos';
  static const _muteSoundKey = 'settings_mute_notification_sound';
  static const _dataSaverKey = 'settings_data_saver';
  static const _activityStatusKey = 'settings_show_activity_status';
  static const _readReceiptsKey = 'settings_read_receipts';
  static const _suggestFriendsKey = 'settings_suggest_friends';

  bool _loading = true;
  bool _autoplayVideos = true;
  bool _muteNotificationSound = false;
  bool _dataSaver = false;
  bool _showActivityStatus = true;
  bool _enableReadReceipts = true;
  bool _suggestFriends = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _autoplayVideos = prefs.getBool(_autoplayKey) ?? true;
        _muteNotificationSound = prefs.getBool(_muteSoundKey) ?? false;
        _dataSaver = prefs.getBool(_dataSaverKey) ?? false;
        _showActivityStatus = prefs.getBool(_activityStatusKey) ?? true;
        _enableReadReceipts = prefs.getBool(_readReceiptsKey) ?? true;
        _suggestFriends = prefs.getBool(_suggestFriendsKey) ?? true;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _updateBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    // Hiển thị dialog xác nhận
    final shouldClear = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa bộ nhớ tạm'),
        content: const Text(
          'Bạn có chắc chắn muốn xóa tất cả bộ nhớ tạm? '
          'Điều này sẽ xóa cache ảnh, video và dữ liệu dịch thuật. '
          'Lần tải tiếp theo có thể chậm hơn một chút.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (shouldClear != true || !mounted) return;

    // Hiển thị dialog loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Đang xóa bộ nhớ tạm...'),
          ],
        ),
      ),
    );

    try {
      // 1. Xóa Flutter image cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 2. Xóa cached_network_image cache
      try {
        await DefaultCacheManager().emptyCache();
      } catch (e) {
        debugPrint('Error clearing cached_network_image cache: $e');
      }

      // 3. Xóa translation cache
      try {
        final translationCacheService = TranslationCacheService();
        await translationCacheService.clearCache();
      } catch (e) {
        debugPrint('Error clearing translation cache: $e');
      }

      // 4. Xóa cache directory nếu có (cho mobile)
      try {
        if (!kIsWeb) {
          final cacheDir = await getTemporaryDirectory();
          if (await cacheDir.exists()) {
            await cacheDir.delete(recursive: true);
            await cacheDir.create();
          }
        }
      } catch (e) {
        debugPrint('Error clearing cache directory: $e');
      }

      // Đóng dialog loading
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Hiển thị thông báo thành công
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã xóa bộ nhớ tạm thành công. Lần tải ảnh/video tiếp theo có thể chậm hơn một chút.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Đóng dialog loading nếu có lỗi
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Hiển thị thông báo lỗi
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi xóa bộ nhớ tạm: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUser = auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: currentUser == null
          ? const Center(child: Text('Vui lòng đăng nhập'))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const ListTile(title: Text('Cài đặt chung'), dense: true),
                SwitchListTile(
                  secondary: const Icon(Icons.play_circle_fill),
                  title: const Text('Tự động phát video'),
                  subtitle: const Text('Tự động phát video khi cuộn news feed'),
                  value: _autoplayVideos,
                  onChanged: (value) {
                    setState(() => _autoplayVideos = value);
                    _updateBool(_autoplayKey, value);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_off),
                  title: const Text('Tắt âm thanh thông báo trong app'),
                  subtitle: const Text('Chỉ hiển thị thông báo, không phát âm'),
                  value: _muteNotificationSound,
                  onChanged: (value) {
                    setState(() => _muteNotificationSound = value);
                    _updateBool(_muteSoundKey, value);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.data_saver_off),
                  title: const Text('Chế độ tiết kiệm dữ liệu'),
                  subtitle: const Text(
                    'Giảm chất lượng ảnh/video để tiết kiệm dữ liệu di động',
                  ),
                  value: _dataSaver,
                  onChanged: (value) {
                    setState(() => _dataSaver = value);
                    _updateBool(_dataSaverKey, value);
                  },
                ),
                const Divider(),
                const ListTile(
                  title: Text('Quyền riêng tư & hoạt động'),
                  dense: true,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.circle),
                  title: const Text('Hiển thị trạng thái hoạt động'),
                  subtitle: const Text(
                    'Cho phép người khác thấy bạn đang online hoặc hoạt động lần cuối',
                  ),
                  value: _showActivityStatus,
                  onChanged: (value) {
                    setState(() => _showActivityStatus = value);
                    _updateBool(_activityStatusKey, value);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.done_all),
                  title: const Text('Hiện đã xem trong tin nhắn'),
                  subtitle: const Text(
                    'Nếu tắt, cả hai bên sẽ không thấy trạng thái "Đã xem"',
                  ),
                  value: _enableReadReceipts,
                  onChanged: (value) {
                    setState(() => _enableReadReceipts = value);
                    _updateBool(_readReceiptsKey, value);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.people_alt),
                  title: const Text('Gợi ý kết bạn'),
                  subtitle: const Text(
                    'Đề xuất kết bạn dựa trên bạn chung, tương tác, danh bạ...',
                  ),
                  value: _suggestFriends,
                  onChanged: (value) {
                    setState(() => _suggestFriends = value);
                    _updateBool(_suggestFriendsKey, value);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off),
                  title: const Text('Danh sách bài viết và người dùng bị ẩn'),
                  subtitle: const Text(
                    'Xem và quản lý bài viết, người dùng đã bị ẩn',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HiddenContentScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('Chặn'),
                  subtitle: const Text(
                    'Xem và quản lý danh sách người dùng bị chặn',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BlockedUsersScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                const ListTile(title: Text('Bộ nhớ tạm'), dense: true),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Xóa bộ nhớ tạm'),
                  subtitle: const Text(
                    'Xóa cache ảnh/video và dữ liệu tạm (không ảnh hưởng dữ liệu tài khoản)',
                  ),
                  onTap: _clearCache,
                ),
                const Divider(),
                const ListTile(title: Text('Tài khoản'), dense: true),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Quản lý tài khoản'),
                  subtitle: const Text('Cập nhật thông tin, đổi mật khẩu, xóa tài khoản'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountManagementScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                const ListTile(title: Text('Bảo mật'), dense: true),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Bảo mật tài khoản'),
                  subtitle: const Text('Thiết bị đăng nhập, đổi mật khẩu'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountSecurityScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
