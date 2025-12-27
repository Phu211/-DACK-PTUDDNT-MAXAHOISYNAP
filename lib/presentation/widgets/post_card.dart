import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../../data/models/post_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/reaction_model.dart';
import '../../data/models/privacy_model.dart';
import '../../data/models/group_model.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/user_service.dart';
import '../../data/services/message_service.dart';
import '../../data/services/feed_control_service.dart';
import '../../data/services/block_service.dart';
import '../../data/services/group_service.dart';
import '../providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/other_user_profile_screen.dart';
import '../screens/post/video_fullscreen_screen.dart';
import '../screens/post/create_post_screen.dart';
import '../screens/post/post_detail_screen.dart';
import '../screens/messages/messages_list_screen.dart';
import '../screens/groups/group_detail_screen.dart';
import 'cached_network_image_widget.dart';
import '../../../data/services/story_service.dart';
import '../../../data/models/story_model.dart';
import '../../../data/models/story_element_model.dart';
import '../../../core/utils/error_message_helper.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/services/libretranslate_service.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';

class PostCard extends StatefulWidget {
  final PostModel post;

  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  final UserService _userService = UserService();
  // ignore: unused_field
  final MessageService _messageService = MessageService();
  final FeedControlService _feedControlService = FeedControlService();
  final StoryService _storyService = StoryService();
  final LibreTranslateService _translateService = LibreTranslateService();
  final GroupService _groupService = GroupService();
  ReactionType? _userReaction;
  int _likesCount = 0;
  UserModel? _postUser;
  GroupModel? _group; // Group info if post belongs to a group
  Map<ReactionType, int> _reactionCounts = {};
  // ignore: unused_field
  bool _isReactionPickerVisible = false;
  // ignore: unused_field
  bool _isProcessingReaction = false;
  // ignore: unused_field
  final GlobalKey _likeButtonKey = GlobalKey();
  // ignore: unused_field
  Timer? _hideTimer;
  bool _isPostSaved = false;
  PostModel? _originalPost; // Original post if this is a shared post
  UserModel? _originalPostUser; // User who created the original post
  List<UserModel> _taggedUsers = []; // Tagged users in the post
  VideoPlayerController? _videoController;
  Future<void>? _initializeVideoFuture;
  StreamSubscription? _videoPositionSubscription;
  Duration _videoPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  bool _isVideoInitialized = false;
  int _lastVideoUiUpdateMs = -1;
  ScrollPosition? _scrollPosition;
  int _lastVisibilityCheckMs = -1;
  bool _autoPausedByScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _likesCount = widget.post.likesCount;
    _checkUserReaction();
    _loadUserData();
    _checkPostSaved();
    // Nếu bài viết đã có lượt reaction, tải luôn breakdown để hiển thị emoji thay vì chỉ số.
    if (_likesCount > 0) {
      _loadReactionCounts();
    }
    if (widget.post.sharedPostId != null) {
      _loadOriginalPost();
    }
    if (widget.post.taggedUserIds.isNotEmpty) {
      _loadTaggedUsers();
    }
    // Load group info if post belongs to a group
    if (widget.post.groupId != null && widget.post.groupId!.isNotEmpty) {
      _loadGroupInfo();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachScrollListener();
  }

