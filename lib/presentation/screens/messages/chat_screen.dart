import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../../../data/services/user_service.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/message_model.dart';
import '../../../data/services/message_service.dart';
import '../../../data/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../../data/services/agora_call_service.dart';
import '../../../data/models/conversation_model.dart';
import '../../widgets/emoji_picker_widget.dart';
import '../../../core/constants/app_colors.dart';
import 'chat_info_screen.dart';
import '../calls/call_screen.dart';
import '../../../data/services/voice_recording_service.dart';
import '../../widgets/voice_message_widget.dart';
import '../../../data/services/location_sharing_service.dart';
import '../../widgets/location_message_widget.dart';
import '../../../data/services/firestore_service.dart';
import '../post/post_detail_screen.dart';
import '../../../core/utils/error_message_helper.dart';
import '../../../data/services/group_service.dart';
import '../../../data/models/group_model.dart';
import '../../../data/services/settings_service.dart';

class ChatScreen extends StatefulWidget {
  final UserModel otherUser;
  final bool openSearchOnInit;
  final String? scrollToMessageId;

  const ChatScreen({super.key, required this.otherUser, this.openSearchOnInit = false, this.scrollToMessageId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final MessageService _messageService = MessageService();
  final StorageService _storageService = StorageService();
  final ImagePicker _picker = ImagePicker();
  final AgoraCallService _callService = AgoraCallService.instance;
  final List<String> _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final AudioPlayer _voicePlayer = AudioPlayer();
  final ScrollController _scrollController = ScrollController();
  String? _conversationId;
  bool _isOtherTyping = false;
  bool _isSearching = false;
  StreamSubscription<bool>? _typingSub;
  StreamSubscription<String?>? _nicknameSub;
  Timer? _typingTimer;
  Timer? _typingDebounceTimer;
  PlayerState _voiceState = PlayerState.stopped;
  MessageModel? _replyingTo;
  bool _isLoading = false;
  List<File> _selectedImages = [];
  List<File> _selectedVideos = [];
  String? _selectedGifUrl; // Selected GIF URL from GIPHY
  String? _displayName;
  bool _hasScrolledToMessage = false;
  bool _showEmojiPicker = false;
  bool _isRecordingVoice = false;
  int _recordingDuration = 0;
  StreamSubscription<int>? _recordingDurationSub;
  final VoiceRecordingService _voiceRecordingService = VoiceRecordingService();
  final LocationSharingService _locationService = LocationSharingService();
  // TODO: Thay YOUR_GIPHY_API_KEY bằng Giphy API key thực tế của bạn
  // Lấy tại: https://developers.giphy.com/dashboard/
  static const String _giphyApiKey = 'YOUR_GIPHY_API_KEY';
  bool _showMoreOptionsMenu = false; // State để hiển thị menu tính năng từ dấu +
  bool _hasText = false; // Track xem có text hay không để tránh rebuild không cần thiết
  bool _readReceiptsEnabled = true; // Read receipts setting
  // Cache the messages stream to avoid creating multiple stream controllers
  Stream<List<MessageModel>>? _messagesStream;
  String? _cachedStreamUserId1;
  String? _cachedStreamUserId2;

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
    _typingSub?.cancel();
    _nicknameSub?.cancel();
    _recordingDurationSub?.cancel();
    _typingTimer?.cancel();
    _typingDebounceTimer?.cancel();
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
    _callService.init();
    _voicePlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _voiceState = state;
        });
      }
    });
    _voicePlayer.setReleaseMode(ReleaseMode.stop);
    _isSearching = widget.openSearchOnInit;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupConversation();
      if (widget.openSearchOnInit) {
        _searchFocus.requestFocus();
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

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload read receipts setting khi quay lại màn hình
    _loadReadReceiptsSetting();
    if (oldWidget.otherUser.id != widget.otherUser.id) {
      _typingSub?.cancel();
      _conversationId = null;
      _isOtherTyping = false;
      // Clear cached stream when conversation changes
      _messagesStream = null;
      _cachedStreamUserId1 = null;
      _cachedStreamUserId2 = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _setupConversation());
    }
  }

  void _setupConversation() {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;
    final parts = [currentUser.id, widget.otherUser.id]..sort();
    final convId = parts.join('_');
    _conversationId = convId;

    // Cache the messages stream for this conversation
    // Convert to broadcast stream to allow multiple listeners (prevent "Stream has already been listened to" error)
    if (_messagesStream == null ||
        _cachedStreamUserId1 != currentUser.id ||
        _cachedStreamUserId2 != widget.otherUser.id) {
      _messagesStream = _messageService.getMessages(currentUser.id, widget.otherUser.id).asBroadcastStream();
      _cachedStreamUserId1 = currentUser.id;
      _cachedStreamUserId2 = widget.otherUser.id;
    }

    _typingSub?.cancel();
    _typingSub = _messageService.typingStatus(convId, widget.otherUser.id).listen((isTyping) {
      if (mounted) {
        setState(() {
          _isOtherTyping = isTyping;
        });
      }
    });

    _nicknameSub?.cancel();
    _nicknameSub = _messageService.watchNickname(convId, widget.otherUser.id).listen((nick) {
      if (!mounted) return;
      setState(() {
        _displayName = (nick != null && nick.isNotEmpty) ? nick : widget.otherUser.fullName;
      });
    });
  }

  Future<void> _sendMessage() async {
    // Prevent multiple simultaneous sends
    if (_isLoading) {
      if (kDebugMode) {
        print('=== _sendMessage: Already loading, skipping');
      }
      return;
    }

    final text = _messageController.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty && _selectedVideos.isEmpty && _selectedGifUrl == null) {
      if (kDebugMode) {
        print('=== _sendMessage: Empty message, skipping');
      }
      return;
    }

    // Check if widget is still mounted before accessing context
    if (!mounted) {
      if (kDebugMode) {
        print('=== _sendMessage: Widget not mounted, skipping');
      }
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      if (kDebugMode) {
        print('=== _sendMessage: No current user, skipping');
      }
      return;
    }

    if (kDebugMode) {
      print('=== _sendMessage: Starting to send message');
      print('=== _sendMessage: Text: "$text"');
      print('=== _sendMessage: SenderId: ${currentUser.id}');
      print('=== _sendMessage: ReceiverId: ${widget.otherUser.id}');
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Send first image if available
      if (_selectedImages.isNotEmpty) {
        final imageUrl = await _storageService.uploadPostImage(_selectedImages.first, 'msg', 0);
        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: widget.otherUser.id,
          content: text,
          imageUrl: imageUrl,
          videoUrl: null,
          createdAt: DateTime.now(),
        );
        await _messageService.sendMessage(message);
      }

      // Send first video if available
      if (_selectedVideos.isNotEmpty) {
        final videoUrl = await _storageService.uploadVideo(_selectedVideos.first, 'msg');
        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: widget.otherUser.id,
          content: text,
          imageUrl: null,
          videoUrl: videoUrl,
          createdAt: DateTime.now(),
        );
        await _messageService.sendMessage(message);
      }

      // Send GIF message if selected
      if (_selectedGifUrl != null) {
        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: widget.otherUser.id,
          content: text,
          imageUrl: null,
          videoUrl: null,
          gifUrl: _selectedGifUrl,
          createdAt: DateTime.now(),
          replyToMessageId: _replyingTo?.id,
          replyToContent: _replyingTo?.content.isNotEmpty == true
              ? _replyingTo!.content
              : (_replyingTo?.imageUrl != null
                    ? '[Ảnh]'
                    : (_replyingTo?.videoUrl != null
                          ? '[Video]'
                          : (_replyingTo?.audioUrl != null
                                ? '[Voice]'
                                : (_replyingTo?.gifUrl != null ? '[GIF]' : '')))),
          replyToSenderId: _replyingTo?.senderId,
          replyToType: _replyType(_replyingTo),
        );
        await _messageService.sendMessage(message);
      }

      // Send text message if no media
      if (_selectedImages.isEmpty && _selectedVideos.isEmpty && _selectedGifUrl == null && text.isNotEmpty) {
        if (kDebugMode) {
          print('=== _sendMessage: Sending text message');
        }
        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: widget.otherUser.id,
          content: text,
          imageUrl: null,
          videoUrl: null,
          createdAt: DateTime.now(),
          replyToMessageId: _replyingTo?.id,
          replyToContent: _replyingTo?.content.isNotEmpty == true
              ? _replyingTo!.content
              : (_replyingTo?.imageUrl != null
                    ? '[Ảnh]'
                    : (_replyingTo?.videoUrl != null
                          ? '[Video]'
                          : (_replyingTo?.audioUrl != null
                                ? '[Voice]'
                                : (_replyingTo?.gifUrl != null ? '[GIF]' : '')))),
          replyToSenderId: _replyingTo?.senderId,
          replyToType: _replyType(_replyingTo),
        );

        if (kDebugMode) {
          print('=== _sendMessage: Calling sendMessage with messageId: ${message.id}');
          print('=== _sendMessage: Message content: "${message.content}"');
        }

        final messageId = await _messageService.sendMessage(message);

        if (kDebugMode) {
          print('=== _sendMessage: Message sent successfully with ID: $messageId');
        }
      }

      // Check mounted before clearing state
      if (!mounted) return;
      _messageController.clear();
      _selectedImages.clear();
      _selectedVideos.clear();
      _selectedGifUrl = null;
      _replyingTo = null;
      setState(() {
        _hasText = false;
        _showMoreOptionsMenu = false;
      });
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('ERROR in _sendMessage: $e');
        print('Stack trace: $stackTrace');
      }
      if (mounted) {
        String errorMessage = 'Không thể gửi tin nhắn';
        if (e.toString().contains('permission') || e.toString().contains('quyền')) {
          errorMessage = 'Bạn không có quyền gửi tin nhắn đến người này';
        } else if (e.toString().contains('blocked') || e.toString().contains('chặn')) {
          errorMessage = 'Bạn đã bị chặn hoặc đã chặn người này';
        } else if (e.toString().contains('network') || e.toString().contains('mạng')) {
          errorMessage = 'Lỗi kết nối mạng. Vui lòng kiểm tra kết nối internet';
        } else if (e.toString().contains('empty') || e.toString().contains('trống')) {
          errorMessage = 'Tin nhắn không thể để trống';
        } else {
          errorMessage = 'Không thể gửi tin nhắn: ${e.toString()}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(errorMessage)),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  // Gửi GIF riêng lẻ ngay sau khi chọn
  Future<void> _sendGifMessage(String gifUrl) async {
    // Check if widget is still mounted before accessing context
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Backend đang không cho phép content rỗng, nên lưu placeholder '[GIF]'
      // nhưng UI vẫn hiển thị ảnh GIF, không hiện đoạn text này.
      final message = MessageModel(
        id: '',
        senderId: currentUser.id,
        receiverId: widget.otherUser.id,
        content: '[GIF]', // placeholder để pass validation backend
        imageUrl: null,
        videoUrl: null,
        gifUrl: gifUrl,
        createdAt: DateTime.now(),
        replyToMessageId: _replyingTo?.id,
        replyToContent: _replyingTo?.content.isNotEmpty == true
            ? _replyingTo!.content
            : (_replyingTo?.imageUrl != null
                  ? '[Ảnh]'
                  : (_replyingTo?.videoUrl != null
                        ? '[Video]'
                        : (_replyingTo?.audioUrl != null ? '[Voice]' : (_replyingTo?.gifUrl != null ? '[GIF]' : '')))),
        replyToSenderId: _replyingTo?.senderId,
        replyToType: _replyType(_replyingTo),
      );
      await _messageService.sendMessage(message);

      // Wait a bit for Firestore to sync
      // Reduced delay to prevent hanging
      await Future.delayed(const Duration(milliseconds: 300));

      // Check mounted before clearing state
      if (!mounted) return;
      // Reset state sau khi gửi
      _selectedGifUrl = null;
      _replyingTo = null;
      if (_conversationId != null) {
        _messageService.setTyping(conversationId: _conversationId!, userId: currentUser.id, isTyping: false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e, defaultMessage: 'Không thể tải tin nhắn'));
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
                border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 2),
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 8, spreadRadius: 0)],
              ),
              child: CircleAvatar(
                radius: 20,
                backgroundImage: widget.otherUser.avatarUrl != null ? NetworkImage(widget.otherUser.avatarUrl!) : null,
                child: widget.otherUser.avatarUrl == null ? Text(widget.otherUser.fullName[0].toUpperCase()) : null,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _displayName ?? widget.otherUser.fullName,
                style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.call, color: AppColors.primary, size: 26),
            onPressed: () => _startCall(video: false),
          ),
          IconButton(
            icon: Icon(Icons.videocam, color: AppColors.primary, size: 26),
            onPressed: () => _startCall(video: true),
          ),
          IconButton(
            icon: Icon(Icons.info, color: AppColors.primary, size: 26),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => ChatInfoScreen(otherUser: widget.otherUser)));
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
                  prefixIcon: Icon(Icons.search, color: Colors.grey[700]),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey[700]),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          if (_isOtherTyping)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.white,
              child: const Text('Đang nhập...', style: TextStyle(color: Colors.black87, fontSize: 13)),
            ),
          // Messages list
          Expanded(
            child: Builder(
              builder: (context) {
                // Stream should already be created in _setupConversation
                // If it's null, create it as a fallback (shouldn't happen normally)
                // Convert to broadcast stream to allow multiple listeners
                if (_messagesStream == null) {
                  _messagesStream = _messageService
                      .getMessages(currentUser.id, widget.otherUser.id)
                      .asBroadcastStream();
                  _cachedStreamUserId1 = currentUser.id;
                  _cachedStreamUserId2 = widget.otherUser.id;
                }
                return StreamBuilder<List<MessageModel>>(
                  key: ValueKey('messages_${currentUser.id}_${widget.otherUser.id}'),
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    // Only log errors to reduce performance impact
                    if (kDebugMode && snapshot.hasError) {
                      print('=== UI: StreamBuilder error: ${snapshot.error}');
                    }

                    if (kDebugMode) {
                      print(
                        '=== UI: StreamBuilder state - connectionState: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}',
                      );
                      if (snapshot.hasData) {
                        print('=== UI: StreamBuilder received ${snapshot.data?.length ?? 0} messages');
                      }
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.black));
                    }

                    if (snapshot.hasError) {
                      if (kDebugMode) {
                        print('=== UI: StreamBuilder has error: ${snapshot.error}');
                      }

                      // Nếu là lỗi permission-denied nhưng vẫn có data cache,
                      // chúng ta bỏ qua lỗi và tiếp tục hiển thị tin nhắn để
                      // tránh làm người dùng hoang mang.
                      final error = snapshot.error;
                      if (!(error is FirebaseException && error.code == 'permission-denied')) {
                        return const Center(
                          child: Text(
                            'Không thể tải tin nhắn. Vui lòng thử lại sau.',
                            style: TextStyle(color: Colors.black),
                          ),
                        );
                      }
                    }

                    final messages = snapshot.data ?? [];

                    if (kDebugMode) {
                      print('=== UI: Processing ${messages.length} messages from stream');
                      if (messages.isNotEmpty) {
                        print('=== UI: Message IDs: ${messages.map((m) => m.id).toList()}');
                      }
                    }

                    // Sắp xếp: tin nhắn đã ghim ở cuối list (sẽ hiển thị ở đầu với reverse: true)
                    // sau đó là các tin nhắn khác sắp xếp theo thời gian (mới nhất trước)
                    // Cache sorted messages để tránh sort lại không cần thiết
                    // Tin nhắn đã ghim vẫn ở vị trí ban đầu (theo thời gian tạo), không di chuyển lên đầu
                    final sortedMessages = List<MessageModel>.from(messages)
                      ..sort((a, b) {
                        // Sắp xếp theo thời gian tạo (mới nhất trước), không ưu tiên tin nhắn đã ghim
                        return b.createdAt.compareTo(a.createdAt);
                      });

                    // Lấy danh sách tin nhắn đã ghim và sort theo pinnedAt (mới nhất trước) để hiển thị trong thanh pinned
                    final pinnedMessages = sortedMessages.where((m) => m.isPinned && !m.isRecalled).toList()
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
                      return 'Tin nhắn';
                    }

                    final query = _searchController.text.trim().toLowerCase();
                    final filteredMessages = query.isEmpty
                        ? sortedMessages
                        : sortedMessages.where((m) {
                            final text = m.content.toLowerCase();
                            if (text.contains(query)) return true;
                            if (m.imageUrl != null && '[ảnh]'.contains(query)) return true;
                            if (m.videoUrl != null && '[video]'.contains(query)) return true;
                            if (m.audioUrl != null && '[voice]'.contains(query)) return true;
                            return false;
                          }).toList();

                    // Debug logging after filtering
                    if (kDebugMode) {
                      print('=== UI: After sorting: ${sortedMessages.length} messages');
                      print('=== UI: After filtering: ${filteredMessages.length} messages');
                      if (filteredMessages.isNotEmpty) {
                        print('=== UI: ✅ ListView will render ${filteredMessages.length} items');
                        print(
                          '=== UI: First item to render - ID: ${filteredMessages.first.id}, content: "${filteredMessages.first.content.length > 30 ? filteredMessages.first.content.substring(0, 30) + "..." : filteredMessages.first.content}"',
                        );
                      } else {
                        print('=== UI: ⚠️ No messages to render after filtering!');
                      }
                    }

                    if (messages.isEmpty) {
                      return const Center(
                        child: Text('Chưa có tin nhắn nào', style: TextStyle(color: Colors.black87)),
                      );
                    }

                    // Scroll đến tin nhắn cụ thể nếu có
                    if (widget.scrollToMessageId != null && !_hasScrolledToMessage && filteredMessages.isNotEmpty) {
                      final targetIndex = filteredMessages.indexWhere((m) => m.id == widget.scrollToMessageId);
                      if (targetIndex != -1) {
                        // Delay để đảm bảo ListView đã render xong
                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (!mounted || !_scrollController.hasClients) return;

                          // Với reverse: true ListView:
                          // - Index 0 là tin nhắn mới nhất (ở dưới cùng, scroll position = 0)
                          // - Index cuối là tin nhắn cũ nhất (ở trên cùng)
                          // Cần scroll lên trên để đến message cũ hơn
                          final estimatedItemHeight = 120.0;
                          final maxScroll = _scrollController.position.maxScrollExtent;

                          // Tính toán vị trí: từ dưới lên trên
                          // Nếu targetIndex = 0 (tin nhắn mới nhất), scroll position = 0
                          // Nếu targetIndex = length - 1 (tin nhắn cũ nhất), scroll position = maxScroll
                          final targetPosition = (filteredMessages.length - 1 - targetIndex) * estimatedItemHeight;
                          final clampedPosition = targetPosition.clamp(0.0, maxScroll);

                          _scrollController.animateTo(
                            clampedPosition,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                          );

                          if (mounted) {
                            setState(() {
                              _hasScrolledToMessage = true;
                            });
                          }
                        });
                      }
                    }

                    return Column(
                      children: [
                        // ✅ Thanh tin nhắn ghim (luôn thấy ngay) – bấm để nhảy tới tin ghim
                        if (query.isEmpty && pinnedMessages.isNotEmpty)
                          Material(
                            color: Colors.white,
                            child: InkWell(
                              onTap: () {
                                if (!_scrollController.hasClients) return;
                                final targetId = pinnedMessages.first.id;
                                final targetIndex = filteredMessages.indexWhere((m) => m.id == targetId);
                                if (targetIndex == -1) return;

                                final estimatedItemHeight = 120.0;
                                final maxScroll = _scrollController.position.maxScrollExtent;
                                final targetPosition =
                                    (filteredMessages.length - 1 - targetIndex) * estimatedItemHeight;
                                final clampedPosition = targetPosition.clamp(0.0, maxScroll);

                                _scrollController.animateTo(
                                  clampedPosition,
                                  duration: const Duration(milliseconds: 450),
                                  curve: Curves.easeInOut,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey[300]!, width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.push_pin, color: Colors.orange, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                            style: TextStyle(color: Colors.grey[700], fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, color: Colors.grey),
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
                            cacheExtent: 500, // Cache 500px để giảm rebuild và cải thiện performance
                            itemCount: filteredMessages.length,
                            itemBuilder: (context, index) {
                              final message = filteredMessages[index];
                              final isMe = message.senderId == currentUser.id;
                              final reactions = message.reactions;
                              final hasReactions =
                                  reactions.isNotEmpty && reactions.values.any((list) => list.isNotEmpty);

                              if (!isMe) {
                                if (message.status == 'sent') {
                                  _messageService.markAsDelivered(message.id, currentUser.id);
                                }
                                // Chỉ mark as read nếu read receipts được bật
                                if (_readReceiptsEnabled && (!message.isRead || message.status != 'read')) {
                                  _messageService.markAsRead(message.id, currentUser.id);
                                }
                              }

                              // Kiểm tra tin nhắn đã được thu hồi
                              final isRecalled = message.isRecalled;
                              // Kiểm tra có thể thu hồi không (trong 24 giờ và chưa bị thu hồi)
                              final canRecall =
                                  isMe && !isRecalled && DateTime.now().difference(message.createdAt).inHours <= 24;
                              // Cả sender và receiver đều có thể ghim/bỏ ghim
                              final canPin = (isMe || message.receiverId == currentUser.id) && !isRecalled;

                              final isTargetMessage = widget.scrollToMessageId == message.id;
                              return GestureDetector(
                                key: isTargetMessage ? ValueKey('message_${message.id}') : null,
                                onLongPress: () => _showMessageOptionsDialog(context, message, canRecall, canPin),
                                child: Align(
                                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Column(
                                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      if (message.replyToMessageId != null)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.06),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                message.replyToSenderId == currentUser.id ? 'Bạn' : 'Đối phương',
                                                style: const TextStyle(
                                                  color: Colors.white70,
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
                                      // Hiển thị icon ghim nếu tin nhắn đã được ghim
                                      if (message.isPinned)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.push_pin, size: 14, color: Colors.grey[500]),
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
                                      // Nguyên tắc 3: Hiển thị tin nhắn đã thu hồi
                                      if (isRecalled)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[300]!,
                                            borderRadius: BorderRadius.circular(18),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.undo, color: Colors.grey[400], size: 16),
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
                                                  margin: const EdgeInsets.only(bottom: 6),
                                                  constraints: const BoxConstraints(maxWidth: 250, maxHeight: 250),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(12),
                                                    child: Image.network(message.imageUrl!, fit: BoxFit.cover),
                                                  ),
                                                ),
                                              );
                                            }

                                            if (message.videoUrl != null) {
                                              parts.add(
                                                Container(
                                                  margin: const EdgeInsets.only(bottom: 6),
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[300]!,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: const [
                                                      Icon(Icons.play_circle_fill, color: Colors.black),
                                                      SizedBox(width: 8),
                                                      Text('Video', style: TextStyle(color: Colors.black)),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }

                                            if (message.latitude != null && message.longitude != null) {
                                              if (kDebugMode) {
                                                debugPrint('=== ADDING LOCATION WIDGET ===');
                                                debugPrint('Message ID: ${message.id}');
                                                debugPrint('Latitude: ${message.latitude}');
                                                debugPrint('Longitude: ${message.longitude}');
                                                debugPrint('Address: ${message.locationAddress}');
                                                debugPrint('IsLiveLocation: ${message.isLiveLocation}');
                                              }
                                              parts.add(
                                                LocationMessageWidget(
                                                  message: message,
                                                  isSentByMe: message.senderId == currentUser.id,
                                                ),
                                              );
                                            } else {
                                              // Debug: log why location widget is NOT added
                                              if (kDebugMode) {
                                                debugPrint('=== LOCATION WIDGET NOT ADDED ===');
                                                debugPrint('Message ID: ${message.id}');
                                                debugPrint(
                                                  'Latitude: ${message.latitude} (null? ${message.latitude == null})',
                                                );
                                                debugPrint(
                                                  'Longitude: ${message.longitude} (null? ${message.longitude == null})',
                                                );
                                                debugPrint('Content: ${message.content}');
                                                debugPrint(
                                                  'This might be a location message that lost its coordinates!',
                                                );
                                              }
                                            }

                                            if (message.gifUrl != null) {
                                              parts.add(
                                                Container(
                                                  margin: const EdgeInsets.only(bottom: 6),
                                                  constraints: const BoxConstraints(maxWidth: 250, maxHeight: 250),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(12),
                                                    child: Image.network(
                                                      message.gifUrl!,
                                                      fit: BoxFit.cover,
                                                      loadingBuilder: (context, child, loadingProgress) {
                                                        if (loadingProgress == null) return child;
                                                        return Container(
                                                          height: 200,
                                                          color: const Color(0xFF2F3031),
                                                          child: Center(
                                                            child: CircularProgressIndicator(
                                                              value: loadingProgress.expectedTotalBytes != null
                                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                                        loadingProgress.expectedTotalBytes!
                                                                  : null,
                                                              color: Colors.black,
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                      errorBuilder: (context, error, stackTrace) {
                                                        return Container(
                                                          height: 200,
                                                          color: const Color(0xFF2F3031),
                                                          child: const Center(
                                                            child: Icon(Icons.error, color: Colors.black),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }

                                            if (message.audioUrl != null && message.audioUrl!.isNotEmpty) {
                                              debugPrint(
                                                'Adding voice widget: id=${message.id}, audioUrl=${message.audioUrl}, duration=${message.audioDuration}',
                                              );
                                              parts.add(
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 6),
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
                                                  margin: const EdgeInsets.only(bottom: 8),
                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: isMe ? const Color(0xFF0084FF) : Colors.grey[300]!,
                                                    borderRadius: BorderRadius.circular(18),
                                                  ),
                                                  child: _buildMessageContent(message.content, isMe),
                                                ),
                                              );
                                            }

                                            // Đảm bảo có ít nhất một widget để hiển thị
                                            if (parts.isEmpty) {
                                              // Nếu không có gì để hiển thị, hiển thị placeholder
                                              debugPrint(
                                                'WARNING: Message has no parts to display: id=${message.id}, '
                                                'content="${message.content}", '
                                                'lat=${message.latitude}, lng=${message.longitude}, '
                                                'image=${message.imageUrl}, video=${message.videoUrl}, '
                                                'audio=${message.audioUrl}, gif=${message.gifUrl}',
                                              );

                                              // Ưu tiên kiểm tra location message trước
                                              if (message.latitude != null && message.longitude != null) {
                                                debugPrint(
                                                  'FIXING: Location message has no widget! Adding location widget manually. '
                                                  'lat=${message.latitude}, lng=${message.longitude}',
                                                );
                                                parts.add(LocationMessageWidget(message: message, isSentByMe: isMe));
                                              } else if (message.audioUrl != null && message.audioUrl!.isNotEmpty) {
                                                // Fallback: thêm voice widget nếu có audioUrl
                                                debugPrint(
                                                  'FIXING: Voice message has no widget! Adding voice widget manually. '
                                                  'audioUrl=${message.audioUrl}, duration=${message.audioDuration}',
                                                );
                                                parts.add(
                                                  Padding(
                                                    padding: const EdgeInsets.only(bottom: 6),
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
                                              } else {
                                                // Fallback: hiển thị placeholder text
                                                parts.add(
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                    decoration: BoxDecoration(
                                                      color: isMe ? const Color(0xFF0084FF) : Colors.grey[300]!,
                                                      borderRadius: BorderRadius.circular(18),
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
                                            } else {
                                              // Debug: log số lượng parts được tạo
                                              debugPrint(
                                                'Message ${message.id} has ${parts.length} parts: '
                                                'hasImage=${message.imageUrl != null}, '
                                                'hasVideo=${message.videoUrl != null}, '
                                                'hasLocation=${message.latitude != null && message.longitude != null}, '
                                                'hasAudio=${message.audioUrl != null}, '
                                                'hasGif=${message.gifUrl != null}, '
                                                'hasContent=${message.content.isNotEmpty}',
                                              );
                                            }

                                            final bubble = Column(
                                              crossAxisAlignment: isMe
                                                  ? CrossAxisAlignment.end
                                                  : CrossAxisAlignment.start,
                                              children: parts,
                                            );

                                            // Avatar theo người gửi
                                            Widget _avatar(bool me) {
                                              final url = me ? currentUser.avatarUrl : widget.otherUser.avatarUrl;
                                              final name = me ? currentUser.fullName : widget.otherUser.fullName;
                                              return CircleAvatar(
                                                radius: 16,
                                                backgroundColor: Colors.grey[300],
                                                backgroundImage: url != null ? NetworkImage(url) : null,
                                                child: url == null
                                                    ? Text(
                                                        (name.isNotEmpty ? name[0] : 'U').toUpperCase(),
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      )
                                                    : null,
                                              );
                                            }

                                            // Với tin nhắn mình gửi (isMe = true): icon nằm trước bubble, avatar ở cuối bên phải.
                                            // Với tin nhắn nhận được: icon nằm sau bubble, avatar ở đầu bên trái.
                                            if (isMe) {
                                              return Row(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 6),
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
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  _avatar(false),
                                                  const SizedBox(width: 6),
                                                  Flexible(child: bubble),
                                                  Padding(
                                                    padding: const EdgeInsets.only(left: 6),
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
                                        if (isMe && !isRecalled)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 2, top: 2),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _statusIcon(message.status, _readReceiptsEnabled),
                                                  size: 14,
                                                  color: _statusColor(message.status, _readReceiptsEnabled),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _statusLabel(message.status, _readReceiptsEnabled),
                                                  style: TextStyle(
                                                    color: _statusColor(message.status, _readReceiptsEnabled),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                      if (!isRecalled && hasReactions)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: reactions.entries.where((e) => e.value.isNotEmpty).map((entry) {
                                              final emoji = entry.key;
                                              final count = entry.value.length;
                                              final reacted = entry.value.contains(currentUser.id);
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: reacted
                                                      ? Colors.blue.withOpacity(0.2)
                                                      : Colors.white.withOpacity(0.08),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: reacted ? Colors.blueAccent : Colors.white24,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(emoji, style: const TextStyle(fontSize: 14)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '$count',
                                                      style: const TextStyle(
                                                        color: Colors.black,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
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
                );
              },
            ),
          ),

          // Media preview section
          if (_selectedImages.isNotEmpty || _selectedVideos.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border(top: BorderSide(color: Colors.grey[300]!, width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with count and delete all button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_getMediaCountText(), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedImages.clear();
                            _selectedVideos.clear();
                          });
                        },
                        child: const Text('Xóa tất cả', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Media preview grid
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length + _selectedVideos.length + 1,
                      itemBuilder: (context, index) {
                        // Add more button (last item)
                        if (index == _selectedImages.length + _selectedVideos.length) {
                          return GestureDetector(
                            onTap: _pickMedia,
                            child: Container(
                              width: 80,
                              height: 80,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey[300]!,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[600]!, width: 1, style: BorderStyle.solid),
                              ),
                              child: const Icon(Icons.add, color: Colors.grey, size: 32),
                            ),
                          );
                        }

                        // Image preview
                        if (index < _selectedImages.length) {
                          return Stack(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: DecorationImage(image: FileImage(_selectedImages[index]), fit: BoxFit.cover),
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
                                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: Colors.black, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        // Video preview
                        final videoIndex = index - _selectedImages.length;
                        return Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                              child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.black, size: 32)),
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
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, color: Colors.white, size: 16),
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
          // Reply preview (moved above composer)
          if (_replyingTo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(top: BorderSide(color: Colors.grey[300]!, width: 1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.reply, color: Colors.grey[700], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _replyPreviewLabel(_replyingTo!),
                      style: const TextStyle(color: Colors.black87, fontSize: 13),
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
                    icon: const Icon(Icons.close, color: Colors.black54, size: 18),
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

          // Message input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[300]!, width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Menu tính năng khi nhấn dấu + (hiển thị phía trên)
                if (_showMoreOptionsMenu)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                            _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
                            color: Colors.black,
                          ),
                          onPressed: _isLoading ? null : () => _toggleEmojiPicker(),
                        ),
                        // GIF button
                        IconButton(
                          icon: const Icon(Icons.gif, color: Colors.black),
                          onPressed: _isLoading ? null : _showGifSearchDialog,
                        ),
                      ],
                      // More options button (+)
                      IconButton(
                        icon: Icon(_showMoreOptionsMenu ? Icons.close : Icons.add_circle_outline, color: Colors.black),
                        onPressed: () {
                          setState(() {
                            _showMoreOptionsMenu = !_showMoreOptionsMenu;
                          });
                        },
                      ),
                    ] else ...[
                      // Khi có text: chỉ hiển thị dấu +
                      IconButton(
                        icon: Icon(_showMoreOptionsMenu ? Icons.close : Icons.add_circle_outline, color: Colors.black),
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
                                content: Text('Lỗi khi bắt đầu ghi âm: ${error.toString()}'),
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
                                content: Text('Lỗi khi dừng ghi âm: ${error.toString()}'),
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
                          hintText: 'Nhập @, tin nhắn tới Cloud của tôi',
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        minLines: 1,
                        maxLines: _hasText ? 5 : 1,
                        textInputAction: TextInputAction.send,
                        enabled: !_isLoading,
                        enableInteractiveSelection: true,
                        keyboardType: TextInputType.multiline,
                        onChanged: (value) {
                          _handleTyping(value);
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
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
    final result = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: true);

    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (final file in result.files) {
        if (file.path == null) continue;

        final ext = (file.extension ?? '').toLowerCase();
        final isVideo = ['mp4', 'mov', 'mkv', 'avi', 'mpeg', 'mpg', 'wmv'].contains(ext);
        final isImage = ['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'].contains(ext);

        if (isVideo) {
          _selectedVideos.add(File(file.path!));
        } else if (isImage) {
          _selectedImages.add(File(file.path!));
        }
      }
    });
  }

  Future<void> _capturePhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12),
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
              title: const Text('Trả lời', style: TextStyle(color: Colors.black)),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.reply_all, color: Colors.black),
              title: const Text('Chuyển tiếp', style: TextStyle(color: Colors.black)),
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
                  style: TextStyle(color: message.isPinned ? Colors.orange : Colors.black87),
                ),
                onTap: () => Navigator.pop(context, message.isPinned ? 'unpin' : 'pin'),
              ),
            if (canRecall)
              ListTile(
                leading: const Icon(Icons.undo, color: Colors.black),
                title: const Text('Thu hồi tin nhắn', style: TextStyle(color: Colors.black)),
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

      await _messageService.reactToMessage(messageId: message.id, userId: currentUser.id, emoji: emoji);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể gửi reaction: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _startRecordingVoice() async {
    try {
      if (kDebugMode) {
        debugPrint('=== STARTING VOICE RECORDING ===');
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
              content: Text('Cần quyền microphone để ghi âm. Vui lòng cấp quyền trong Settings.'),
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

      // Listen to duration updates
      _recordingDurationSub = _voiceRecordingService.durationStream?.listen((duration) {
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
        debugPrint('ERROR in _startRecordingVoice: $e');
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

      // Upload và gửi voice message
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      setState(() {
        _isLoading = true;
      });

      try {
        // Upload voice file
        if (kDebugMode) {
          debugPrint('Starting voice file upload...');
          debugPrint('File path: $filePath');
          debugPrint('Duration: $_recordingDuration seconds');
        }

        final audioUrl = await _voiceRecordingService.uploadVoiceFile(filePath, duration: _recordingDuration);

        if (kDebugMode) {
          debugPrint('Voice file upload completed. URL: $audioUrl');
          debugPrint('URL length: ${audioUrl.length}');
          debugPrint('URL is empty: ${audioUrl.isEmpty}');
        }

        // Tạo và gửi message
        final message = MessageModel(
          id: '',
          senderId: currentUser.id,
          receiverId: widget.otherUser.id,
          content: '',
          audioUrl: audioUrl,
          audioDuration: _recordingDuration,
          createdAt: DateTime.now(),
          replyToMessageId: _replyingTo?.id,
          replyToContent: _replyingTo?.content.isNotEmpty == true
              ? _replyingTo!.content
              : (_replyingTo?.imageUrl != null
                    ? '[Ảnh]'
                    : (_replyingTo?.videoUrl != null
                          ? '[Video]'
                          : (_replyingTo?.audioUrl != null
                                ? '[Voice]'
                                : (_replyingTo?.gifUrl != null ? '[GIF]' : '')))),
          replyToSenderId: _replyingTo?.senderId,
          replyToType: _replyType(_replyingTo),
        );

        if (kDebugMode) {
          debugPrint('Sending message to Firestore...');
          debugPrint('Message audioUrl before send: ${message.audioUrl}');
          debugPrint('Message audioDuration: ${message.audioDuration}');
        }

        final messageId = await _messageService.sendMessage(message);

        if (kDebugMode) {
          debugPrint('Voice message sent with ID: $messageId');
          debugPrint('Voice message data: audioUrl=${message.audioUrl}, duration=${message.audioDuration}');
        }

        // Wait a bit for Firestore to sync
        // Increased delay to ensure message is indexed and appears in next poll
        await Future.delayed(const Duration(milliseconds: 600));

        if (mounted) {
          setState(() {
            _replyingTo = null;
            _recordingDuration = 0;
          });
        }
      } catch (e, stackTrace) {
        if (kDebugMode) {
          debugPrint('ERROR in _stopRecordingVoice: $e');
          debugPrint('Stack trace: $stackTrace');
        }

        if (!mounted) return;

        // Show user-friendly error message
        String errorMessage = 'Không thể gửi voice message';
        if (e.toString().contains('rỗng') || e.toString().contains('Empty file')) {
          errorMessage = 'File ghi âm rỗng. Vui lòng thử ghi âm lại.';
        } else if (e.toString().contains('không tồn tại')) {
          errorMessage = 'File ghi âm không tồn tại. Vui lòng thử ghi âm lại.';
        } else if (e.toString().contains('internet') || e.toString().contains('kết nối')) {
          errorMessage = 'Lỗi kết nối mạng. Vui lòng kiểm tra và thử lại.';
        } else {
          errorMessage = 'Không thể gửi voice message: ${e.toString()}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
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
          content: Text(ErrorMessageHelper.getErrorMessage(e, defaultMessage: 'Không thể dừng ghi âm')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelRecordingVoice() async {
    try {
      await _voiceRecordingService.cancelRecording();
      _recordingDurationSub?.cancel();
      _recordingDurationSub = null;
      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
          _recordingDuration = 0;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error canceling recording: $e');
      }
      // Still reset state even if cancel fails
      _recordingDurationSub?.cancel();
      _recordingDurationSub = null;
      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
          _recordingDuration = 0;
        });
      }
    }
  }

  Widget _buildMoreOptionButton({required IconData icon, required String label, required VoidCallback onTap}) {
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
              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Icon(icon, color: Colors.black87, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }

  Future<void> _showMoreOptions() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy'))],
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
                onChanged: (value) => setDialogState(() => selectedDuration = value),
              ),
              RadioListTile<int>(
                title: const Text('1 giờ'),
                value: 60,
                groupValue: selectedDuration,
                activeColor: Colors.green,
                onChanged: (value) => setDialogState(() => selectedDuration = value),
              ),
              RadioListTile<int>(
                title: const Text('8 giờ'),
                value: 480,
                groupValue: selectedDuration,
                activeColor: Colors.green,
                onChanged: (value) => setDialogState(() => selectedDuration = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
            TextButton(
              onPressed: selectedDuration != null ? () => Navigator.pop(context, selectedDuration) : null,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bạn cần đăng nhập để gửi vị trí'), backgroundColor: Colors.red));
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
        debugPrint('=== STARTING LOCATION SEND PROCESS ===');
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
              content: Text('Cần quyền truy cập vị trí để gửi vị trí. Vui lòng cấp quyền trong Settings.'),
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
              content: Text('Không thể lấy vị trí. Vui lòng kiểm tra quyền truy cập và đảm bảo GPS đã bật.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('Position obtained: lat=${position.latitude}, lng=${position.longitude}');
      }

      // Lấy địa chỉ với timeout
      String? address;
      try {
        if (kDebugMode) {
          debugPrint('Getting address from coordinates...');
        }
        address = await _locationService.getAddressFromCoordinates(position.latitude, position.longitude);
        if (kDebugMode) {
          debugPrint('Address obtained: $address');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error getting address: $e');
        }
        // Vẫn gửi location ngay cả khi không lấy được address
        address = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        if (kDebugMode) {
          debugPrint('Using fallback address: $address');
        }
      }

      final message = MessageModel(
        id: '',
        senderId: currentUser.id,
        receiverId: widget.otherUser.id,
        content: '',
        latitude: position.latitude,
        longitude: position.longitude,
        locationAddress: address,
        isLiveLocation: false,
        createdAt: DateTime.now(),
      );

      if (kDebugMode) {
        debugPrint('=== SENDING LOCATION MESSAGE ===');
        debugPrint('SenderId: ${message.senderId}');
        debugPrint('ReceiverId: ${message.receiverId}');
        debugPrint('Latitude: ${message.latitude}');
        debugPrint('Longitude: ${message.longitude}');
        debugPrint('Address: ${message.locationAddress}');
        debugPrint('IsLiveLocation: ${message.isLiveLocation}');
        debugPrint('Message toMap: ${message.toMap()}');
      }

      final messageId = await _messageService.sendMessage(message);

      if (kDebugMode) {
        debugPrint('Location message sent with ID: $messageId');
        debugPrint(
          'Message data after send: lat=${message.latitude}, lng=${message.longitude}, address=${message.locationAddress}',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi vị trí'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('ERROR in _sendCurrentLocation: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessageHelper.getErrorMessage(e, defaultMessage: 'Không thể gửi vị trí')),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bạn cần đăng nhập để gửi vị trí'), backgroundColor: Colors.red));
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
              content: Text('Cần quyền truy cập vị trí để gửi vị trí. Vui lòng cấp quyền trong Settings.'),
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
              content: Text('Không thể lấy vị trí. Vui lòng kiểm tra quyền truy cập và đảm bảo GPS đã bật.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      String? address;
      try {
        address = await _locationService.getAddressFromCoordinates(position.latitude, position.longitude);
      } catch (e) {
        debugPrint('Error getting address: $e');
        // Vẫn gửi location ngay cả khi không lấy được address
        address = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      }

      final expiresAt = DateTime.now().add(Duration(minutes: durationMinutes));

      final message = MessageModel(
        id: '',
        senderId: currentUser.id,
        receiverId: widget.otherUser.id,
        content: '',
        latitude: position.latitude,
        longitude: position.longitude,
        locationAddress: address,
        isLiveLocation: true,
        locationExpiresAt: expiresAt,
        createdAt: DateTime.now(),
      );

      final messageId = await _messageService.sendMessage(message);

      // Bắt đầu tracking real-time
      if (messageId.isNotEmpty) {
        await _locationService.startLiveLocationTracking(
          messageId: messageId,
          conversationId: _conversationId ?? '',
          receiverId: widget.otherUser.id,
          durationMinutes: durationMinutes,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã bắt đầu chia sẻ vị trí trực tiếp trong $durationMinutes phút'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending live location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessageHelper.getErrorMessage(e, defaultMessage: 'Không thể gửi vị trí trực tiếp')),
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

  Future<void> _startCall({required bool video}) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn cần đăng nhập để gọi')));
      }
      return;
    }

    // Chỉ mở màn hình CallScreen, để CallScreen tự xử lý call + lỗi
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(otherUser: widget.otherUser, isIncoming: false, isVideoCall: video),
        ),
      );
    }
  }

  IconData _statusIcon(String status, bool readReceiptsEnabled) {
    switch (status) {
      case 'delivered':
        return Icons.done_all;
      case 'read':
        // Nếu read receipts tắt, hiển thị như delivered
        return readReceiptsEnabled ? Icons.done_all : Icons.done_all;
      case 'sent':
      default:
        return Icons.check;
    }
  }

  Color _statusColor(String status, bool readReceiptsEnabled) {
    switch (status) {
      case 'read':
        // Nếu read receipts tắt, hiển thị như delivered
        return readReceiptsEnabled ? Colors.lightBlueAccent : Colors.white70;
      case 'delivered':
        return Colors.white70;
      case 'sent':
      default:
        return Colors.white54;
    }
  }

  String _statusLabel(String status, bool readReceiptsEnabled) {
    switch (status) {
      case 'read':
        // Nếu read receipts tắt, không hiển thị "Đã xem"
        return readReceiptsEnabled ? 'Đã xem' : 'Đã gửi';
      case 'delivered':
        return 'Đã gửi';
      case 'sent':
      default:
        return 'Đang gửi';
    }
  }

  void _handleTyping(String value) {
    // Check if widget is still mounted before accessing context
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null || _conversationId == null) return;

    // Debounce typing indicator to avoid too many calls
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      // Check mounted again before async operation
      if (!mounted) return;

      // Báo đang nhập
      _messageService.setTyping(conversationId: _conversationId!, userId: currentUser.id, isTyping: true);

      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        // Check mounted before async operation
        if (!mounted) return;
        _messageService.setTyping(conversationId: _conversationId!, userId: currentUser.id, isTyping: false);
      });
    });
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
            'url': gif['images']['original']['url'] ?? gif['images']['fixed_height']['url'],
            'title': gif['title'] ?? '',
            'preview': gif['images']['fixed_height_small']['url'] ?? gif['images']['fixed_height']['url'],
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

    // Load trending GIFs initially
    if (initialLoad) {
      try {
        final url = Uri.parse('https://api.giphy.com/v1/gifs/trending?api_key=$_giphyApiKey&limit=25&rating=g');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> gifsData = data['data'] ?? [];
          gifs = gifsData.map((gif) {
            return {
              'id': gif['id'],
              'url': gif['images']['original']['url'] ?? gif['images']['fixed_height']['url'],
              'title': gif['title'] ?? '',
              'preview': gif['images']['fixed_height_small']['url'] ?? gif['images']['fixed_height']['url'],
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
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
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
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white70),
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
                      ? const Center(child: CircularProgressIndicator(color: Colors.black))
                      : gifs.isEmpty
                      ? const Center(
                          child: Text('Nhập từ khóa để tìm kiếm GIF', style: TextStyle(color: Colors.grey)),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                          itemCount: gifs.length,
                          itemBuilder: (context, index) {
                            final gif = gifs[index];
                            return InkWell(
                              onTap: () async {
                                final gifUrl = gif['url'] as String;
                                Navigator.pop(context);
                                // Xóa ảnh và video nếu đã chọn GIF
                                setState(() {
                                  _selectedImages.clear();
                                  _selectedVideos.clear();
                                });
                                // Gửi GIF ngay lập tức (không cần lưu vào state)
                                await _sendGifMessage(gifUrl);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  gif['preview'] as String,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: Colors.grey[300]!,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          value: loadingProgress.expectedTotalBytes != null
                                              ? loadingProgress.cumulativeBytesLoaded /
                                                    loadingProgress.expectedTotalBytes!
                                              : null,
                                          color: Colors.black,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[300]!,
                                      child: const Icon(Icons.error, color: Colors.black),
                                    );
                                  },
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
            final post = await firestoreService.getPost(postId, viewerId: currentUser.id);

            if (post != null && mounted) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
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
                  content: Text(ErrorMessageHelper.getErrorMessage(e, defaultMessage: 'Không thể tải tin nhắn')),
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

  Future<void> _recallMessage(MessageModel message) async {
    try {
      await _messageService.recallMessage(message.id, message.senderId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã thu hồi tin nhắn'), backgroundColor: Colors.black));
      }
    } catch (e) {
      if (mounted) {
        String message = 'Thu hồi tin nhắn thất bại. Vui lòng thử lại.';
        if (e is FirebaseException && e.code == 'permission-denied') {
          message = 'Bạn không có quyền thu hồi tin nhắn này. Vui lòng kiểm tra lại.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã ghim tin nhắn'), backgroundColor: Colors.green));
        // Không scroll tự động - tin nhắn đã ghim vẫn ở vị trí cũ
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã bỏ ghim tin nhắn'), backgroundColor: Colors.black));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    }
  }

  Widget _messageActionBar({
    required MessageModel message,
    required bool canRecall,
    required bool canPin,
    required bool isMe,
  }) {
    final color = Colors.white;
    final iconStyle = IconButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(24, 24),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      // ✅ tránh bị đè 2 lớp nền (M3 IconButton theme + nền của widget khác)
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          style: iconStyle,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          iconSize: 20,
          icon: Icon(Icons.more_horiz, color: color),
          onPressed: () => _showMessageOptionsDialog(context, message, canRecall, canPin),
        ),
        const SizedBox(width: 6),
        IconButton(
          style: iconStyle,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          iconSize: 20,
          icon: const Icon(Icons.reply, color: Colors.white70),
          onPressed: () {
            setState(() {
              _replyingTo = message;
            });
          },
        ),
        const SizedBox(width: 6),
        IconButton(
          style: iconStyle,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          iconSize: 20,
          icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white70),
          onPressed: () => _openReactionPicker(message),
        ),
      ],
    );
  }

  Future<void> _openReactionPicker(MessageModel message) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
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
      selection: TextSelection.collapsed(offset: selection.start + emoji.length),
    );
  }

  Future<void> _forwardMessage(MessageModel message) async {
    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    // Hiển thị dialog chọn conversation để forward
    final selectedConversation = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ForwardMessageDialog(currentUserId: currentUser.id, messageService: _messageService),
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
                      : (message.audioUrl != null ? '[Voice]' : (message.gifUrl != null ? '[GIF]' : ''))));

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
            ? conversationId.split('_').firstWhere((id) => id != currentUser.id)
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã chuyển tiếp tin nhắn'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessageHelper.getErrorMessage(e, defaultMessage: 'Không thể chuyển tiếp tin nhắn')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _ForwardMessageDialog extends StatelessWidget {
  final String currentUserId;
  final MessageService messageService;

  const _ForwardMessageDialog({required this.currentUserId, required this.messageService});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'Chọn cuộc trò chuyện',
                    style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ConversationModel>>(
                stream: messageService.getConversations(currentUserId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.black));
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text('Chưa có cuộc trò chuyện nào', style: TextStyle(color: Colors.black87)),
                    );
                  }

                  final conversations = snapshot.data!;

                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];

                      // Direct conversation
                      if (conversation.type == 'direct') {
                        final otherUserId = conversation.getOtherUserId(currentUserId);
                        if (otherUserId == null) return const SizedBox.shrink();

                        return FutureBuilder<UserModel?>(
                          future: UserService().getUserById(otherUserId),
                          builder: (context, userSnapshot) {
                            if (!userSnapshot.hasData) {
                              return const SizedBox.shrink();
                            }

                            final user = userSnapshot.data!;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                                child: user.avatarUrl == null ? Text(user.fullName[0].toUpperCase()) : null,
                              ),
                              title: Text(user.fullName, style: const TextStyle(color: Colors.black)),
                              subtitle: Text(
                                conversation.lastMessageContent ?? '',
                                style: TextStyle(color: Colors.grey[400]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () =>
                                  Navigator.pop(context, {'conversationId': conversation.id, 'type': 'direct'}),
                            );
                          },
                        );
                      }

                      // Group conversation
                      if (conversation.type == 'group' && conversation.groupId != null) {
                        return FutureBuilder<GroupModel?>(
                          future: GroupService().getGroup(conversation.groupId!),
                          builder: (context, groupSnapshot) {
                            if (!groupSnapshot.hasData) {
                              return const SizedBox.shrink();
                            }

                            final group = groupSnapshot.data!;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: group.coverUrl != null ? NetworkImage(group.coverUrl!) : null,
                                child: group.coverUrl == null ? Text(group.name[0].toUpperCase()) : null,
                              ),
                              title: Row(
                                children: [
                                  Text(group.name, style: const TextStyle(color: Colors.black)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.group, size: 16, color: Colors.grey),
                                ],
                              ),
                              subtitle: Text(
                                conversation.lastMessageContent ?? '',
                                style: TextStyle(color: Colors.grey[400]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(context, {
                                'conversationId': conversation.id,
                                'type': 'group',
                                'groupId': group.id,
                              }),
                            );
                          },
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
