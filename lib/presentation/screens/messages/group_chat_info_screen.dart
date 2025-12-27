import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/group_model.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/group_call_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/message_service.dart';
import '../../../data/services/group_call_service.dart';
import '../../../data/services/group_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/user_service.dart';
import '../../providers/auth_provider.dart';
import '../calls/group_call_screen.dart';
import 'add_member_screen.dart';
import 'group_chat_screen.dart';
import '../profile/other_user_profile_screen.dart';
import '../../../core/utils/error_message_helper.dart';

class GroupChatInfoScreen extends StatefulWidget {
  final GroupModel group;

  const GroupChatInfoScreen({super.key, required this.group});

  @override
  State<GroupChatInfoScreen> createState() => _GroupChatInfoScreenState();
}

class _GroupChatInfoScreenState extends State<GroupChatInfoScreen> {
  final MessageService _messageService = MessageService();
  final GroupCallService _groupCallService = GroupCallService();
  final GroupService _groupService = GroupService();
  final StorageService _storageService = StorageService();
  final UserService _userService = UserService();
  final ImagePicker _picker = ImagePicker();
  String? _conversationId;
  String? _currentUserId;
  DateTime? _muteUntil;
  bool _loadingMute = false;
  bool _uploadingAvatar = false;
  String? _newAvatarUrl;
  List<UserModel> _members = [];
  bool _loadingMembers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initData());
  }

  Future<void> _initData() async {
    final auth = context.read<AuthProvider>();
    final me = auth.currentUser;
    if (me == null) return;

    // Conversation ID cho group là 'group_${groupId}'
    final convId = 'group_${widget.group.id}';
    setState(() {
      _currentUserId = me.id;
      _conversationId = convId;
    });
    await Future.wait([_loadMute(convId, me.id), _loadMembers()]);
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loadingMembers = true;
    });

    final members = <UserModel>[];
    for (final memberId in widget.group.memberIds) {
      final user = await _userService.getUserById(memberId);
      if (user != null) {
        members.add(user);
      }
    }

    if (!mounted) return;
    setState(() {
      _members = members;
      _loadingMembers = false;
    });
  }

  Future<void> _loadMute(String convId, String userId) async {
    final until = await _messageService.getMuteUntil(convId, userId);
    if (!mounted) return;
    setState(() {
      _muteUntil = until;
    });
  }

  bool get _isAdmin {
    if (_currentUserId == null) return false;
    final userRole = widget.group.memberRoles[_currentUserId];
    return userRole == GroupRole.admin ||
        widget.group.creatorId == _currentUserId;
  }

  Future<void> _changeAvatar() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chỉ admin mới có thể đổi avatar nhóm'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _uploadingAvatar = true;
      });

      // Upload ảnh lên Cloudinary
      final file = File(image.path);
      final imageUrl = await _storageService.uploadCover(file, widget.group.id);

      // Cập nhật avatar trong group
      await _groupService.updateGroup(widget.group.id, coverUrl: imageUrl);

      setState(() {
        _newAvatarUrl = imageUrl;
        _uploadingAvatar = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật avatar nhóm'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error changing avatar: $e');
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    }
  }

  Future<void> _removeMember(UserModel member) async {
    if (_currentUserId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          'Xóa thành viên',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa ${member.fullName} khỏi nhóm?',
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Hủy',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _groupService.removeMember(
        widget.group.id,
        _currentUserId!,
        member.id,
      );

      // Reload members
      await _loadMembers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa ${member.fullName} khỏi nhóm'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    }
  }

  Future<void> _showAddMemberScreen() async {
    if (_currentUserId == null) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddMemberScreen(
          group: widget.group,
          currentUserId: _currentUserId!,
        ),
      ),
    );

    // Reload members nếu có thành viên mới được thêm
    if (result == true && mounted) {
      await _loadMembers();
    }
  }

  String _muteLabel() {
    if (_muteUntil == null) return 'Đang bật thông báo';
    final now = DateTime.now();
    if (_muteUntil!.isBefore(now)) return 'Đang bật thông báo';
    return 'Đã tắt đến ${_formatTime(_muteUntil!)}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month} $h:$m';
  }

  Future<void> _openMuteSheet() async {
    if (_conversationId == null || _currentUserId == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.notifications_active,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                'Bật lại thông báo',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              onTap: () => Navigator.pop(context, 'unmute'),
            ),
            ListTile(
              leading: Icon(
                Icons.notifications_off,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                'Tắt 8 giờ',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              onTap: () => Navigator.pop(context, '8h'),
            ),
            ListTile(
              leading: Icon(
                Icons.notifications_off,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                'Tắt 1 ngày',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              onTap: () => Navigator.pop(context, '1d'),
            ),
            ListTile(
              leading: Icon(
                Icons.notifications_off,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                'Tắt cho đến khi bật lại',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
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
        userId: _currentUserId!,
        duration: duration,
      );
      final until = await _messageService.getMuteUntil(
        _conversationId!,
        _currentUserId!,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
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
                _deleteConversation();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteConversation() async {
    if (_conversationId == null || _currentUserId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Xóa đoạn chat?',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa đoạn chat này? Tất cả tin nhắn sẽ bị xóa vĩnh viễn.',
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

    if (confirm == true && _currentUserId != null) {
      try {
        await _messageService.deleteGroupConversation(
          widget.group.id,
          _currentUserId!,
        );
        if (mounted) {
          Navigator.of(context).pop(); // Pop GroupChatInfoScreen
          Navigator.of(context).pop(); // Pop GroupChatScreen
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã xóa đoạn chat'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
        }
      }
    }
  }

  Future<void> _startGroupCall({required bool video}) async {
    if (_currentUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bạn cần đăng nhập để gọi')),
        );
      }
      return;
    }

    // Hiển thị loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang khởi tạo cuộc gọi nhóm...'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      final callId = await _groupCallService.createGroupCall(
        groupId: widget.group.id,
        creatorId: _currentUserId!,
        participantIds: widget.group.memberIds,
        isVideoCall: video,
      );

      if (mounted) {
        // Tạo GroupCallModel từ callId
        final groupCall = GroupCallModel(
          id: callId,
          groupId: widget.group.id,
          creatorId: _currentUserId!,
          participantIds: widget.group.memberIds,
          participantStatus: {},
          isVideoCall: video,
          createdAt: DateTime.now(),
          status: 'active',
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupCallScreen(
              group: widget.group,
              groupCall: groupCall,
              isIncoming: false,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting group call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorMessageHelper.getErrorMessage(
                e,
                defaultMessage: 'Không thể thực hiện cuộc gọi nhóm',
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_currentUserId == null || _conversationId == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
            onPressed: () => _showMenu(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Group Avatar với nút edit
            Stack(
              children: [
                CircleAvatar(
                  radius: 62,
                  backgroundColor: theme.cardColor,
                  backgroundImage:
                      (_newAvatarUrl ?? widget.group.coverUrl) != null
                      ? NetworkImage(_newAvatarUrl ?? widget.group.coverUrl!)
                      : null,
                  child: (_newAvatarUrl ?? widget.group.coverUrl) == null
                      ? Text(
                          widget.group.name.isNotEmpty
                              ? widget.group.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 28,
                            color: theme.textTheme.bodyLarge?.color,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : _uploadingAvatar
                      ? CircularProgressIndicator(color: theme.primaryColor)
                      : null,
                ),
                if (_isAdmin && !_uploadingAvatar)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _changeAvatar,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: theme.colorScheme.onPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.group.name,
              style: TextStyle(
                color: theme.textTheme.titleLarge?.color,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (widget.group.description != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.group.description!,
                style: TextStyle(color: theme.textTheme.bodySmall?.color),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.4),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, color: theme.iconTheme.color, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Được mã hóa đầu cuối',
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
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
                  onTap: () => _startGroupCall(video: false),
                ),
                _quickAction(
                  icon: Icons.videocam,
                  label: 'Gọi video',
                  onTap: () => _startGroupCall(video: true),
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
            _settingItem(Icons.color_lens, 'Chủ đề'),
            _settingItem(Icons.thumb_up_alt_rounded, 'Cảm xúc nhanh'),
            _settingItem(Icons.auto_fix_high, 'Hiệu ứng từ ngữ'),
            const SizedBox(height: 20),
            _sectionTitle('Thành viên'),
            const SizedBox(height: 8),
            if (_isAdmin)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Thêm thành viên',
                  style: TextStyle(color: Colors.blue, fontSize: 15),
                ),
                onTap: () => _showAddMemberScreen(),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            if (_loadingMembers)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(color: Colors.black),
                ),
              )
            else
              ..._members.map((member) {
                final memberRole = widget.group.memberRoles[member.id];
                final isCreator = widget.group.creatorId == member.id;
                final isCurrentUser = member.id == _currentUserId;
                final canRemove =
                    _isAdmin &&
                    !isCreator &&
                    !isCurrentUser &&
                    memberRole != GroupRole.admin;

                final theme = Theme.of(context);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: member.avatarUrl != null
                        ? NetworkImage(member.avatarUrl!)
                        : null,
                    child: member.avatarUrl == null
                        ? Text(
                            member.fullName.isNotEmpty
                                ? member.fullName[0].toUpperCase()
                                : '?',
                          )
                        : null,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          member.fullName,
                          style: TextStyle(
                            color: isCurrentUser 
                                ? Colors.blue 
                                : theme.textTheme.bodyLarge?.color ?? Colors.black,
                            fontWeight: isCurrentUser
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isCreator)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Trưởng nhóm',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else if (memberRole == GroupRole.admin)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Admin',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '@${member.username}',
                    style: TextStyle(
                      color: theme.textTheme.bodySmall?.color ?? Colors.grey[600],
                    ),
                  ),
                  trailing: canRemove
                      ? IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeMember(member),
                        )
                      : null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OtherUserProfileScreen(user: member),
                      ),
                    );
                  },
                );
              }),
            const SizedBox(height: 20),
            _sectionTitle('Hành động khác'),
            const SizedBox(height: 8),
            _settingItem(
              Icons.image,
              'Xem file phương tiện, file và liên kết',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupMediaLinksScreen(
                    conversationId: _conversationId!,
                    currentUserId: _currentUserId!,
                    groupId: widget.group.id,
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
                  builder: (_) => GroupPinnedMessagesScreen(
                    conversationId: _conversationId!,
                    currentUserId: _currentUserId!,
                    groupId: widget.group.id,
                    group: widget.group,
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
                Navigator.of(context).pop(); // Pop info screen
                Navigator.of(context).pop(); // Pop group chat screen
                // Navigate back to group chat screen with search enabled
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupChatScreen(
                      group: widget.group,
                      enableSearch: true,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _settingItem(
              Icons.notifications,
              'Trạng thái thông báo',
              subtitle: _muteLabel(),
              onTap: _openMuteSheet,
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
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: CircleAvatar(
            radius: 30,
            backgroundColor: theme.cardColor,
            child: Icon(icon, color: theme.iconTheme.color, size: 22),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _settingItem(
    IconData icon,
    String label, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.iconTheme.color),
      title: Text(
        label,
        style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color: theme.textTheme.bodySmall?.color,
                fontSize: 12,
              ),
            )
          : null,
      onTap: onTap,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _sectionTitle(String text) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: theme.textTheme.bodySmall?.color,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class GroupMediaLinksScreen extends StatelessWidget {
  final String conversationId;
  final String currentUserId;
  final String groupId;
  final MessageService messageService;

  const GroupMediaLinksScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.groupId,
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
        stream: messageService.getGroupMessages(groupId, currentUserId),
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

class GroupPinnedMessagesScreen extends StatelessWidget {
  final String conversationId;
  final String currentUserId;
  final String groupId;
  final GroupModel group;
  final MessageService messageService;

  const GroupPinnedMessagesScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.groupId,
    required this.group,
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
        stream: messageService.getGroupMessages(groupId, currentUserId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
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
                  Navigator.of(context).pop(); // Pop pinned messages screen
                  Navigator.of(context).pop(); // Pop info screen
                  // Navigate to group chat screen and scroll to message
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupChatScreen(
                        group: group,
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
