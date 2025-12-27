import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../../../data/models/story_model.dart';
import '../../../data/models/story_element_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/story_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/models/post_model.dart';
import '../../providers/auth_provider.dart';
import '../../../core/utils/error_message_helper.dart';
import '../../widgets/post_card.dart';
import '../messages/chat_screen.dart';

class StoryViewerScreen extends StatefulWidget {
  final String userId;
  final List<String>?
  usersWithStories; // Danh sách users có stories để chuyển đổi
  final int? initialUserIndex; // Index của user hiện tại trong danh sách
  final bool
  allowExpiredStories; // Cho phép xem lại story đã hết hạn (cho màn hình Kỷ niệm)
  final String?
  initialStoryId; // ID của story để bắt đầu xem (cho màn hình Kỷ niệm)
  final List<StoryModel>?
  initialStories; // Danh sách stories đã được load sẵn (cho highlights)

  const StoryViewerScreen({
    super.key,
    required this.userId,
    this.usersWithStories,
    this.initialUserIndex,
    this.allowExpiredStories = false,
    this.initialStoryId,
    this.initialStories,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  final StoryService _storyService = StoryService();
  final UserService _userService = UserService();
  final FirestoreService _firestoreService = FirestoreService();

  UserModel? _user;
  int _currentIndex = 0;
  late PageController _pageController;
  final List<_FloatingReaction> _floatingReactions = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentMusicUrl;
  
  // Post data for shared posts in story
  PostModel? _sharedPost;

  // Progress bar và timer
  Timer? _progressTimer;
  double _currentProgress = 0.0;
  bool _isPaused = false;
  Duration _currentStoryDuration = const Duration(
    seconds: 5,
  ); // Duration thực tế của story
  bool _isMediaReady = false; // Đánh dấu video/nhạc đã sẵn sàng
  StreamSubscription<Duration>? _videoPositionSubscription;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  List<StoryModel> _stories = [];
  bool _isLoadingStories = true;
  VideoPlayerController? _videoController;
  Future<void>? _initializeVideoFuture;

  // Điều khiển âm thanh
  bool _isMuted = false;

  // Danh sách users có stories để chuyển đổi
  List<String> _usersWithStories = [];
  int _currentUserIndex = 0;

  // Friend service để load danh sách users
  final FriendService _friendService = FriendService();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Cấu hình AudioPlayer
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    // Set volume mặc định
    _audioPlayer.setVolume(_isMuted ? 0.0 : 1.0);
    _loadUser();
    _loadUsersWithStories();
    _loadStories();
  }

  String? _lastLoadedUserId;
  bool _isLoading = false;

  Future<void> _loadStories() async {
    // Nếu có initialStories, sử dụng trực tiếp (cho highlights)
    if (widget.initialStories != null && widget.initialStories!.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('=== STORY VIEWER: USING INITIAL STORIES ===');
        debugPrint('Total stories: ${widget.initialStories!.length}');
      }
      
      int initialIndex = 0;
      if (widget.initialStoryId != null && widget.initialStoryId!.isNotEmpty) {
        final foundIndex = widget.initialStories!.indexWhere(
          (story) => story.id == widget.initialStoryId,
        );
        if (foundIndex != -1) {
          initialIndex = foundIndex;
        }
      }
      
      if (mounted) {
        setState(() {
          _stories = widget.initialStories!;
          _isLoadingStories = false;
          _lastLoadedUserId = widget.userId;
          _currentIndex = initialIndex;
          _currentProgress = 0.0;
          _progressTimer?.cancel();
        });
        
        // Jump PageController đến đúng index
        if (widget.initialStories!.isNotEmpty && initialIndex > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients && initialIndex < _stories.length) {
              if (kDebugMode) {
                debugPrint('Jumping to story index: $initialIndex');
              }
              _pageController.jumpToPage(initialIndex);
            }
          });
        }
        
