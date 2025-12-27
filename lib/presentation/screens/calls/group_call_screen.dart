import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../../data/services/group_call_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/agora_call_service.dart';
import '../../../data/models/group_call_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';

class GroupCallScreen extends StatefulWidget {
  final GroupModel group;
  final GroupCallModel groupCall;
  final bool isIncoming; // true nếu là cuộc gọi đến, false nếu là cuộc gọi đi

  const GroupCallScreen({
    super.key,
    required this.group,
    required this.groupCall,
    this.isIncoming = false,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final GroupCallService _groupCallService = GroupCallService();
  final UserService _userService = UserService();
  final AgoraCallService _agoraService = AgoraCallService.instance;

  Map<String, UserModel> _participantCache = {};
  Timer? _callTimer;
  Duration _callDuration = Duration.zero;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true;
  bool _isJoined = false;
  String? _channelName;
  String? _token;

  @override
  void initState() {
    super.initState();
    _loadParticipants();
    _listenToGroupCall();
    _initAgora();
    if (!widget.isIncoming) {
      _joinAgoraChannel();
    }
  }

  Future<void> _initAgora() async {
    await _agoraService.init();
    // Lắng nghe remote users join/leave
    // Note: AgoraCallService hiện tại chỉ hỗ trợ 1-1, cần mở rộng cho group
  }

  Future<void> _joinAgoraChannel() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    // Tạo channel name từ group ID
    _channelName = 'group_${widget.group.id}';

    // Lấy token
    _token = await _agoraService.fetchToken(currentUser.id, _channelName!);
    if (_token == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Không thể lấy token')));
      }
      return;
    }

    // Join channel
    final success = await _agoraService.joinChannel(
      userId: currentUser.id,
      channelName: _channelName!,
      token: _token!,
      isVideo: widget.groupCall.isVideoCall,
    );

    if (success) {
      setState(() {
        _isJoined = true;
      });
      _startCallTimer();
      // Tham gia group call trong Firestore
      await _joinCall();
    }
  }

  Future<void> _loadParticipants() async {
    for (final participantId in widget.groupCall.participantIds) {
      final user = await _userService.getUserById(participantId);
      if (user != null) {
        setState(() {
          _participantCache[participantId] = user;
        });
      }
    }
  }

