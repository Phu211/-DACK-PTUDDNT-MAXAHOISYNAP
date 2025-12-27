import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/story_model.dart';
import '../../../data/services/story_service.dart';
import '../stories/story_viewer_screen.dart';

class MemoriesScreen extends StatelessWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final storyService = StoryService();

    if (currentUser == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Text(
            'Vui lòng đăng nhập',
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Kỷ niệm',
          style: TextStyle(
            color: theme.textTheme.titleLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<List<StoryModel>>(
        stream: storyService.getAllStoriesByUser(currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: theme.primaryColor),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Lỗi: ${snapshot.error}',
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
            );
          }

          final allStories = snapshot.data ?? [];
          
          // Debug logs
          if (kDebugMode) {
            debugPrint('=== MEMORIES SCREEN ===');
            debugPrint('Total stories fetched: ${allStories.length}');
            debugPrint('Current time: ${DateTime.now()}');
            if (allStories.isNotEmpty) {
              for (var story in allStories) {
                final now = DateTime.now();
                final isExpired = now.isAfter(story.expiresAt);
                debugPrint('Story ID: ${story.id}');
                debugPrint('  createdAt: ${story.createdAt}');
                debugPrint('  expiresAt: ${story.expiresAt}');
                debugPrint('  now: $now');
                debugPrint('  now.isAfter(expiresAt): $isExpired');
                debugPrint('  story.isExpired: ${story.isExpired}');
                debugPrint('  Time difference: ${now.difference(story.expiresAt).inHours} hours');
              }
            }
          }
          
          final expiredStories = allStories.where((s) => s.isExpired).toList();
          
          if (kDebugMode) {
            debugPrint('Expired stories count: ${expiredStories.length}');
            if (expiredStories.isNotEmpty) {
              debugPrint('First expired story ID: ${expiredStories.first.id}');
              debugPrint('First expired story expiresAt: ${expiredStories.first.expiresAt}');
            }
          }

          if (expiredStories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.access_time,
                    size: 64,
                    color: theme.iconTheme.color?.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Bạn chưa có story nào đã hết hạn',
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Các story sẽ xuất hiện ở đây sau 24 giờ',
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }

          // Group stories by date
          final storiesByDate = <String, List<StoryModel>>{};
          for (final story in expiredStories) {
            final dateKey = _formatDateKey(story.createdAt);
            storiesByDate.putIfAbsent(dateKey, () => []).add(story);
          }

          // Sort dates (newest first)
          final sortedDates = storiesByDate.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedDates.length,
            itemBuilder: (context, index) {
              final dateKey = sortedDates[index];
              final dateStories = storiesByDate[dateKey]!;
              // Sort stories in each date group (newest first)
              dateStories.sort((a, b) => b.createdAt.compareTo(a.createdAt));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: 12,
                      top: index > 0 ? 24 : 0,
                    ),
                    child: Text(
                      _formatDateHeader(dateKey),
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio:
                              0.85, // Tăng từ 0.8 để tránh overflow
                        ),
                    itemCount: dateStories.length,
                    itemBuilder: (context, storyIndex) {
                      final story = dateStories[storyIndex];
                      return _MemoryStoryCard(
                        story: story,
                        theme: theme,
                        onTap: () {
                          // Debug: log story được chọn
                          if (kDebugMode) {
                            debugPrint('=== MEMORIES: STORY TAPPED ===');
                            debugPrint('Selected story ID: ${story.id}');
                            debugPrint(
                              'Selected story createdAt: ${story.createdAt}',
                            );
                            debugPrint(
                              'Total stories in date group: ${dateStories.length}',
                            );
                            debugPrint(
                              'Story index in date group: $storyIndex',
                            );
                            debugPrint(
                              'All story IDs in date group: ${dateStories.map((s) => s.id).toList()}',
                            );
                          }

                          // Navigate to story viewer với allowExpiredStories = true
                          // và initialStoryId để bắt đầu từ story được chọn
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StoryViewerScreen(
                                userId: currentUser.id,
                                allowExpiredStories: true,
                                initialStoryId:
                                    story.id, // Truyền ID của story được chọn
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _formatDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateHeader(String dateKey) {
    final parts = dateKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    final date = DateTime(year, month, day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) {
      return 'Hôm nay';
    } else if (date == yesterday) {
      return 'Hôm qua';
    } else {
      final months = [
        'Tháng 1',
        'Tháng 2',
        'Tháng 3',
        'Tháng 4',
        'Tháng 5',
        'Tháng 6',
        'Tháng 7',
        'Tháng 8',
        'Tháng 9',
        'Tháng 10',
        'Tháng 11',
        'Tháng 12',
      ];
      return '${day} ${months[month - 1]} ${year}';
    }
  }
}

class _MemoryStoryCard extends StatelessWidget {
  final StoryModel story;
  final VoidCallback onTap;
  final ThemeData theme;

  const _MemoryStoryCard({
    required this.story,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: story.isExpired ? theme.dividerColor : theme.primaryColor,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Story image/video thumbnail
              if (story.imageUrl != null)
                Image.network(
                  story.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: theme.cardColor,
                      child: Icon(
                        Icons.broken_image,
                        color: theme.iconTheme.color?.withOpacity(0.6),
                        size: 40,
                      ),
                    );
                  },
                )
              else if (story.videoUrl != null)
                Container(
                  color: theme.cardColor,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.play_circle_filled,
                        color: theme.iconTheme.color,
                        size: 40,
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.videocam,
                            color: theme.iconTheme.color,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (story.text != null)
                Container(
                  color: theme.primaryColor,
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: Text(
                      story.text!,
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Container(
                  color: Colors.grey[300],
                  child: const Icon(
                    Icons.auto_stories,
                    color: Colors.grey,
                    size: 40,
                  ),
                ),
              // Overlay gradient for better text visibility
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                ),
              ),
              // Time indicator
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _formatTime(story.createdAt),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              offset: Offset(1, 1),
                              blurRadius: 2,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (story.isExpired) ...[
                      const SizedBox(width: 4),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[700]!.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Đã hết hạn',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
