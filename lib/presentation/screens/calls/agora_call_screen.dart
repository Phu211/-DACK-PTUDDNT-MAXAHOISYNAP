import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../../data/services/agora_call_service.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../../data/services/user_service.dart';

class AgoraCallScreen extends StatefulWidget {
  final UserModel? otherUser;
  final bool isIncoming;
  final bool isVideoCall;
  final String? channelName;
  final String? token;

  const AgoraCallScreen({
    super.key,
    this.otherUser,
    this.isIncoming = false,
    this.isVideoCall = false,
    this.channelName,
    this.token,
  });

  @override
  State<AgoraCallScreen> createState() => _AgoraCallScreenState();
}

class _AgoraCallScreenState extends State<AgoraCallScreen> {
  final AgoraCallService _callService = AgoraCallService.instance;
  final UserService _userService = UserService();

  UserModel? _otherUser;
  String _callStatus = 'Đang gọi...';
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;
  bool _isLocalVideoEnabled = true;

  StreamSubscription<String>? _callStateSubscription;
  StreamSubscription<String>? _connectionStateSubscription;
  Timer? _callTimer;
  Duration _callDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _otherUser = widget.otherUser;
    _loadOtherUser();
    _listenToCallState();
    _listenToConnectionState();

    if (!widget.isIncoming) {
      _startCall();
    } else {
      _answerCall();
    }
  }

  Future<void> _loadOtherUser() async {
    if (_otherUser != null) return;

    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser != null && _callService.toUserId != null) {
      final user = await _userService.getUserById(_callService.toUserId!);
      if (mounted) {
        setState(() {
          _otherUser = user;
        });
      }
    }
  }

  Future<void> _startCall() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null || _otherUser == null) return;

    setState(() {
      _callStatus = 'Đang gọi...';
    });

    final success = await _callService.call(
      fromUserId: currentUser.id,
      toUserId: _otherUser!.id,
      isVideo: widget.isVideoCall,
    );

    if (!success && mounted) {
      setState(() {
        _callStatus = 'Gọi thất bại';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  Future<void> _answerCall() async {
    if (widget.channelName == null || widget.token == null) {
      // Nếu không có channelName và token, cần lấy từ notification hoặc call service
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      // Tạo channel name từ userIds
      final fromUserId = _callService.fromUserId ?? '';
      final toUserId = currentUser.id;
      final channelName = _callService.generateChannelName(fromUserId, toUserId);
      
      // Lấy token
      final token = await _callService.fetchToken(currentUser.id, channelName);
      if (token == null) {
        setState(() {
          _callStatus = 'Không thể lấy token';
        });
        return;
      }

      final success = await _callService.joinChannel(
        userId: currentUser.id,
        channelName: channelName,
        token: token,
        isVideo: widget.isVideoCall,
      );

      if (success) {
        _startCallTimer();
      }
    } else {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      final success = await _callService.joinChannel(
        userId: currentUser.id,
        channelName: widget.channelName!,
        token: widget.token!,
        isVideo: widget.isVideoCall,
      );

      if (success) {
        _startCallTimer();
      }
    }
  }

  void _listenToCallState() {
    _callStateSubscription?.cancel();
    _callStateSubscription = _callService.callStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        if (state.contains('Đã kết nối')) {
          _callStatus = 'Đã kết nối';
          if (!widget.isIncoming) {
            _startCallTimer();
          }
        } else if (state.contains('Đã kết thúc') ||
            state.contains('Đã từ chối') ||
            state.contains('Người dùng đã rời khỏi')) {
          _callStatus = state;
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _endCall();
            }
          });
        } else {
          _callStatus = state;
        }
      });
    });
  }

  void _listenToConnectionState() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription =
        _callService.connectionStateStream.listen((state) {
      if (!mounted) return;
      debugPrint('Connection state: $state');
    });
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration = Duration(seconds: _callDuration.inSeconds + 1);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _rejectCall() async {
    await _callService.reject();
    _endCall();
  }

  Future<void> _hangupCall() async {
    await _callService.hangup();
    _endCall();
  }

  void _endCall() {
    _callTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _toggleMute() async {
    await _callService.toggleMute();
    setState(() {
      _isMuted = _callService.isMuted;
    });
  }

  Future<void> _toggleSpeaker() async {
    await _callService.toggleSpeaker();
    setState(() {
      _isSpeakerOn = _callService.isSpeakerOn;
    });
  }

  Future<void> _toggleVideo() async {
    await _callService.toggleVideo();
    setState(() {
      _isVideoEnabled = _callService.isVideoEnabled;
    });
  }

  @override
  void dispose() {
    _callStateSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _callTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FA5),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF5B7FA8).withOpacity(0.95),
                const Color(0xFF4A6FA5),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Video view cho remote user (nếu là video call)
              if (widget.isVideoCall &&
                  _callService.remoteUid != null &&
                  _callService.engine != null)
                Positioned.fill(
                  child: AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: _callService.engine!,
                      canvas: VideoCanvas(uid: _callService.remoteUid),
                      connection: RtcConnection(
                        channelId: widget.channelName ?? '',
                      ),
                    ),
                  ),
                ),

              // Local video view (nếu là video call)
              if (widget.isVideoCall &&
                  _isLocalVideoEnabled &&
                  _callService.engine != null)
                Positioned(
                  top: 40,
                  right: 16,
                  child: Container(
                    width: 120,
                    height: 160,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AgoraVideoView(
                        controller: VideoViewController(
                          rtcEngine: _callService.engine!,
                          canvas: const VideoCanvas(uid: 0),
                        ),
                      ),
                    ),
                  ),
                ),

              // UI overlay
              Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.black),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Row(
                          children: [
                            if (widget.isVideoCall)
                              IconButton(
                                icon: const Icon(Icons.person_add,
                                    color: Colors.black, size: 24),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Tính năng đang phát triển'),
                                    ),
                                  );
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.more_vert,
                                  color: Colors.black, size: 24),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (context) => Container(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.info_outline),
                                          title: const Text('Thông tin cuộc gọi'),
                                          onTap: () {
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Tính năng đang phát triển')),
                                            );
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.block),
                                          title: const Text('Chặn người dùng'),
                                          onTap: () {
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Tính năng đang phát triển')),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Nội dung chính
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Avatar (chỉ hiện khi không phải video call hoặc chưa có video)
                        if (!widget.isVideoCall ||
                            _callService.remoteUid == null)
                          Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black.withOpacity(0.3),
                                width: 3,
                              ),
                            ),
                            child: ClipOval(
                              child: _otherUser?.avatarUrl != null
                                  ? Image.network(
                                      _otherUser!.avatarUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.grey[700],
                                          child: Center(
                                            child: Text(
                                              (_otherUser?.fullName.isNotEmpty ==
                                                      true)
                                                  ? _otherUser!
                                                      .fullName[0]
                                                      .toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 64,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      color: Colors.grey[700],
                                      child: Center(
                                        child: Text(
                                          (_otherUser?.fullName.isNotEmpty ==
                                                  true)
                                              ? _otherUser!
                                                  .fullName[0]
                                                  .toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 64,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),

                        const SizedBox(height: 32),

                        // Tên người dùng
                        Text(
                          _otherUser?.fullName ?? 'Đang tải...',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Trạng thái cuộc gọi
                        Text(
                          _callStatus,
                          style: TextStyle(
                            color: _callStatus.contains('kết thúc') ||
                                    _callStatus.contains('thất bại') ||
                                    _callStatus.contains('lỗi')
                                ? Colors.red[300]
                                : Colors.white.withOpacity(0.8),
                            fontSize: 18,
                            fontWeight: _callStatus.contains('kết thúc') ||
                                    _callStatus.contains('thất bại')
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        // Hiển thị thời gian nếu đã kết nối
                        if (_callDuration.inSeconds > 0 &&
                            _callStatus == 'Đã kết nối')
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _formatDuration(_callDuration),
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Bottom control bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 32,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A5A7A).withOpacity(0.8),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Video toggle (chỉ hiện khi là video call)
                        if (widget.isVideoCall)
                          _buildControlButton(
                            icon: _isVideoEnabled
                                ? Icons.videocam
                                : Icons.videocam_off,
                            onPressed: _toggleVideo,
                            isActive: _isVideoEnabled,
                            showDisabled: !_isVideoEnabled,
                          ),

                        // Mute button
                        _buildControlButton(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          onPressed: _toggleMute,
                          isActive: !_isMuted,
                        ),

                        // Share screen button (chỉ hiện khi là video call)
                        if (widget.isVideoCall)
                          _buildControlButton(
                            icon: Icons.screen_share,
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Tính năng chia sẻ màn hình đang phát triển'),
                                ),
                              );
                            },
                            isActive: false,
                          ),

                        // Speaker button
                        _buildControlButton(
                          icon: _isSpeakerOn
                              ? Icons.volume_up
                              : Icons.volume_off,
                          onPressed: _toggleSpeaker,
                          isActive: _isSpeakerOn,
                        ),

                        // End call button
                        _buildEndCallButton(
                          onPressed: widget.isIncoming &&
                                  _callStatus == 'Đang gọi...'
                              ? _rejectCall
                              : _hangupCall,
                        ),
                      ],
                    ),
                  ),

                  // Nút Answer/Reject nếu là cuộc gọi đến
                  if (widget.isIncoming && _callStatus == 'Đang gọi...')
                    Container(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildAnswerButton(),
                          const SizedBox(width: 32),
                          _buildRejectButton(),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isActive,
    bool showDisabled = false,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(isActive ? 0.2 : 0.15),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: showDisabled
              ? Colors.white.withOpacity(0.6)
              : Colors.white,
          size: 26,
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildEndCallButton({required VoidCallback onPressed}) {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.red,
      ),
      child: IconButton(
        icon: const Icon(Icons.call_end, color: Colors.black, size: 28),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildAnswerButton() {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.green,
      ),
      child: IconButton(
        icon: const Icon(Icons.call, color: Colors.black, size: 28),
        onPressed: _answerCall,
      ),
    );
  }

  Widget _buildRejectButton() {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.red,
      ),
      child: IconButton(
        icon: const Icon(Icons.call_end, color: Colors.black, size: 28),
        onPressed: _rejectCall,
      ),
    );
  }
}