  Future<void> _loadOriginalPost() async {
    if (widget.post.sharedPostId == null) return;

    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      final originalPost = await _firestoreService.getPost(
        widget.post.sharedPostId!,
        viewerId: currentUser?.id,
      );
      if (originalPost != null && mounted) {
        setState(() {
          _originalPost = originalPost;
        });
        // Load original post user
        final originalUser = await _userService.getUserById(
          originalPost.userId,
        );
        if (mounted) {
          setState(() {
            _originalPostUser = originalUser;
          });
        }
      }
    } catch (e) {
      // Silently fail - original post might be deleted
      if (mounted) {
        debugPrint('Error loading original post: $e');
      }
    }
  }

  Future<void> _loadTaggedUsers() async {
    if (widget.post.taggedUserIds.isEmpty) return;

    try {
      // Filter out removed tagged users
      final activeTaggedUserIds = widget.post.taggedUserIds
          .where((id) => !widget.post.removedTaggedUserIds.contains(id))
          .toList();

      if (activeTaggedUserIds.isEmpty) return;

      final users = await _userService.getUsersByIds(activeTaggedUserIds);
      if (mounted) {
        setState(() {
          _taggedUsers = users;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error loading tagged users: $e');
      }
    }
  }

  Future<void> _checkPostSaved() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser != null) {
      final saved = await _firestoreService.isPostSaved(
        widget.post.id,
        currentUser.id,
      );
      if (mounted) {
        setState(() {
          _isPostSaved = saved;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollPosition?.removeListener(_onScroll);
    _videoPositionSubscription?.cancel();
    _videoController?.removeListener(_updateVideoPosition);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Defensive: pause video when app goes background.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      final controller = _videoController;
      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        controller.pause();
      }
    }
  }

  void _attachScrollListener() {
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos == _scrollPosition) return;
    _scrollPosition?.removeListener(_onScroll);
    _scrollPosition = pos;
    _scrollPosition?.addListener(_onScroll);
  }

  void _onScroll() {
    // Throttle visibility checks to reduce overhead.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastVisibilityCheckMs >= 0 && nowMs - _lastVisibilityCheckMs < 200) {
      return;
    }
    _lastVisibilityCheckMs = nowMs;
    _maybeAutoPauseVideoByVisibility();
  }

  void _maybeAutoPauseVideoByVisibility() async {
    final controller = _videoController;
    
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;

    final topLeft = renderBox.localToGlobal(Offset.zero);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(Offset.zero),
    );
    final screenH = MediaQuery.of(context).size.height;

    final top = topLeft.dy;
    final bottom = bottomRight.dy;
    final visibleH = (bottom.clamp(0.0, screenH) - top.clamp(0.0, screenH));

    // Consider visible if at least 25% of the card height is on screen.
    final minVisible = renderBox.size.height * 0.25;
    final isVisibleEnough = visibleH >= minVisible;

    // Nếu video đã được khởi tạo
    if (controller != null && controller.value.isInitialized) {
      // Only do work if it's playing (or we previously auto-paused it).
      if (!controller.value.isPlaying && !_autoPausedByScroll) {
        // Kiểm tra autoplay setting và tự động phát nếu visible và autoplay enabled
        if (isVisibleEnough && widget.post.videoUrl != null && widget.post.videoUrl!.isNotEmpty) {
          final autoplayEnabled = await SettingsService.isAutoplayVideosEnabled();
          if (autoplayEnabled && !_autoPausedByScroll) {
            await controller.play();
          }
        }
        return;
      }

      if (!isVisibleEnough && controller.value.isPlaying) {
        controller.pause();
        _autoPausedByScroll = true;
        return;
      }

      if (isVisibleEnough && _autoPausedByScroll) {
        // Don't auto-resume (avoid surprising playback); just reset the flag
        // so future scroll-out events can auto-pause again.
        _autoPausedByScroll = false;
      }
    } else {
      // Nếu video chưa được khởi tạo và card đủ visible, kiểm tra autoplay setting
      if (isVisibleEnough && widget.post.videoUrl != null && widget.post.videoUrl!.isNotEmpty) {
        final autoplayEnabled = await SettingsService.isAutoplayVideosEnabled();
        if (autoplayEnabled && _initializeVideoFuture == null) {
          await _ensureVideoInitialized(autoplay: true);
        }
      }
    }
  }

  Future<void> _ensureVideoInitialized({bool autoplay = false}) async {
    final url = widget.post.videoUrl;
    if (url == null || url.isEmpty) return;
    if (_videoController != null && _videoController!.value.isInitialized) {
      if (autoplay && !_videoController!.value.isPlaying) {
        await _videoController!.play();
      }
      return;
    }
    if (_initializeVideoFuture != null) {
      // Already initializing; wait for it.
      try {
        await _initializeVideoFuture;
        if (!mounted) return;
        if (autoplay &&
            _videoController != null &&
            _videoController!.value.isInitialized &&
            !_videoController!.value.isPlaying) {
          await _videoController!.play();
        }
      } catch (_) {}
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = controller;
    _lastVideoUiUpdateMs = -1;

    setState(() {
      _initializeVideoFuture = controller.initialize().then((_) async {
        if (!mounted) return;
        setState(() {
          _isVideoInitialized = true;
          _videoDuration = controller.value.duration;
          _videoPosition = controller.value.position;
        });
        _listenToVideoPosition();
        if (autoplay) {
          try {
            await controller.play();
            // In case user tapped play while the card is barely visible,
            // re-check visibility and auto-pause if needed.
            _maybeAutoPauseVideoByVisibility();
          } catch (_) {}
        }
      });
    });
  }

  Widget _buildVideoPlaceholder() {
    return InkWell(
      onTap: () async {
        await _ensureVideoInitialized(autoplay: true);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Colors.black,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_fill, color: Colors.white, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Phát video',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _listenToVideoPosition() {
    if (_videoController != null) {
      _videoController!.addListener(_updateVideoPosition);
    }
  }

  void _updateVideoPosition() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized || !mounted) {
      return;
    }

    final position = controller.value.position;
    final duration = controller.value.duration;
    if (duration.inMilliseconds <= 0) return;

    // Throttle UI updates to reduce jank in scrolling feed.
    final posMs = position.inMilliseconds;
    final durMs = duration.inMilliseconds;
    final ended = posMs >= durMs;
    final shouldUpdate =
        ended ||
        _lastVideoUiUpdateMs < 0 ||
        (posMs - _lastVideoUiUpdateMs).abs() >= 250;
    if (!shouldUpdate) return;
    _lastVideoUiUpdateMs = posMs;

    if (_videoPosition == position && _videoDuration == duration) return;

    setState(() {
      _videoPosition = position;
      _videoDuration = duration;
      // Nếu video đã kết thúc, đảm bảo position = duration
      if (_videoPosition >= _videoDuration) {
        _videoPosition = _videoDuration;
      }
    });
  }

  Future<void> _seekVideo(Duration position) async {
    if (_videoController != null && _videoController!.value.isInitialized) {
      await _videoController!.seekTo(position);
      setState(() {
        _videoPosition = position;
      });
    }
  }

  Future<void> _loadUserData() async {
    final user = await _userService.getUserById(widget.post.userId);
    if (mounted) {
      setState(() {
        _postUser = user;
      });
    }
  }

  Future<void> _loadGroupInfo() async {
    if (widget.post.groupId == null || widget.post.groupId!.isEmpty) return;

    try {
      final group = await _groupService.getGroup(widget.post.groupId!);
      if (mounted && group != null) {
        setState(() {
          _group = group;
        });
      }
    } catch (e) {
      debugPrint('Error loading group info: $e');
    }
  }

  void _openProfile(BuildContext context, UserModel user) {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser != null && currentUser.id == user.id) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OtherUserProfileScreen(user: user)),
      );
    }
  }

  // Build feeling text inline: "đang cảm thấy tức giận 😡"
  Widget _buildFeelingTextInline(String feeling) {
    // Parse feeling: "😊 Vui vẻ" -> emoji: "😊", text: "Vui vẻ"
    String emoji = '';
    String feelingText = feeling;

    // Extract emoji (first rune if it's an emoji)
    if (feeling.isNotEmpty) {
      final runes = feeling.runes.toList();
      if (runes.isNotEmpty) {
        final firstRune = runes[0];
        // Check if first rune is emoji (Unicode ranges for emojis)
        final isEmoji =
            (firstRune >= 0x1F600 && firstRune <= 0x1F64F) || // Emoticons
            (firstRune >= 0x1F300 &&
                firstRune <= 0x1F5FF) || // Misc Symbols and Pictographs
            (firstRune >= 0x1F680 &&
                firstRune <= 0x1F6FF) || // Transport and Map
            (firstRune >= 0x2600 && firstRune <= 0x26FF) || // Misc symbols
            (firstRune >= 0x2700 && firstRune <= 0x27BF) || // Dingbats
            (firstRune >= 0x1F900 &&
                firstRune <= 0x1F9FF) || // Supplemental Symbols
            (firstRune >= 0x1F1E0 &&
                firstRune <= 0x1F1FF); // Regional indicators

        if (isEmoji) {
          // Get emoji (could be multiple runes for some emojis with modifiers)
          int emojiLength = 1;
          // Check for emoji with variation selector or skin tone modifier
          if (runes.length > 1) {
            final secondRune = runes[1];
            if ((secondRune >= 0xFE00 &&
                    secondRune <= 0xFE0F) || // Variation selector
                (secondRune >= 0x1F3FB && secondRune <= 0x1F3FF)) {
              // Skin tone
              emojiLength = 2;
            }
          }
          emoji = String.fromCharCodes(runes.sublist(0, emojiLength));
          // Extract text after emoji and space
          if (feeling.length > emoji.length) {
            final remaining = feeling.substring(emoji.length).trim();
            feelingText = remaining;
          } else {
            feelingText = '';
          }
        }
      }
    }

    // Map feeling text to appropriate phrase
    String feelingPhrase = feelingText;
    final feelingMap = {
      'Vui vẻ': 'cảm thấy hạnh phúc',
      'Yêu thích': 'cảm thấy yêu thích',
      'Ngạc nhiên': 'cảm thấy ngạc nhiên',
      'Buồn': 'cảm thấy buồn',
      'Tức giận': 'cảm thấy tức giận',
      'Thích': 'cảm thấy thích',
      'Yêu': 'cảm thấy yêu',
      'Haha': 'cảm thấy vui vẻ',
      'Wow': 'cảm thấy ngạc nhiên',
    };
    feelingPhrase =
        feelingMap[feelingText] ??
        (feelingText.isNotEmpty ? 'cảm thấy $feelingText' : 'cảm thấy vui vẻ');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'đang $feelingPhrase',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.normal),
            softWrap: true,
            overflow: TextOverflow.visible,
            maxLines: 2,
          ),
        ),
        if (emoji.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(emoji, style: const TextStyle(fontSize: 16)),
        ],
      ],
    );
  }

  // Build milestone text like "Đình Phú đang [milestone]"
  Widget _buildMilestoneText() {
    return Text(
      '${_postUser?.fullName ?? 'Người dùng'} đang ${widget.post.milestoneEvent}.',
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    );
  }

  Future<void> _checkUserReaction() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser != null && mounted) {
        final reaction = await _firestoreService.getUserReaction(
          widget.post.id,
          currentUser.id,
        );
        if (!mounted) return;
        setState(() {
          _userReaction = reaction;
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('ERROR in _checkUserReaction: $e');
        print('Stack trace: $stackTrace');
      }
      // Don't crash, just log the error
    }
  }

  Future<void> _loadReactionCounts() async {
    try {
      if (!mounted) return;
      final counts = await _firestoreService.getPostReactions(widget.post.id);
      if (!mounted) return;
      setState(() {
        _reactionCounts = counts;
        _likesCount = counts.values.fold(0, (sum, count) => sum + count);
      });
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('ERROR in _loadReactionCounts: $e');
        print('Stack trace: $stackTrace');
      }
      // Don't crash, just log the error
    }
  }

  Future<void> _reactToPost(ReactionType type) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null || !mounted) return;

    // Prevent multiple simultaneous reactions
    if (_isProcessingReaction) {
      if (kDebugMode) {
        print('Reaction already processing, ignoring duplicate call');
      }
      return;
    }

    // Set processing flag to prevent duplicate calls
    if (mounted) {
      setState(() {
        _isProcessingReaction = true;
      });
    }

    final previousReaction = _userReaction;
    final wasReacted = previousReaction != null;

    if (mounted) {
      setState(() {
        _userReaction = type;
        if (!wasReacted) {
          _likesCount++;
          _reactionCounts[type] = (_reactionCounts[type] ?? 0) + 1;
        } else if (previousReaction != type) {
          _reactionCounts[previousReaction] =
              (_reactionCounts[previousReaction] ?? 1) - 1;
          if (_reactionCounts[previousReaction] == 0) {
            _reactionCounts.remove(previousReaction);
          }
          _reactionCounts[type] = (_reactionCounts[type] ?? 0) + 1;
        } else {
          _likesCount--;
          _reactionCounts[type] = (_reactionCounts[type] ?? 1) - 1;
          if (_reactionCounts[type] == 0) {
            _reactionCounts.remove(type);
          }
          _userReaction = null;
        }
      });
    }

    // Don't hide picker immediately - let user see the reaction
    // It will be hidden when mouse leaves the area

    try {
      if (!mounted) {
        if (kDebugMode) {
          print('_reactToPost: Not mounted before reactToPost call');
        }
        return;
      }

      if (kDebugMode) {
        print('_reactToPost: Calling firestoreService.reactToPost...');
      }

      await _firestoreService.reactToPost(widget.post.id, currentUser.id, type);

      if (kDebugMode) {
        print('_reactToPost: reactToPost completed successfully');
      }

      // Reload user reaction to ensure UI is in sync (counts are updated optimistically)
      // Wrap each reload in try-catch to prevent one failure from crashing the whole operation
      if (mounted) {
        try {
          await _checkUserReaction();
        } catch (reloadError) {
          if (kDebugMode) {
            print('ERROR reloading user reaction after react: $reloadError');
          }
          // Continue even if reload fails
        }

        // Also reload reaction counts to ensure accuracy
        try {
          await _loadReactionCounts();
        } catch (reloadError) {
          if (kDebugMode) {
            print('ERROR reloading reaction counts after react: $reloadError');
          }
          // Continue even if reload fails
        }
      }
    } catch (e, stackTrace) {
      // Log error for debugging
      if (kDebugMode) {
        print('=== ERROR in _reactToPost ===');
        print('Error: $e');
        print('Error type: ${e.runtimeType}');
        print('Stack trace: $stackTrace');
      }

      // Revert on error - wrap in try-catch to prevent setState crash
      if (mounted) {
        try {
          setState(() {
            _userReaction = previousReaction;
            // Revert counts
            if (!wasReacted) {
              _likesCount--;
              _reactionCounts[type] = (_reactionCounts[type] ?? 1) - 1;
              if (_reactionCounts[type] == 0) {
                _reactionCounts.remove(type);
              }
            } else if (previousReaction != type) {
              // Revert the change
              _reactionCounts[type] = (_reactionCounts[type] ?? 1) - 1;
              if (_reactionCounts[type] == 0) {
                _reactionCounts.remove(type);
              }
              _reactionCounts[previousReaction] =
                  (_reactionCounts[previousReaction] ?? 0) + 1;
            } else {
              // Revert the removal
              _likesCount++;
              _reactionCounts[type] = (_reactionCounts[type] ?? 0) + 1;
            }
          });
        } catch (setStateError) {
          if (kDebugMode) {
            print('ERROR in setState (revert): $setStateError');
          }
          // Don't crash, just log
        }
      }

      // Try to reload reaction state - wrap in try-catch
      if (mounted) {
        try {
          await _checkUserReaction();
        } catch (reloadError) {
          if (kDebugMode) {
            print(
              'ERROR reloading user reaction (error handler): $reloadError',
            );
          }
          // Don't crash, just log
        }
      }

      // Show error message - wrap in try-catch to prevent crash
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            ErrorMessageHelper.createErrorSnackBar(
              e,
              defaultMessage: 'Không thể bày tỏ cảm xúc',
            ),
          );
        } catch (snackBarError) {
          if (kDebugMode) {
            print('ERROR showing SnackBar: $snackBarError');
          }
          // Don't crash if SnackBar fails
        }
      }
    } finally {
      // Always clear processing flag, even if there was an error
      if (kDebugMode) {
        print('_reactToPost: Finally block - mounted: $mounted');
      }

      if (mounted) {
        try {
          setState(() {
            _isProcessingReaction = false;
          });
          if (kDebugMode) {
            print('_reactToPost: Processing flag cleared');
          }
        } catch (setStateError) {
          if (kDebugMode) {
            print('ERROR in setState (finally block): $setStateError');
            print('Stack trace: ${StackTrace.current}');
          }
          // Ignore setState errors in finally block to prevent crash
        }
      } else {
        if (kDebugMode) {
          print(
            '_reactToPost: Widget not mounted, cannot clear processing flag',
          );
        }
      }

      if (kDebugMode) {
        print('=== _reactToPost END ===');
      }
    }
  }

  Future<void> _showReactionUsersDialog(ReactionType reactionType) async {
    try {
      final userIds = await _firestoreService.getPostReactionUsers(
        widget.post.id,
        reactionType,
      );

      if (userIds.isEmpty) return;

      if (!mounted) return;

      final users = <UserModel>[];
      for (final userId in userIds) {
        final user = await _userService.getUserById(userId);
        if (user != null) {
          users.add(user);
        }
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          return AlertDialog(
            backgroundColor: theme.cardColor,
            title: Row(
              children: [
                Text(reactionType.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${reactionType.name} (${users.length})',
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: theme.iconTheme.color),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: users.isEmpty
                  ? Center(
                      child: Text(
                        'Chưa có người nào',
                        style: TextStyle(
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: user.avatarUrl != null
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(
                                    user.fullName.isNotEmpty
                                        ? user.fullName[0].toUpperCase()
                                        : '?',
                                  )
                                : null,
                          ),
                          title: Text(
                            user.fullName,
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                          subtitle: Text(
                            '@${user.username}',
                            style: TextStyle(
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    OtherUserProfileScreen(user: user),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(
            e,
            defaultMessage: 'Không thể chia sẻ bài viết',
          ),
        );
      }
    }
  }

  Future<void> _showAllReactionsDialog() async {
    try {
      // Lazy-load reaction breakdown only when user taps (avoid heavy query per post).
      if (_reactionCounts.isEmpty && _likesCount > 0) {
        await _loadReactionCounts();
      }
      if (_reactionCounts.isEmpty) return;

      if (!mounted) return;

      // Lấy tất cả users cho tất cả reaction types
      final Map<ReactionType, List<UserModel>> reactionUsers = {};

      for (final entry in _reactionCounts.entries) {
        final userIds = await _firestoreService.getPostReactionUsers(
          widget.post.id,
          entry.key,
        );

        final users = <UserModel>[];
        for (final userId in userIds) {
          final user = await _userService.getUserById(userId);
          if (user != null) {
            users.add(user);
          }
        }
        reactionUsers[entry.key] = users;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          return AlertDialog(
            backgroundColor: theme.cardColor,
            title: Row(
              children: [
                Text(
                  'Tất cả cảm xúc',
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: theme.iconTheme.color),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: reactionUsers.length,
                itemBuilder: (context, index) {
                  final entry = reactionUsers.entries.elementAt(index);
                  final reactionType = entry.key;
                  final users = entry.value;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (index > 0) Divider(color: theme.dividerColor),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Text(
                              reactionType.emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${reactionType.name} (${users.length})',
                              style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...users.map(
                        (user) => ListTile(
                          leading: CircleAvatar(
                            backgroundImage: user.avatarUrl != null
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(
                                    user.fullName.isNotEmpty
                                        ? user.fullName[0].toUpperCase()
                                        : '?',
                                  )
                                : null,
                          ),
                          title: Text(
                            user.fullName,
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                          subtitle: Text(
                            '@${user.username}',
                            style: TextStyle(
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    OtherUserProfileScreen(user: user),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(
            e,
            defaultMessage: 'Không thể chia sẻ bài viết',
          ),
        );
      }
    }
  }

  Future<void> _openReactionSheet() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null || !mounted) return;

    // Nếu đã thả cảm xúc rồi, tap lần nữa sẽ gỡ cảm xúc hiện tại
    if (_userReaction != null) {
      await _reactToPost(_userReaction!);
      return;
    }

    // Prevent multiple calls
    if (_isProcessingReaction) {
      if (kDebugMode) {
        print('Reaction already processing, ignoring');
      }
      return;
    }

    try {
      if (!mounted) return;

      final selected = await showModalBottomSheet<ReactionType>(
        context: context,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder: (ctx) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: ReactionType.values.map((type) {
                  return GestureDetector(
                    onTap: () {
                      // Close modal immediately
                      Navigator.of(ctx).pop(type);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        type.emoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        },
      );

      // Only process if modal was closed with a selection and widget is still mounted
      if (selected != null && mounted) {
        // Use unawaited to prevent blocking, but still handle errors
        _reactToPost(selected).catchError((error) {
          if (kDebugMode) {
            print('ERROR in _reactToPost (from _openReactionSheet): $error');
          }
          // Error is already handled in _reactToPost, just log here
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('ERROR in _openReactionSheet: $e');
        print('Stack trace: $stackTrace');
      }
      // Don't crash the app, just log the error
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ErrorMessageHelper.getErrorMessage(
                  e,
                  defaultMessage: 'Không thể hiển thị bày tỏ cảm xúc',
                ),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        } catch (snackBarError) {
          if (kDebugMode) {
            print(
              'ERROR showing SnackBar in _openReactionSheet: $snackBarError',
            );
          }
        }
      }
    }
  }

  Future<void> _showPostOptionsMenu(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final isOwnPost = widget.post.userId == currentUser.id;
    final authorName = _postUser?.fullName ?? 'Người dùng';
    // Check if current user is tagged and not removed
    final isCurrentUserTagged = widget.post.taggedUserIds.contains(currentUser.id) &&
        !widget.post.removedTaggedUserIds.contains(currentUser.id);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Options list
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Section: Post actions
                      // Show "Gỡ thẻ" option if current user is tagged
                      if (isCurrentUserTagged)
                        _buildMenuOption(
                          icon: Icons.label_off,
                          title: 'Gỡ thẻ',
                          description: 'Gỡ thẻ của bạn khỏi bài viết này. Bài viết sẽ không hiển thị trong mục "Được gắn thẻ" của bạn.',
                          titleColor: Colors.red,
                          onTap: () async {
                            Navigator.pop(ctx);
                            // Show confirmation dialog
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                title: const Text('Gỡ thẻ'),
                                content: const Text('Bạn có chắc chắn muốn gỡ thẻ khỏi bài viết này? Bài viết sẽ không hiển thị trong mục "Được gắn thẻ" của bạn nữa.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogCtx, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogCtx, true),
                                    child: const Text('Gỡ thẻ', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              try {
                                await _firestoreService.removeTagFromPost(
                                  widget.post.id,
                                  currentUser.id,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã gỡ thẻ khỏi bài viết'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    ErrorMessageHelper.createErrorSnackBar(e),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      _buildMenuOption(
                        icon: _isPostSaved
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        title: _isPostSaved
                            ? 'Bỏ lưu bài viết'
                            : 'Lưu bài viết',
                        description: _isPostSaved
                            ? 'Xóa khỏi danh sách các mục đã lưu.'
                            : 'Thêm vào danh sách các mục đã lưu.',
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            if (_isPostSaved) {
                              await _firestoreService.unsavePost(
                                widget.post.id,
                                currentUser.id,
                              );
                              if (mounted) {
                                setState(() {
                                  _isPostSaved = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã bỏ lưu bài viết'),
                                  ),
                                );
                              }
                            } else {
                              await _firestoreService.savePost(
                                widget.post.id,
                                currentUser.id,
                              );
                              if (mounted) {
                                setState(() {
                                  _isPostSaved = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã lưu bài viết'),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                ErrorMessageHelper.createErrorSnackBar(e),
                              );
                            }
                          }
                        },
                      ),
                      _buildMenuOption(
                        icon: Icons.visibility_off_outlined,
                        title: 'Ẩn bài viết',
                        description: 'Ẩn bớt các bài viết tương tự.',
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await _firestoreService.hidePost(
                              widget.post.id,
                              currentUser.id,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Đã ẩn bài viết')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                ErrorMessageHelper.createErrorSnackBar(e),
                              );
                            }
                          }
                        },
                      ),
                      _buildMenuOption(
                        icon: Icons.link_outlined,
                        title: 'Sao chép liên kết',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _copyPostLink();
                        },
                      ),
                      if (!isOwnPost) ...[
                        const Divider(height: 1),
                        _buildMenuOption(
                          icon: Icons.access_time_outlined,
                          title: 'Tạm ẩn $authorName trong 30 ngày',
                          description: 'Tạm thời không nhìn thấy bài viết nữa. Bạn có thể bỏ ẩn bất cứ lúc nào.',
                          onTap: () async {
                            Navigator.pop(ctx);
                            // Show confirmation dialog
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                title: const Text('Tạm ẩn người dùng'),
                                content: Text(
                                  'Bạn có chắc chắn muốn tạm ẩn $authorName trong 30 ngày? Bạn sẽ không nhìn thấy bài viết của họ trong feed, nhưng vẫn là bạn bè. Bạn có thể bỏ ẩn bất cứ lúc nào trong mục "Quản lý Bảng feed".',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogCtx, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogCtx, true),
                                    child: const Text('Tạm ẩn', style: TextStyle(color: Colors.blue)),
                                  ),
                                ],
                              ),
                            );
                            
                            if (confirmed == true) {
                              try {
                                await _firestoreService.temporarilyHideUser(
                                  currentUser.id,
                                  widget.post.userId,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã tạm ẩn người dùng trong 30 ngày'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    ErrorMessageHelper.createErrorSnackBar(e),
                                  );
                                }
                              }
                            }
                          },
                        ),
                        _buildMenuOption(
                          icon: Icons.block_outlined,
                          title: 'Ẩn tất cả từ $authorName',
                          description:
                              'Ngừng theo dõi, nhưng không hủy kết bạn. Bạn có thể bỏ ẩn bất cứ lúc nào.',
                          onTap: () async {
                            Navigator.pop(ctx);
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                title: const Text('Ẩn tất cả bài viết'),
                                content: Text(
                                  'Bạn có chắc chắn muốn ẩn tất cả bài viết từ $authorName? Bạn sẽ không nhìn thấy bài viết của họ trong feed nữa, nhưng vẫn là bạn bè. Bạn có thể bỏ ẩn bất cứ lúc nào trong mục "Quản lý Bảng feed".',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogCtx, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogCtx, true),
                                    child: const Text('Ẩn', style: TextStyle(color: Colors.blue)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              try {
                                await _feedControlService.unfollowUser(
                                  currentUser.id,
                                  widget.post.userId,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã ẩn tất cả bài viết từ người dùng này'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    ErrorMessageHelper.createErrorSnackBar(e),
                                  );
                                }
                              }
                            }
                          },
                        ),
                        _buildMenuOption(
                          icon: Icons.person_off_outlined,
                          title: 'Chặn trang cá nhân của $authorName',
                          description:
                              'Các bạn sẽ không thể nhìn thấy hoặc liên hệ với nhau.',
                          onTap: () async {
                            Navigator.pop(ctx);
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                title: const Text('Chặn người dùng'),
                                content: Text(
                                  'Bạn có chắc chắn muốn chặn $authorName? Các bạn sẽ không thể nhìn thấy hoặc liên hệ với nhau.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogCtx, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogCtx, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Chặn'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              try {
                                final blockService = BlockService();
                                await blockService.blockUser(
                                  currentUser.id,
                                  widget.post.userId,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã chặn người dùng'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    ErrorMessageHelper.createErrorSnackBar(e),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      ],
                      // Edit and Delete post options (only for own posts)
                      if (isOwnPost) ...[
                        const Divider(height: 1),
                        _buildMenuOption(
                          icon: Icons.edit_outlined,
                          title: 'Chỉnh sửa bài viết',
                          description: 'Chỉnh sửa nội dung, ảnh, video và các thông tin khác của bài viết.',
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CreatePostScreen(postToEdit: widget.post),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        _buildMenuOption(
                          icon: Icons.delete_outline,
                          title: 'Xóa bài viết',
                          titleColor: Colors.red,
                          onTap: () async {
                            Navigator.pop(ctx);
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                title: const Text('Xóa bài viết'),
                                content: const Text(
                                  'Bạn có chắc chắn muốn xóa bài viết này? Hành động này không thể hoàn tác.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogCtx, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogCtx, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('Xóa'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              try {
                                await _firestoreService.deletePost(
                                  widget.post.id,
                                );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã xóa bài viết'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  // Optionally, you can navigate back or refresh the feed
                                  // Navigator.of(context).pop();
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    ErrorMessageHelper.createErrorSnackBar(e),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showShareSheet(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      'Chia sẻ bài viết',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: theme.iconTheme.color),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              // Share options
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Share to story
                      _buildShareOption(
                        icon: Icons.auto_stories,
                        iconColor: Colors.purple,
                        title: 'Chia sẻ lên tin của bạn',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _sharePostToStory();
                        },
                      ),
                      // Share to profile
                      _buildShareOption(
                        icon: Icons.person,
                        iconColor: Colors.blue,
                        title: 'Chia sẻ lên trang cá nhân',
                        onTap: () async {
                          Navigator.pop(ctx);
                          try {
                            await _firestoreService.sharePost(
                              widget.post.id,
                              currentUser.id,
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Đã chia sẻ bài viết lên trang cá nhân',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                ErrorMessageHelper.createErrorSnackBar(e),
                              );
                            }
                          }
                        },
                      ),
                      // Send in message
                      _buildShareOption(
                        icon: Icons.message,
                        iconColor: Colors.blue,
                        title: 'Gửi trong tin nhắn',
                        onTap: () {
                          Navigator.pop(ctx);
                          // Navigate to messages list to select recipient with postId
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MessagesListScreen(
                                postIdToShare: widget.post.id,
                              ),
                            ),
                          );
                        },
                      ),
                      // Copy link
                      _buildShareOption(
                        icon: Icons.link,
                        iconColor: Colors.blue[700]!,
                        title: 'Sao chép liên kết',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _copyPostLink();
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShareOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
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
                  Icons.chevron_right,
                  color: theme.iconTheme.color?.withOpacity(0.6),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sharePostToStory() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng đăng nhập'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Tạo link đến bài viết
      final postLink = 'https://synap.app/post/${widget.post.id}';

      // Lấy ảnh đầu tiên của bài viết (nếu có) để làm ảnh nền cho story
      String? imageUrl;
      if (widget.post.mediaUrls.isNotEmpty) {
        imageUrl = widget.post.mediaUrls.first;
      }

      // Tạo text overlay với thông tin bài viết
      final postText = widget.post.content.isNotEmpty
          ? widget.post.content
          : 'Xem bài viết';
      final textOverlay = StoryTextOverlay(
        text: postText.length > 100
            ? '${postText.substring(0, 100)}...'
            : postText,
        x: 0.5, // Giữa màn hình
        y: 0.8, // Gần dưới cùng
        color: '#FFFFFF',
        fontSize: 20.0,
        isBold: true,
        textAlign: TextAlign.center,
      );

      // Tạo story link
      final storyLink = StoryLink(
        url: postLink,
        title: 'Bài viết từ ${_postUser?.fullName ?? "Người dùng"}',
        description: widget.post.content.isNotEmpty
            ? (widget.post.content.length > 150
                  ? '${widget.post.content.substring(0, 150)}...'
                  : widget.post.content)
            : null,
        imageUrl: imageUrl,
      );

      // Tạo story
      final story = StoryModel(
        id: '',
        userId: currentUser.id,
        imageUrl: imageUrl, // Ảnh đầu tiên của bài viết làm ảnh nền
        text: null, // Không dùng text field, dùng textOverlay thay thế
        privacy: PrivacyType.public, // Mặc định public
        textOverlays: [textOverlay],
        link: storyLink,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      await _storyService.createStory(story);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã chia sẻ bài viết lên tin của bạn'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorMessageHelper.getErrorMessage(
                e,
                defaultMessage: 'Không thể chia sẻ bài viết',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyPostLink() async {
    try {
      // Tạo link đến bài viết
      final postLink = 'https://synap.app/post/${widget.post.id}';

      // Copy vào clipboard
      await Clipboard.setData(ClipboardData(text: postLink));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đã sao chép liên kết bài viết',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Không thể sao chép liên kết: $e',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    String? description,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final defaultColor = titleColor ?? theme.textTheme.bodyLarge?.color;
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 24, color: titleColor ?? defaultColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: titleColor ?? defaultColor,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Get translated content if auto-translate is enabled
  Future<String> _getTranslatedContent(
    String originalText,
    LanguageProvider languageProvider,
  ) async {
    // Nếu không bật auto-translate, trả về text gốc
    if (!languageProvider.autoTranslate) {
      return originalText;
    }

    // Nếu ngôn ngữ hiện tại là tiếng Việt, không cần dịch
    final currentLang = languageProvider.currentLanguageCode;
    if (currentLang == 'vi') {
      return originalText;
    }

    try {
      // Dịch từ tiếng Việt sang ngôn ngữ đích
      final translated = await _translateService.translate(
        text: originalText,
        source: 'vi',
        target: currentLang,
      );

      return translated;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error translating post content: $e');
      }
      return originalText; // Trả về text gốc nếu lỗi
    }
  }

  String _formatDate(DateTime date) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      color: theme.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group badge (if post belongs to a group)
          if (_group != null)
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupDetailScreen(group: _group!),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(
                      color: theme.dividerColor,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.group,
                      size: 16,
                      color: theme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _group!.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '·',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Bài viết trong nhóm',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Post header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar
                GestureDetector(
                  onTap: () {
                    if (_postUser != null) {
                      _openProfile(context, _postUser!);
                    }
                  },
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.scaffoldBackgroundColor,
                    backgroundImage: _postUser?.avatarUrl != null
                        ? NetworkImage(_postUser!.avatarUrl!)
                        : null,
                    child: _postUser?.avatarUrl == null
                        ? Text(
                            (_postUser?.fullName.isNotEmpty == true)
                                ? _postUser!.fullName[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // Name and time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () {
                                if (_postUser != null) {
                                  _openProfile(context, _postUser!);
                                }
                              },
                              child: Text(
                                _postUser?.fullName ?? 'Người dùng',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                          // Feeling display inline with name
                          if (widget.post.feeling != null &&
                              _postUser != null) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: _buildFeelingTextInline(
                                widget.post.feeling!,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            _formatDate(widget.post.createdAt),
                            style: TextStyle(
                              color: theme.textTheme.bodySmall?.color,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            widget.post.privacy.icon,
                            size: 12,
                            color: theme.iconTheme.color?.withOpacity(0.6),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // More options
                IconButton(
                  icon: Icon(Icons.more_horiz, color: theme.iconTheme.color),
                  onPressed: () => _showPostOptionsMenu(context),
                ),
              ],
            ),
          ),

          // Milestone display
          if (widget.post.milestoneCategory != null &&
              widget.post.milestoneEvent != null &&
              _postUser != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _buildMilestoneText(),
            ),

          // Tagged users info - hiển thị tất cả người được gắn thẻ
          if (_taggedUsers.isNotEmpty)
            Builder(
              builder: (context) {
                final authProvider = context.read<AuthProvider>();
                final currentUser = authProvider.currentUser;
                final isCurrentUserTagged = currentUser != null &&
                    widget.post.taggedUserIds.contains(currentUser.id) &&
                    !widget.post.removedTaggedUserIds.contains(currentUser.id);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isCurrentUserTagged 
                          ? Colors.blue.withOpacity(0.15)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrentUserTagged 
                            ? Colors.blue.withOpacity(0.4)
                            : Colors.grey.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.label, size: 18, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isCurrentUserTagged)
                                Text(
                                  _postUser != null
                                      ? '${_postUser!.fullName} đã gắn thẻ bạn'
                                      : 'Đã gắn thẻ bạn',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              if (_taggedUsers.length == 1)
                                Text(
                                  'Đã gắn thẻ ${_taggedUsers.first.fullName}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: theme.textTheme.bodyMedium?.color,
                                  ),
                                )
                              else
                                Text(
                                  'Đã gắn thẻ ${_taggedUsers.map((u) => u.fullName).join(", ")}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          // Post content
          if (widget.post.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Consumer<LanguageProvider>(
                builder: (context, languageProvider, _) {
                  return FutureBuilder<String>(
                    future: _getTranslatedContent(
                      widget.post.content,
                      languageProvider,
                    ),
                    builder: (context, snapshot) {
                      final displayText = snapshot.data ?? widget.post.content;
                      return Text(
                        displayText,
                        style: TextStyle(
                          fontSize: 15,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      );
                    },
                  );
                },
              ),
            ),

          // Shared post content (original post)
          if (widget.post.sharedPostId != null && _originalPost != null) ...[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Original post header
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (_originalPostUser != null) {
                              _openProfile(context, _originalPostUser!);
                            }
                          },
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.scaffoldBackgroundColor,
                            backgroundImage:
                                _originalPostUser?.avatarUrl != null
                                ? NetworkImage(_originalPostUser!.avatarUrl!)
                                : null,
                            child: _originalPostUser?.avatarUrl == null
                                ? Text(
                                    (_originalPostUser?.fullName.isNotEmpty ==
                                            true)
                                        ? _originalPostUser!.fullName[0]
                                              .toUpperCase()
                                        : 'U',
                                    style: TextStyle(
                                      color: theme.textTheme.bodyLarge?.color,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (_originalPostUser != null) {
                                    _openProfile(context, _originalPostUser!);
                                  }
                                },
                                child: Text(
                                  _originalPostUser?.fullName ?? 'Người dùng',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: theme.textTheme.bodyLarge?.color,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    _originalPost != null
                                        ? _formatDate(_originalPost!.createdAt)
                                        : '',
                                    style: TextStyle(
                                      color: theme.textTheme.bodySmall?.color,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.public,
                                    size: 12,
                                    color: theme.iconTheme.color?.withOpacity(
                                      0.6,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Original post content
                  if (_originalPost != null &&
                      _originalPost!.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Consumer<LanguageProvider>(
                        builder: (context, languageProvider, _) {
                          return FutureBuilder<String>(
                            future: _getTranslatedContent(
                              _originalPost!.content,
                              languageProvider,
                            ),
                            builder: (context, snapshot) {
                              final displayText = snapshot.data ?? _originalPost!.content;
                              return Text(
                                displayText,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.textTheme.bodyLarge?.color,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  // Original post images
                  if (_originalPost != null &&
                      _originalPost!.mediaUrls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    if (_originalPost!.mediaUrls.length == 1)
                      CachedNetworkImageWidget(
                        imageUrl: _originalPost!.mediaUrls[0],
                        width: double.infinity,
                        height: 300,
                        fit: BoxFit.cover,
                      )
                    else
                      SizedBox(
                        height: 250,
                        child: GridView.builder(
                          scrollDirection: Axis.horizontal,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 1,
                                mainAxisSpacing: 4,
                              ),
                          itemCount: _originalPost!.mediaUrls.length,
                          itemBuilder: (context, index) {
                            return CachedNetworkImageWidget(
                              imageUrl: _originalPost!.mediaUrls[index],
                              width: 250,
                              height: 250,
                              fit: BoxFit.cover,
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ] else if (widget.post.sharedPostId != null) ...[
            // Original post không tải được (bị xóa / không có quyền xem)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Không thể tải bài viết gốc (có thể đã bị xóa hoặc bạn không có quyền xem).',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
          ],

          // Post images (only if not a shared post)
          // Video (only if not a shared post)
          if (widget.post.videoUrl != null &&
              widget.post.videoUrl!.isNotEmpty &&
              widget.post.sharedPostId == null) ...[
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: _videoController?.value.aspectRatio ?? 16 / 9,
              child: FutureBuilder(
                future: _initializeVideoFuture,
                builder: (context, snapshot) {
                  if (_initializeVideoFuture == null) {
                    return _buildVideoPlaceholder();
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(child: Text('Không tải được video'));
                  }
                  if (_videoController == null ||
                      !_videoController!.value.isInitialized) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: VideoPlayer(_videoController!),
                      ),
                      // Progress bar with scrub handle
                      if (_isVideoInitialized &&
                          _videoDuration.inMilliseconds > 0)
                        Positioned(
                          bottom: 50,
                          left: 8,
                          right: 8,
                          child: GestureDetector(
                            onTapDown: (details) async {
                              if (_videoController != null &&
                                  _videoController!.value.isInitialized) {
                                final RenderBox? renderBox =
                                    context.findRenderObject() as RenderBox?;
                                if (renderBox != null) {
                                  final localPosition = renderBox.globalToLocal(
                                    details.globalPosition,
                                  );
                                  final double progress =
                                      (localPosition.dx / renderBox.size.width)
                                          .clamp(0.0, 1.0);
                                  final newPosition = Duration(
                                    milliseconds:
                                        (_videoDuration.inMilliseconds *
                                                progress)
                                            .round(),
                                  );
                                  await _seekVideo(newPosition);
                                }
                              }
                            },
                            onHorizontalDragStart: (details) async {
                              if (_videoController != null &&
                                  _videoController!.value.isInitialized) {
                                final RenderBox? renderBox =
                                    context.findRenderObject() as RenderBox?;
                                if (renderBox != null) {
                                  final localPosition = renderBox.globalToLocal(
                                    details.globalPosition,
                                  );
                                  final double progress =
                                      (localPosition.dx / renderBox.size.width)
                                          .clamp(0.0, 1.0);
                                  final newPosition = Duration(
                                    milliseconds:
                                        (_videoDuration.inMilliseconds *
                                                progress)
                                            .round(),
                                  );
                                  await _seekVideo(newPosition);
                                }
                              }
                            },
                            onHorizontalDragUpdate: (details) async {
                              if (_videoController != null &&
                                  _videoController!.value.isInitialized) {
                                final RenderBox? renderBox =
                                    context.findRenderObject() as RenderBox?;
                                if (renderBox != null) {
                                  final localPosition = renderBox.globalToLocal(
                                    details.globalPosition,
                                  );
                                  final double progress =
                                      (localPosition.dx / renderBox.size.width)
                                          .clamp(0.0, 1.0);
                                  final newPosition = Duration(
                                    milliseconds:
                                        (_videoDuration.inMilliseconds *
                                                progress)
                                            .round(),
                                  );
                                  await _seekVideo(newPosition);
                                }
                              }
                            },
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final progress =
                                      _videoDuration.inMilliseconds > 0
                                      ? (_videoPosition.inMilliseconds /
                                                _videoDuration.inMilliseconds)
                                            .clamp(0.0, 1.0)
                                      : 0.0;
                                  return Stack(
                                    children: [
                                      // Progress indicator
                                      FractionallySizedBox(
                                        widthFactor: progress,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Scrub handle (draggable circle)
                                      Positioned(
                                        left:
                                            (progress * constraints.maxWidth) -
                                            6,
                                        top: -3,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.35,
                                                ),
                                                blurRadius: 4,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      // Video controls: Rewind, Play/Pause, Forward
                      if (_videoController != null &&
                          _videoController!.value.isInitialized)
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Rewind 10 seconds
                              IconButton(
                                iconSize: 32,
                                color: Colors.white,
                                icon: const Icon(Icons.replay_10),
                                onPressed: () async {
                                  if (_videoController != null &&
                                      _videoController!.value.isInitialized) {
                                    final currentPosition =
                                        _videoController!.value.position;
                                    final newPosition =
                                        currentPosition -
                                        const Duration(seconds: 10);
                                    await _seekVideo(
                                      newPosition < Duration.zero
                                          ? Duration.zero
                                          : newPosition,
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              // Play/Pause button
                              IconButton(
                                iconSize: 40,
                                color: Colors.white,
                                icon: Icon(
                                  _videoController!.value.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_fill,
                                ),
                                onPressed: () {
                                  if (_videoController != null &&
                                      _videoController!.value.isInitialized) {
                                    setState(() {
                                      if (_videoController!.value.isPlaying) {
                                        _videoController!.pause();
                                      } else {
                                        _videoController!.play();
                                      }
                                    });
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              // Forward 10 seconds
                              IconButton(
                                iconSize: 32,
                                color: Colors.white,
                                icon: const Icon(Icons.forward_10),
                                onPressed: () async {
                                  if (_videoController != null &&
                                      _videoController!.value.isInitialized) {
                                    final currentPosition =
                                        _videoController!.value.position;
                                    final duration =
                                        _videoController!.value.duration;
                                    final newPosition =
                                        currentPosition +
                                        const Duration(seconds: 10);
                                    await _seekVideo(
                                      newPosition > duration
                                          ? duration
                                          : newPosition,
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              // Fullscreen button
                              IconButton(
                                iconSize: 32,
                                color: Colors.white,
                                icon: const Icon(Icons.fullscreen),
                                onPressed: () {
                                  if (_videoController != null &&
                                      _videoController!.value.isInitialized) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            VideoFullscreenScreen(
                                              controller: _videoController!,
                                              videoUrl: widget.post.videoUrl!,
                                            ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],

          if (widget.post.mediaUrls.isNotEmpty &&
              widget.post.sharedPostId == null) ...[
            const SizedBox(height: 8),
            if (widget.post.mediaUrls.length == 1)
              // Single image - full width
              CachedNetworkImageWidget(
                imageUrl: widget.post.mediaUrls[0],
                width: double.infinity,
                height: 400,
                fit: BoxFit.cover,
              )
            else
              // Multiple images - grid
              SizedBox(
                height: 300,
                child: GridView.builder(
                  scrollDirection: Axis.horizontal,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 1,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: widget.post.mediaUrls.length,
                  itemBuilder: (context, index) {
                    return CachedNetworkImageWidget(
                      imageUrl: widget.post.mediaUrls[index],
                      width: 300,
                      height: 300,
                      fit: BoxFit.cover,
                    );
                  },
                ),
              ),
          ],

          // Reactions and comments count
          if (_likesCount > 0 || widget.post.commentsCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (_likesCount > 0) ...[
                    // Reaction emojis
                    ..._reactionCounts.entries.take(3).map((entry) {
                      return GestureDetector(
                        onTap: () => _showReactionUsersDialog(entry.key),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            entry.key.emoji,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      );
                    }),
                    GestureDetector(
                      onTap: () => _showAllReactionsDialog(),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, right: 4),
                        child: Text(
                          _likesCount.toString(),
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_likesCount > 0 && widget.post.commentsCount > 0)
                    const SizedBox(width: 16),
                  if (widget.post.commentsCount > 0)
                    Text(
                      strings?.postComments(widget.post.commentsCount) ?? '${widget.post.commentsCount} bình luận',
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),

          // Divider
          Divider(height: 1, thickness: 1, color: theme.dividerColor),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomLeft,
              children: [
                Row(
                  children: [
                    // Like button (takes 1/3 width) - fixed icon/text style
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.favorite_border,
                        label: _userReaction?.name ?? 'Thích',
                        emoji: _userReaction?.emoji,
                        color: _userReaction != null
                            ? theme.primaryColor
                            : theme.iconTheme.color?.withOpacity(0.6),
                        onTap: _openReactionSheet,
                      ),
                    ),
                    // Comment button (takes 1/3 width)
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.chat_bubble_outline,
                        label: 'Bình luận',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PostDetailScreen(post: widget.post),
                            ),
                          );
                        },
                      ),
                    ),
                    // Share button (takes 1/3 width)
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.share_outlined,
                        label: 'Chia sẻ',
                        onTap: () => _showShareSheet(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? emoji;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emoji,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedColor =
        color ?? theme.iconTheme.color?.withOpacity(0.6) ?? Colors.grey[700]!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (emoji != null) ...[
              Text(
                emoji!,
                style: TextStyle(fontSize: 18, color: resolvedColor),
              ),
              const SizedBox(width: 4),
            ] else ...[
              Icon(icon, color: resolvedColor, size: 18),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: resolvedColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
