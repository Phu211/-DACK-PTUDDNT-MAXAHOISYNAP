import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/models/friend_request_model.dart';
import 'friend_requests_grid_screen.dart';
import 'people_you_may_know_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  String _selectedMenu = 'Trang chủ';
  final FriendService _friendService = FriendService();

  void _showSettings(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'Cài đặt bạn bè',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add, color: Colors.black),
              title: const Text(
                'Gợi ý bạn bè',
                style: TextStyle(color: Colors.black),
              ),
              subtitle: const Text(
                'Hiển thị gợi ý bạn bè dựa trên thông tin của bạn',
                style: TextStyle(color: Colors.black87, fontSize: 12),
              ),
              trailing: Switch(
                value: true,
                onChanged: (value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tính năng đang phát triển')),
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications, color: Colors.black),
              title: const Text(
                'Thông báo bạn bè',
                style: TextStyle(color: Colors.black),
              ),
              subtitle: const Text(
                'Nhận thông báo khi có bạn bè mới',
                style: TextStyle(color: Colors.black87, fontSize: 12),
              ),
              trailing: Switch(
                value: true,
                onChanged: (value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tính năng đang phát triển')),
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip, color: Colors.black),
              title: const Text(
                'Quyền riêng tư',
                style: TextStyle(color: Colors.black),
              ),
              subtitle: const Text(
                'Ai có thể gửi lời mời kết bạn',
                style: TextStyle(color: Colors.black87, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white70),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tính năng đang phát triển')),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập')));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // Left Sidebar
          Container(
            width: 320,
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header + search
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Bạn bè',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.settings_outlined,
                              color: Colors.white70,
                            ),
                            onPressed: () => _showSettings(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Tìm kiếm bạn bè',
                          hintStyle: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white60,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[800]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Colors.blueAccent,
                            ),
                          ),
                        ),
                        style: const TextStyle(color: Colors.black),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _QuickActionButton(
                        icon: Icons.person_add_alt_1,
                        label: 'Thêm bạn',
                        onTap: () {
                          setState(() => _selectedMenu = 'Lời mời kết bạn');
                        },
                      ),
                      const SizedBox(width: 8),
                      _QuickActionButton(
                        icon: Icons.group,
                        label: 'Tất cả',
                        onTap: () {
                          setState(() => _selectedMenu = 'Tất cả bạn bè');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Menu items
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _MenuItem(
                        label: 'Trang chủ',
                        icon: Icons.dashboard_rounded,
                        accentColor: Colors.blueAccent,
                        badge: StreamBuilder<List<FriendRequestModel>>(
                          stream: _friendService.getFriendRequests(
                            currentUser.id,
                          ),
                          builder: (context, snapshot) {
                            final count = snapshot.data?.length ?? 0;
                            return count > 0
                                ? Text(
                                    '$count',
                                    style: const TextStyle(fontSize: 12),
                                  )
                                : const SizedBox.shrink();
                          },
                        ),
                        isSelected: _selectedMenu == 'Trang chủ',
                        onTap: () =>
                            setState(() => _selectedMenu = 'Trang chủ'),
                      ),
                      _MenuItem(
                        label: 'Lời mời kết bạn',
                        icon: Icons.person_add_alt_1,
                        accentColor: Colors.orangeAccent,
                        badge: StreamBuilder<List<FriendRequestModel>>(
                          stream: _friendService.getFriendRequests(
                            currentUser.id,
                          ),
                          builder: (context, snapshot) {
                            final count = snapshot.data?.length ?? 0;
                            return count > 0
                                ? Text(
                                    '$count mới',
                                    style: const TextStyle(fontSize: 12),
                                  )
                                : const SizedBox.shrink();
                          },
                        ),
                        isSelected: _selectedMenu == 'Lời mời kết bạn',
                        onTap: () =>
                            setState(() => _selectedMenu = 'Lời mời kết bạn'),
                      ),
                      _MenuItem(
                        label: 'Gợi ý',
                        icon: Icons.lightbulb_outline,
                        accentColor: Colors.purpleAccent,
                        isSelected: _selectedMenu == 'Gợi ý',
                        onTap: () => setState(() => _selectedMenu = 'Gợi ý'),
                      ),
                      _MenuItem(
                        label: 'Tất cả bạn bè',
                        icon: Icons.people_alt_outlined,
                        accentColor: Colors.tealAccent,
                        isSelected: _selectedMenu == 'Tất cả bạn bè',
                        onTap: () =>
                            setState(() => _selectedMenu = 'Tất cả bạn bè'),
                      ),
                      _MenuItem(
                        label: 'Sinh nhật',
                        icon: Icons.cake_outlined,
                        accentColor: Colors.pinkAccent,
                        isSelected: _selectedMenu == 'Sinh nhật',
                        onTap: () =>
                            setState(() => _selectedMenu = 'Sinh nhật'),
                      ),
                      _MenuItem(
                        label: 'Danh sách tùy chỉnh',
                        icon: Icons.list_alt_outlined,
                        accentColor: Colors.greenAccent,
                        isSelected: _selectedMenu == 'Danh sách tùy chỉnh',
                        onTap: () => setState(
                          () => _selectedMenu = 'Danh sách tùy chỉnh',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Main Content
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedMenu) {
      case 'Trang chủ':
      case 'Lời mời kết bạn':
        return const FriendRequestsGridScreen();
      case 'Gợi ý':
        return const PeopleYouMayKnowScreen();
      case 'Tất cả bạn bè':
        return const AllFriendsScreen();
      case 'Sinh nhật':
        return const BirthdaysScreen();
      case 'Danh sách tùy chỉnh':
        return const CustomListsScreen();
      default:
        return const FriendRequestsGridScreen();
    }
  }
}

class _MenuItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? badge;

  const _MenuItem({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A1C23) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? accentColor.withOpacity(0.6)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(isSelected ? 1 : 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              icon,
              color: isSelected ? accentColor : Colors.white70,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withOpacity(0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    child: badge!,
                  ),
                ),
              ),
            ],
            if (!isSelected)
              const Icon(Icons.chevron_right, color: Colors.white30, size: 20),
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1C23),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[850]!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.black, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Placeholder screens
class AllFriendsScreen extends StatelessWidget {
  const AllFriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Tất cả bạn bè', style: TextStyle(color: Colors.black)),
    );
  }
}

class BirthdaysScreen extends StatelessWidget {
  const BirthdaysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Sinh nhật', style: TextStyle(color: Colors.black)),
    );
  }
}

class CustomListsScreen extends StatelessWidget {
  const CustomListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Danh sách tùy chỉnh', style: TextStyle(color: Colors.black)),
    );
  }
}

