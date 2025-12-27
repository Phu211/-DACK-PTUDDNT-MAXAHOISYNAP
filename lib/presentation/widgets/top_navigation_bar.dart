import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../data/services/user_service.dart';
import '../../data/models/user_model.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/messages/messages_list_screen.dart';
import 'synap_logo.dart';

class TopNavigationBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const TopNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  State<TopNavigationBar> createState() => _TopNavigationBarState();
}

class _TopNavigationBarState extends State<TopNavigationBar> {
  final UserService _userService = UserService();
  UserModel? _currentUser;

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
      }
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    if (!mounted) return;
    
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất?'),
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
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    
    if (!mounted || shouldLogout != true) return;
    
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    try {
      await context.read<AuthProvider>().signOut();
      
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi đăng xuất: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1200;
    
    return Container(
      height: 56,
      color: const Color(0xFF1877F2), // Facebook blue
      child: Row(
        children: [
          // Left side - Logo and navigation icons
          Expanded(
            child: Row(
              children: [
                const SizedBox(width: 16),
                // Logo
                Row(
                  children: [
                    const SynapLogo(size: 28),
                    const SizedBox(width: 8),
                    const Text(
                      'Synap',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 8),
                  // Navigation icons - only show on desktop
                  _NavIcon(
                    icon: Icons.home,
                    isSelected: widget.selectedIndex == 0,
                    onTap: () => widget.onItemSelected(0),
                  ),
                  _NavIcon(
                    icon: Icons.flag_outlined,
                    isSelected: widget.selectedIndex == 1,
                    onTap: () => widget.onItemSelected(1),
                  ),
                  _NavIcon(
                    icon: Icons.grid_view_outlined,
                    isSelected: widget.selectedIndex == 2,
                    onTap: () => widget.onItemSelected(2),
                  ),
                  _NavIcon(
                    icon: Icons.video_library_outlined,
                    isSelected: widget.selectedIndex == 3,
                    onTap: () => widget.onItemSelected(3),
                  ),
                  _NavIcon(
                    icon: Icons.people_outline,
                    isSelected: widget.selectedIndex == 4,
                    onTap: () => widget.onItemSelected(4),
                  ),
                ],
              ],
            ),
          ),
          // Right side - Actions
          Row(
            children: [
              // Search bar - only show on desktop
              if (isDesktop)
                Container(
                  width: 240,
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm trên Synap',
                      hintStyle: TextStyle(color: Colors.black.withOpacity(0.7)),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.black.withOpacity(0.7),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              // Menu icon
              IconButton(
                icon: const Icon(Icons.apps, color: Colors.black),
                onPressed: () {
                  // Menu screen có thể được mở từ drawer hoặc bottom navigation
                  Scaffold.of(context).openDrawer();
                },
              ),
              // Messenger icon
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Colors.black),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MessagesListScreen(),
                    ),
                  );
                },
              ),
              // Notifications icon
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.black),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
              // Profile dropdown
              PopupMenuButton<String>(
                offset: const Offset(0, 50),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: _currentUser?.avatarUrl != null
                            ? NetworkImage(_currentUser!.avatarUrl!)
                            : null,
                        child: _currentUser?.avatarUrl == null
                            ? Text(
                                _currentUser?.fullName[0].toUpperCase() ?? 'U',
                                style: const TextStyle(color: Colors.black),
                              )
                            : null,
                      ),
                      if (isDesktop)
                        const Icon(Icons.arrow_drop_down, color: Colors.black),
                    ],
                  ),
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'profile',
                    child: Row(
                      children: [
                        Icon(Icons.person_outline),
                        SizedBox(width: 8),
                        Text('Trang cá nhân'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined),
                        SizedBox(width: 8),
                        Text('Cài đặt'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout),
                        SizedBox(width: 8),
                        Text('Đăng xuất'),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'logout') {
                    _handleLogout(context);
                  } else if (value == 'profile') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProfileScreen(),
                      ),
                    );
                  } else if (value == 'settings') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavIcon({
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Icon(
          icon,
          color: Colors.black,
          size: 24,
        ),
      ),
    );
  }
}


