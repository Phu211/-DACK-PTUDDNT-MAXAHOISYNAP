import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../data/models/highlight_model.dart';
import '../../data/services/highlight_service.dart';
import '../../data/services/story_service.dart';
import '../screens/stories/story_viewer_screen.dart';
import '../screens/stories/create_highlight_screen.dart';
import '../screens/stories/edit_highlight_screen.dart';

class ProfileHighlightsWidget extends StatelessWidget {
  final String userId;
  final bool isOwnProfile;

  const ProfileHighlightsWidget({
    super.key,
    required this.userId,
    this.isOwnProfile = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlightService = HighlightService();

    return StreamBuilder<List<HighlightModel>>(
      stream: highlightService.getHighlightsByUser(userId),
      builder: (context, snapshot) {
        // Debug logging
        debugPrint('ProfileHighlightsWidget: connectionState = ${snapshot.connectionState}');
        debugPrint('ProfileHighlightsWidget: hasData = ${snapshot.hasData}');
        debugPrint('ProfileHighlightsWidget: hasError = ${snapshot.hasError}');
        if (snapshot.hasError) {
          debugPrint('ProfileHighlightsWidget: error = ${snapshot.error}');
          debugPrint('ProfileHighlightsWidget: error stack = ${snapshot.stackTrace}');
        }
        if (snapshot.hasData) {
          debugPrint('ProfileHighlightsWidget: highlights count = ${snapshot.data!.length}');
        }
        
        // Nếu đang loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint('ProfileHighlightsWidget: Waiting for data...');
          return const SizedBox.shrink(); // Hoặc có thể hiển thị loading indicator
        }

        // Nếu có lỗi
        if (snapshot.hasError) {
          debugPrint('ProfileHighlightsWidget: Error loading highlights: ${snapshot.error}');
          // Vẫn hiển thị nút "Mới" nếu là own profile
          if (isOwnProfile) {
            return Container(
              height: 100,
              margin: const EdgeInsets.symmetric(vertical: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 1,
                itemBuilder: (context, index) => _buildNewHighlightButton(context, theme),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final highlights = snapshot.data ?? [];
        debugPrint('ProfileHighlightsWidget: Final highlights count = ${highlights.length}');

        // Nếu không có highlights
        if (highlights.isEmpty) {
          // Nếu là own profile, vẫn hiển thị nút "Mới"
          if (isOwnProfile) {
            return Container(
              height: 100,
              margin: const EdgeInsets.symmetric(vertical: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 1,
                itemBuilder: (context, index) => _buildNewHighlightButton(context, theme),
              ),
            );
          }
          // Nếu không phải own profile và không có highlights, không hiển thị gì
          return const SizedBox.shrink();
        }

        return Container(
          height: 100,
          margin: const EdgeInsets.symmetric(vertical: 16),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: highlights.length + (isOwnProfile ? 1 : 0),
            itemBuilder: (context, index) {
              // Nút tạo highlight mới (chỉ hiển thị cho chủ profile)
              if (isOwnProfile && index == highlights.length) {
                return _buildNewHighlightButton(context, theme);
              }

              final highlight = highlights[index];
              return _buildHighlightCircle(context, theme, highlight);
            },
          ),
        );
      },
    );
  }

  Widget _buildHighlightCircle(
    BuildContext context,
    ThemeData theme,
    HighlightModel highlight,
  ) {
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: () => _showHighlightStories(context, highlight),
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.dividerColor, width: 2),
                    image: highlight.coverImageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(highlight.coverImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: highlight.coverImageUrl == null
                      ? Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.cardColor,
                          ),
                          child: Center(
                            child: Text(
                              highlight.iconName ?? '📌',
                              style: const TextStyle(fontSize: 32),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
              // Edit button (chỉ hiển thị cho chủ profile)
              if (isOwnProfile)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _showHighlightOptions(context, highlight),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        Icons.edit,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            highlight.title,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNewHighlightButton(BuildContext context, ThemeData theme) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CreateHighlightScreen(),
          ),
        );
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.dividerColor,
                  width: 2,
                  style: BorderStyle.solid,
                ),
                color: theme.cardColor,
              ),
              child: Icon(Icons.add, color: theme.iconTheme.color, size: 32),
            ),
            const SizedBox(height: 4),
            Text(
              'Mới',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHighlightStories(
    BuildContext context,
    HighlightModel highlight,
  ) async {
    if (highlight.storyIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Highlight này chưa có story nào')),
      );
      return;
    }

    // Lấy stories trực tiếp từ IDs (bao gồm cả story đã hết hạn)
    final storyService = StoryService();
    final highlightStories = await storyService.fetchStoriesByIds(
      highlight.storyIds,
    );

    if (highlightStories.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy stories')),
        );
      }
      return;
    }

    if (context.mounted) {
      // Navigate to story viewer với danh sách stories từ highlight
      // allowExpiredStories: true để cho phép xem story đã hết hạn
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            userId: userId,
            allowExpiredStories: true, // Cho phép xem story đã hết hạn
            initialStories: highlightStories, // Truyền trực tiếp danh sách stories (kể cả expired)
            initialStoryId: highlightStories.first.id,
          ),
        ),
      );
    }
  }

  void _showHighlightOptions(BuildContext context, HighlightModel highlight) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Chỉnh sửa highlight'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditHighlightScreen(highlight: highlight),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Xóa highlight', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(context).pop();
                _deleteHighlight(context, highlight);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Hủy'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteHighlight(BuildContext context, HighlightModel highlight) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa highlight'),
        content: Text('Bạn có chắc chắn muốn xóa highlight "${highlight.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final highlightService = HighlightService();
      await highlightService.deleteHighlight(highlight.id);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa highlight'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể xóa highlight: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
