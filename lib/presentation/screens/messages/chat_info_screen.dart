import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/message_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/message_service.dart';
import '../../../data/services/presence_service.dart';
import '../../../data/services/settings_service.dart';
import '../../providers/auth_provider.dart';
import '../profile/other_user_profile_screen.dart';
import '../calls/call_screen.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import '../../../core/utils/error_message_helper.dart';

class ChatInfoScreen extends StatefulWidget {
  final UserModel otherUser;

  const ChatInfoScreen({super.key, required this.otherUser});

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  final MessageService _messageService = MessageService();
  final PresenceService _presenceService = PresenceService();
  String? _conversationId;
  UserModel? _currentUser;
  String? _nickname;
  DateTime? _muteUntil;
  bool _loadingMute = false;
  bool _loadingNickname = false;
  bool _activityStatusEnabled = true;
  bool _isOnline = false;
  DateTime? _lastSeen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initData());
  }

  Future<void> _initData() async {
    final auth = context.read<AuthProvider>();
    final me = auth.currentUser;
    if (me == null) return;
    final parts = [me.id, widget.otherUser.id]..sort();
    final convId = parts.join('_');
    setState(() {
      _currentUser = me;
      _conversationId = convId;
    });
    await Future.wait([
      _loadNickname(convId),
      _loadMute(convId, me.id),
      _loadActivityStatusSetting(),
    ]);
    _loadOnlineStatus();
  }

  Future<void> _loadActivityStatusSetting() async {
    final enabled = await SettingsService.isActivityStatusEnabled();
    if (mounted) {
      setState(() {
        _activityStatusEnabled = enabled;
      });
    }
  }

  void _loadOnlineStatus() {
    if (!_activityStatusEnabled) return;
    
    // Listen to online status
    _presenceService.isUserOnline(widget.otherUser.id).listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });

    // Load last seen
    _presenceService.getLastSeen(widget.otherUser.id).then((lastSeen) {
      if (mounted) {
        setState(() {
          _lastSeen = lastSeen;
        });
      }
    });
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return '';
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inMinutes < 1) {
      return 'Vừa hoạt động';
    } else if (difference.inMinutes < 60) {
      return 'Hoạt động ${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return 'Hoạt động ${difference.inHours} giờ trước';
    } else if (difference.inDays < 7) {
      return 'Hoạt động ${difference.inDays} ngày trước';
    } else {
      return 'Hoạt động lần cuối ${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
    }
  }

  Future<void> _loadNickname(String convId) async {
    _messageService.watchNickname(convId, widget.otherUser.id).listen((value) {
      if (!mounted) return;
      setState(() {
        _nickname = value;
      });
    });
  }

  Future<void> _loadMute(String convId, String userId) async {
    final until = await _messageService.getMuteUntil(convId, userId);
    if (!mounted) return;
    setState(() {
      _muteUntil = until;
    });
  }

  Future<void> _openMuteSheet() async {
    if (_conversationId == null || _currentUser == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.notifications_active,
                color: Colors.black,
              ),
              title: const Text(
                'Bật lại thông báo',
                style: TextStyle(color: Colors.black),
              ),
              onTap: () => Navigator.pop(context, 'unmute'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off, color: Colors.black),
              title: const Text(
                'Tắt 8 giờ',
                style: TextStyle(color: Colors.black),
              ),
              onTap: () => Navigator.pop(context, '8h'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off, color: Colors.black),
              title: const Text(
                'Tắt 1 ngày',
                style: TextStyle(color: Colors.black),
              ),
              onTap: () => Navigator.pop(context, '1d'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off, color: Colors.black),
              title: const Text(
                'Tắt cho đến khi bật lại',
                style: TextStyle(color: Colors.black),
              ),
              onTap: () => Navigator.pop(context, 'forever'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );

    if (choice == null) return;
    setState(() {
      _loadingMute = true;
    });

    try {
      Duration? duration;
      if (choice == '8h') duration = const Duration(hours: 8);
      if (choice == '1d') duration = const Duration(days: 1);
      if (choice == 'forever') duration = const Duration(days: 365 * 5);
      if (choice == 'unmute') duration = null;

      await _messageService.muteConversation(
        conversationId: _conversationId!,
        userId: _currentUser!.id,
        duration: duration,
      );
      final until = await _messageService.getMuteUntil(
        _conversationId!,
        _currentUser!.id,
      );
      if (!mounted) return;
      setState(() {
        _muteUntil = until;
        _loadingMute = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMute = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ErrorMessageHelper.createErrorSnackBar(e),
      );
    }
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block, color: Colors.black),
              title: Text(
                'Chặn ${widget.otherUser.fullName}',
                style: const TextStyle(color: Colors.black),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tính năng đang phát triển')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.report, color: Colors.black),
              title: const Text(
                'Báo cáo',
                style: TextStyle(color: Colors.black),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tính năng đang phát triển')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Xóa đoạn chat',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteConversation(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteConversation(BuildContext context) async {
    if (_conversationId == null || _currentUser == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Xóa đoạn chat?',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa đoạn chat này?',
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Colors.black87)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && _currentUser != null) {
      try {
        final parts = _conversationId!.split('_');
        if (parts.length == 2) {
          await _messageService.deleteConversation(
            parts[0],
            parts[1],
            _currentUser!.id,
          );
        }
        if (mounted) {
          Navigator.of(context).pop(); // Pop ChatInfoScreen
          Navigator.of(context).pop(); // Pop ChatScreen
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ErrorMessageHelper.createErrorSnackBar(e),
          );
        }
      }
    }
  }

  Future<void> _startCall({required bool video}) async {
    if (_currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bạn cần đăng nhập để gọi')),
        );
      }
      return;
    }

    try {
      // ✅ Chỉ mở CallScreen; CallScreen tự tạo call invitation + xử lý ringing/accepted.
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              otherUser: widget.otherUser,
              isIncoming: false,
              isVideoCall: video,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorMessageHelper.getErrorMessage(
                e,
                defaultMessage: 'Không thể thực hiện cuộc gọi',
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _openNicknameDialog() async {
    if (_conversationId == null) return;
    final controller = TextEditingController(text: _nickname ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Đặt biệt danh',
          style: TextStyle(color: Colors.black),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.black),
          decoration: const InputDecoration(
            hintText: 'Nhập biệt danh...',
            hintStyle: TextStyle(color: Colors.black54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blueAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.black87)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Lưu',
              style: TextStyle(color: Colors.blueAccent),
            ),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _loadingNickname = true);
    await _messageService.setNickname(
      conversationId: _conversationId!,
      targetUserId: widget.otherUser.id,
      nickname: result,
    );
    if (!mounted) return;
    setState(() => _loadingNickname = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null || _conversationId == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () => _showMenu(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar + online indicator
            Stack(
              children: [
                CircleAvatar(
                  radius: 62,
                  backgroundColor: Colors.grey.shade800,
                  backgroundImage: widget.otherUser.avatarUrl != null
                      ? NetworkImage(widget.otherUser.avatarUrl!)
                      : null,
                  child: widget.otherUser.avatarUrl == null
                      ? Text(
                          widget.otherUser.fullName.isNotEmpty
                              ? widget.otherUser.fullName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 28,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                // Online indicator - chỉ hiển thị khi setting được bật
                if (_activityStatusEnabled && _isOnline)
                  Positioned(
                    right: 4,
                    bottom: 6,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _nickname?.isNotEmpty == true
                  ? _nickname!
                  : widget.otherUser.fullName,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            // Hiển thị trạng thái hoạt động hoặc last seen
            if (_activityStatusEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _isOnline ? 'Đang hoạt động' : _formatLastSeen(_lastSeen),
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.lock, color: Colors.black, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Được mã hóa đầu cuối',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _quickAction(
                  icon: Icons.call,
                  label: 'Gọi thoại',
                  onTap: () => _startCall(video: false),
                ),
                _quickAction(
                  icon: Icons.videocam,
                  label: 'Gọi video',
                  onTap: () => _startCall(video: true),
                ),
                _quickAction(
                  icon: Icons.person,
                  label: 'Trang cá nhân',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            OtherUserProfileScreen(user: widget.otherUser),
                      ),
                    );
                  },
                ),
                _quickAction(
                  icon: Icons.notifications_off,
                  label: _loadingMute ? 'Đang tải...' : 'Tắt thông báo',
                  onTap: _loadingMute ? null : _openMuteSheet,
                ),
              ],
            ),
            const SizedBox(height: 28),
            _sectionTitle('Tùy chỉnh'),
            const SizedBox(height: 8),
            _settingItem(
              Icons.text_fields,
              'Biệt danh',
              subtitle: _loadingNickname
                  ? 'Đang lưu...'
                  : (_nickname?.isNotEmpty == true
                        ? _nickname!
                        : 'Đặt biệt danh'),
              onTap: _openNicknameDialog,
            ),
            const SizedBox(height: 20),
            _sectionTitle('Hành động khác'),
            const SizedBox(height: 8),
            _settingItem(
              Icons.group_add,
              'Tạo nhóm chat với ${widget.otherUser.fullName.split(' ').last}',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NewChatScreen(
                      isGroupMode: true,
                      preSelectedUserIds: [widget.otherUser.id],
                    ),
                  ),
                );
              },
            ),
            _settingItem(
              Icons.image,
              'Xem file phương tiện, file và liên kết',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MediaLinksScreen(
                    conversationId: _conversationId!,
                    currentUserId: _currentUser!.id,
                    otherUser: widget.otherUser,
                    messageService: _messageService,
                  ),
                ),
              ),
            ),
            _settingItem(Icons.download, 'Tự động lưu ảnh'),
            _settingItem(
              Icons.push_pin,
              'Tin nhắn đã ghim',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PinnedMessagesScreen(
                    conversationId: _conversationId!,
                    currentUserId: _currentUser!.id,
                    otherUser: widget.otherUser,
                    messageService: _messageService,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _settingItem(
              Icons.search,
              'Tìm kiếm trong cuộc trò chuyện',
              onTap: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      otherUser: widget.otherUser,
                      openSearchOnInit: true,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Icon(icon, color: Colors.black, size: 22),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.black, fontSize: 12)),
      ],
    );
  }

  Widget _settingItem(
    IconData icon,
    String label, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.black),
      title: Text(
        label,
        style: const TextStyle(color: Colors.black, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.black87, fontSize: 12),
            )
          : null,
      onTap: onTap,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _sectionTitle(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class MediaLinksScreen extends StatelessWidget {
  final String conversationId;
  final String currentUserId;
  final UserModel otherUser;
  final MessageService messageService;

  const MediaLinksScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.otherUser,
    required this.messageService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'File, phương tiện & liên kết',
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: StreamBuilder<List<MessageModel>>(
        stream: messageService.getMessages(currentUserId, otherUser.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.black),
            );
          }
          final messages = snapshot.data!;
          final media = messages
              .where((m) => m.imageUrl != null || m.videoUrl != null)
              .toList();
          final links = messages
              .where(
                (m) =>
                    m.content.contains('http://') ||
                    m.content.contains('https://'),
              )
              .toList();

          if (media.isEmpty && links.isEmpty) {
            return const Center(
              child: Text(
                'Chưa có nội dung',
                style: TextStyle(color: Colors.black87),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (media.isNotEmpty)
                const Text(
                  'Ảnh/Video',
                  style: TextStyle(color: Colors.black87, fontSize: 14),
                ),
              if (media.isNotEmpty) const SizedBox(height: 12),
              if (media.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: media.length,
                  itemBuilder: (context, index) {
                    final m = media[index];
                    final isImage = m.imageUrl != null;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: isImage
                          ? Image.network(m.imageUrl!, fit: BoxFit.cover)
                          : Container(
                              color: Colors.grey[300]!,
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.black,
                                  size: 32,
                                ),
                              ),
                            ),
                    );
                  },
                ),
              const SizedBox(height: 16),
              if (links.isNotEmpty)
                const Text(
                  'Liên kết',
                  style: TextStyle(color: Colors.black87, fontSize: 14),
                ),
              if (links.isNotEmpty) const SizedBox(height: 8),
              ...links.map(
                (m) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link, color: Colors.white70),
                  title: Text(
                    m.content,
                    style: const TextStyle(color: Colors.black),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PinnedMessagesScreen extends StatelessWidget {
  final String conversationId;
  final String currentUserId;
  final UserModel otherUser;
  final MessageService messageService;

  const PinnedMessagesScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.otherUser,
    required this.messageService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Tin nhắn đã ghim',
          style: TextStyle(color: Colors.black),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<List<MessageModel>>(
        stream: messageService.getMessages(currentUserId, otherUser.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          final pinned = snapshot.data!.where((m) => m.isPinned).toList()
            ..sort(
              (a, b) => b.pinnedAt?.compareTo(a.pinnedAt ?? DateTime(0)) ?? 0,
            );

          if (pinned.isEmpty) {
            return const Center(
              child: Text(
                'Chưa có tin nhắn ghim',
                style: TextStyle(color: Colors.black87),
              ),
            );
          }

          return ListView.builder(
            itemCount: pinned.length,
            itemBuilder: (context, index) {
              final m = pinned[index];
              return ListTile(
                leading: const Icon(Icons.push_pin, color: Colors.orange),
                title: Text(
                  m.content.isNotEmpty
                      ? m.content
                      : (m.imageUrl != null ? '[Ảnh]' : '[Media]'),
                  style: const TextStyle(color: Colors.black),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        otherUser: otherUser,
                        scrollToMessageId: m.id,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
