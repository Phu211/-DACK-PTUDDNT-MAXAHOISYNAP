import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../data/services/user_service.dart';
import '../../data/models/user_model.dart';
import '../screens/post/create_post_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/messages/messages_list_screen.dart';
import 'synap_logo.dart';

class HeaderNavigationBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const HeaderNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  State<HeaderNavigationBar> createState() => _HeaderNavigationBarState();
}

class _HeaderNavigationBarState extends State<HeaderNavigationBar> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // Header bar
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Logo
                Row(
                  children: [
                    const SynapLogo(size: 32),
                    const SizedBox(width: 8),
                    Text(
                      'Synap',
                      style: TextStyle(
                        color: theme.primaryColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Right side icons
                IconButton(
                  icon: Icon(
                    Icons.add_box_outlined,
                    size: 24,
                    color: theme.iconTheme.color,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreatePostScreen(),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.search,
                    size: 24,
                    color: theme.iconTheme.color,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SearchScreen(),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Stack(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 24,
                        color: theme.iconTheme.color,
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.bolt,
                            size: 10,
                            color: theme.scaffoldBackgroundColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MessagesListScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Navigation bar
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _NavItem(
                  icon: Icons.home,
                  isSelected: widget.selectedIndex == 0,
                  onTap: () => widget.onItemSelected(0),
                ),
                _NavItem(
                  icon: Icons.video_library_outlined,
                  isSelected: widget.selectedIndex == 1,
                  onTap: () => widget.onItemSelected(1),
                ),
                _NavItem(
                  icon: Icons.people_outline,
                  isSelected: widget.selectedIndex == 2,
                  onTap: () => widget.onItemSelected(2),
                ),
                _NavItem(
                  icon: Icons.storefront_outlined,
                  isSelected: widget.selectedIndex == 3,
                  onTap: () => widget.onItemSelected(3),
                ),
                _NavItem(
                  icon: Icons.notifications_outlined,
                  isSelected: widget.selectedIndex == 4,
                  onTap: () => widget.onItemSelected(4),
                ),
                _NavItem(
                  icon: null,
                  isSelected: widget.selectedIndex == 5,
                  onTap: () => widget.onItemSelected(5),
                  isProfile: true,
                  avatarUrl: _currentUser?.avatarUrl,
                  userName: _currentUser?.fullName,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isProfile;
  final String? avatarUrl;
  final String? userName;

  const _NavItem({
    this.icon,
    required this.isSelected,
    required this.onTap,
    this.isProfile = false,
    this.avatarUrl,
    this.userName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? theme.primaryColor : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Center(
            child: isProfile
                ? Stack(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.cardColor,
                        backgroundImage: avatarUrl != null
                            ? NetworkImage(avatarUrl!)
                            : null,
                        child: avatarUrl == null
                            ? Text(
                                userName?[0].toUpperCase() ?? 'U',
                                style: TextStyle(
                                  color: theme.textTheme.bodyLarge?.color,
                                  fontSize: 14,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.scaffoldBackgroundColor,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.menu,
                            size: 10,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
                    ],
                  )
                : icon == Icons.home
                ? _buildHomeIcon(isSelected, theme)
                : Icon(
                    icon,
                    color: isSelected
                        ? theme.primaryColor
                        : theme.iconTheme.color?.withOpacity(0.6),
                    size: 24,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeIcon(bool isSelected, ThemeData theme) {
    if (isSelected) {
      // Filled blue home icon with white rectangle inside (like Facebook)
      return CustomPaint(
        size: const Size(24, 24),
        painter: _HomeIconPainter(theme),
      );
    } else {
      return Icon(
        Icons.home_outlined,
        color: theme.iconTheme.color?.withOpacity(0.6),
        size: 24,
      );
    }
  }
}

class _HomeIconPainter extends CustomPainter {
  final ThemeData theme;

  _HomeIconPainter(this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = theme.primaryColor
      ..style = PaintingStyle.fill;

    // Draw house shape (roof + base)
    final path = Path();
    // Roof (triangle)
    path.moveTo(size.width / 2, 0);
    path.lineTo(0, size.height * 0.4);
    path.lineTo(size.width, size.height * 0.4);
    path.close();

    // Base (rectangle)
    path.addRect(
      Rect.fromLTWH(0, size.height * 0.4, size.width, size.height * 0.6),
    );

    canvas.drawPath(path, paint);

    // Draw rectangle inside using scaffold background color
    final innerPaint = Paint()
      ..color = theme.scaffoldBackgroundColor
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.7),
          width: size.width * 0.35,
          height: size.height * 0.25,
        ),
        const Radius.circular(1),
      ),
      innerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
