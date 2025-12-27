import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../../data/services/user_service.dart';
import '../../data/services/friend_service.dart';
import '../../data/services/message_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/models/user_model.dart';
import '../../../core/constants/app_colors.dart';
import '../screens/messages/messages_list_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/friends/friend_requests_screen.dart';
import '../screens/menu/menu_screen.dart';

class HomeTopNavBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const HomeTopNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  State<HomeTopNavBar> createState() => _HomeTopNavBarState();
}

class _HomeTopNavBarState extends State<HomeTopNavBar> {
  final UserService _userService = UserService();
  UserModel? _currentUser;
  final FriendService _friendService = FriendService();
  final MessageService _messageService = MessageService();
  final NotificationService _notificationService = NotificationService();

  int _pendingRequests = 0;
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
    // Friend requests (pending)
    _friendService.getFriendRequests(userId).listen((requests) {
      if (!mounted) return;
      setState(() {
        _pendingRequests = requests.length;
      });
    });

    // Unread messages
    _messageService.getUnreadCount(userId).then((count) {
      if (!mounted) return;
      setState(() {
        _unreadMessages = count;
      });
    });

    // Unread notifications (realtime)
    _notificationService.getUnreadCountStream(userId).listen((count) {
      if (!mounted) return;
      setState(() {
        _unreadNotifications = count;
      });
    });
  }

  void _showMenu(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MenuScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 1024;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              // Left: Logo & Search
              Flexible(
                flex: 1,
                fit: FlexFit.tight,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    // Logo text
                    Text(
                      strings?.appTitle ?? 'Synap',
                      style: TextStyle(
                        color: theme.textTheme.titleLarge?.color,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      strings?.homeTitle ?? 'Trang chủ',
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),

              // Center: Nav Tabs (desktop only)
              if (isDesktop)
                Flexible(
                  flex: 2,
                  fit: FlexFit.tight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _NavTab(
                        icon: Icons.home,
                        isSelected: widget.selectedIndex == 0,
                        onTap: () => widget.onItemSelected(0),
                      ),
                      _NavTab(
                        icon: Icons.people,
                        isSelected: widget.selectedIndex == 1,
                        onTap: () => widget.onItemSelected(1),
                        badge: true,
                      ),
                      _NavTab(
                        icon: Icons.tv,
                        isSelected: widget.selectedIndex == 2,
                        onTap: () => widget.onItemSelected(2),
                      ),
                      _NavTab(
                        icon: Icons.store,
                        isSelected: widget.selectedIndex == 3,
                        onTap: () => widget.onItemSelected(3),
                      ),
                      _NavTab(
                        icon: Icons.sports_esports,
                        isSelected: widget.selectedIndex == 4,
                        onTap: () => widget.onItemSelected(4),
                      ),
                    ],
                  ),
                ),

              // Right: Actions & Profile
              Flexible(
                fit: FlexFit.loose,
                child: SizedBox(
                  height: 56,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isDesktop) ...[
                          IconButton(
                            icon: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.1),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.apps,
                                size: 20,
                                color: AppColors.primary,
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const MenuScreen(),
                                ),
                              );
                            },
                            padding: EdgeInsets.zero,
                          ),
                          Stack(
                            children: [
                              IconButton(
                                icon: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.chat_bubble_outline,
                                    size: 20,
                                    color: AppColors.primary,
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const MessagesListScreen(),
                                    ),
                                  );
                                },
                                padding: EdgeInsets.zero,
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.accentRed,
                                        AppColors.error,
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.black,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '4',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Stack(
                            children: [
                              IconButton(
                                icon: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.notifications_outlined,
                                    size: 20,
                                    color: AppColors.primary,
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const NotificationsScreen(),
                                    ),
                                  );
                                },
                                padding: EdgeInsets.zero,
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.accentRed,
                                        AppColors.error,
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.black,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '2',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          // Profile with gradient
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ProfileScreen(),
                                ),
                              );
                            },
                            child: Stack(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.primary,
                                        AppColors.primaryDark,
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.3),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(
                                          0.3,
                                        ),
                                        blurRadius: 8,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: _currentUser?.avatarUrl != null
                                      ? ClipOval(
                                          child: Image.network(
                                            _currentUser!.avatarUrl!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            _currentUser?.fullName[0]
                                                    .toUpperCase() ??
                                                'U',
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.expand_more,
                                      size: 6,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        if (!isDesktop) ...[
                          // Friend requests (mobile) with badge
                          _BadgeIconButton(
                            icon: Icons.person_add_alt_1_outlined,
                            count: _pendingRequests,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const FriendRequestsScreen(),
                                ),
                              );
                            },
                          ),
                          // Only keep notifications badge on mobile to avoid overflow
                          _BadgeIconButton(
                            icon: Icons.notifications_outlined,
                            count: _unreadNotifications,
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const NotificationsScreen(),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.menu,
                              color: Colors.black,
                              size: 20,
                            ),
                            onPressed: () {
                              _showMenu(context);
                            },
                            padding: const EdgeInsets.only(
                              left: 4.0,
                              right: 8.0,
                              top: 4.0,
                              bottom: 4.0,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            iconSize: 20,
                          ),
                        ],
                      ],
                    ),
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

class _NavTab extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final bool badge;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.isSelected,
    this.badge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(
                  icon,
                  size: 24,
                  color: isSelected ? AppColors.primary : Colors.grey[500],
                ),
              ),
              if (badge)
                Positioned(
                  top: 12,
                  right: 20,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.accentRed, AppColors.error],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeIconButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback onPressed;

  const _BadgeIconButton({
    required this.icon,
    required this.count,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Icon(icon, color: Colors.black, size: 20),
          ),
          onPressed: onPressed,
          padding: const EdgeInsets.all(4.0),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          iconSize: 24,
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentRed, AppColors.error],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