  void _listenToGroupCall() {
    _groupCallService.getActiveGroupCall(widget.group.id).listen((groupCall) {
      if (groupCall == null || groupCall.status == 'ended') {
        _endCall();
        return;
      }

      // Reload participants khi có thay đổi
      _loadParticipants();
    });
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration = _callDuration + const Duration(seconds: 1);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _joinCall() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    try {
      // Join Agora channel trước
      if (!_isJoined) {
        await _joinAgoraChannel();
      }

      // Sau đó join group call trong Firestore
      await _groupCallService.joinGroupCall(
        widget.groupCall.id,
        currentUser.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _declineCall() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    try {
      await _groupCallService.declineGroupCall(
        widget.groupCall.id,
        currentUser.id,
      );
      _endCall();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _leaveCall() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    try {
      await _groupCallService.leaveGroupCall(
        widget.groupCall.id,
        currentUser.id,
      );
      _endCall();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _endCall() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    try {
      // Leave Agora channel
      if (_isJoined) {
        await _agoraService.hangup();
      }

      // Chỉ creator mới có thể kết thúc cuộc gọi
      if (widget.groupCall.creatorId == currentUser.id) {
        await _groupCallService.endGroupCall(
          widget.groupCall.id,
          currentUser.id,
        );
      } else {
        await _groupCallService.leaveGroupCall(
          widget.groupCall.id,
          currentUser.id,
        );
      }
    } catch (e) {
      // Ignore errors khi đã kết thúc
    }

    _callTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _toggleMute() async {
    await _agoraService.toggleMute();
    setState(() {
      _isMuted = _agoraService.isMuted;
    });
  }

  Future<void> _toggleSpeaker() async {
    await _agoraService.toggleSpeaker();
    setState(() {
      _isSpeakerOn = _agoraService.isSpeakerOn;
    });
  }

  Future<void> _toggleVideo() async {
    if (widget.groupCall.isVideoCall) {
      await _agoraService.toggleVideo();
      setState(() {
        _isVideoEnabled = _agoraService.isVideoEnabled;
      });
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    // Leave Agora channel khi dispose
    if (_isJoined) {
      _agoraService.hangup();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final currentUserStatus = currentUser != null
        ? widget.groupCall.participantStatus[currentUser.id]
        : null;
    final isJoined = currentUserStatus == CallStatus.joined;

    // Lấy danh sách người đã tham gia
    final joinedParticipants = widget.groupCall.participantIds
        .where(
          (id) => widget.groupCall.participantStatus[id] == CallStatus.joined,
        )
        .toList();

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
              // Video views cho remote users (nếu là video call)
              if (widget.groupCall.isVideoCall &&
                  _isJoined &&
                  _agoraService.engine != null)
                ..._buildRemoteVideoViews(),

              // Local video view (nếu là video call)
              if (widget.groupCall.isVideoCall &&
                  _isVideoEnabled &&
                  _isJoined &&
                  _agoraService.engine != null)
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
                          rtcEngine: _agoraService.engine!,
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
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.black,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Text(
                          'Cuộc gọi nhóm',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 48), // Để cân bằng
                      ],
                    ),
                  ),

                  // Nội dung chính
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Tên nhóm
                        Text(
                          widget.group.name,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 8),

                        // Số người tham gia
                        Text(
                          '${joinedParticipants.length}/${widget.groupCall.participantIds.length} người tham gia',
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Danh sách participants (grid view)
                        // Chỉ hiện khi không phải video call hoặc chưa có video
                        if (joinedParticipants.isNotEmpty &&
                            (!widget.groupCall.isVideoCall ||
                                !_isJoined ||
                                _agoraService.remoteUid == null))
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: GridView.builder(
                              shrinkWrap: true,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: 1,
                                  ),
                              itemCount: joinedParticipants.length,
                              itemBuilder: (context, index) {
                                final participantId = joinedParticipants[index];
                                final user = _participantCache[participantId];

                                return Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.black.withOpacity(0.3),
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: user?.avatarUrl != null
                                        ? Image.network(
                                            user!.avatarUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Container(
                                                    color: Colors.grey[700],
                                                    child: Center(
                                                      child: Text(
                                                        (user
                                                                    .fullName
                                                                    .isNotEmpty ==
                                                                true)
                                                            ? user.fullName[0]
                                                                  .toUpperCase()
                                                            : '?',
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                          fontSize: 24,
                                                          fontWeight:
                                                              FontWeight.bold,
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
                                                (user?.fullName.isNotEmpty ==
                                                        true)
                                                    ? user!.fullName[0]
                                                          .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                );
                              },
                            ),
                          ),

                        const SizedBox(height: 32),

                        // Thời gian cuộc gọi
                        if (isJoined && _callDuration.inSeconds > 0)
                          Text(
                            _formatDuration(_callDuration),
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.7),
                              fontSize: 16,
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
                        // Video toggle
                        if (widget.groupCall.isVideoCall)
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
                          onPressed: widget.isIncoming && !isJoined
                              ? _declineCall
                              : _leaveCall,
                        ),
                      ],
                    ),
                  ),

                  // Nút Answer/Reject nếu là cuộc gọi đến và chưa tham gia
                  if (widget.isIncoming && !isJoined)
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

  List<Widget> _buildRemoteVideoViews() {
    // Note: AgoraCallService hiện tại chỉ hỗ trợ 1 remote user
    // Để hỗ trợ nhiều users, cần mở rộng AgoraCallService
    if (_agoraService.remoteUid == null) return [];

    return [
      Positioned.fill(
        child: AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _agoraService.engine!,
            canvas: VideoCanvas(uid: _agoraService.remoteUid),
            connection: RtcConnection(channelId: _channelName ?? ''),
          ),
        ),
      ),
    ];
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
          color: showDisabled ? Colors.white.withOpacity(0.6) : Colors.white,
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
        onPressed: _joinCall,
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
        onPressed: _declineCall,
      ),
    );
  }
}