        // Khởi động timer cho story được chọn
        if (widget.initialStories!.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && initialIndex < _stories.length) {
              _onStoryChanged(initialIndex);
            }
          });
        }
      }
      return;
    }
    
    // Chỉ load lại nếu userId thay đổi và chưa đang load
    if ((_lastLoadedUserId == widget.userId && _stories.isNotEmpty) ||
        _isLoading) {
      return;
    }

    _isLoading = true;
    setState(() {
      _isLoadingStories = true;
    });

    try {
      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;

      if (!mounted) return;

      final stories = await _storyService.fetchStoriesByUserOnce(
        widget.userId,
        viewerId: currentUser?.id,
        includeExpired: widget.allowExpiredStories,
      );

      if (!mounted) return;
      
      // Đảm bảo stories được sort giống như trong MemoriesScreen
      // (theo createdAt descending - mới nhất trước)
      stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      if (kDebugMode) {
        debugPrint('=== STORY VIEWER: LOADED STORIES ===');
        debugPrint('Total stories loaded: ${stories.length}');
        debugPrint('InitialStoryId from widget: ${widget.initialStoryId}');
        debugPrint('AllowExpiredStories: ${widget.allowExpiredStories}');
        debugPrint('All story IDs (sorted by createdAt desc):');
        for (int i = 0; i < stories.length; i++) {
          debugPrint('  [$i] id=${stories[i].id}, createdAt=${stories[i].createdAt}');
        }
      }

      // Tìm index của story được chọn (nếu có initialStoryId)
      int initialIndex = 0;
      if (widget.initialStoryId != null &&
          widget.initialStoryId!.isNotEmpty) {
        final foundIndex = stories.indexWhere(
          (story) => story.id == widget.initialStoryId,
        );
        if (foundIndex != -1) {
          initialIndex = foundIndex;
          if (kDebugMode) {
            debugPrint('=== FOUND STORY IN LIST ===');
            debugPrint('InitialStoryId: ${widget.initialStoryId}');
            debugPrint('Found index: $initialIndex');
            debugPrint('Total stories: ${stories.length}');
            if (initialIndex < stories.length) {
              debugPrint(
                'Story at index $initialIndex: id=${stories[initialIndex].id}, createdAt=${stories[initialIndex].createdAt}',
              );
            }
            // Log một vài stories xung quanh để debug
            final start = (initialIndex - 2).clamp(0, stories.length - 1);
            final end = (initialIndex + 2).clamp(0, stories.length - 1);
            debugPrint('Stories around index $initialIndex:');
            for (int i = start; i <= end; i++) {
              debugPrint(
                '  [$i] id=${stories[i].id}, createdAt=${stories[i].createdAt}',
              );
            }
          }
        } else {
          if (kDebugMode) {
            debugPrint('=== STORY NOT FOUND IN LIST ===');
            debugPrint('InitialStoryId: ${widget.initialStoryId}');
            debugPrint('Total stories: ${stories.length}');
            debugPrint(
              'Story IDs in list: ${stories.map((s) => s.id).toList()}',
            );
            debugPrint('This might be a timing issue - stories list changed between MemoriesScreen and StoryViewerScreen');
          }
        }
      }
      
      if (!mounted) {
        _isLoading = false;
        return;
      }

      final finalIndex = initialIndex.clamp(0, stories.length - 1);
      
      setState(() {
        _stories = stories;
        _isLoadingStories = false;
        _lastLoadedUserId = widget.userId;
        // Set index về story được chọn hoặc story đầu tiên
        _currentIndex = finalIndex;
        _currentProgress = 0.0;
        _progressTimer?.cancel();
      });
      
      if (kDebugMode) {
        debugPrint('=== SET INITIAL INDEX ===');
        debugPrint('InitialIndex: $initialIndex');
        debugPrint('Clamped index: $finalIndex');
        debugPrint('CurrentIndex set to: $_currentIndex');
        debugPrint('Stories length: ${_stories.length}');
        if (_currentIndex < _stories.length) {
          debugPrint('Story at currentIndex: id=${_stories[_currentIndex].id}, createdAt=${_stories[_currentIndex].createdAt}');
        }
      }
      
      // Jump PageController đến đúng index sau khi stories được load
      if (stories.isNotEmpty && mounted && finalIndex > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients && finalIndex < _stories.length) {
            if (kDebugMode) {
              debugPrint('=== JUMPING PAGE CONTROLLER ===');
              debugPrint('Jumping to index: $finalIndex');
            }
            _pageController.jumpToPage(finalIndex);
          }
        });
      }
      
      // Khởi động timer cho story được chọn
      if (stories.isNotEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && finalIndex < _stories.length) {
            _onStoryChanged(finalIndex);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStories = false;
        });
      }
    } finally {
      _isLoading = false;
    }
  }

  @override
  void didUpdateWidget(StoryViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload stories nếu userId thay đổi
    if (oldWidget.userId != widget.userId && !_isLoading) {
      _loadStories();
      _loadUser();
    }
  }

  Future<void> _loadUsersWithStories() async {
    // Nếu đã có danh sách users từ widget, sử dụng nó
    if (widget.usersWithStories != null && widget.initialUserIndex != null) {
      setState(() {
        _usersWithStories = widget.usersWithStories!;
        _currentUserIndex = widget.initialUserIndex!;
      });
      return;
    }

    // Nếu không, load danh sách từ friends
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    try {
      final friendIds = await _friendService.getFriends(currentUser.id);
      final allUserIds = [...friendIds, currentUser.id];

      setState(() {
        _usersWithStories = allUserIds;
        _currentUserIndex = _usersWithStories.indexOf(widget.userId);
        if (_currentUserIndex == -1) _currentUserIndex = 0;
      });
    } catch (e) {
      // Ignore error
    }
  }

  Future<void> _loadUser() async {
    final user = await _userService.getUserById(widget.userId);
    if (mounted) {
      setState(() {
        _user = user;
      });
    }
  }

  // Helper function để format thời gian
  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} phút trước';
    } else {
      return 'Vừa xong';
    }
  }

  // Toggle mute/unmute
  void _toggleMute() async {
    setState(() {
      _isMuted = !_isMuted;
    });
    final volume = _isMuted ? 0.0 : 1.0;
    await _audioPlayer.setVolume(volume);

    // Cập nhật volume của video:
    // - Nếu có nhạc: video luôn tắt tiếng (volume = 0)
    // - Nếu không có nhạc: video volume theo _isMuted
    if (_stories.isNotEmpty) {
      final currentStory = _stories[_currentIndex];
      await _updateVideoVolume(currentStory);
    }

    // Nếu đang unmute và có nhạc, đảm bảo nhạc vẫn phát
    if (!_isMuted && _currentMusicUrl != null && _stories.isNotEmpty) {
      final currentStory = _stories[_currentIndex];
      if (currentStory.musicUrl != null && currentStory.musicUrl!.isNotEmpty) {
        // Kiểm tra trạng thái player và resume nếu cần
        final state = _audioPlayer.state;
        if (state == PlayerState.stopped || state == PlayerState.completed) {
        try {
          await _audioPlayer.play(UrlSource(currentStory.musicUrl!));
          } catch (e) {
            if (mounted) {
              debugPrint('Lỗi phát lại nhạc: $e');
            }
          }
        }
      }
    }
  }

  // Extract postId from URL
  String? _extractPostIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Kiểm tra nếu là link bài viết: https://synap.app/post/{postId}
      if (uri.host.contains('synap.app') && uri.path.startsWith('/post/')) {
        final postId = uri.pathSegments.last;
        if (postId.isNotEmpty) {
          return postId;
        }
      }
    } catch (e) {
      // Nếu không parse được, thử regex
      final regex = RegExp(r'https?://[^/]+/post/([^/?\s]+)');
      final match = regex.firstMatch(url);
      if (match != null && match.groupCount >= 1) {
        return match.group(1);
      }
    }
    return null;
  }

  // Load post data if story has post link
  Future<void> _loadSharedPost(StoryModel story) async {
    if (story.link == null || story.link!.url.isEmpty) {
      setState(() {
        _sharedPost = null;
      });
      return;
    }

    final postId = _extractPostIdFromUrl(story.link!.url);
    if (postId == null) {
      setState(() {
        _sharedPost = null;
      });
      return;
    }

    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        setState(() {
          _sharedPost = null;
        });
        return;
      }

      final post = await _firestoreService.getPost(
        postId,
        viewerId: currentUser.id,
      );

      if (mounted) {
        setState(() {
          _sharedPost = post;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sharedPost = null;
        });
      }
    }
  }

  // Xử lý swipe up để mở link/sticker hoặc hiển thị bài viết
  Future<void> _handleSwipeUp(StoryModel story) async {
    if (story.link != null && story.link!.url.isNotEmpty) {
      // Kiểm tra nếu là link bài viết
      final postId = _extractPostIdFromUrl(story.link!.url);
      if (postId != null) {
        // Hiển thị dialog với PostCard
        if (mounted) {
          if (_sharedPost != null) {
            showDialog(
              context: context,
              barrierColor: Colors.black87,
              builder: (ctx) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(16),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 600),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header với nút đóng
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey, width: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Bài viết được chia sẻ',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      // PostCard
                      Flexible(
                        child: SingleChildScrollView(
                          child: PostCard(post: _sharedPost!),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          } else {
            // Nếu chưa load được post, thử load lại
            await _loadSharedPost(story);
            if (mounted && _sharedPost != null) {
              _handleSwipeUp(story); // Gọi lại để hiển thị
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Không thể tải bài viết')),
              );
            }
          }
        }
      } else {
        // Mở link thông thường
        final uri = Uri.parse(story.link!.url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Không thể mở link')));
          }
        }
      }
    } else if (story.stickers.isNotEmpty) {
      // Hiển thị thông tin sticker
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Stickers'),
            content: Text('Story có ${story.stickers.length} sticker'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    }
  }

  // Xử lý swipe down để đóng story
  void _handleSwipeDown() {
    Navigator.of(context).pop();
  }

  // Xử lý swipe left/right để chuyển sang story của người khác
  void _handleSwipeToNextUser() {
    if (_usersWithStories.isEmpty) return;

    final nextIndex = (_currentUserIndex + 1) % _usersWithStories.length;
    final nextUserId = _usersWithStories[nextIndex];

    if (nextUserId != widget.userId) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            userId: nextUserId,
            usersWithStories: _usersWithStories,
            initialUserIndex: nextIndex,
          ),
        ),
      );
    }
  }

  void _handleSwipeToPreviousUser() {
    if (!mounted || _usersWithStories.isEmpty) return;

    final prevIndex =
        (_currentUserIndex - 1 + _usersWithStories.length) %
        _usersWithStories.length;
    final prevUserId = _usersWithStories[prevIndex];

    if (prevUserId != widget.userId && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            userId: prevUserId,
            usersWithStories: _usersWithStories,
            initialUserIndex: prevIndex,
          ),
        ),
      );
    }
  }

  // Reply story (mở chat với story owner)
  void _replyToStory(StoryModel story) async {
    if (!mounted) return;
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser != null && story.userId != currentUser.id && mounted) {
      try {
        final storyOwner = await _userService.getUserById(story.userId);
        if (storyOwner != null && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(otherUser: storyOwner),
            ),
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không tìm thấy người dùng')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: $e')),
          );
        }
      }
    }
  }


  // Lưu story về thiết bị
  Future<void> _saveStoryToDevice(StoryModel story) async {
    try {
      late final String url;
      late final String fileName;

      if (story.imageUrl != null && story.imageUrl!.isNotEmpty) {
        url = story.imageUrl!;
        fileName =
            'story_${story.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      } else if (story.videoUrl != null && story.videoUrl!.isNotEmpty) {
        url = story.videoUrl!;
        fileName =
            'story_${story.id}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Story này không có ảnh/video để lưu'),
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đang tải...')));
      }

      // Download file
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to download: ${response.statusCode}');
      }

      if (kIsWeb) {
        // Web: trigger download using url_launcher
        try {
          await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đã mở file trong tab mới. Nhấn chuột phải để lưu.'),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi khi mở file: $e'),
              ),
            );
          }
        }
      } else {
        // Mobile/Desktop: Save to device
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã lưu vào: ${file.path}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(
            e,
            defaultMessage: 'Không thể lưu story',
          ),
        );
      }
    }
  }

  void _addFloatingReaction(String emoji) {
    final width = MediaQuery.of(context).size.width;
    final left =
        (width * 0.2) +
        (width * 0.6) * (DateTime.now().microsecondsSinceEpoch % 1000) / 1000.0;
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    setState(() {
      _floatingReactions.add(
        _FloatingReaction(id: id, emoji: emoji, left: left),
      );
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        _floatingReactions.removeWhere((r) => r.id == id);
      });
    });
  }

  Future<void> _playStoryMusic(StoryModel story) async {
    final url = story.musicUrl;

    if (mounted) {
      debugPrint(
        '_playStoryMusic called - musicUrl: $url, musicName: ${story.musicName}',
      );
    }

    if (url == null || url.isEmpty) {
      if (_currentMusicUrl != null) {
        await _audioPlayer.stop();
        _currentMusicUrl = null;
      }
      // Nếu không có nhạc và không có video, dùng duration mặc định
      if (_videoController == null && mounted) {
        setState(() {
          _isMediaReady = true;
          _currentStoryDuration = const Duration(seconds: 5);
        });
        _startProgressTimer();
      }
      if (mounted) {
        debugPrint('Story không có nhạc');
      }
      return;
    }

    if (url == _currentMusicUrl) {
      // Nếu cùng URL, chỉ cần đảm bảo volume đúng và resume nếu cần
      await _audioPlayer.setVolume(_isMuted ? 0.0 : 1.0);
      final state = _audioPlayer.state;
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        try {
          await _audioPlayer.play(UrlSource(url));
          await _audioPlayer.setVolume(_isMuted ? 0.0 : 1.0);
          if (mounted) {
            debugPrint('Đã phát lại nhạc: $url');
          }
        } catch (e) {
          if (mounted) {
            debugPrint('Lỗi phát lại nhạc: $e');
          }
        }
      }
      return;
    }

    _audioStateSubscription?.cancel();
    _currentMusicUrl = url;
    try {
      // Dừng nhạc cũ trước
      await _audioPlayer.stop();
      // Đợi một chút để đảm bảo player đã sẵn sàng
      await Future.delayed(const Duration(milliseconds: 100));
      // Set volume trước khi phát
      await _audioPlayer.setVolume(_isMuted ? 0.0 : 1.0);

      // Nếu có nhạc, đảm bảo video được tắt tiếng
      if (_videoController != null && _videoController!.value.isInitialized) {
        await _updateVideoVolume(story);
      }

      // Lắng nghe sự kiện khi nhạc kết thúc
      _audioStateSubscription = _audioPlayer.onPlayerStateChanged.listen((
        state,
      ) {
        if (state == PlayerState.completed && mounted) {
          // Nhạc đã kết thúc, chuyển sang story tiếp theo
          _nextStory();
        }
      });

      // Lấy duration của nhạc nếu có
      final source = UrlSource(url);
      await _audioPlayer.play(source);

      // Đợi một chút để lấy duration
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final duration = await _audioPlayer.getDuration();
        if (duration != null && duration.inMilliseconds > 0 && mounted) {
          setState(() {
            // Nếu có video, dùng duration dài hơn giữa video và nhạc
            if (_videoController != null &&
                _videoController!.value.isInitialized) {
              final videoDuration = _videoController!.value.duration;
              _currentStoryDuration = duration > videoDuration
                  ? duration
                  : videoDuration;
            } else {
              _currentStoryDuration = duration;
            }
            _isMediaReady = true;
          });
          _startProgressTimer();
        } else if (mounted && _videoController == null) {
          // Nếu không có video và không lấy được duration nhạc, dùng mặc định
          setState(() {
            _isMediaReady = true;
            _currentStoryDuration = const Duration(seconds: 5);
          });
          _startProgressTimer();
        }
      } catch (e) {
        // Nếu không lấy được duration, dùng mặc định
        if (mounted && _videoController == null) {
          setState(() {
            _isMediaReady = true;
            _currentStoryDuration = const Duration(seconds: 5);
          });
          _startProgressTimer();
        }
      }

      if (mounted) {
        debugPrint('Đã phát nhạc: $url');
      }
    } catch (e) {
      // tránh crash nếu URL lỗi
      if (mounted) {
        debugPrint('Lỗi phát nhạc: $e, URL: $url');
        // Nếu lỗi và không có video, vẫn cho phép progress chạy với duration mặc định
        if (_videoController == null) {
          setState(() {
            _isMediaReady = true;
            _currentStoryDuration = const Duration(seconds: 5);
          });
          _startProgressTimer();
        }
      }
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _currentProgress = 0.0;

    if (_isPaused || _stories.isEmpty || !_isMediaReady) return;

    const tickDuration = Duration(milliseconds: 50);
    final totalTicks =
        _currentStoryDuration.inMilliseconds ~/ tickDuration.inMilliseconds;
    var currentTick = 0;

    _progressTimer = Timer.periodic(tickDuration, (timer) {
      if (!mounted || _isPaused) return;

      // Nếu có video, đồng bộ với video position
      if (_videoController != null && _videoController!.value.isInitialized) {
        final position = _videoController!.value.position;
        final duration = _videoController!.value.duration;
        if (duration.inMilliseconds > 0) {
          setState(() {
            _currentProgress =
                position.inMilliseconds / duration.inMilliseconds;
          });

          // Kiểm tra nếu video đã kết thúc (với tolerance nhỏ)
          if (_currentProgress >= 0.99) {
            timer.cancel();
            _nextStory();
          }
          return;
        }
      }

      // Nếu không có video, dùng timer thông thường
      currentTick++;
      setState(() {
        _currentProgress = currentTick / totalTicks;
      });

      if (_currentProgress >= 1.0) {
        timer.cancel();
        _nextStory();
      }
    });
  }

  void _pauseProgress() {
    setState(() {
      _isPaused = true;
    });
    _progressTimer?.cancel();

    // Pause video nếu đang phát
    if (_videoController != null &&
        _videoController!.value.isInitialized &&
        _videoController!.value.isPlaying) {
      _videoController!.pause();
    }

    // Pause audio nếu đang phát
    if (_audioPlayer.state == PlayerState.playing) {
      _audioPlayer.pause();
    }
  }

  void _resumeProgress() {
    if (_isPaused) {
      setState(() {
        _isPaused = false;
      });
      _startProgressTimer();

      // Resume video nếu đã được initialized
      if (_videoController != null &&
          _videoController!.value.isInitialized &&
          !_videoController!.value.isPlaying) {
        _videoController!.play();
      }

      // Resume audio nếu đang paused
      if (_audioPlayer.state == PlayerState.paused &&
          _currentMusicUrl != null) {
        _audioPlayer.resume();
      }
    }
  }

  void _nextStory() {
    // Chỉ cho phép chuyển story khi đã phát hết story hiện tại
    // (được gọi khi video/nhạc kết thúc hoặc progress >= 1.0)
    if (_currentIndex < _stories.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Hết story hiện tại, thử chuyển sang user có story tiếp theo (nếu có)
      if (_usersWithStories.isNotEmpty) {
        final nextIndex = (_currentUserIndex + 1) % _usersWithStories.length;
        final nextUserId = _usersWithStories[nextIndex];

        if (nextUserId != widget.userId) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => StoryViewerScreen(
                userId: nextUserId,
                usersWithStories: _usersWithStories,
                initialUserIndex: nextIndex,
              ),
            ),
          );
          return;
        }
      }

      // Nếu không còn user nào khác, quay về màn trước an toàn
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  void _previousStory() {
    // Cho phép chuyển story trước khi đang phát (tap để chuyển)
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Story đầu tiên, quay lại màn hình trước
      Navigator.of(context).pop();
    }
  }

  void _onStoryChanged(int index) {
    if (!mounted) {
      if (kDebugMode) {
        debugPrint('=== _onStoryChanged: Widget unmounted, returning ===');
      }
      return;
    }
    
    if (index < 0 || index >= _stories.length) {
      if (kDebugMode) {
        debugPrint('=== _onStoryChanged: Invalid index ===');
        debugPrint('Index: $index');
        debugPrint('Stories length: ${_stories.length}');
      }
      return;
    }

    // Reset trạng thái
    _progressTimer?.cancel();
    _videoPositionSubscription?.cancel();
    _audioStateSubscription?.cancel();
    
    // Load post data if story has post link
    final currentStory = _stories[index];
    _loadSharedPost(currentStory);
    _videoController?.removeListener(_videoListener);

    setState(() {
      _currentIndex = index;
      _currentProgress = 0.0;
      _isPaused = false;
      _isMediaReady = false; // Reset trạng thái sẵn sàng
      _currentStoryDuration = const Duration(seconds: 5); // Reset về mặc định
    });

    // Đảm bảo timer chỉ start sau khi state đã update
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _stories.isEmpty || index >= _stories.length) return;
      
      final story = _stories[index];
      
      if (kDebugMode) {
        debugPrint('=== _onStoryChanged called ===');
        debugPrint('Index: $index');
        debugPrint('Story ID: ${story.id}');
        debugPrint('Story createdAt: ${story.createdAt}');
        debugPrint('Total stories: ${_stories.length}');
      }

      // Khởi tạo video trước (nếu có)
      if (mounted) {
        await _initVideoController(story);
      }

      // Phát nhạc với delay nhỏ để đảm bảo AudioPlayer sẵn sàng
      // Sau khi phát nhạc, volume của video sẽ được cập nhật trong _playStoryMusic
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted && _currentIndex == index && index < _stories.length) {
        await _playStoryMusic(story);
        // Đảm bảo volume video được set đúng sau khi phát nhạc
        if (_videoController != null &&
            _videoController!.value.isInitialized &&
            mounted) {
          await _updateVideoVolume(story);
        }
      }

      // Nếu không có video và không có nhạc, vẫn cho phép progress chạy
      if (mounted && _currentIndex == index && index < _stories.length && !_isMediaReady) {
        final currentStory = _stories[index];
        if (currentStory.videoUrl == null || currentStory.videoUrl!.isEmpty) {
          if (currentStory.musicUrl == null || currentStory.musicUrl!.isEmpty) {
            if (mounted) {
              setState(() {
                _isMediaReady = true;
                _currentStoryDuration = const Duration(seconds: 5);
              });
              if (mounted) {
                _startProgressTimer();
              }
            }
          }
        }
      }

      // Track story view
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser != null && mounted) {
        _storyService.addStoryView(
          storyId: story.id,
          storyOwnerId: story.userId,
          viewerId: currentUser.id,
        );
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _videoPositionSubscription?.cancel();
    _audioStateSubscription?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initVideoController(StoryModel story) async {
    if (story.videoUrl == null || story.videoUrl!.isEmpty) {
      _videoController?.dispose();
      _videoController = null;
      _initializeVideoFuture = null;
      _videoPositionSubscription?.cancel();
      return;
    }

    // Nếu cùng nguồn video, không cần khởi tạo lại
    if (_videoController != null &&
        _videoController!.dataSource == story.videoUrl) {
      // Cập nhật volume của video dựa trên việc có nhạc hay không
      _updateVideoVolume(story);
      return;
    }

    _videoPositionSubscription?.cancel();
    _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(story.videoUrl!),
    );
    _initializeVideoFuture = _videoController!.initialize().then((_) async {
      if (!mounted) return;

      final duration = _videoController!.value.duration;
      if (duration.inMilliseconds > 0) {
        if (mounted) {
          setState(() {
            _currentStoryDuration = duration;
            _isMediaReady = true;
          });
        }
      } else {
        // Nếu video không có duration hợp lệ, dùng duration mặc định
        if (mounted) {
          setState(() {
            _currentStoryDuration = const Duration(seconds: 5);
            _isMediaReady = true;
          });
        }
      }

      await _videoController!.setLooping(
        false,
      ); // Không loop để có thể detect khi kết thúc

      // Thiết lập volume của video:
      // - Nếu có nhạc: tắt tiếng video (volume = 0)
      // - Nếu không có nhạc: phát video với âm thanh (volume theo _isMuted)
      await _updateVideoVolume(story);

      await _videoController!.play(); // Tự động phát

      // Lắng nghe sự kiện khi video kết thúc
      _videoController!.addListener(_videoListener);

      if (mounted) {
        setState(() {});
      }

      // Bắt đầu progress timer sau khi video đã sẵn sàng
      // (Sẽ được gọi lại trong _playStoryMusic nếu có nhạc, hoặc ngay bây giờ nếu không có nhạc)
      if (mounted && _isMediaReady) {
        _startProgressTimer();
      }
    }).catchError((error) {
      // Xử lý lỗi khởi tạo video
      if (mounted) {
        debugPrint('Lỗi khởi tạo video: $error');
        setState(() {
          _isMediaReady = true;
          _currentStoryDuration = const Duration(seconds: 5);
        });
        _startProgressTimer();
      }
    });
  }

  // Cập nhật volume của video dựa trên việc có nhạc hay không
  Future<void> _updateVideoVolume(StoryModel story) async {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }

    // Nếu có nhạc: tắt tiếng video (volume = 0)
    // Nếu không có nhạc: phát video với âm thanh (volume theo _isMuted)
    final hasMusic = story.musicUrl != null && story.musicUrl!.isNotEmpty;
    final videoVolume = hasMusic ? 0.0 : (_isMuted ? 0.0 : 1.0);

    await _videoController!.setVolume(videoVolume);
  }

  void _videoListener() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }

    // Kiểm tra nếu video đã kết thúc
    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;

    if (duration.inMilliseconds > 0 &&
        position.inMilliseconds >= duration.inMilliseconds - 100) {
      // Video đã kết thúc, chuyển sang story tiếp theo
      _videoController!.removeListener(_videoListener);
      _nextStory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập')));
    }

    if (_isLoadingStories) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    if (_stories.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: Text(
            'Không có story nào để hiển thị',
            style: TextStyle(color: Colors.black87),
          ),
        ),
      );
    }

    final isOwnStory = widget.userId == currentUser.id;
    final currentStory = _stories[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Swipe down để đóng story, swipe up để mở link/sticker
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! > 500) {
              // Swipe down
              _handleSwipeDown();
            } else if (details.primaryVelocity! < -500) {
              // Swipe up
              _handleSwipeUp(currentStory);
            }
          }
        },
        // Swipe left/right để chuyển sang story của người khác (chỉ khi ở story đầu/cuối)
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            // Chỉ chuyển user khi đang ở story đầu tiên hoặc cuối cùng
            if (_currentIndex == 0 && details.primaryVelocity! > 500) {
              // Swipe right ở story đầu -> user trước
              _handleSwipeToPreviousUser();
            } else if (_currentIndex == _stories.length - 1 &&
                details.primaryVelocity! < -500) {
              // Swipe left ở story cuối -> user tiếp theo
              _handleSwipeToNextUser();
            }
          }
        },
        child: Stack(
          children: [
            // Progress bar ở trên cùng
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 8.0,
                  ),
                  child: _StoryProgressBar(
                    storyCount: _stories.length,
                    currentIndex: _currentIndex,
                    progress: _currentProgress,
                  ),
                ),
              ),
            ),

            // Gesture areas để điều khiển story: tap để phát, long press để tạm dừng
            Positioned.fill(
              child: Row(
                children: [
                  // Vùng trái: tap để chuyển story trước, long press để pause
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_isPaused) {
                          _resumeProgress();
                        } else {
                          _previousStory();
                        }
                      },
                      onLongPressStart: (_) => _pauseProgress(),
                      onLongPressEnd: (_) => _resumeProgress(),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  // Vùng giữa: tap để phát nếu đang pause, long press để pause
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        if (_isPaused) {
                          _resumeProgress();
                        }
                      },
                      onLongPressStart: (_) => _pauseProgress(),
                      onLongPressEnd: (_) => _resumeProgress(),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                  // Vùng phải: tap để chuyển story sau, long press để pause
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_isPaused) {
                          _resumeProgress();
                        } else {
                          _nextStory();
                        }
                      },
                      onLongPressStart: (_) => _pauseProgress(),
                      onLongPressEnd: (_) => _resumeProgress(),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ],
              ),
            ),

            PageView.builder(
              controller: _pageController,
              itemCount: _stories.length,
              onPageChanged: _onStoryChanged,
              // Cho phép swipe để chuyển story (vuốt sang phải -> story trước, vuốt sang trái -> story sau)
              physics: const PageScrollPhysics(),
              itemBuilder: (context, index) {
                final story = _stories[index];

                Widget content;
                if (story.imageUrl != null) {
                  content = Image.network(
                    story.imageUrl!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  );
                } else if (story.videoUrl != null) {
                  content = FutureBuilder(
                    future: _initializeVideoFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError || _videoController == null) {
                        return const Center(
                          child: Text(
                            'Không phát được video',
                            style: TextStyle(color: Colors.black87),
                          ),
                        );
                      }

                      return Container(
                        width: double.infinity,
                        height: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoController!.value.size.width,
                            height: _videoController!.value.size.height,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),
                      );
                    },
                  );
                } else if (story.text != null && story.text!.isNotEmpty) {
                  content = Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        story.text!,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                } else {
                  content = const Center(
                    child: Text(
                      'Story này không có nội dung hiển thị',
                      style: TextStyle(color: Colors.black87),
                    ),
                  );
                }

                return Container(
                  width: double.infinity,
                  height: double.infinity,
                  child: Stack(
                    children: [
                      // Content area - giới hạn để không che progress bar và header
                      Positioned(
                        top: 40, // Bên dưới progress bar
                        left: 0,
                        right: 0,
                        bottom: 100, // Bên trên footer (để tránh che footer)
                        child: content,
                      ),
                      // Stickers overlay - trong vùng content
                      if (story.stickers.isNotEmpty)
                        Positioned(
                          top: 40,
                          left: 0,
                          right: 0,
                          bottom: 100,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Stack(
                                children: story.stickers.map((sticker) {
                                  return Positioned(
                                    left: sticker.x * constraints.maxWidth,
                                    top: sticker.y * constraints.maxHeight,
                                    child: Transform.rotate(
                                      angle: sticker.rotation * 3.14159 / 180,
                                      child: Transform.scale(
                                        scale: sticker.scale,
                                        alignment: Alignment.center,
                                        child: Text(
                                          sticker.emoji,
                                          style: const TextStyle(fontSize: 30),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                      // Text overlays overlay - trong vùng content
                      if (story.textOverlays.isNotEmpty)
                        Positioned(
                          top: 40,
                          left: 0,
                          right: 0,
                          bottom: 100,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Stack(
                                children: story.textOverlays.map((textOverlay) {
                                  Color textColor;
                                  try {
                                    final colorString = textOverlay.color
                                        .replaceFirst('#', '');
                                    if (colorString.length == 6) {
                                      final colorValue = int.parse(
                                        colorString,
                                        radix: 16,
                                      );
                                      textColor = Color(
                                        0xFF000000 | colorValue,
                                      );
                                    } else if (colorString.length == 8) {
                                      textColor = Color(
                                        int.parse(colorString, radix: 16),
                                      );
                                    } else {
                                      textColor = Colors.white;
                                    }
                                  } catch (e) {
                                    textColor = Colors.white;
                                  }

                                  return Positioned(
                                    left: textOverlay.x * constraints.maxWidth,
                                    top: textOverlay.y * constraints.maxHeight,
                                    child: Transform.rotate(
                                      angle:
                                          textOverlay.rotation * 3.14159 / 180,
                                      child: Transform.scale(
                                        scale: textOverlay.scale,
                                        alignment: Alignment.center,
                                        child: Container(
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                constraints.maxWidth * 0.8,
                                          ),
                                          child: Text(
                                            textOverlay.text,
                                            style: TextStyle(
                                              color: textColor,
                                              fontSize: textOverlay.fontSize,
                                              fontWeight: textOverlay.isBold
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              fontStyle: textOverlay.isItalic
                                                  ? FontStyle.italic
                                                  : FontStyle.normal,
                                              fontFamily:
                                                  textOverlay.fontFamily,
                                            ),
                                            textAlign: textOverlay.textAlign,
                                            maxLines: null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                      // Mentions overlay - trong vùng content
                      if (story.mentions.isNotEmpty)
                        Positioned(
                          top: 40,
                          left: 0,
                          right: 0,
                          bottom: 100,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Stack(
                                children: story.mentions.map((mention) {
                                  return Positioned(
                                    left: mention.x * constraints.maxWidth,
                                    top: mention.y * constraints.maxHeight,
                                    child: Transform.scale(
                                      scale: mention.scale,
                                      alignment: Alignment.center,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.6),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.alternate_email,
                                              color: Colors.blue,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              mention.userName,
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                      // Drawings overlay - trong vùng content
                      if (story.drawings.isNotEmpty)
                        Positioned(
                          top: 40,
                          left: 0,
                          right: 0,
                          bottom: 100,
                          child: _DraggableDrawingsContainer(
                            key: ValueKey('drawings_${story.id}'),
                            drawings: story.drawings,
                          ),
                        ),
                      // Hiển thị tên nhạc nếu có
                      if (story.musicName != null &&
                          story.musicName!.isNotEmpty)
                        Positioned(
                          bottom: 100,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.music_note,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      story.musicName!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        shadows: [
                                          Shadow(color: Colors.black, blurRadius: 2),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // Hiển thị hint để swipe up nếu có link bài viết
                      if (story.link != null && 
                          story.link!.url.isNotEmpty &&
                          _extractPostIdFromUrl(story.link!.url) != null)
                        Positioned(
                          bottom: 50,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.arrow_upward,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Vuốt lên để xem bài viết',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),

            // Menu 3 chấm ở góc dưới bên phải (chỉ hiển thị cho story của mình)
            if (isOwnStory)
              Positioned(
                bottom: 24,
                right: 16,
                child: SafeArea(
                  top: false,
                  child: _StoryMenuButton(
                    story: currentStory,
                    onSave: _saveStoryToDevice,
                  ),
                ),
              ),

            // Header với avatar, tên, thời gian và các nút điều khiển
            // Đặt sau PageView để luôn hiển thị trên cùng (không bị video che)
            Positioned(
              top: 40, // Vị trí bên dưới progress bar
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  // Thêm gradient background để header nổi bật trên video
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.grey.withOpacity(0.5),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.3],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      if (_user != null)
                        CircleAvatar(
                          backgroundColor: Colors.grey[800],
                          backgroundImage: _user!.avatarUrl != null
                              ? NetworkImage(_user!.avatarUrl!)
                              : null,
                          child: _user!.avatarUrl == null
                              ? Text(
                                  _user!.fullName.isNotEmpty
                                      ? _user!.fullName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(color: Colors.black),
                                )
                              : null,
                        ),
                      const SizedBox(width: 8),
                      // Tên và thời gian
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _user?.fullName ?? 'Story',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 2),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _formatTimeAgo(currentStory.createdAt),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 2),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Nút mute/unmute
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: _toggleMute,
                        ),
                      ),
                      // Nút reply (chỉ khi không phải story của mình)
                      if (!isOwnStory)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.reply,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: () => _replyToStory(currentStory),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Icon danh sách người xem (góc trái bottom) - chỉ hiển thị cho story của mình
            if (isOwnStory)
              Positioned(
                left: 16,
                bottom: 24,
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _storyService.getStoryViews(currentStory.id),
                  builder: (context, snapshot) {
                    final views = snapshot.data ?? [];

                    return GestureDetector(
                      onTap: () async {
                        // Mở dialog danh sách người xem + cảm xúc
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.white.withOpacity(0.87),
                          builder: (ctx) {
                            return SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 8),
                                  Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Người đã xem story',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: _StoryViewersList(storyId: currentStory.id),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.remove_red_eye,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${views.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 2),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Bottom overlay: viewers hoặc reaction
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: isOwnStory
                  ? _OwnerStoryFooter(
                      story: currentStory,
                      onSave: _saveStoryToDevice,
                    )
                  : _ViewerStoryFooter(
                      story: currentStory,
                      onReact: (emoji) async {
                        _addFloatingReaction(emoji);
                        try {
                          await _storyService.reactToStory(
                            storyId: currentStory.id,
                            storyOwnerId: currentStory.userId,
                            userId: currentUser.id,
                            emoji: emoji,
                          );
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(
                              ErrorMessageHelper.createErrorSnackBar(e),
                            );
                          }
                        }
                      },
                    ),
            ),

            // Floating reaction animations
            ..._floatingReactions.map(
              (r) => Positioned(
                bottom: 80,
                left: r.left,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 750),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: 1 - value,
                      child: Transform.translate(
                        offset: Offset(0, -60 * value),
                        child: child,
                      ),
                    );
                  },
                  child: Text(r.emoji, style: const TextStyle(fontSize: 32)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Widget Progress Bar với nhiều segment
class _StoryProgressBar extends StatelessWidget {
  final int storyCount;
  final int currentIndex;
  final double progress; // 0.0 - 1.0 cho story hiện tại

  const _StoryProgressBar({
    required this.storyCount,
    required this.currentIndex,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(storyCount, (index) {
        final isActive = index == currentIndex;
        final isCompleted = index < currentIndex;

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index < storyCount - 1 ? 4 : 0),
            height: 3,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Stack(
              children: [
                // Background (màu xám)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Progress fill
                FractionallySizedBox(
                  widthFactor: isCompleted
                      ? 1.0
                      : isActive
                      ? progress
                      : 0.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _FloatingReaction {
  final String id;
  final String emoji;
  final double left;

  _FloatingReaction({
    required this.id,
    required this.emoji,
    required this.left,
  });
}

class _OwnerStoryFooter extends StatelessWidget {
  final StoryModel story;
  final Future<void> Function(StoryModel)? onSave;

  const _OwnerStoryFooter({required this.story, this.onSave});

  @override
  Widget build(BuildContext context) {
    // Footer chỉ hiển thị reactions, menu đã được di chuyển lên góc phải
    final storyService = StoryService();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        // 4 cảm xúc gần nhất
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: storyService.getStoryReactions(story.id),
          builder: (context, reactionSnapshot) {
            final reactions = reactionSnapshot.data ?? [];
            if (reactions.isEmpty) {
              return const SizedBox.shrink();
            }

            reactions.sort((a, b) {
              final aTime =
                  DateTime.tryParse(a['createdAt'] ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  DateTime.tryParse(b['createdAt'] ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

            final recentReactions = reactions.take(4).toList();

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: recentReactions.map((reaction) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    reaction['emoji'] ?? '👍',
                    style: const TextStyle(fontSize: 24),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

// Menu 3 chấm ở góc phải màn hình
class _StoryMenuButton extends StatelessWidget {
  final StoryModel story;
  final Future<void> Function(StoryModel)? onSave;

  const _StoryMenuButton({
    required this.story,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.more_vert,
          color: Colors.white,
          size: 24,
        ),
      ),
      onSelected: (value) async {
        final storyService = StoryService();
        if (value == 'save' && onSave != null) {
          await onSave!(story);
        } else if (value == 'delete') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Xóa story'),
              content: const Text(
                'Bạn có chắc chắn muốn xóa story này?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Hủy'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Xóa'),
                ),
              ],
            ),
          );

          if (confirm == true) {
            try {
              await storyService.deleteStory(story.id);
              if (context.mounted) {
                Navigator.of(context).pop(); // đóng viewer
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa story')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  ErrorMessageHelper.createErrorSnackBar(
                    e,
                    defaultMessage: 'Không thể xóa story',
                  ),
                );
              }
            }
          }
        }
      },
      itemBuilder: (ctx) => [
        if (onSave != null)
          const PopupMenuItem(
            value: 'save',
            child: Row(
              children: [
                Icon(Icons.download, size: 20),
                SizedBox(width: 8),
                Text('Lưu story'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 20, color: Colors.red),
              SizedBox(width: 8),
              Text('Xóa story', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StoryViewersList extends StatelessWidget {
  final String storyId;

  const _StoryViewersList({required this.storyId});

  @override
  Widget build(BuildContext context) {
    final storyService = StoryService();
    final userService = UserService();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: storyService.getStoryViews(storyId),
      builder: (context, snapshot) {
        final allViews = snapshot.data ?? [];

        if (allViews.isEmpty) {
          return const Center(
            child: Text(
              'Chưa có ai xem story này',
              style: TextStyle(color: Colors.black87),
            ),
          );
        }

        // Lấy ownerId từ bất kỳ bản ghi nào và loại bỏ lượt xem của owner
        final storyOwnerId = allViews.first['storyOwnerId'] as String?;
        final views = storyOwnerId == null
            ? allViews
            : allViews.where((v) => v['viewerId'] != storyOwnerId).toList();

        if (views.isEmpty) {
          return const Center(
            child: Text(
              'Chưa có ai xem story này',
              style: TextStyle(color: Colors.black87),
            ),
          );
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: storyService.getStoryReactions(storyId),
          builder: (context, reactionSnapshot) {
            final reactions = reactionSnapshot.data ?? [];

            return FutureBuilder<List<UserModel?>>(
              future: Future.wait(
                views.map((v) async {
                  final id = v['viewerId'] as String?;
                  if (id == null) return null;
                  return userService.getUserById(id);
                }),
              ),
              builder: (context, usersSnapshot) {
                final users = usersSnapshot.data ?? [];

                return ListView.builder(
                  itemCount: views.length,
                  itemBuilder: (context, index) {
                    final view = views[index];
                    final user = users[index];
                    if (user == null) return const SizedBox.shrink();

                    final viewerId = view['viewerId'] as String?;
                    final reactionForUser = reactions.firstWhere(
                      (r) => r['userId'] == viewerId,
                      orElse: () => {},
                    );
                    final emoji = (reactionForUser['emoji'] as String?) ?? '';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey[700],
                        backgroundImage: user.avatarUrl != null
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                        child: user.avatarUrl == null
                            ? Text(
                                user.fullName[0].toUpperCase(),
                                style: const TextStyle(color: Colors.black),
                              )
                            : null,
                      ),
                      title: Text(
                        user.fullName,
                        style: const TextStyle(color: Colors.black),
                      ),
                      trailing: emoji.isNotEmpty
                          ? Text(emoji, style: const TextStyle(fontSize: 20))
                          : null,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ViewerStoryFooter extends StatelessWidget {
  final StoryModel story;
  final Future<void> Function(String emoji) onReact;

  const _ViewerStoryFooter({required this.story, required this.onReact});

  @override
  Widget build(BuildContext context) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: emojis.map((e) {
          return IconButton(
            onPressed: () => onReact(e),
            icon: Text(e, style: const TextStyle(fontSize: 24)),
          );
        }).toList(),
      ),
    );
  }
}

// Container quản lý tất cả drawings có thể di chuyển
class _DraggableDrawingsContainer extends StatefulWidget {
  final List<StoryDrawing> drawings;

  const _DraggableDrawingsContainer({super.key, required this.drawings});

  @override
  State<_DraggableDrawingsContainer> createState() =>
      _DraggableDrawingsContainerState();
}

class _DraggableDrawingsContainerState
    extends State<_DraggableDrawingsContainer> {
  final Map<int, Offset> _offsets = {};
  int? _draggingIndex;
  Offset? _panStart;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        _panStart = details.localPosition;
        // Tìm drawing gần điểm bắt đầu nhất
        final size = MediaQuery.of(context).size;
        double minDistance = double.infinity;
        int? closestIndex;

        for (int i = 0; i < widget.drawings.length; i++) {
          final drawing = widget.drawings[i];
          if (drawing.points.isEmpty) continue;

          // Tính toán bounding box của drawing
          double minX = double.infinity;
          double maxX = double.negativeInfinity;
          double minY = double.infinity;
          double maxY = double.negativeInfinity;

          final offset = _offsets[i] ?? Offset.zero;

          for (final point in drawing.points) {
            final x = point.x * size.width + offset.dx;
            final y = point.y * size.height + offset.dy;
            minX = minX < x ? minX : x;
            maxX = maxX > x ? maxX : x;
            minY = minY < y ? minY : y;
            maxY = maxY > y ? maxY : y;
          }

          // Kiểm tra xem điểm touch có trong bounding box không (với margin)
          final margin = drawing.strokeWidth * 2;
          if (details.localPosition.dx >= minX - margin &&
              details.localPosition.dx <= maxX + margin &&
              details.localPosition.dy >= minY - margin &&
              details.localPosition.dy <= maxY + margin) {
            // Tính khoảng cách đến center của drawing
            final centerX = (minX + maxX) / 2;
            final centerY = (minY + maxY) / 2;
            final distance =
                (details.localPosition.dx - centerX).abs() +
                (details.localPosition.dy - centerY).abs();

            if (distance < minDistance) {
              minDistance = distance;
              closestIndex = i;
            }
          }
        }

        _draggingIndex = closestIndex;
      },
      onPanUpdate: (details) {
        if (_draggingIndex != null && _panStart != null) {
          setState(() {
            final currentOffset = _offsets[_draggingIndex!] ?? Offset.zero;
            _offsets[_draggingIndex!] =
                currentOffset + (details.localPosition - _panStart!);
            _panStart = details.localPosition;
          });
        }
      },
      onPanEnd: (details) {
        _panStart = null;
        _draggingIndex = null;
      },
      onPanCancel: () {
        _panStart = null;
        _draggingIndex = null;
      },
      child: CustomPaint(
        painter: _StoryDrawingsPainter(
          drawings: widget.drawings,
          offsets: _offsets,
        ),
      ),
    );
  }
}

// Custom painter for multiple story drawings với offsets
class _StoryDrawingsPainter extends CustomPainter {
  final List<StoryDrawing> drawings;
  final Map<int, Offset> offsets;

  _StoryDrawingsPainter({required this.drawings, required this.offsets});

  @override
  void paint(Canvas canvas, Size size) {
    for (int index = 0; index < drawings.length; index++) {
      final drawing = drawings[index];
      if (drawing.points.isEmpty) continue;

      final offset = offsets[index] ?? Offset.zero;

      // Parse color từ hex string
      Color color;
      try {
        final colorString = drawing.color.replaceFirst('#', '');
        if (colorString.length == 6) {
          final colorValue = int.parse(colorString, radix: 16);
          color = Color(0xFF000000 | colorValue);
        } else if (colorString.length == 8) {
          // Format: AARRGGBB
          color = Color(int.parse(colorString, radix: 16));
        } else {
          // Fallback to black
          color = Colors.black;
        }
      } catch (e) {
        // Fallback to black nếu parse lỗi
        color = Colors.black;
      }

      final paint = Paint()
        ..color = color
        ..strokeWidth = drawing.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      // Vẽ các đường nối giữa các điểm với offset
      for (int i = 0; i < drawing.points.length - 1; i++) {
        final point1 = drawing.points[i];
        final point2 = drawing.points[i + 1];

        canvas.drawLine(
          Offset(point1.x * size.width, point1.y * size.height) + offset,
          Offset(point2.x * size.width, point2.y * size.height) + offset,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StoryDrawingsPainter oldDelegate) {
    return oldDelegate.drawings != drawings || oldDelegate.offsets != offsets;
  }
}
