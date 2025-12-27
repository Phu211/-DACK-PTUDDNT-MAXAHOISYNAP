import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../../core/theme/app_theme.dart';

class DarkModeSettingsScreen extends StatefulWidget {
  const DarkModeSettingsScreen({super.key});

  @override
  State<DarkModeSettingsScreen> createState() => _DarkModeSettingsScreenState();
}

class _DarkModeSettingsScreenState extends State<DarkModeSettingsScreen> {
  ThemeMode? _previewMode; // Mode đang xem trước (chưa apply)
  ThemeMode? _originalMode; // Mode ban đầu khi vào màn hình

  @override
  void initState() {
    super.initState();
    // Lưu mode ban đầu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final themeProvider = context.read<ThemeProvider>();
      setState(() {
        _originalMode = themeProvider.themeMode;
        _previewMode = themeProvider.themeMode;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final currentAppliedMode = themeProvider.themeMode;

    // Sử dụng previewMode nếu có, nếu không thì dùng mode hiện tại
    final displayMode = _previewMode ?? currentAppliedMode;

    // Xác định theme để hiển thị preview
    final previewTheme = _getThemeForMode(displayMode);

    return Theme(
      data: previewTheme,
      child: Scaffold(
        backgroundColor: previewTheme.scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Chế độ tối'), elevation: 0),
        body: Builder(
          builder: (context) {
            final theme = Theme.of(context);

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    color: theme.cardColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chọn chế độ hiển thị',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Chọn chế độ để xem trước, sau đó nhấn "Áp dụng" để lưu thay đổi',
                          style: TextStyle(fontSize: 14, color: theme.textTheme.bodySmall?.color),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Options
                  _buildOptionTile(
                    context: context,
                    theme: theme,
                    title: 'Tắt',
                    subtitle: 'Luôn sử dụng chế độ sáng',
                    icon: Icons.light_mode,
                    iconColor: Colors.amber,
                    isSelected: displayMode == ThemeMode.light,
                    onTap: () {
                      setState(() {
                        _previewMode = ThemeMode.light;
                      });
                    },
                  ),

                  _buildOptionTile(
                    context: context,
                    theme: theme,
                    title: 'Bật',
                    subtitle: 'Luôn sử dụng chế độ tối',
                    icon: Icons.dark_mode,
                    iconColor: Colors.blue,
                    isSelected: displayMode == ThemeMode.dark,
                    onTap: () {
                      setState(() {
                        _previewMode = ThemeMode.dark;
                      });
                    },
                  ),

                  _buildOptionTile(
                    context: context,
                    theme: theme,
                    title: 'Tự động',
                    subtitle: 'Theo cài đặt hệ thống',
                    icon: Icons.brightness_auto,
                    iconColor: Colors.purple,
                    isSelected: displayMode == ThemeMode.system,
                    onTap: () {
                      setState(() {
                        _previewMode = ThemeMode.system;
                      });
                    },
                  ),

                  const SizedBox(height: 16),

                  // Preview section
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.preview, color: theme.textTheme.bodyLarge?.color, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Xem trước',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: theme.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildPreviewCard(theme),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
        // Nút áp dụng ở bottom (nếu có thay đổi)
        bottomNavigationBar: _previewMode != null && _previewMode != _originalMode
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: previewTheme.scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2)),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _previewMode = _originalMode;
                            });
                          },
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            if (_previewMode != null) {
                              themeProvider.setThemeMode(_previewMode!);
                              setState(() {
                                _originalMode = _previewMode;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã áp dụng chế độ mới'),
                                  duration: Duration(seconds: 2),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          child: const Text('Áp dụng'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }

  ThemeData _getThemeForMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return AppTheme.lightTheme;
      case ThemeMode.dark:
        return AppTheme.darkTheme;
      case ThemeMode.system:
        // Lấy brightness từ hệ thống
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        return brightness == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme;
    }
  }

  Widget _buildOptionTile({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : theme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 14, color: theme.textTheme.bodySmall?.color)),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: Theme.of(context).primaryColor, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.primaryColor,
                child: const Icon(Icons.person, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: 100,
                      decoration: BoxDecoration(
                        color: theme.textTheme.bodyLarge?.color?.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 8,
                      width: 60,
                      decoration: BoxDecoration(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 8,
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.textTheme.bodyLarge?.color?.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 8,
            width: 200,
            decoration: BoxDecoration(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
