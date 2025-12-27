import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';
import '../../../data/services/menu_preferences_service.dart';
import '../../providers/auth_provider.dart';
import '../feed/feed_tabs_screen.dart';
import '../saved/saved_posts_screen.dart';
import '../groups/groups_screen.dart';
import '../reels/reels_screen.dart';
import '../games/games_screen.dart';
import '../settings/settings_screen.dart';
import '../friends/friends_tabs_screen.dart';
import '../memories/memories_screen.dart';
import '../settings/time_management_screen.dart';
import '../settings/language_screen.dart';
import '../settings/dark_mode_settings_screen.dart';
import '../analytics/analytics_screen.dart';
import 'hide_menu_items_dialog.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  bool _isSettingsExpanded = false;
  final MenuPreferencesService _menuPreferencesService =
      MenuPreferencesService();
  List<String> _hiddenMenuItems = [];

  @override
  void initState() {
    super.initState();
    _loadHiddenMenuItems();
  }

  Future<void> _loadHiddenMenuItems() async {
    try {
      final hiddenItems = await _menuPreferencesService.getHiddenMenuItems();
      setState(() {
        _hiddenMenuItems = hiddenItems;
      });
    } catch (e) {
      // Ignore errors
    }
  }

  bool _isMenuItemHidden(String itemId) {
    return _hiddenMenuItems.contains(itemId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          strings?.appTitle ?? 'Synap',
          style: TextStyle(color: theme.textTheme.titleLarge?.color),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Core features vertical list
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Column(
                children: [
                  if (!_isMenuItemHidden('friends'))
                    _buildFeatureCard(
                      id: 'friends',
                      icon: Icons.people,
                      iconColor: Colors.blue,
                      title: strings?.friends ?? 'Bạn bè',
                      subtitle: strings?.menuFriendsOnline ?? '23 người online',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FriendsTabsScreen(),
                          ),
                        );
                      },
                    ),
                  if (!_isMenuItemHidden('memories'))
                    _buildFeatureCard(
                      id: 'memories',
                      icon: Icons.access_time,
                      iconColor: Colors.blue,
                      title: strings?.menuMemories ?? 'Kỷ niệm',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MemoriesScreen(),
                          ),
                        );
                      },
                    ),
                  if (!_isMenuItemHidden('find_friends'))
                    _buildFeatureCard(
                      id: 'find_friends',
                      icon: Icons.person_search,
                      iconColor: Colors.black87,
                      title: strings?.menuFindFriends ?? 'Tìm bạn bè',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const FriendsTabsScreen(initialTabIndex: 0),
                          ),
                        );
                      },
                    ),
                  if (!_isMenuItemHidden('feed_preferences'))
                    _buildFeatureCard(
                      id: 'feed_preferences',
                      icon: Icons.access_time,
                      iconColor: Colors.blue,
                      title: strings?.menuFeed ?? 'Bảng feed',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FeedTabsScreen(),
                          ),
                        );
                      },
                    ),
                  if (!_isMenuItemHidden('games'))
                    _buildFeatureCard(
                      id: 'games',
                      icon: Icons.sports_esports,
                      iconColor: Colors.blue,
                      title: strings?.menuGames ?? 'Game',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const GamesScreen(),
                          ),
                        );
                      },
                    ),
                  if (!_isMenuItemHidden('saved'))
                    _buildFeatureCard(
                      id: 'saved',
                      icon: Icons.bookmark,
                      iconColor: Colors.purple,
                      title: strings?.menuSaved ?? 'Đã lưu',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SavedPostsScreen(),
                          ),
                        );
                      },
                    ),
                  if (!_isMenuItemHidden('analytics'))
                    _buildFeatureCard(
                      id: 'analytics',
                      icon: Icons.analytics,
                      iconColor: Colors.blue,
                      title: strings?.menuAnalytics ?? 'Thống kê cá nhân',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AnalyticsScreen(),
                          ),
                        );
                      },
                    ),
                  if (!_isMenuItemHidden('groups'))
                    _buildFeatureCard(
                      id: 'groups',
                      icon: Icons.group,
                      iconColor: Colors.blue,
                      title: strings?.menuGroups ?? 'Nhóm',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const GroupsScreen(),
                          ),
                        );
                      },
                    ),
                  if (!_isMenuItemHidden('reels'))
                    _buildFeatureCard(
                      id: 'reels',
                      icon: Icons.video_library,
                      iconColor: Colors.red,
                      title: strings?.menuReels ?? 'Thước phim',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ReelsScreen(),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            // Hide less button
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ElevatedButton(
                  onPressed: () {
                    _showHideMenuItemsDialog();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(strings?.menuHideLess ?? 'Ẩn bớt'),
                ),
              ),
            ),

            // Settings & Privacy section
            _buildExpandableSection(
              icon: Icons.settings,
              title:
                  strings?.menuSettingsPrivacy ?? 'Cài đặt và quyền riêng tư',
              isExpanded: _isSettingsExpanded,
              onTap: () {
                setState(() {
                  _isSettingsExpanded = !_isSettingsExpanded;
                });
              },
              children: [
                _buildMenuItem(
                  icon: Icons.person_outline,
                  title: strings?.menuSettings ?? 'Cài đặt',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.access_time,
                  title: strings?.menuTimeManagement ?? 'Quản lý thời gian',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TimeManagementScreen(),
                      ),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.dark_mode,
                  title: strings?.menuDarkMode ?? 'Chế độ tối',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DarkModeSettingsScreen(),
                      ),
                    );
                  },
                ),
                _buildMenuItem(
                  icon: Icons.language,
                  title: strings?.menuLanguage ?? 'Ngôn ngữ',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LanguageScreen()),
                    );
                  },
                ),
              ],
            ),

            // Logout button
            InkWell(
              onTap: () => _handleLogout(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: Theme.of(context).cardColor,
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        strings?.logout ?? 'Đăng xuất',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required String id,
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.textTheme.bodySmall?.color ??
                            Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableSection({
    required IconData icon,
    required String title,
    required bool isExpanded,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: theme.cardColor,
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...children,
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: theme.cardColor,
        child: Row(
          children: [
            const SizedBox(width: 40),
            Icon(
              icon,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    if (!mounted) return;
    
    final strings = AppLocalizations.of(context);
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(strings?.logout ?? 'Đăng xuất'),
        content: Text(
          strings?.logoutConfirm ?? 'Bạn có chắc chắn muốn đăng xuất?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings?.cancel ?? 'Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text(strings?.logout ?? 'Đăng xuất'),
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
      final authProvider = context.read<AuthProvider>();
      await authProvider.signOut();
      
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

  void _showHideMenuItemsDialog() {
    final allMenuItems = [
      {'id': 'friends', 'title': 'Bạn bè', 'icon': Icons.people},
      {'id': 'memories', 'title': 'Kỷ niệm', 'icon': Icons.access_time},
      {
        'id': 'find_friends',
        'title': 'Tìm bạn bè',
        'icon': Icons.person_search,
      },
      {
        'id': 'feed_preferences',
        'title': 'Bảng feed',
        'icon': Icons.access_time,
      },
      {'id': 'games', 'title': 'Game', 'icon': Icons.sports_esports},
      {'id': 'saved', 'title': 'Đã lưu', 'icon': Icons.bookmark},
      {'id': 'analytics', 'title': 'Thống kê cá nhân', 'icon': Icons.analytics},
      {'id': 'groups', 'title': 'Nhóm', 'icon': Icons.group},
      {'id': 'reels', 'title': 'Thước phim', 'icon': Icons.video_library},
    ];

    showDialog(
      context: context,
      builder: (ctx) => HideMenuItemsDialog(
        allMenuItems: allMenuItems,
        hiddenItems: List.from(_hiddenMenuItems),
        onSave: (hiddenItems) async {
          await _menuPreferencesService.saveHiddenMenuItems(hiddenItems);
          setState(() {
            _hiddenMenuItems = hiddenItems;
          });
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đã cập nhật danh sách menu'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }
}
