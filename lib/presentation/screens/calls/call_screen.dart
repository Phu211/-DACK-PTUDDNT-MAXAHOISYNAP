import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../data/services/call_notification_service.dart';
import '../../../data/services/agora_call_service.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/message_service.dart';
import '../../../data/models/message_model.dart';

class CallScreen extends StatefulWidget {
  final UserModel? otherUser; // User đang gọi hoặc nhận cuộc gọi
  final bool isIncoming; // true nếu là cuộc gọi đến, false nếu là cuộc gọi đi
  final bool isVideoCall; // true nếu là video call, false nếu là voice call
  final String? callId; // Firestore callNotifications doc id
  final String? channelName; // Agora channel name (call_xxx_xxx)

  const CallScreen({
    super.key,
    this.otherUser,
    this.isIncoming = false,
    this.isVideoCall = false,
    this.callId,
    this.channelName,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final AgoraCallService _callService = AgoraCallService.instance;
  final UserService _userService = UserService();
  final MessageService _messageService = MessageService();
  final CallNotificationService _callNotificationService =
      CallNotificationService.instance;
  final AudioPlayer _ringPlayer = AudioPlayer();

  UserModel? _otherUser;
  String _callStatus = 'Đang gọi...';
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = true; // Mặc định bật video khi là video call

  // ✅ Tách trạng thái UI khỏi _callStatus (string) để tránh render sai/chồng UI.
  // Khi là cuộc gọi đến: chỉ show nút Nghe/Từ chối cho đến khi user bấm Nghe.
  bool _hasAnsweredIncoming = false;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  StreamSubscription<String>? _callStateSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _callDocSubscription;
  Timer? _ringTimeoutTimer;
  Timer? _callTimer;
  Duration _callDuration = Duration.zero;
  bool _hasLoggedHistory = false;
  String? _callId;
  String? _channelName;
  bool _isConnectingAgora = false;

  bool _isRinging = false;
  Uint8List? _ringWavBytes;
  bool _isEndingCall = false; // Flag để tránh gọi _endCall() nhiều lần

  @override
  void initState() {
    super.initState();
    _otherUser = widget.otherUser;
    _callId = widget.callId;
    _channelName = widget.channelName;
    _loadOtherUser();
    _listenToCallState();

    // ✅ Pre-initialize Agora engine để giảm delay khi nhấn "Nghe"
    // Đặc biệt quan trọng cho incoming calls
    unawaited(_callService.init());

    if (!widget.isIncoming) {
      // ✅ Cuộc gọi đi: chỉ "đổ chuông" trước, CHƯA join Agora
      _startOutgoingRinging();
    } else {
      // ✅ Cuộc gọi đến: chỉ hiện UI nhận/reject, CHƯA join Agora
      // 🔔 chuông cuộc gọi đến: phát từ CallNotificationService (toàn app)
      if (_callId != null) {
        unawaited(
          _callNotificationService.startIncomingRingtone(callId: _callId!),
        );
      }
      _listenToCallDoc();
    }
  }

  bool get _showIncomingActions => widget.isIncoming && !_hasAnsweredIncoming;

  Uint8List _buildRingWavBytes({int sampleRate = 44100, double seconds = 2.0}) {
    // Pattern: 0.6s tone + 0.4s silence + 0.6s tone + 0.4s silence (2s)
    final totalSamples = (sampleRate * seconds).toInt();
    final pcm = Int16List(totalSamples);

    const double f1 = 440.0;
    const double f2 = 480.0;
    const double amp = 0.22;

    bool isToneAt(double t) {
      return (t >= 0.0 && t < 0.6) || (t >= 1.0 && t < 1.6);
    }

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      if (!isToneAt(t)) {
        pcm[i] = 0;
        continue;
      }
      final s =
          (math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)) *
          0.5 *
          amp;
      pcm[i] = (s * 32767).clamp(-32768, 32767).toInt();
    }

    final byteData = ByteData(44 + pcm.lengthInBytes);
    byteData.setUint32(0, 0x46464952, Endian.little); // RIFF
    byteData.setUint32(4, 36 + pcm.lengthInBytes, Endian.little);
    byteData.setUint32(8, 0x45564157, Endian.little); // WAVE
    byteData.setUint32(12, 0x20746D66, Endian.little); // fmt
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, 1, Endian.little); // mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little); // byteRate
    byteData.setUint16(32, 2, Endian.little); // blockAlign
    byteData.setUint16(34, 16, Endian.little); // bits
    byteData.setUint32(36, 0x61746164, Endian.little); // data
    byteData.setUint32(40, pcm.lengthInBytes, Endian.little);

