import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../data/services/user_service.dart';
import '../../data/services/message_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/models/user_model.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/messages/messages_list_screen.dart';
import '../screens/post/create_post_screen.dart';

class HomeLeftSidebar extends StatefulWidget {
  const HomeLeftSidebar({super.key});

  @override
  State<HomeLeftSidebar> createState() => _HomeLeftSidebarState();
}

class _HomeLeftSidebarState extends State<HomeLeftSidebar> {
  final UserService _userService = UserService();
  final MessageService _messageService = MessageService();
  final NotificationService _notificationService = NotificationService();
  
  UserModel? _currentUser;
  int _unreadMessages = 0;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
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
        _listenCounts(user.id);
      }
    }
  }

  void _listenCounts(String userId) {
    // Unread messages
    _messageService.getUnreadCount(userId).then((count) {
      if (!mounted) return;
      setState(() {
        _unreadMessages = count;
      });
    });

    // Unread notifications
    _notificationService.getUnreadCountStream(userId).listen((count) {
      if (!mounted) return;
      setState(() {
        _unreadNotifications = count;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLarge = MediaQuery.of(context).size.width >= 1280;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Logo
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: isLarge ? 32 : 0),
            child: Row(
              mainAxisAlignment: isLarge ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Text(
                        'N',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (isLarge) ...[
                  const SizedBox(width: 12),
                  const Text(
                    'NEXUS',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _MenuItem(
                    icon: Icons.home,
                    label: 'Trang chủ',
                    isSelected: true,
                    showLabel: isLarge,
                  ),
                  const SizedBox(height: 4),
                  _MenuItem(
                    icon: Icons.search,
                    label: 'Khám phá',
                    showLabel: isLarge,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  _MenuItem(
                    icon: Icons.notifications_outlined,
                    label: 'Thông báo',
                    showLabel: isLarge,
                    badge: _unreadNotifications > 0,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  _MenuItem(
                    icon: Icons.chat_bubble_outline,
                    label: 'Tin nhắn',
                    showLabel: isLarge,
                    badge: _unreadMessages > 0,
                    badgeCount: _unreadMessages,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MessagesListScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  _MenuItem(
                    icon: Icons.person_outline,
                    label: 'Hồ sơ',
                    showLabel: isLarge,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // New Post Button
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isLarge ? 24 : 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, size: 18),
                    if (isLarge) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'Đăng bài',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // User Mini Profile
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isLarge ? 16 : 12),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    ClipOval(
                      child: _currentUser?.avatarUrl != null
                          ? Image.network(
                              _currentUser!.avatarUrl!,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 36,
                                  height: 36,
                                  color: Colors.grey[300],
                                  child: Center(
                                    child: Text(
                                      _currentUser?.fullName[0].toUpperCase() ?? 'U',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(
                              width: 36,
                              height: 36,
                              color: Colors.grey[300],
                              child: Center(
                                child: Text(
                                  _currentUser?.fullName[0].toUpperCase() ?? 'U',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    if (isLarge) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentUser?.fullName ?? 'User',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '@${_currentUser?.username ?? 'user'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.more_horiz,
                        color: Colors.grey[400],
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool showLabel;
  final bool badge;
  final int? badgeCount;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.showLabel = true,
    this.badge = false,
    this.badgeCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 16 : 12,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey[200] : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected ? Colors.black : Colors.grey[600],
                ),
                if (badge && badgeCount == null)
                  Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.red[500],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
            if (showLabel) ...[
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child:                       Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.grey[700],
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (badge && badgeCount != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[500],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                        child: Text(
                          badgeCount! > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
