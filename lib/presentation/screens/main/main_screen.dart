import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../home/home_screen.dart';
import '../search/search_screen.dart';
import '../post/create_post_screen.dart';
import '../messages/messages_list_screen.dart';
import '../profile/profile_screen.dart';
import '../../../data/services/story_service.dart';
import '../../../data/services/agora_call_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/call_notification_service.dart';
import '../../../data/services/message_service.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/presence_service.dart';
import '../../../data/services/group_service.dart';
import '../../../data/services/notification_tap_service.dart';
import '../../../data/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/user_model.dart';
import '../calls/call_screen.dart';
import '../messages/chat_screen.dart';
import '../messages/group_chat_screen.dart';
import '../notifications/notifications_screen.dart';
import '../post/post_detail_screen.dart';
import '../friends/friend_requests_screen.dart';
import '../profile/other_user_profile_screen.dart';
import '../../providers/auth_provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final StoryService _storyService = StoryService();
  final AgoraCallService _callService = AgoraCallService.instance;
  final UserService _userService = UserService();
  final GroupService _groupService = GroupService();
  final MessageService _messageService = MessageService();
  final PresenceService _presenceService = PresenceService();
  final CallNotificationService _callNotificationService =
      CallNotificationService.instance;

  StreamSubscription<Map<String, dynamic>>? _incomingCallSubscription;
  StreamSubscription<String>? _connectionStateSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationTapSubscription;

  int _unreadMessages = 0;
  UserModel? _currentUser;
  bool _handlingNotificationTap = false;

  final List<Widget> _screens = [
    const HomeScreen(),
    const SearchScreen(),
    const CreatePostScreen(), // Create post screen
    const MessagesListScreen(), // Messages screen
    const ProfileScreen(), // Profile screen
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Automatically delete expired stories when app starts
    _storyService.deleteExpiredStories();
    _loadCurrentUser();
    _listenToNotificationTaps();

    // Khởi tạo call service và lắng nghe incoming calls (chỉ trên mobile)
    if (!kIsWeb) {
      try {
        _callService.init();
        _listenToIncomingCalls();
        _listenToConnectionState();
        _setupCallNotificationHandler();

        // Khởi tạo Agora engine ngay khi app mở
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureCallServiceConnected();
        });
      } catch (e) {
        debugPrint('Error initializing call services: $e');
      }
    }
  }

  Future<void> _loadCurrentUser() async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user != null) {
      final userData = await _userService.getUserById(user.id);
      if (mounted) {
        setState(() {
          _currentUser = userData;
        });
        _listenToMessages(user.id);
      }

      // Khởi tạo call notification service để nhận cuộc gọi khi app ở background
      if (!kIsWeb) {
        try {
          await _callNotificationService.init(user.id);
        } catch (e) {
          debugPrint('Error initializing call notification service: $e');
        }
      }

      // Nếu app được mở bằng cách bấm notification (terminated), xử lý sau khi có user.
      await _handleInitialNotificationTap();
    }
  }

  void _listenToMessages(String userId) {
    _messageService.getUnreadCount(userId).then((count) {
      if (!mounted) return;
      setState(() {
        _unreadMessages = count;
      });
    });
  }

  void _listenToNotificationTaps() {
    _notificationTapSubscription?.cancel();
    _notificationTapSubscription = NotificationTapService.instance.stream
        .listen((data) {
          _handleNotificationTap(data);
        });
  }

  Future<void> _handleInitialNotificationTap() async {
    final data = NotificationTapService.instance.consumePending();
    if (data == null) return;

    // Đảm bảo call service đã được khởi tạo trước khi xử lý incoming call
    if (data['type'] == 'incoming_call' && !kIsWeb) {
      try {
        await _callService.init();
        await _ensureCallServiceConnected();
      } catch (e) {
        debugPrint('Error initializing call service for incoming call: $e');
      }
    }

    await _handleNotificationTap(data);
  }

  bool _parseBool(dynamic v) {
    if (v is bool) return v;
    final s = v?.toString().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> data) async {
    if (!mounted) return;
    if (_handlingNotificationTap) return;
    _handlingNotificationTap = true;
    try {
      final type = data['type']?.toString();
      if (type == null || type.isEmpty) return;

      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      // 🔔 Incoming call
      if (type == 'incoming_call') {
        final callerId = data['callerId']?.toString();
        final callId = data['callId']?.toString();
        final channelName = data['channelName']?.toString();
        final isVideo = _parseBool(data['isVideo']);
        final actionId = data['actionId']?.toString(); // accept hoặc reject

        if (callerId == null ||
            callerId.isEmpty ||
            callId == null ||
            callId.isEmpty ||
            channelName == null ||
            channelName.isEmpty) {
          return;
        }

        // Xử lý action buttons (accept/reject) từ notification
        if (actionId == 'reject') {
          // Từ chối cuộc gọi
          try {
            await CallNotificationService.instance.updateCallStatus(callId, {
              'status': 'rejected',
              'rejectedAt': FieldValue.serverTimestamp(),
            });
          } catch (e) {
            debugPrint('Error rejecting call from notification: $e');
          }
          return;
        }

        // Đảm bảo call service đã được khởi tạo
        if (!kIsWeb) {
          try {
            await _callService.init();
            await _ensureCallServiceConnected();
          } catch (e) {
            debugPrint('Error initializing call service for incoming call: $e');
          }
        }

        final caller = await _userService.getUserById(callerId);
        if (!mounted || caller == null) return;

        // Nếu là action "accept" hoặc tap vào notification, mở màn hình cuộc gọi
        // (CallScreen sẽ tự động answer nếu actionId == 'accept')
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CallScreen(
                otherUser: caller,
                isIncoming: true,
                isVideoCall: isVideo,
                callId: callId,
                channelName: channelName,
              ),
            ),
          );
          
          // Nếu là action "accept", tự động answer call
          if (actionId == 'accept') {
            // Đợi một chút để CallScreen được khởi tạo
            await Future.delayed(const Duration(milliseconds: 500));
            // CallScreen sẽ tự động answer khi được mở với isIncoming=true
            // Nhưng để chắc chắn, ta có thể trigger answer từ đây nếu cần
          }
        }
        return;
      }

      // 💬 Direct chat
      if (type == 'chat_message') {
        final senderId = data['senderId']?.toString();
        final receiverId = data['receiverId']?.toString();
        final messageId = data['messageId']?.toString();

        final otherUserId = (receiverId == currentUser.id)
            ? senderId
            : receiverId;
        if (otherUserId == null || otherUserId.isEmpty) return;

        final other = await _userService.getUserById(otherUserId);
        if (!mounted || other == null) return;

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ChatScreen(otherUser: other, scrollToMessageId: messageId),
          ),
        );
        return;
      }

      // 👥 Group chat
      if (type == 'group_chat_message') {
        final groupId = data['groupId']?.toString();
        if (groupId == null || groupId.isEmpty) return;

        final group = await _groupService.getGroup(groupId);
        if (!mounted || group == null) return;

        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)),
        );
        return;
      }

      // 🔔 App notifications (like/follow/friend request...)
      if (type == 'app_notification') {
        final notificationId = data['notificationId']?.toString();
        final notificationType = data['notificationType']?.toString();
        final postId = data['postId']?.toString();
        final actorId = data['actorId']?.toString();

        // Best effort: mark as read
        if (notificationId != null && notificationId.isNotEmpty) {
          try {
            await NotificationService().markAsRead(notificationId);
          } catch (_) {}
        }

        // If there is a postId -> open post detail directly
        if (postId != null && postId.isNotEmpty) {
          final post = await FirestoreService().getPost(
            postId,
            viewerId: currentUser.id,
          );
          if (!mounted || post == null) return;

          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
          );
          return;
        }

        // Friend request -> open friend requests list
        if (notificationType == 'friendRequest') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FriendRequestsScreen()),
          );
          return;
        }

        // Follow -> open actor profile
        if (notificationType == 'follow' &&
            actorId != null &&
            actorId.isNotEmpty) {
          final actor = await _userService.getUserById(actorId);
          if (!mounted || actor == null) return;

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OtherUserProfileScreen(user: actor),
            ),
          );
          return;
        }

        // Fallback -> open notifications screen
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      }
    } finally {
      _handlingNotificationTap = false;
    }
  }

  /// Setup handler cho incoming calls từ notification
  void _setupCallNotificationHandler() {
    _callNotificationService.setIncomingCallCallback((
      callerId,
      isVideo,
      callId,
      channelName,
    ) async {
      if (!mounted) return;

      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      // Load caller info
      final caller = await _userService.getUserById(callerId);
      if (caller == null) return;

      // Mở màn hình gọi điện
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              otherUser: caller,
              isIncoming: true,
              isVideoCall: isVideo,
              callId: callId,
              channelName: channelName,
            ),
          ),
        );
      }
    });
  }

  // Đảm bảo call service được kết nối (chỉ trên mobile)
  Future<void> _ensureCallServiceConnected([String? userId]) async {
    if (kIsWeb || !mounted) return;

    try {
      // Nếu có userId được truyền vào, dùng nó thay vì truy cập context
      String? targetUserId = userId;

      // Nếu không có userId, thử lấy từ context (chỉ khi widget còn mounted)
      if (targetUserId == null && mounted) {
        try {
          final authProvider = context.read<AuthProvider>();
          final currentUser = authProvider.currentUser;
          targetUserId = currentUser?.id;
        } catch (e) {
          // Widget đã bị deactivate, bỏ qua
          debugPrint('MainScreen: Cannot get user - widget deactivated');
          return;
        }
      }

      if (targetUserId != null && mounted) {
        // Kiểm tra xem đã kết nối chưa
        // Nếu chưa, thử kết nối (có thể AuthProvider đã kết nối rồi)
        try {
          // Khởi tạo Agora engine nếu chưa có
          if (!_callService.hasActiveCall) {
            await _callService.init();
            debugPrint('MainScreen: Đã khởi tạo Agora engine');
          }
        } catch (e) {
          debugPrint('MainScreen: Lỗi khởi tạo Agora: $e');
        }
      }
    } catch (e) {
      // Widget đã bị deactivate, bỏ qua
      debugPrint('MainScreen: Cannot ensure connection - widget deactivated');
    }
  }

  // Lắng nghe trạng thái kết nối để tự động reconnect nếu bị ngắt
  void _listenToConnectionState() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _callService.connectionStateStream.listen((
      state,
    ) {
      if (!mounted) return;

      debugPrint('Agora connection state: $state');

      // Nếu bị ngắt kết nối hoặc lỗi, thử kết nối lại
      if (state == 'disconnected' ||
          state == 'error' ||
          state == 'token_refresh_required') {
        // Lưu reference của AuthProvider và currentUser trước khi dùng trong Future.delayed
        final authProvider = context.read<AuthProvider>();
        final currentUser = authProvider.currentUser;

        if (currentUser != null) {
          // Lưu userId để dùng sau khi delay (không cần truy cập context lại)
          final userId = currentUser.id;
          // Đợi một chút rồi thử kết nối lại
          Future.delayed(const Duration(seconds: 2), () {
            if (!mounted) return;
            // Truyền userId đã lưu để tránh truy cập context trong callback
            _ensureCallServiceConnected(userId);
          });
        }
      }
    });
  }

  void _listenToIncomingCalls() {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = _callService.incomingCallStream.listen((
      callData,
    ) async {
      if (!mounted) return;

      // Lấy thông tin user từ call data (Map<String, dynamic>)
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      // Lấy userId của người gọi từ call data
      final fromUserId = callData['fromUserId'] as String?;
      final toUserId = callData['toUserId'] as String?;
      final isVideo = callData['isVideo'] as bool? ?? false;

      // Xác định caller userId
      String? callerUserId;
      if (fromUserId == currentUser.id) {
        callerUserId = toUserId;
      } else if (toUserId == currentUser.id) {
        callerUserId = fromUserId;
      } else if (fromUserId != null) {
        callerUserId = fromUserId;
      }

      // Load user info
      UserModel? otherUser;
      if (callerUserId != null) {
        otherUser = await _userService.getUserById(callerUserId);
      }

      // Mở màn hình gọi điện
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              otherUser: otherUser,
              isIncoming: true,
              isVideoCall: isVideo,
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    // Best effort: mark offline when leaving MainScreen.
    final userId = _currentUser?.id;
    if (userId != null) {
      unawaited(_presenceService.setUserOffline(userId));
    }
    WidgetsBinding.instance.removeObserver(this);
    _notificationTapSubscription?.cancel();
    _incomingCallSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_presenceService.setUserOnline(userId));
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_presenceService.setUserOffline(userId));
        break;
    }
  }

  void _onItemTapped(int index) {
    if (index == 2) {
      // Create post
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CreatePostScreen()));
      return;
    }
    if (index == 3) {
      // Messages
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MessagesListScreen()));
      return;
    }
    if (index == 4) {
      // Profile
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
      return;
    }
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _screens[_currentIndex],
      bottomNavigationBar: isMobile
          ? Container(
              height: 64,
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(color: theme.dividerColor, width: 1),
                ),
              ),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _BottomNavItem(
                      icon: Icons.home,
                      isSelected: _currentIndex == 0,
                      onTap: () => _onItemTapped(0),
                    ),
                    _BottomNavItem(
                      icon: Icons.search,
                      isSelected: _currentIndex == 1,
                      onTap: () => _onItemTapped(1),
                    ),
                    _BottomNavItem(
                      icon: Icons.add,
                      isSelected: false,
                      isCreateButton: true,
                      onTap: () => _onItemTapped(2),
                    ),
                    _BottomNavItem(
                      icon: Icons.chat_bubble_outline,
                      isSelected: _currentIndex == 3,
                      badge: _unreadMessages > 0,
                      onTap: () => _onItemTapped(3),
                    ),
                    _BottomNavItem(
                      icon: null,
                      isSelected: _currentIndex == 4,
                      isProfile: true,
                      avatarUrl: _currentUser?.avatarUrl,
                      userName: _currentUser?.fullName,
                      onTap: () => _onItemTapped(4),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData? icon;
  final bool isSelected;
  final bool isCreateButton;
  final bool isProfile;
  final bool badge;
  final String? avatarUrl;
  final String? userName;
  final VoidCallback onTap;

  const _BottomNavItem({
    this.icon,
    this.isSelected = false,
    this.isCreateButton = false,
    this.isProfile = false,
    this.badge = false,
    this.avatarUrl,
    this.userName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isCreateButton) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.primaryColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Icon(
            Icons.add,
            color: theme.scaffoldBackgroundColor,
            size: 24,
          ),
        ),
      );
    }

    if (isProfile) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.dividerColor, width: 1),
          ),
          child: ClipOval(
            child: avatarUrl != null
                ? Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: theme.cardColor,
                        child: Center(
                          child: Text(
                            userName?[0].toUpperCase() ?? 'U',
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    color: theme.cardColor,
                    child: Center(
                      child: Text(
                        userName?[0].toUpperCase() ?? 'U',
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? theme.primaryColor
                  : theme.iconTheme.color?.withOpacity(0.6),
              size: 24,
            ),
            if (badge)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.red[500],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.scaffoldBackgroundColor,
                      width: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