    final pcmBytes = pcm.buffer.asUint8List();
    for (int i = 0; i < pcmBytes.length; i++) {
      byteData.setUint8(44 + i, pcmBytes[i]);
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _startRingTone() async {
    if (_isRinging) return;
    _isRinging = true;
    _ringWavBytes ??= _buildRingWavBytes();
    try {
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.play(BytesSource(_ringWavBytes!), volume: 1.0);
    } catch (e) {
      // ignore: avoid_print
      print('Ring tone play error: $e');
    }
  }

  Future<void> _stopRingTone() async {
    if (!_isRinging) return;
    _isRinging = false;
    try {
      await _ringPlayer.stop();
    } catch (_) {}
  }

  Future<void> _startOutgoingRinging() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null || _otherUser == null) return;

    setState(() {
      _callStatus = 'Đang gọi...';
    });

    // Tạo call invitation trên Firestore (B sẽ thấy UI nhận cuộc gọi)
    final created = await _callNotificationService.createCallInvitation(
      recipientUserId: _otherUser!.id,
      callerId: currentUser.id,
      isVideo: widget.isVideoCall,
    );

    if (!mounted) return;
    if (created == null) {
      setState(() => _callStatus = 'Gọi thất bại');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _endCall();
      });
      return;
    }

    _callId = created['callId'];
    _channelName = created['channelName'];
    await _startRingTone(); // 🔔 ringback cho bên gọi khi chờ bắt máy

    _listenToCallDoc();

    // Timeout đổ chuông: 30s không nhận -> missed
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(const Duration(seconds: 30), () async {
      if (!mounted) return;
      // Nếu chưa kết nối (chưa accepted) thì coi là missed
      if (_callStatus == 'Đang gọi...' && _callId != null) {
        await _stopRingTone();
        try {
          await _callNotificationService.updateCallStatus(_callId!, {
            'status': 'missed',
            'missedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
        await _logCallHistory('missed');
        _endCall();
      }
    });
  }

  Future<void> _loadOtherUser() async {
    if (_otherUser != null) return;

    // Nếu không có otherUser, cố gắng lấy từ call service
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser != null) {
      // Lấy userId từ call service
      final otherUserId = widget.isIncoming
          ? _callService.fromUserId
          : _callService.toUserId;
      if (otherUserId != null) {
        final user = await _userService.getUserById(otherUserId);
        if (mounted) {
          setState(() {
            _otherUser = user;
          });
        }
      }
    }
  }

  void _listenToCallState() {
    _callStateSubscription?.cancel();
    _callStateSubscription = _callService.callStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        if (state.contains('Đang kết nối') ||
            state.contains('Media: connected') ||
            state.contains('Đã kết nối')) {
          _callStatus = 'Đã kết nối';
          // ✅ đã kết nối thì tắt chuông
          unawaited(_stopRingTone());
          _startCallTimer();
        } else if (state.contains('Đã kết thúc') ||
            state.contains('Đã từ chối') ||
            state.contains('ended') ||
            state.contains('busy') ||
            state.contains('Người dùng đã rời khỏi') ||
            state.contains('Đã ngắt kết nối')) {
          // Đợi một chút trước khi đóng để user có thể thấy thông báo
          _callStatus = state.contains('busy')
              ? 'Máy bận'
              : (state.contains('Đã kết thúc') || state.contains('Người dùng đã rời khỏi') || state.contains('Đã ngắt kết nối')
                  ? 'Đã kết thúc'
                  : state);

          unawaited(_stopRingTone());

          // Ghi lịch sử nếu chưa ghi (kết thúc do remote hoặc bận)
          _logCallHistory(
            state.contains('busy')
                ? 'failed'
                : (_callDuration.inSeconds > 0 ? 'ended' : 'cancelled'),
          );
          
          // Tự động đóng màn hình sau 1 giây khi một bên tắt cuộc gọi
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              _endCall();
            }
          });
        } else if (state.contains('failed') || state.contains('Lỗi')) {
          _callStatus = 'Kết nối thất bại';
          unawaited(_stopRingTone());
          _logCallHistory('failed');
        } else if (state.contains('Đang gọi') ||
            state.contains('Đang đổ chuông') ||
            state.contains('ringing') ||
            state.contains('calling')) {
          _callStatus = 'Đang gọi...';
        } else {
          _callStatus = state;
        }
      });
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

  Future<void> _logCallHistory(String reason) async {
    if (_hasLoggedHistory) return;
    // ✅ khóa ngay lập tức để tránh spam khi callback bắn liên tục
    _hasLoggedHistory = true;
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null || _otherUser == null) return;

    final isVideo = widget.isVideoCall;
    final isIncoming = widget.isIncoming;

    String description;
    if (_callDuration.inSeconds > 0 && reason == 'ended') {
      final dur = _formatDuration(_callDuration);
      if (isIncoming) {
        description =
            'Bạn đã trả lời cuộc gọi ${isVideo ? 'video' : 'thoại'} (${dur})';
      } else {
        description = 'Bạn đã gọi ${isVideo ? 'video' : 'thoại'} (${dur})';
      }
    } else {
      // Các trường hợp chưa kết nối được / bị hủy / từ chối
      if (reason == 'rejected') {
        description = 'Bạn đã từ chối cuộc gọi ${isVideo ? 'video' : 'thoại'}';
      } else if (reason == 'missed') {
        description = 'Bạn đã bỏ lỡ cuộc gọi ${isVideo ? 'video' : 'thoại'}';
      } else if (reason == 'failed') {
        description =
            'Cuộc gọi ${isVideo ? 'video' : 'thoại'} không thành công';
      } else {
        // cancelled hoặc kết thúc mà chưa kết nối
        description = 'Bạn đã hủy cuộc gọi ${isVideo ? 'video' : 'thoại'}';
      }
    }

    final message = MessageModel(
      id: '',
      senderId: currentUser.id,
      receiverId: _otherUser!.id,
      content: description,
      createdAt: DateTime.now(),
    );

    try {
      await _messageService.sendMessage(message);
    } catch (e) {
      // Không chặn UI nếu ghi lịch sử thất bại
      // ignore: avoid_print
      print('Error logging call history: $e');
    }
  }

  Future<void> _answerCall() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    if (_isConnectingAgora) return;
    _isConnectingAgora = true;
    _safeSetState(() {
      // ✅ Ngay khi bấm "Nhận", ẩn UI Nghe/Từ chối để không bị chồng UI.
      _hasAnsweredIncoming = true;
      _callStatus = 'Đang kết nối...';
    });
    await _stopRingTone();
    await _callNotificationService.stopIncomingRingtone();
    if (!mounted) {
      _isConnectingAgora = false;
      return;
    }

    // Chỉ join Agora khi user bấm "Nhận"
    if (_callId == null || _channelName == null || _otherUser == null) {
      _safeSetState(() {
        _callStatus = 'Lỗi: Không có thông tin cuộc gọi';
      });
      _isConnectingAgora = false;
      return;
    }

    // ✅ Đảm bảo engine đã được init (fallback nếu pre-init chưa xong)
    await _callService.init();

    // ✅ Parallelize: Update Firestore và fetch token cùng lúc để tăng tốc
    // (Token fetch không phụ thuộc vào Firestore update)
    final results = await Future.wait([
      // Update Firestore status
      _callNotificationService.updateCallStatus(_callId!, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      }).catchError((e) {
        print('Failed to update call status accepted: $e');
        return null;
      }),
      // Fetch token
      _callService.fetchToken(currentUser.id, _channelName!),
    ]);

    if (!mounted) {
      _isConnectingAgora = false;
      return;
    }

    final token = results[1] as String?;
    if (!mounted) {
      _isConnectingAgora = false;
      return;
    }
    if (token == null) {
      _safeSetState(() {
        _callStatus = 'Không thể lấy token';
      });
      _isConnectingAgora = false;
      return;
    }

    // Join channel
    final success = await _callService.joinChannel(
      userId: currentUser.id,
      channelName: _channelName!,
      token: token,
      isVideo: widget.isVideoCall,
    );
    if (!mounted) {
      _isConnectingAgora = false;
      return;
    }

    if (success) {
      _safeSetState(() {
        _callStatus = 'Đã kết nối';
      });
      _startCallTimer();
    } else {
      _safeSetState(() {
        _callStatus = 'Kết nối thất bại';
      });
    }
    _isConnectingAgora = false;
  }

  Future<void> _rejectCall() async {
    await _stopRingTone();
    await _callNotificationService.stopIncomingRingtone();
    if (_callId != null) {
      try {
        await _callNotificationService.updateCallStatus(_callId!, {
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
    await _callService.reject(); // đảm bảo rời channel nếu lỡ join
    await _logCallHistory('rejected');
    _endCall();
  }

  Future<void> _hangupCall() async {
    await _stopRingTone();
    await _callNotificationService.stopIncomingRingtone();
    // Nếu chưa kết nối (đang đổ chuông) thì coi là cancel
    final wasConnected = _callStatus == 'Đã kết nối';
    
    // ✅ Cập nhật status TRƯỚC khi rời channel để bên kia nhận được thông báo ngay lập tức
    if (!wasConnected && _callId != null) {
      try {
        await _callNotificationService.updateCallStatus(_callId!, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    } else if (wasConnected && _callId != null) {
      try {
        await _callNotificationService.updateCallStatus(_callId!, {
          'status': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    // Rời channel sau khi đã update status
    await _callService.hangup();
    await _logCallHistory(wasConnected ? 'ended' : 'cancelled');
    _endCall();
  }

  void _endCall() {
    // Tránh gọi nhiều lần
    if (_isEndingCall) return;
    _isEndingCall = true;
    
    _callTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _toggleMute() async {
    await _callService.toggleMute();
    _safeSetState(() {
      _isMuted = _callService.isMuted;
    });
  }

  Future<void> _toggleSpeaker() async {
    await _callService.toggleSpeaker();
    _safeSetState(() {
      _isSpeakerOn = _callService.isSpeakerOn;
    });
  }

  Future<void> _toggleVideo() async {
    if (widget.isVideoCall) {
      await _callService.toggleVideo();
      _safeSetState(() {
        _isVideoEnabled = _callService.isVideoEnabled;
      });
    }
  }

  @override
  void dispose() {
    _callStateSubscription?.cancel();
    _callDocSubscription?.cancel();
    _ringTimeoutTimer?.cancel();
    _callTimer?.cancel();
    unawaited(_ringPlayer.stop());
    unawaited(_ringPlayer.dispose());
    unawaited(_callNotificationService.stopIncomingRingtone());
    super.dispose();
  }

  void _listenToCallDoc() {
    final callId = _callId;
    if (callId == null || callId.isEmpty) return;

    _callDocSubscription?.cancel();
    _callDocSubscription = FirebaseFirestore.instance
        .collection('callNotifications')
        .doc(callId)
        .snapshots()
        .listen((snap) async {
          if (!mounted) return;
          if (!snap.exists) return;

          final data = snap.data();
          if (data == null) return;

          final status = (data['status'] as String?) ?? 'ringing';
          final channelName = (data['channelName'] as String?) ?? _channelName;
          if (channelName != null && channelName.isNotEmpty) {
            _channelName ??= channelName;
          }

          // Nếu bên kia hủy / bỏ lỡ / kết thúc thì đóng màn hình ngay lập tức
          if (status == 'cancelled' ||
              status == 'missed' ||
              status == 'ended' ||
              status == 'rejected') {
            await _stopRingTone();
            await _callNotificationService.stopIncomingRingtone();
            if (status == 'missed') {
              await _logCallHistory('missed');
            } else if (status == 'cancelled') {
              await _logCallHistory('cancelled');
            } else if (status == 'ended') {
              await _logCallHistory('ended');
            } else if (status == 'rejected') {
              await _logCallHistory('rejected');
            }
            // Đóng màn hình ngay lập tức khi bên kia tắt cuộc gọi
            _endCall();
            return;
          }

          // Nếu mình là người gọi: chỉ join Agora khi B bấm "accepted"
          if (!widget.isIncoming && status == 'accepted') {
            _ringTimeoutTimer?.cancel();
            await _stopRingTone();
            if (_isConnectingAgora) return;
            final authProvider = context.read<AuthProvider>();
            final currentUser = authProvider.currentUser;
            if (currentUser == null || _otherUser == null) return;
            _isConnectingAgora = true;
            
            // ✅ Đảm bảo engine đã được init
            await _callService.init();
            
            try {
              final success = await _callService.call(
                fromUserId: currentUser.id,
                toUserId: _otherUser!.id,
                isVideo: widget.isVideoCall,
              );
              if (!success && mounted) {
                setState(() => _callStatus = 'Gọi thất bại');
                await _logCallHistory('failed');
                _endCall();
              }
            } finally {
              _isConnectingAgora = false;
            }
          }

          // Nếu mình là người nhận và status bị rejected (do mình) thì ignore
          if (widget.isIncoming && status == 'rejected') {
            _endCall();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    // Màu nền cho incoming call (màu xanh như agora_call_screen)
    final backgroundColor = widget.isIncoming && _showIncomingActions
        ? const Color(0xFF4A6FA5)
        : Colors.white;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Container(
          decoration: widget.isIncoming && _showIncomingActions
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF5B7FA8).withOpacity(0.95),
                      const Color(0xFF4A6FA5),
                    ],
                  ),
                )
              : null,
          color: widget.isIncoming && _showIncomingActions ? null : Colors.white,
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
                        channelId: _callService.generateChannelName(
                          _callService.fromUserId ?? '',
                          _callService.toUserId ?? '',
                        ),
                      ),
                    ),
                  ),
                ),

              // Local video view (nếu là video call)
              // Lưu ý: Local preview luôn dùng uid: 0 (theo Agora docs)
              if (widget.isVideoCall && _callService.engine != null)
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
                      child: _isVideoEnabled
                          ? AgoraVideoView(
                              controller: VideoViewController(
                                rtcEngine: _callService.engine!,
                                canvas: const VideoCanvas(uid: 0),
                              ),
                            )
                          : Container(
                              color: Colors.black,
                              child: const Center(
                                child: Icon(
                                  Icons.videocam_off,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),

              // UI overlay
              Column(
                children: [
                  // Header với nút back và các nút điều khiển
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
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.person_add,
                                color: Colors.black,
                                size: 24,
                              ),
                              onPressed: () {
                                // TODO: Thêm người vào cuộc gọi
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.black,
                                size: 24,
                              ),
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // ✅ Fix "RenderFlex overflowed..." on smaller heights:
                        // Avatar will shrink to fit; name/status scale down.
                        final availableH = constraints.maxHeight;

                        final showAvatar =
                            !widget.isVideoCall ||
                            _callService.remoteUid == null;

                        final gapAvatarToName = availableH < 420 ? 16.0 : 32.0;
                        final gapNameToStatus = availableH < 420 ? 8.0 : 12.0;

                        // Rough reserved heights for name + status + gaps (+ small safety).
                        const nameLineH = 46.0;
                        const statusLineH = 26.0;
                        const safety = 12.0;
                        final reserved =
                            nameLineH +
                            statusLineH +
                            gapAvatarToName +
                            gapNameToStatus +
                            safety;

                        final avatarMax = 180.0;
                        final avatarMin = 110.0;
                        final avatarSize = (availableH - reserved)
                            .clamp(avatarMin, avatarMax)
                            .toDouble();

                        Widget buildAvatarFallback() {
                          return Container(
                            color: Colors.grey[700],
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  (_otherUser?.fullName.isNotEmpty == true)
                                      ? _otherUser!.fullName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 64,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        Widget buildAvatar() {
                          return SizedBox(
                            width: avatarSize,
                            height: avatarSize,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.black.withOpacity(0.3),
                                  width: 3,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: ClipOval(
                                  child: _otherUser?.avatarUrl != null
                                      ? Image.network(
                                          _otherUser!.avatarUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return buildAvatarFallback();
                                              },
                                        )
                                      : buildAvatarFallback(),
                                ),
                              ),
                            ),
                          );
                        }

                        Widget buildName() {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _otherUser?.fullName ?? 'Đang tải...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }

                        Widget buildStatus() {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _callStatus,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      _callStatus.contains('kết thúc') ||
                                          _callStatus.contains('thất bại') ||
                                          _callStatus.contains('lỗi')
                                      ? Colors.red[300]
                                      : Colors.black.withOpacity(0.7),
                                  fontSize: 18,
                                  fontWeight:
                                      _callStatus.contains('kết thúc') ||
                                          _callStatus.contains('thất bại')
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (showAvatar) buildAvatar(),
                            if (showAvatar) SizedBox(height: gapAvatarToName),
                            buildName(),
                            SizedBox(height: gapNameToStatus),
                            buildStatus(),

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
                        );
                      },
                    ),
                  ),

                  // ✅ Incoming (chưa trả lời): chỉ show nút Nghe/Từ chối.
                  // ✅ Sau khi trả lời: show control bar (mic/speaker/end).
                  if (_showIncomingActions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40, top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildAnswerButton(),
                          const SizedBox(width: 32),
                          _buildRejectButton(),
                        ],
                      ),
                    )
                  else
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

                          // Share screen (chỉ hiện khi là video call)
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
                          _buildEndCallButton(onPressed: _hangupCall),
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
