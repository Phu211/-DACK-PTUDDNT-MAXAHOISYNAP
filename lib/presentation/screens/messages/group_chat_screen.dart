import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../../../data/services/user_service.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/services/message_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/group_call_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../screens/calls/group_call_screen.dart';
import '../../widgets/emoji_picker_widget.dart';
import 'group_chat_info_screen.dart';
import '../../../data/services/voice_recording_service.dart';
import '../../widgets/voice_message_widget.dart';
import '../../../data/services/location_sharing_service.dart';
import '../../widgets/location_message_widget.dart';
import '../../../data/services/firestore_service.dart';
import '../post/post_detail_screen.dart';
import '../../../core/utils/error_message_helper.dart';
import 'group_chat_screen_forward_dialog.dart';
import '../../../data/services/settings_service.dart';

class GroupChatScreen extends StatefulWidget {
  final GroupModel group;
  final bool enableSearch;
  final String? scrollToMessageId;

  const GroupChatScreen({
    super.key,
    required this.group,
    this.enableSearch = false,
    this.scrollToMessageId,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final MessageService _messageService = MessageService();
  final StorageService _storageService = StorageService();
  final UserService _userService = UserService();
  final GroupCallService _groupCallService = GroupCallService();
  final ImagePicker _picker = ImagePicker();
  final List<String> _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final AudioPlayer _voicePlayer = AudioPlayer();
  final ScrollController _scrollController = ScrollController();
  bool _isSearching = false;
  StreamSubscription<MessageModel?>? _incomingSub;
  Timer? _typingTimer;
  PlayerState _voiceState = PlayerState.stopped;
  MessageModel? _replyingTo;
  bool _isLoading = false;
  bool _showEmojiPicker = false;
  List<File> _selectedImages = [];
  List<File> _selectedVideos = [];
  String? _selectedGifUrl;
  Map<String, UserModel> _memberCache = {};
  bool _isRecordingVoice = false;
  int _recordingDuration = 0;
  StreamSubscription<int>? _recordingDurationSub;
  final VoiceRecordingService _voiceRecordingService = VoiceRecordingService();
  final LocationSharingService _locationService = LocationSharingService();
  // TODO: Thay YOUR_GIPHY_API_KEY bằng Giphy API key thực tế của bạn
  // Lấy tại: https://developers.giphy.com/dashboard/
  static const String _giphyApiKey = 'YOUR_GIPHY_API_KEY';
  String? _pendingScrollToMessageId;
  bool _readReceiptsEnabled = true; // Read receipts setting
  bool _showMoreOptionsMenu = false; // State để hiển thị menu tính năng từ dấu +
  bool _hasText = false; // Track xem có text hay không để tránh rebuild không cần thiết

  void _onMessageTextChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      // Sử dụng WidgetsBinding để đảm bảo focus được giữ lại sau rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _hasText = hasText;
          });
          // Đảm bảo focus được giữ lại
          if (!_messageFocusNode.hasFocus && _messageController.text.isNotEmpty) {
            _messageFocusNode.requestFocus();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageTextChanged);
    _messageController.dispose();
    _messageFocusNode.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    _incomingSub?.cancel();
    _recordingDurationSub?.cancel();
    _typingTimer?.cancel();
    _voicePlayer.dispose();
    _voiceRecordingService.dispose();
    _replyingTo = null;
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Listen to text changes để update _hasText mà không cần setState trong onChanged
    _messageController.addListener(_onMessageTextChanged);
    _loadReadReceiptsSetting();
    _voicePlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _voiceState = state;
        });
      }
    });
    _voicePlayer.setReleaseMode(ReleaseMode.stop);
    _isSearching = widget.enableSearch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupConversation();
      _loadMembers();
      if (widget.enableSearch && mounted) {
        _searchFocus.requestFocus();
      }
      if (widget.scrollToMessageId != null && mounted) {
        _pendingScrollToMessageId = widget.scrollToMessageId;
      }
    });
  }

  Future<void> _loadReadReceiptsSetting() async {
    final enabled = await SettingsService.isReadReceiptsEnabled();
    if (mounted) {
      setState(() {
        _readReceiptsEnabled = enabled;
      });
    }
  }

  void _setupConversation() async {
    try {
      await _messageService.getOrCreateGroupConversation(widget.group.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(
            e,
            defaultMessage: 'Không thể gửi tin nhắn',
          ),
        );
      }
    }
  }

  Future<void> _loadMembers() async {
    final members = <String, UserModel>{};
    for (final memberId in widget.group.memberIds) {
      final user = await _userService.getUserById(memberId);
      if (user != null) {
        members[memberId] = user;
      }
    }
    if (mounted) {
      setState(() {
        _memberCache = members;
      });
    }
  }

  void _scrollToMessageInList(List<MessageModel> messages, String messageId) {
    if (!_scrollController.hasClients) return;
    
    final targetIndex = messages.indexWhere((m) => m.id == messageId);
    if (targetIndex == -1) return;

    final estimatedItemHeight = 120.0;
    final maxScroll = _scrollController.position.maxScrollExtent;
    // Messages được reverse nên index từ cuối lên
    final targetPosition = (messages.length - 1 - targetIndex) * estimatedItemHeight;
    final clampedPosition = targetPosition.clamp(0.0, maxScroll);

    _scrollController.animateTo(
      clampedPosition,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty &&
        _selectedImages.isEmpty &&
        _selectedVideos.isEmpty &&
        _selectedGifUrl == null)
      return;

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Send first image if available
      if (_selectedImages.isNotEmpty) {
        final imageUrl = await _storageService.uploadPostImage(
          _selectedImages.first,
          'msg',
          0,
        );
        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: '', // Không cần cho group message
          content: text,
          imageUrl: imageUrl,
          createdAt: DateTime.now(),
          groupId: widget.group.id,
        );
        await _messageService.sendGroupMessage(message);
      }

      // Send first video if available
      if (_selectedVideos.isNotEmpty) {
        final videoUrl = await _storageService.uploadVideo(
          _selectedVideos.first,
          'msg',
        );
        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: '',
          content: text,
          videoUrl: videoUrl,
          createdAt: DateTime.now(),
          groupId: widget.group.id,
        );
        await _messageService.sendGroupMessage(message);
      }

      // Send GIF message if selected
      if (_selectedGifUrl != null) {
        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: '',
          content: text,
          gifUrl: _selectedGifUrl,
          createdAt: DateTime.now(),
          groupId: widget.group.id,
          replyToMessageId: _replyingTo?.id,
          replyToContent: _replyingTo?.content.isNotEmpty == true
              ? _replyingTo!.content
              : (_replyingTo?.imageUrl != null
                    ? '[Ảnh]'
                    : (_replyingTo?.videoUrl != null
                          ? '[Video]'
                          : (_replyingTo?.audioUrl != null
                                ? '[Voice]'
                                : (_replyingTo?.gifUrl != null
                                      ? '[GIF]'
                                      : '')))),
          replyToSenderId: _replyingTo?.senderId,
          replyToType: _replyType(_replyingTo),
        );
        await _messageService.sendGroupMessage(message);
      }

      // Send text message if no media
      if (_selectedImages.isEmpty &&
          _selectedVideos.isEmpty &&
          _selectedGifUrl == null &&
          text.isNotEmpty) {
        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: '',
          content: text,
          createdAt: DateTime.now(),
          groupId: widget.group.id,
          replyToMessageId: _replyingTo?.id,
          replyToContent: _replyingTo?.content.isNotEmpty == true
              ? _replyingTo!.content
              : (_replyingTo?.imageUrl != null
                    ? '[Ảnh]'
                    : (_replyingTo?.videoUrl != null
                          ? '[Video]'
                          : (_replyingTo?.audioUrl != null
                                ? '[Voice]'
                                : (_replyingTo?.gifUrl != null
                                      ? '[GIF]'
                                      : '')))),
          replyToSenderId: _replyingTo?.senderId,
          replyToType: _replyType(_replyingTo),
        );
        await _messageService.sendGroupMessage(message);
      }

      _messageController.clear();
      _selectedImages.clear();
      _selectedVideos.clear();
      _selectedGifUrl = null;
      _replyingTo = null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ErrorMessageHelper.createErrorSnackBar(
            e,
            defaultMessage: 'Không thể gửi tin nhắn',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 20,
                backgroundImage: widget.group.coverUrl != null
                    ? NetworkImage(widget.group.coverUrl!)
                    : null,
                child: widget.group.coverUrl == null
                    ? Text(widget.group.name[0].toUpperCase())
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.group.name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${widget.group.memberIds.length} thành viên',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam, color: AppColors.primary),
            onPressed: () =>
                _startGroupCall(context, currentUser, isVideo: true),
          ),
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.primary),
            onPressed: () =>
                _startGroupCall(context, currentUser, isVideo: false),
          ),
          IconButton(
            icon: const Icon(Icons.info, color: AppColors.primary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupChatInfoScreen(group: widget.group),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSearching)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Tìm tin nhắn...',
                  hintStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.search, color: Colors.black87),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.black87),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          // Messages list
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _messageService.getGroupMessages(
                widget.group.id,
                currentUser.id,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.black),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];
                
                // Scroll đến message nếu có pending
                if (_pendingScrollToMessageId != null && messages.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToMessageInList(messages, _pendingScrollToMessageId!);
                    _pendingScrollToMessageId = null;
                  });
                }
                
                // Tin nhắn đã ghim vẫn ở vị trí ban đầu (theo thời gian tạo), không di chuyển lên đầu
                final sortedMessages = List<MessageModel>.from(messages)
                  ..sort((a, b) {
                    // Sắp xếp theo thời gian tạo (mới nhất trước), không ưu tiên tin nhắn đã ghim
                    return b.createdAt.compareTo(a.createdAt);
                  });
                // Lấy danh sách tin nhắn đã ghim và sort theo pinnedAt (mới nhất trước) để hiển thị trong thanh pinned
                final pinnedMessages =
                    sortedMessages
                        .where((m) => m.isPinned && !m.isRecalled)
                        .toList()
                      ..sort((a, b) {
                        final ap = a.pinnedAt ?? a.createdAt;
                        final bp = b.pinnedAt ?? b.createdAt;
                        return bp.compareTo(ap); // Mới nhất trước
                      });

                String pinnedPreview(MessageModel m) {
                  if (m.isRecalled) return '[Tin nhắn đã thu hồi]';
                  final text = m.content.trim();
                  if (text.isNotEmpty) return text;
                  if (m.imageUrl != null) return '[Ảnh]';
                  if (m.videoUrl != null) return '[Video]';
                  if (m.audioUrl != null) return '[Voice]';
                  if (m.gifUrl != null) return '[GIF]';
                  if (m.latitude != null && m.longitude != null) {
                    return m.isLiveLocation == true
                        ? '[Live Location]'
                        : '[Location]';
                  }
                  return 'Tin nhắn';
                }

                final query = _searchController.text.trim().toLowerCase();
                final filteredMessages = query.isEmpty
                    ? sortedMessages
                    : sortedMessages.where((m) {
                        final text = m.content.toLowerCase();
                        if (text.contains(query)) return true;
                        if (m.imageUrl != null && '[ảnh]'.contains(query))
                          return true;
                        if (m.videoUrl != null && '[video]'.contains(query))
                          return true;
                        if (m.audioUrl != null && '[voice]'.contains(query))
                          return true;
                        return false;
                      }).toList();

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Chưa có tin nhắn nào',
                      style: TextStyle(color: Colors.black87),
                    ),
                  );
                }

                return Column(
                  children: [
                    if (query.isEmpty && pinnedMessages.isNotEmpty)
                      Material(
                        color: Colors.white,
                        child: InkWell(
                          onTap: () {
                            if (!_scrollController.hasClients) return;
                            final targetId = pinnedMessages.first.id;
                            final targetIndex = filteredMessages.indexWhere(
                              (m) => m.id == targetId,
                            );
                            if (targetIndex == -1) return;

                            final estimatedItemHeight = 120.0;
                            final maxScroll =
                                _scrollController.position.maxScrollExtent;
                            final targetPosition =
                                (filteredMessages.length - 1 - targetIndex) *
                                estimatedItemHeight;
                            final clampedPosition = targetPosition.clamp(
                              0.0,
                              maxScroll,
                            );

                            _scrollController.animateTo(
                              clampedPosition,
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey[300]!,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.push_pin,
                                  color: Colors.orange,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tin nhắn đã ghim (${pinnedMessages.length})',
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        pinnedPreview(pinnedMessages.first),
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredMessages.length,
                        itemBuilder: (context, index) {
                          final message = filteredMessages[index];
                          final isMe = message.senderId == currentUser.id;
                          final sender = _memberCache[message.senderId];
                          final reactions = message.reactions;
                          final hasReactions =
                              reactions.isNotEmpty &&
                              reactions.values.any((list) => list.isNotEmpty);

                          if (!isMe && message.status == 'sent') {
                            _messageService.markAsDelivered(
                              message.id,
                              currentUser.id,
                            );
                          }
                          // Chỉ mark as read nếu read receipts được bật
                          if (_readReceiptsEnabled &&
                              !isMe &&
                              (!message.isRead || message.status != 'read')) {
                            _messageService.markAsRead(
                              message.id,
                              currentUser.id,
                            );
                          }

                          final isRecalled = message.isRecalled;
                          final canRecall =
                              isMe &&
                              !isRecalled &&
                              DateTime.now()
                                      .difference(message.createdAt)
                                      .inHours <=
                                  24;
                          final canPin = isMe && !isRecalled;

                          return GestureDetector(
                            onLongPress: () => _showMessageOptionsDialog(
                              context,
                              message,
                              canRecall,
                              canPin,
                            ),
                            child: Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe && sender != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        sender.fullName,
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (message.replyToMessageId != null)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            message.replyToSenderId ==
                                                    currentUser.id
                                                ? 'Bạn'
                                                : (_memberCache[message
                                                              .replyToSenderId]
                                                          ?.fullName ??
                                                      'Người khác'),
                                            style: TextStyle(
                                              color: Colors.grey[800],
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _replyPreviewLabel(message),
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (message.isPinned)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.push_pin,
                                            size: 14,
                                            color: Colors.grey[500],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Đã ghim',
                                            style: TextStyle(
                                              color: Colors.grey[500],
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (isRecalled)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300]!,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.undo,
                                            color: Colors.grey[400],
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Tin nhắn đã được thu hồi',
                                            style: TextStyle(
                                              color: Colors.grey[400],
                                              fontStyle: FontStyle.italic,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else ...[
                                    Builder(
                                      builder: (context) {
                                        final List<Widget> parts = [];

                                        if (message.imageUrl != null) {
                                          parts.add(
                                            Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              constraints: const BoxConstraints(
                                                maxWidth: 250,
                                                maxHeight: 250,
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.network(
                                                  message.imageUrl!,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        if (message.videoUrl != null) {
                                          parts.add(
                                            Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[300]!,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Icon(
                                                    Icons.play_circle_fill,
                                                    color: Colors.black,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Video',
                                                    style: TextStyle(
                                                      color: Colors.black,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }

                                        if (message.latitude != null &&
                                            message.longitude != null) {
                                          parts.add(
                                            LocationMessageWidget(
                                              message: message,
                                              isSentByMe:
                                                  message.senderId ==
                                                  currentUser.id,
                                            ),
                                          );
                                        }

                                        if (message.gifUrl != null) {
                                          parts.add(
                                            Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              constraints: const BoxConstraints(
                                                maxWidth: 250,
                                                maxHeight: 250,
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.network(
                                                  message.gifUrl!,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        if (message.audioUrl != null &&
                                            message.audioUrl!.isNotEmpty) {
                                          parts.add(
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 6,
                                              ),
                                              child: VoiceMessageWidget(
                                                message: message,
                                                isOwnMessage: isMe,
                                                onPlayStateChanged: () {
                                                  setState(() {
                                                    // Update UI when play state changes
                                                  });
                                                },
                                              ),
                                            ),
                                          );
                                        }

                                        if (message.content.isNotEmpty) {
                                          parts.add(
                                            Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isMe
                                                    ? AppColors.primary
                                                    : Colors.grey[300]!,
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),
                                              child: _buildMessageContent(
                                                message.content,
                                                isMe,
                                              ),
                                            ),
                                          );
                                        }

                                        // Đảm bảo có ít nhất một widget để hiển thị
                                        if (parts.isEmpty) {
                                          // Nếu không có gì để hiển thị, hiển thị placeholder
                                          parts.add(
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isMe
                                                    ? AppColors.primary
                                                    : Colors.grey[300]!,
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),
                                              child: const Text(
                                                'Tin nhắn',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        final bubble = Column(
                                          crossAxisAlignment: isMe
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: parts,
                                        );

                                        Widget _avatar(bool me) {
                                          if (me) {
                                            final url = currentUser.avatarUrl;
                                            final name = currentUser.fullName;
                                            return CircleAvatar(
                                              radius: 16,
                                              backgroundColor: Colors.grey[300],
                                              backgroundImage: url != null
                                                  ? NetworkImage(url)
                                                  : null,
                                              child: url == null
                                                  ? Text(
                                                      (name.isNotEmpty
                                                              ? name[0]
                                                              : 'U')
                                                          .toUpperCase(),
                                                      style: const TextStyle(
                                                        color: Colors.black,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    )
                                                  : null,
                                            );
                                          } else {
                                            final sender =
                                                _memberCache[message.senderId];
                                            if (sender == null) {
                                              return const CircleAvatar(
                                                radius: 16,
                                                backgroundColor: Colors.grey,
                                                child: Icon(
                                                  Icons.person,
                                                  size: 16,
                                                ),
                                              );
                                            }
                                            final url = sender.avatarUrl;
                                            final name = sender.fullName;
                                            return CircleAvatar(
                                              radius: 16,
                                              backgroundColor: Colors.grey[300],
                                              backgroundImage: url != null
                                                  ? NetworkImage(url)
                                                  : null,
                                              child: url == null
                                                  ? Text(
                                                      (name.isNotEmpty
                                                              ? name[0]
                                                              : 'U')
                                                          .toUpperCase(),
                                                      style: const TextStyle(
                                                        color: Colors.black,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    )
                                                  : null,
                                            );
                                          }
                                        }

                                        if (isMe) {
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                child: _messageActionBar(
                                                  message: message,
                                                  canRecall: canRecall,
                                                  canPin: canPin,
                                                  isMe: isMe,
                                                ),
                                              ),
                                              Flexible(child: bubble),
                                              const SizedBox(width: 6),
                                              _avatar(true),
                                            ],
                                          );
                                        } else {
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              _avatar(false),
                                              const SizedBox(width: 6),
                                              Flexible(child: bubble),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 6,
                                                ),
                                                child: _messageActionBar(
                                                  message: message,
                                                  canRecall: canRecall,
                                                  canPin: canPin,
                                                  isMe: isMe,
                                                ),
                                              ),
                                            ],
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                  if (!isRecalled && hasReactions)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: reactions.entries
                                            .where((e) => e.value.isNotEmpty)
                                            .map((entry) {
                                              final emoji = entry.key;
                                              final count = entry.value.length;
                                              final reacted = entry.value
                                                  .contains(currentUser.id);
                                              return Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: reacted
                                                      ? Colors.blue.withOpacity(
                                                          0.2,
                                                        )
                                                      : Colors.grey[200],
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: reacted
                                                        ? Colors.blueAccent
                                                        : Colors.grey[400]!,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      emoji,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '$count',
                                                      style: const TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            })
                                            .toList(),
                                      ),
                                    ),
                                ],
                              ),
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

          // Media preview section
          if (_selectedImages.isNotEmpty || _selectedVideos.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getMediaCountText(),
                        style: TextStyle(color: Colors.grey[800], fontSize: 14),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedImages.clear();
                            _selectedVideos.clear();
                          });
                        },
                        child: const Text(
                          'Xóa tất cả',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          _selectedImages.length + _selectedVideos.length + 1,
                      itemBuilder: (context, index) {
                        if (index ==
                            _selectedImages.length + _selectedVideos.length) {
                          return GestureDetector(
                            onTap: _pickMedia,
                            child: Container(
                              width: 80,
                              height: 80,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey[300]!,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.grey[600]!,
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.add,
                                color: Colors.grey,
                                size: 32,
                              ),
                            ),
                          );
                        }

                        if (index < _selectedImages.length) {
                          return Stack(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: DecorationImage(
                                    image: FileImage(_selectedImages[index]),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 12,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedImages.removeAt(index);
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.black87,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        final videoIndex = index - _selectedImages.length;
                        return Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.black87,
                                  size: 32,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedVideos.removeAt(videoIndex);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.black87,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          // Reply preview
          if (_replyingTo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply, color: Colors.black87, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _replyPreviewLabel(_replyingTo!),
                      style: const TextStyle(color: Colors.black, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _replyingTo = null;
                      });
                    },
                    icon: const Icon(
                      Icons.close,
                      color: Colors.black54,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),

          // Emoji picker
          if (_showEmojiPicker)
            EmojiPickerWidget(
              onEmojiSelected: (emoji) {
                _insertEmoji(emoji);
              },
            ),

          // Recording UI
          if (_isRecordingVoice)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border(
                  top: BorderSide(color: Colors.red[300]!, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.mic, color: Colors.red[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Đang ghi âm...',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(
                            Duration(seconds: _recordingDuration),
                          ),
                          style: TextStyle(
                            color: Colors.red[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: _cancelRecordingVoice,
                    tooltip: 'Hủy',
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _stopRecordingVoice,
                      tooltip: 'Gửi',
                    ),
                  ),
                ],
              ),
            ),

          // Message input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Menu tính năng khi nhấn dấu + (hiển thị phía trên)
                if (_showMoreOptionsMenu)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMoreOptionButton(
                          icon: Icons.photo,
                          label: 'Ảnh',
                          onTap: () {
                            setState(() {
                              _showMoreOptionsMenu = false;
                            });
                            _pickMedia();
                          },
                        ),
                        _buildMoreOptionButton(
                          icon: Icons.emoji_emotions_outlined,
                          label: 'Emoji',
                          onTap: () {
                            setState(() {
                              _showMoreOptionsMenu = false;
                            });
                            _toggleEmojiPicker();
                          },
                        ),
                        _buildMoreOptionButton(
                          icon: Icons.gif,
                          label: 'GIF',
                          onTap: () {
                            setState(() {
                              _showMoreOptionsMenu = false;
                            });
                            _showGifSearchDialog();
                          },
                        ),
                        _buildMoreOptionButton(
                          icon: Icons.location_on,
                          label: 'Vị trí',
                          onTap: () {
                            setState(() {
                              _showMoreOptionsMenu = false;
                            });
                            _showLocationOptions();
                          },
                        ),
                        _buildMoreOptionButton(
                          icon: Icons.photo_camera,
                          label: 'Camera',
                          onTap: () {
                            setState(() {
                              _showMoreOptionsMenu = false;
                            });
                            _capturePhoto();
                          },
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    // Khi chưa có text: hiển thị các icon trải dài (ẩn khi menu hiển thị)
                    // Khi có text: chỉ hiển thị dấu +
                    if (_messageController.text.trim().isEmpty) ...[
                      if (!_showMoreOptionsMenu) ...[
                        // Photo button
                        IconButton(
                          icon: const Icon(Icons.photo, color: Colors.black),
                          onPressed: _pickMedia,
                        ),
                        // Emoji button
                        IconButton(
                          icon: Icon(
                            _showEmojiPicker
                                ? Icons.keyboard
                                : Icons.emoji_emotions_outlined,
                            color: Colors.black,
                          ),
                          onPressed: _isLoading
                              ? null
                              : () => _toggleEmojiPicker(),
                        ),
                        // GIF button
                        IconButton(
                          icon: const Icon(Icons.gif, color: Colors.black),
                          onPressed: _isLoading ? null : _showGifSearchDialog,
                        ),
                      ],
                      // More options button (+)
                      IconButton(
                        icon: Icon(
                          _showMoreOptionsMenu
                              ? Icons.close
                              : Icons.add_circle_outline,
                          color: Colors.black,
                        ),
                        onPressed: () {
                          setState(() {
                            _showMoreOptionsMenu = !_showMoreOptionsMenu;
                          });
                        },
                      ),
                    ] else ...[
                      // Khi có text: chỉ hiển thị dấu +
                      IconButton(
                        icon: Icon(
                          _showMoreOptionsMenu
                              ? Icons.close
                              : Icons.add_circle_outline,
                          color: Colors.black,
                        ),
                        onPressed: () {
                          setState(() {
                            _showMoreOptionsMenu = !_showMoreOptionsMenu;
                          });
                        },
                      ),
                    ],
                    // Voice message button (luôn hiển thị)
                    GestureDetector(
                      onLongPressStart: (_) {
                        _startRecordingVoice().catchError((error) {
                          if (kDebugMode) {
                            debugPrint('Error in onLongPressStart: $error');
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Lỗi khi bắt đầu ghi âm: ${error.toString()}',
                                ),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        });
                      },
                      onLongPressEnd: (_) {
                        _stopRecordingVoice().catchError((error) {
                          if (kDebugMode) {
                            debugPrint('Error in onLongPressEnd: $error');
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Lỗi khi dừng ghi âm: ${error.toString()}',
                                ),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        });
                      },
                      onLongPressCancel: () {
                        _cancelRecordingVoice().catchError((error) {
                          if (kDebugMode) {
                            debugPrint('Error in onLongPressCancel: $error');
                          }
                        });
                      },
                      child: IconButton(
                        icon: Icon(
                          _isRecordingVoice ? Icons.mic : Icons.mic_none,
                          color: _isRecordingVoice ? Colors.red : Colors.black,
                        ),
                        onPressed: null, // Disable tap, only long press
                      ),
                    ),
                    // TextField - sử dụng một widget duy nhất để tránh mất focus
                    Expanded(
                      child: TextField(
                        key: const ValueKey('message_input'), // Key để giữ widget ổn định
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          hintText: 'Nhập tin nhắn...',
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        minLines: 1,
                        maxLines: _hasText ? 5 : 1,
                        textInputAction: TextInputAction.send,
                        enabled: !_isLoading,
                        enableInteractiveSelection: true,
                        keyboardType: TextInputType.multiline,
                        onChanged: (value) {
                          // Không gọi setState ở đây, để listener xử lý
                        },
                        onTap: () {
                          if (_showEmojiPicker) {
                            setState(() {
                              _showEmojiPicker = false;
                            });
                          }
                          // Đảm bảo focus được giữ lại
                          if (!_messageFocusNode.hasFocus) {
                            _messageFocusNode.requestFocus();
                          }
                        },
                        onSubmitted: (_) {
                          if (!_isLoading) {
                            _sendMessage();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        ),
                      )
                    else if (_messageController.text.trim().isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.send, color: AppColors.primary),
                        onPressed: _isLoading ? null : _sendMessage,
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

  String _getMediaCountText() {
    final imageCount = _selectedImages.length;
    final videoCount = _selectedVideos.length;

    if (imageCount > 0 && videoCount > 0) {
      return '$imageCount ảnh, $videoCount video';
    } else if (imageCount > 0) {
      return '$imageCount ${imageCount == 1 ? 'ảnh' : 'ảnh'}';
    } else if (videoCount > 0) {
      return '$videoCount ${videoCount == 1 ? 'video' : 'video'}';
    }
    return '';
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (final file in result.files) {
        if (file.path == null) continue;

        final ext = (file.extension ?? '').toLowerCase();
        final isVideo = [
          'mp4',
          'mov',
          'mkv',
          'avi',
          'mpeg',
          'mpg',
          'wmv',
        ].contains(ext);
        final isImage = [
          'jpg',
          'jpeg',
          'png',
          'heic',
          'heif',
          'webp',
        ].contains(ext);

        if (isVideo) {
          _selectedVideos.add(File(file.path!));
        } else if (isImage) {
          _selectedImages.add(File(file.path!));
        }
      }
    });
  }

  Future<void> _capturePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() {
        _selectedImages.add(File(picked.path));
      });
    }
  }

  Future<void> _showMessageOptionsDialog(
    BuildContext context,
    MessageModel message,
    bool canRecall,
    bool canPin,
  ) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final result = await showModalBottomSheet<String>(
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
              padding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _reactionEmojis.map((emoji) {
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, 'react:$emoji'),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  );
                }).toList(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.black),
              title: const Text(
                'Trả lời',
                style: TextStyle(color: Colors.black),
              ),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.reply_all, color: Colors.black),
              title: const Text(
                'Chuyển tiếp',
                style: TextStyle(color: Colors.black),
              ),
              onTap: () => Navigator.pop(context, 'forward'),
            ),
            if (canPin)
              ListTile(
                leading: Icon(
                  message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: message.isPinned ? Colors.orange : Colors.black87,
                ),
                title: Text(
                  message.isPinned ? 'Bỏ ghim tin nhắn' : 'Ghim tin nhắn',
                  style: TextStyle(
                    color: message.isPinned ? Colors.orange : Colors.black87,
                  ),
                ),
                onTap: () =>
                    Navigator.pop(context, message.isPinned ? 'unpin' : 'pin'),
              ),
            if (canRecall)
              ListTile(
                leading: const Icon(Icons.undo, color: Colors.black),
                title: const Text(
                  'Thu hồi tin nhắn',
                  style: TextStyle(color: Colors.black),
                ),
                onTap: () => Navigator.pop(context, 'recall'),
              ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.grey),
              title: const Text('Hủy', style: TextStyle(color: Colors.grey)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );

    if (result == 'pin') {
      await _pinMessage(message);
    } else if (result == 'unpin') {
      await _unpinMessage(message);
    } else if (result == 'recall') {
      await _recallMessage(message);
    } else if (result == 'forward') {
      await _forwardMessage(message);
    } else if (result != null && result.startsWith('react:')) {
      final emoji = result.split('react:').last;
      await _reactToMessage(message, emoji);
    } else if (result == 'reply') {
      setState(() {
        _replyingTo = message;
      });
    }
  }

  Future<void> _reactToMessage(MessageModel message, String emoji) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      await _messageService.reactToMessage(
        messageId: message.id,
        userId: currentUser.id,
        emoji: emoji,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể gửi reaction: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startRecordingVoice() async {
    try {
      if (kDebugMode) {
        debugPrint('=== STARTING VOICE RECORDING (GROUP) ===');
      }

      // CRITICAL: Stop any playing audio before starting recording to prevent resource conflicts
      try {
        if (_voiceState == PlayerState.playing) {
          await _voicePlayer.stop();
          if (kDebugMode) {
            debugPrint('Stopped playing voice before recording');
          }
        }
        // Small delay to ensure audio resources are released
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error stopping voice player before recording: $e');
        }
        // Continue anyway - recording might still work
      }

      // Kiểm tra permission trước
      final hasPermission = await _voiceRecordingService.hasPermission();
      if (!hasPermission) {
        if (kDebugMode) {
          debugPrint('Microphone permission denied');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cần quyền microphone để ghi âm. Vui lòng cấp quyền trong Settings.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('Permission granted, starting recording...');
      }

      final filePath = await _voiceRecordingService.startRecording();

      if (kDebugMode) {
        debugPrint('Recording started successfully. File path: $filePath');
      }

      _recordingDurationSub = _voiceRecordingService.durationStream?.listen((
        duration,
      ) {
        if (mounted) {
          setState(() {
            _recordingDuration = duration;
          });
        }
        if (kDebugMode && duration % 5 == 0) {
          debugPrint('Recording duration: $duration seconds');
        }
      });

      if (mounted) {
        setState(() {
          _isRecordingVoice = true;
          _recordingDuration = 0;
        });
      }

      if (kDebugMode) {
        debugPrint('Voice recording state updated: _isRecordingVoice = true');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('ERROR in _startRecordingVoice (group): $e');
        debugPrint('Stack trace: $stackTrace');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể bắt đầu ghi âm: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _stopRecordingVoice() async {
    try {
      if (!_isRecordingVoice) return;

      if (kDebugMode) {
        debugPrint('=== STOPPING VOICE RECORDING (GROUP) ===');
        debugPrint('Current duration: $_recordingDuration seconds');
      }

      // CRITICAL: Stop recording first
      final filePath = await _voiceRecordingService.stopRecording();
      _recordingDurationSub?.cancel();
      _recordingDurationSub = null;

      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
        });
      }

      // CRITICAL: Add delay after stopping recording to ensure audio resources are released
      // This prevents conflicts when creating new AudioPlayer instances
      await Future.delayed(const Duration(milliseconds: 300));

      if (filePath == null || _recordingDuration < 1) {
        // Recording too short, cancel
        await _voiceRecordingService.cancelRecording();
        return;
      }

      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      setState(() {
        _isLoading = true;
      });

      try {
        final audioUrl = await _voiceRecordingService.uploadVoiceFile(
          filePath,
          duration: _recordingDuration,
        );

        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: '',
          content: '',
          audioUrl: audioUrl,
          audioDuration: _recordingDuration,
          createdAt: DateTime.now(),
          groupId: widget.group.id,
          replyToMessageId: _replyingTo?.id,
          replyToContent: _replyingTo?.content.isNotEmpty == true
              ? _replyingTo!.content
              : (_replyingTo?.imageUrl != null
                    ? '[Ảnh]'
                    : (_replyingTo?.videoUrl != null
                          ? '[Video]'
                          : (_replyingTo?.audioUrl != null
                                ? '[Voice]'
                                : (_replyingTo?.gifUrl != null
                                      ? '[GIF]'
                                      : '')))),
          replyToSenderId: _replyingTo?.senderId,
          replyToType: _replyType(_replyingTo),
        );

        await _messageService.sendGroupMessage(message);

        if (mounted) {
          setState(() {
            _replyingTo = null;
            _recordingDuration = 0;
          });
        }
      } catch (e, stackTrace) {
        if (kDebugMode) {
          debugPrint('ERROR in _stopRecordingVoice (group): $e');
          debugPrint('Stack trace: $stackTrace');
        }

        if (!mounted) return;

        // Show user-friendly error message
        String errorMessage = 'Không thể gửi voice message';
        if (e.toString().contains('rỗng') ||
            e.toString().contains('Empty file')) {
          errorMessage = 'File ghi âm rỗng. Vui lòng thử ghi âm lại.';
        } else if (e.toString().contains('không tồn tại')) {
          errorMessage = 'File ghi âm không tồn tại. Vui lòng thử ghi âm lại.';
        } else if (e.toString().contains('internet') ||
            e.toString().contains('kết nối')) {
          errorMessage = 'Lỗi kết nối mạng. Vui lòng kiểm tra và thử lại.';
        } else {
          errorMessage = 'Không thể gửi voice message: ${e.toString()}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorMessageHelper.getErrorMessage(
              e,
              defaultMessage: 'Không thể dừng ghi âm',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelRecordingVoice() async {
    await _voiceRecordingService.cancelRecording();
    _recordingDurationSub?.cancel();
    _recordingDurationSub = null;
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingDuration = 0;
      });
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildMoreOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoreOptions() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, size: 32),
              title: const Text('Chụp ảnh'),
              subtitle: const Text('Chụp ảnh hoặc quay video'),
              onTap: () {
                Navigator.pop(context);
                _capturePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on, size: 32),
              title: const Text('Gửi vị trí'),
              subtitle: const Text('Chia sẻ vị trí hiện tại'),
              onTap: () {
                Navigator.pop(context);
                _showLocationOptions();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLocationOptions() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chia sẻ vị trí'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_on),
              title: const Text('Gửi vị trí hiện tại'),
              subtitle: const Text('Chia sẻ vị trí một lần'),
              onTap: () => Navigator.pop(context, 'current'),
            ),
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Chia sẻ vị trí trực tiếp'),
              subtitle: const Text('Theo dõi vị trí real-time'),
              onTap: () => Navigator.pop(context, 'live'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );

    if (result == 'current') {
      await _sendCurrentLocation();
    } else if (result == 'live') {
      await _showLiveLocationDurationDialog();
    }
  }

  Future<void> _showLiveLocationDurationDialog() async {
    int? selectedDuration;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Chia sẻ vị trí trực tiếp'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Chọn thời gian chia sẻ:'),
              const SizedBox(height: 16),
              RadioListTile<int>(
                title: const Text('15 phút'),
                value: 15,
                groupValue: selectedDuration,
                activeColor: Colors.green,
                onChanged: (value) =>
                    setDialogState(() => selectedDuration = value),
              ),
              RadioListTile<int>(
                title: const Text('1 giờ'),
                value: 60,
                groupValue: selectedDuration,
                activeColor: Colors.green,
                onChanged: (value) =>
                    setDialogState(() => selectedDuration = value),
              ),
              RadioListTile<int>(
                title: const Text('8 giờ'),
                value: 480,
                groupValue: selectedDuration,
                activeColor: Colors.green,
                onChanged: (value) =>
                    setDialogState(() => selectedDuration = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: selectedDuration != null
                  ? () => Navigator.pop(context, selectedDuration)
                  : null,
              child: const Text('Gửi'),
            ),
          ],
        ),
      ),
    ).then((duration) {
      if (duration != null) {
        _sendLiveLocation(duration as int);
      }
    });
  }

  Future<void> _sendCurrentLocation() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bạn cần đăng nhập để gửi vị trí'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      if (kDebugMode) {
        debugPrint('=== STARTING GROUP LOCATION SEND PROCESS ===');
      }

      // Kiểm tra và yêu cầu permission trước
      if (kDebugMode) {
        debugPrint('Requesting location permission...');
      }
      final hasPermission = await _locationService.requestLocationPermission();
      if (!hasPermission) {
        if (kDebugMode) {
          debugPrint('Location permission denied');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cần quyền truy cập vị trí để gửi vị trí. Vui lòng cấp quyền trong Settings.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('Permission granted, getting current position...');
      }

      // Lấy vị trí với timeout
      final position = await _locationService.getCurrentPosition();
      if (position == null) {
        if (kDebugMode) {
          debugPrint('Failed to get position');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Không thể lấy vị trí. Vui lòng kiểm tra quyền truy cập và đảm bảo GPS đã bật.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      if (kDebugMode) {
        debugPrint(
          'Position obtained: lat=${position.latitude}, lng=${position.longitude}',
        );
      }

      // Lấy địa chỉ với timeout
      String? address;
      try {
        if (kDebugMode) {
          debugPrint('Getting address from coordinates...');
        }
        address = await _locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (kDebugMode) {
          debugPrint('Address obtained: $address');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error getting address: $e');
        }
        // Vẫn gửi location ngay cả khi không lấy được address
        address =
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        if (kDebugMode) {
          debugPrint('Using fallback address: $address');
        }
      }

      final message = MessageModel(
        id: '',
        senderId: currentUser.id,
        receiverId: widget.group.id, // For group, receiverId is groupId
        content: '',
        latitude: position.latitude,
        longitude: position.longitude,
        locationAddress: address,
        isLiveLocation: false,
        groupId: widget.group.id,
        createdAt: DateTime.now(),
      );

      if (kDebugMode) {
        debugPrint('=== SENDING GROUP LOCATION MESSAGE ===');
        debugPrint('SenderId: ${message.senderId}');
        debugPrint('GroupId: ${message.groupId}');
        debugPrint('Latitude: ${message.latitude}');
        debugPrint('Longitude: ${message.longitude}');
        debugPrint('Address: ${message.locationAddress}');
        debugPrint('IsLiveLocation: ${message.isLiveLocation}');
        debugPrint('Message toMap: ${message.toMap()}');
      }

      final messageId = await _messageService.sendGroupMessage(message);

      if (kDebugMode) {
        debugPrint('Group location message sent with ID: $messageId');
        debugPrint(
          'Message data after send: lat=${message.latitude}, lng=${message.longitude}, address=${message.locationAddress}',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã gửi vị trí'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('ERROR in _sendCurrentLocation (group): $e');
        debugPrint('Stack trace: $stackTrace');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorMessageHelper.getErrorMessage(
                e,
                defaultMessage: 'Không thể gửi vị trí',
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendLiveLocation(int durationMinutes) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bạn cần đăng nhập để gửi vị trí'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Kiểm tra và yêu cầu permission trước
      final hasPermission = await _locationService.requestLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cần quyền truy cập vị trí để gửi vị trí. Vui lòng cấp quyền trong Settings.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final position = await _locationService.getCurrentPosition();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Không thể lấy vị trí. Vui lòng kiểm tra quyền truy cập và đảm bảo GPS đã bật.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      String? address;
      try {
        address = await _locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
      } catch (e) {
        debugPrint('Error getting address: $e');
        // Vẫn gửi location ngay cả khi không lấy được address
        address =
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      }

      final expiresAt = DateTime.now().add(Duration(minutes: durationMinutes));

      final message = MessageModel(
        id: '',
        senderId: currentUser.id,
        receiverId: '', // Không cần cho group message
        content: '',
        latitude: position.latitude,
        longitude: position.longitude,
        locationAddress: address,
        isLiveLocation: true,
        locationExpiresAt: expiresAt,
        groupId: widget.group.id,
        createdAt: DateTime.now(),
      );

      final messageId = await _messageService.sendGroupMessage(message);

      // Bắt đầu tracking real-time
      final conversationId = await _messageService.getOrCreateGroupConversation(
        widget.group.id,
      );
      await _locationService.startLiveLocationTracking(
        messageId: messageId,
        conversationId: conversationId,
        receiverId: widget.group.id,
        durationMinutes: durationMinutes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã bắt đầu chia sẻ vị trí trực tiếp trong $durationMinutes phút',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sending live location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorMessageHelper.getErrorMessage(
                e,
                defaultMessage: 'Không thể gửi vị trí trực tiếp',
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _replyType(MessageModel? msg) {
    if (msg == null) return 'text';
    if (msg.imageUrl != null) return 'image';
    if (msg.videoUrl != null) return 'video';
    if (msg.audioUrl != null) return 'audio';
    if (msg.gifUrl != null) return 'gif';
    if (msg.latitude != null && msg.longitude != null) return 'location';
    return 'text';
  }

  String _replyPreviewLabel(MessageModel msg) {
    if (msg.content.isNotEmpty) return msg.content;
    if (msg.imageUrl != null) return '[Ảnh]';
    if (msg.videoUrl != null) return '[Video]';
    if (msg.audioUrl != null) return '[Voice]';
    if (msg.gifUrl != null) return '[GIF]';
    if (msg.latitude != null && msg.longitude != null) {
      return msg.isLiveLocation == true ? '[Live Location]' : '[Location]';
    }
    return 'Tin nhắn';
  }

  Future<void> _recallMessage(MessageModel message) async {
    try {
      await _messageService.recallMessage(message.id, message.senderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã thu hồi tin nhắn'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Thu hồi tin nhắn thất bại: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _forwardMessage(MessageModel message) async {
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    // Hiển thị dialog chọn conversation để forward
    final selectedConversation = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ForwardMessageDialog(
        currentUserId: currentUser.id,
        messageService: _messageService,
      ),
    );

    if (selectedConversation == null || selectedConversation.isEmpty) return;

    try {
      // Tạo message mới với nội dung forward
      final forwardContent = message.content.isNotEmpty
          ? message.content
          : (message.imageUrl != null
                ? '[Ảnh]'
                : (message.videoUrl != null
                      ? '[Video]'
                      : (message.audioUrl != null
                            ? '[Voice]'
                            : (message.gifUrl != null ? '[GIF]' : ''))));

      final conversationType = selectedConversation['type'] as String? ?? 'direct';
      final conversationId = selectedConversation['conversationId'] as String? ?? '';
      
      if (conversationType == 'group') {
        // Forward to group
        final groupId = selectedConversation['groupId'] as String? ?? '';
        final forwardMessage = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: '', // Group messages don't need receiverId
          content: 'Chuyển tiếp: $forwardContent',
          createdAt: DateTime.now(),
          replyToMessageId: message.id,
          replyToContent: forwardContent,
          replyToSenderId: message.senderId,
          replyToType: _replyType(message),
          imageUrl: message.imageUrl,
          videoUrl: message.videoUrl,
          audioUrl: message.audioUrl,
          gifUrl: message.gifUrl,
          groupId: groupId,
        );

        await _messageService.sendGroupMessage(forwardMessage);
      } else {
        // Forward to direct conversation
        final receiverId = conversationId.contains('_')
            ? conversationId
                  .split('_')
                  .firstWhere((id) => id != currentUser.id)
            : '';
        
        final forwardMessage = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: receiverId,
          content: 'Chuyển tiếp: $forwardContent',
          createdAt: DateTime.now(),
          replyToMessageId: message.id,
          replyToContent: forwardContent,
          replyToSenderId: message.senderId,
          replyToType: _replyType(message),
          imageUrl: message.imageUrl,
          videoUrl: message.videoUrl,
          audioUrl: message.audioUrl,
          gifUrl: message.gifUrl,
        );

        await _messageService.sendMessage(forwardMessage);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã chuyển tiếp tin nhắn'),
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
                defaultMessage: 'Không thể chuyển tiếp tin nhắn',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pinMessage(MessageModel message) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      await _messageService.pinMessage(message.id, currentUser.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã ghim tin nhắn'),
            backgroundColor: Colors.green,
          ),
        );
        // Không scroll tự động - tin nhắn đã ghim vẫn ở vị trí cũ
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    }
  }

  Future<void> _unpinMessage(MessageModel message) async {
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      await _messageService.unpinMessage(message.id, currentUser.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã bỏ ghim tin nhắn'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    }
  }

  Widget _messageActionBar({
    required MessageModel message,
    required bool canRecall,
    required bool canPin,
    required bool isMe,
  }) {
    // Đã loại bỏ các icon (more options, reply, emoji)
    return const SizedBox.shrink();
  }

  Future<void> _openReactionPicker(MessageModel message) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _reactionEmojis
                .map(
                  (e) => GestureDetector(
                    onTap: () => Navigator.pop(context, e),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );

    if (emoji != null) {
      await _reactToMessage(message, emoji);
    }
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
  }

  void _insertEmoji(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final newText = text.replaceRange(selection.start, selection.end, emoji);
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + emoji.length,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _searchGifs(String query) async {
    try {
      final url = Uri.parse(
        'https://api.giphy.com/v1/gifs/search?api_key=$_giphyApiKey&q=${Uri.encodeComponent(query)}&limit=25&rating=g',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> gifs = data['data'] ?? [];
        return gifs.map((gif) {
          return {
            'id': gif['id'],
            'url':
                gif['images']['original']['url'] ??
                gif['images']['fixed_height']['url'],
            'title': gif['title'] ?? '',
            'preview':
                gif['images']['fixed_height_small']['url'] ??
                gif['images']['fixed_height']['url'],
          };
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error searching GIFs: $e');
      return [];
    }
  }

  void _showGifSearchDialog() async {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> gifs = [];
    bool isSearching = false;
    bool initialLoad = true;

    if (initialLoad) {
      try {
        final url = Uri.parse(
          'https://api.giphy.com/v1/gifs/trending?api_key=$_giphyApiKey&limit=25&rating=g',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> gifsData = data['data'] ?? [];
          gifs = gifsData.map((gif) {
            return {
              'id': gif['id'],
              'url':
                  gif['images']['original']['url'] ??
                  gif['images']['fixed_height']['url'],
              'title': gif['title'] ?? '',
              'preview':
                  gif['images']['fixed_height_small']['url'] ??
                  gif['images']['fixed_height']['url'],
            };
          }).toList();
        }
      } catch (e) {
        debugPrint('Error loading trending GIFs: $e');
      }
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Text(
                        'Tìm kiếm GIF',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    controller: searchController,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm GIF...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.black87,
                      ),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Colors.black87,
                              ),
                              onPressed: () {
                                searchController.clear();
                                setDialogState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      filled: true,
                      fillColor: Colors.grey[300]!,
                    ),
                    onChanged: (value) {
                      setDialogState(() {});
                    },
                    onSubmitted: (value) async {
                      if (value.trim().isEmpty) return;
                      setDialogState(() {
                        isSearching = true;
                        initialLoad = false;
                      });
                      final results = await _searchGifs(value.trim());
                      setDialogState(() {
                        gifs = results;
                        isSearching = false;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isSearching
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.black),
                        )
                      : gifs.isEmpty
                      ? const Center(
                          child: Text(
                            'Nhập từ khóa để tìm kiếm GIF',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1,
                              ),
                          itemCount: gifs.length,
                          itemBuilder: (context, index) {
                            final gif = gifs[index];
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedGifUrl = gif['url'] as String;
                                  _selectedImages.clear();
                                  _selectedVideos.clear();
                                });
                                Navigator.pop(context);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  gif['preview'] as String,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    searchController.dispose();
  }

  Future<void> _startGroupCall(
    BuildContext context,
    UserModel currentUser, {
    required bool isVideo,
  }) async {
    try {
      // Kiểm tra xem đã có cuộc gọi active chưa
      final activeCall = await _groupCallService
          .getActiveGroupCall(widget.group.id)
          .first;

      if (activeCall != null) {
        // Nếu đã có cuộc gọi active, tham gia vào cuộc gọi đó
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GroupCallScreen(
                group: widget.group,
                groupCall: activeCall,
                isIncoming: false,
              ),
            ),
          );
        }
        return;
      }

      // Tạo cuộc gọi nhóm mới
      final callId = await _groupCallService.createGroupCall(
        groupId: widget.group.id,
        creatorId: currentUser.id,
        participantIds: widget.group.memberIds,
        isVideoCall: isVideo,
      );

      // Lấy thông tin cuộc gọi vừa tạo
      final groupCall = await _groupCallService.getGroupCall(callId);
      if (groupCall != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupCallScreen(
              group: widget.group,
              groupCall: groupCall,
              isIncoming: false,
            ),
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
                defaultMessage: 'Không thể tạo cuộc gọi nhóm',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Parse postId từ URL bài viết
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

  // Widget để hiển thị message content với link có thể click
  Widget _buildMessageContent(String content, bool isMe) {
    final postId = _extractPostIdFromUrl(content);

    // Nếu là link bài viết, tạo widget có thể click
    if (postId != null) {
      return GestureDetector(
        onTap: () async {
          try {
            final authProvider = context.read<AuthProvider>();
            final currentUser = authProvider.currentUser;
            if (currentUser == null) return;

            final firestoreService = FirestoreService();
            final post = await firestoreService.getPost(
              postId,
              viewerId: currentUser.id,
            );

            if (post != null && mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
              );
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                ErrorMessageHelper.createErrorSnackBar(
                  'Bài viết không tồn tại hoặc đã bị xóa',
                  defaultMessage: 'Không tìm thấy bài viết',
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
                      defaultMessage: 'Không thể mở bài viết',
                    ),
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        child: Text(
          content,
          style: TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: isMe ? Colors.white : Colors.blue,
            color: isMe ? Colors.white : Colors.blue,
          ),
        ),
      );
    }

    // Nếu không phải link bài viết, hiển thị text bình thường
    return Text(content, style: const TextStyle(color: Colors.black));
  }
}
