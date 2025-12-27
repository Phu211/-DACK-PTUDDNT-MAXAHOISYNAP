import 'dart:async';
import 'dart:convert';
// import 'dart:io'; // Unused import

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_constants.dart';

/// Agora Call Service for voice and video calls (1-1).
/// NOTE: You need to provide Agora App ID and Token endpoint.
class AgoraCallService {
  AgoraCallService._();
  static final AgoraCallService instance = AgoraCallService._();

  RtcEngine? _engine;
  bool _isVideo = false;
  String? _fromUserId;
  String? _toUserId;
  int? _localUid;
  int? _remoteUid;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = true;

  // App ID từ Agora Console
  // Lấy tại: https://console.agora.io/
  // TODO: Thay YOUR_AGORA_APP_ID bằng Agora App ID thực tế của bạn
  static const String appId = 'YOUR_AGORA_APP_ID';

  // Token endpoint - tự động chuyển giữa dev và production
  // Development: dùng localhost khi debug
  // Production: dùng URL server thực khi release
  String get tokenEndpoint {
    // Dùng luôn endpoint deploy để thiết bị thật không phải truy cập localhost.
    // Nếu cần tự host, chỉnh lại thành IP LAN của máy dev (ví dụ: http://192.168.x.x:3000/agora/token).
    return '${AppConstants.backendBaseUrl}/agora/token';
  }

  final _connectionStateCtrl = StreamController<String>.broadcast();
  final _callStateCtrl = StreamController<String>.broadcast();
  final _incomingCallCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<String> get connectionStateStream => _connectionStateCtrl.stream;
  Stream<String> get callStateStream => _callStateCtrl.stream;
  Stream<Map<String, dynamic>> get incomingCallStream =>
      _incomingCallCtrl.stream;

  bool get hasActiveCall => _engine != null && _localUid != null;
  bool get isVideoCall => _isVideo;
  int? get localUid => _localUid;
  int? get remoteUid => _remoteUid;
  String? get fromUserId => _fromUserId;
  String? get toUserId => _toUserId;
  bool get isMuted => _isMuted;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isSpeakerOn => _isSpeakerOn;
  RtcEngine? get engine => _engine;

  // Export các hàm helper để dùng từ bên ngoài
  String generateChannelName(String userId1, String userId2) {
    return _generateChannelName(userId1, userId2);
  }

  int generateUid(String userId) {
    return _generateUid(userId);
  }

  Future<void> init() async {
    // ✅ Tránh init nhiều lần (AuthProvider/MainScreen có thể gọi lặp),
    // nếu tạo engine mới sẽ làm rớt kết nối/treo "Đang kết nối...".
    if (_engine != null) {
      debugPrint('Agora engine already initialized');
      return;
    }
    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // ✅ Default audio route: ưu tiên loa ngoài khi bật speaker.
      // Voice-call thường dễ bị route vào earpiece (nghe rất nhỏ).
      try {
        await _engine!.setDefaultAudioRouteToSpeakerphone(_isSpeakerOn);
      } catch (e) {
        debugPrint('Agora: setDefaultAudioRouteToSpeakerphone ignored: $e');
      }

      // Đăng ký event handlers
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            debugPrint('Joined channel successfully');
            _callStateCtrl.add('Đã kết nối');
            _connectionStateCtrl.add('connected');
            // Defensive: re-apply routing after join.
            unawaited(_applyAudioRoute());
          },
          onLeaveChannel: (RtcConnection connection, RtcStats stats) {
            debugPrint('Left channel');
            _callStateCtrl.add('Đã kết thúc');
            _connectionStateCtrl.add('disconnected');
            _localUid = null;
            _remoteUid = null;
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            debugPrint('Remote user joined: $remoteUid');
            _remoteUid = remoteUid;
            _callStateCtrl.add('Đã kết nối');
          },
          onUserOffline:
              (
                RtcConnection connection,
                int remoteUid,
                UserOfflineReasonType reason,
              ) {
                debugPrint('Remote user offline: $remoteUid');
                _remoteUid = null;
                _callStateCtrl.add('Người dùng đã rời khỏi');
              },
          onError: (ErrorCodeType err, String msg) {
            debugPrint('Agora error: $err - $msg');
            _callStateCtrl.add('Lỗi: $msg');
            _connectionStateCtrl.add('error');
          },
          onConnectionStateChanged:
              (
                RtcConnection connection,
                ConnectionStateType state,
                ConnectionChangedReasonType reason,
              ) {
                debugPrint('Connection state changed: $state, reason: $reason');
                switch (state) {
                  case ConnectionStateType.connectionStateConnecting:
                    _connectionStateCtrl.add('connecting');
                    _callStateCtrl.add('Đang kết nối...');
                    break;
                  case ConnectionStateType.connectionStateConnected:
                    _connectionStateCtrl.add('connected');
                    // Defensive: re-apply routing when connected.
                    unawaited(_applyAudioRoute());
                    break;
                  case ConnectionStateType.connectionStateDisconnected:
                    _connectionStateCtrl.add('disconnected');
                    _callStateCtrl.add('Đã ngắt kết nối');
                    break;
                  case ConnectionStateType.connectionStateReconnecting:
                    _connectionStateCtrl.add('reconnecting');
                    _callStateCtrl.add('Đang kết nối lại...');
                    break;
                  case ConnectionStateType.connectionStateFailed:
                    _connectionStateCtrl.add('failed');
                    _callStateCtrl.add('Kết nối thất bại');
                    // Nếu thất bại (ví dụ: token không hợp lệ), đảm bảo rời khỏi channel
                    try {
                      _engine?.leaveChannel();
                    } catch (e) {
                      debugPrint('Error leaving channel on failed state: $e');
                    }
                    _localUid = null;
                    _remoteUid = null;
                    break;
                }
              },
        ),
      );

      debugPrint('Agora engine initialized');
    } catch (e) {
      debugPrint('Error initializing Agora: $e');
    }
  }

  Future<void> _applyAudioRoute() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.setDefaultAudioRouteToSpeakerphone(_isSpeakerOn);
    } catch (_) {}
    try {
      await engine.setEnableSpeakerphone(_isSpeakerOn);
    } catch (_) {}
  }

  Future<String?> fetchToken(String userId, String channelName) async {
    final uri = Uri.parse(
      '$tokenEndpoint?userId=$userId&channelName=$channelName',
    );

    // ✅ Giảm timeout và retry để tăng tốc kết nối
    // Timeout: 30s -> 10s, Retry: 3 -> 2
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint(
          'Fetching Agora token (attempt $attempt/$maxAttempts) from: $uri',
        );

        final resp = await http
            .get(uri)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException('Token request timeout'),
            );

        debugPrint('Token response status: ${resp.statusCode}');
        debugPrint('Token response body: ${resp.body}');

        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final token = data['token'] as String?;
          if (token != null && token.isNotEmpty) {
            debugPrint(
              'Agora token fetched successfully (length: ${token.length})',
            );
            return token;
          }
          debugPrint('Token is null or empty in response');
        } else {
          debugPrint('Token fetch failed: ${resp.statusCode} - ${resp.body}');
        }
      } catch (e) {
        debugPrint('Error fetching Agora token (attempt $attempt): $e');
      }

      if (attempt < maxAttempts) {
        // backoff: 500ms (giảm từ 800ms để tăng tốc)
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return null;
  }

  Future<bool> ensurePermissions(bool isVideo) async {
    if (kIsWeb) {
      // Web tự động xử lý permissions
      return true;
    }

    try {
      final permissions = <Permission>[
        Permission.microphone,
        if (isVideo) Permission.camera,
      ];

      final statuses = await permissions.request();
      final allGranted = statuses.values.every((status) => status.isGranted);

      if (!allGranted) {
        _callStateCtrl.add('Chưa được cấp quyền mic/camera');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return false;
    }
  }

  Future<bool> call({
    required String fromUserId,
    required String toUserId,
    bool isVideo = false,
  }) async {
    try {
      debugPrint(
        'Starting Agora call from $fromUserId to $toUserId (video: $isVideo)',
      );

      // Kiểm tra permissions
      final hasPermissions = await ensurePermissions(isVideo);
      if (!hasPermissions) {
        return false;
      }

      // Nếu đang ở trong 1 channel cũ thì rời ra trước khi gọi mới
      if (_localUid != null) {
        debugPrint(
          'Already in a call, leaving old channel before starting new',
        );
        try {
          await _engine?.leaveChannel();
        } catch (e) {
          debugPrint('Error leaving previous channel: $e');
        }
        _localUid = null;
        _remoteUid = null;
      }

      // Khởi tạo engine nếu chưa có
      if (_engine == null) {
        await init();
      }

      if (_engine == null) {
        _callStateCtrl.add('Không thể khởi tạo Agora engine');
        return false;
      }

      _isVideo = isVideo;
      _fromUserId = fromUserId;
      _toUserId = toUserId;

      // Tạo channel name từ userIds (đảm bảo thứ tự nhất quán)
      final channelName = _generateChannelName(fromUserId, toUserId);

      // Generate UID để log (dùng lại sau khi join)
      final uid = _generateUid(fromUserId);

      // 🔍 Log để debug - so sánh với server
      debugPrint(
        '🔍 Client: Generate token request { userId: $fromUserId, uid: $uid, channelName: $channelName }',
      );

      // Lấy token
      final token = await fetchToken(fromUserId, channelName);
      if (token == null) {
        _callStateCtrl.add('Không lấy được token từ server');
        return false;
      }

      // Enable video nếu là video call
      if (isVideo) {
        await _engine!.enableVideo();
        await _engine!.startPreview();
      } else {
        await _engine!.disableVideo();
      }

      // Enable audio
      await _engine!.enableAudio();

      // Set speaker mode (bọc riêng để nếu lỗi cũng không làm fail cả cuộc gọi)
      try {
        await _engine!.setDefaultAudioRouteToSpeakerphone(_isSpeakerOn);
        await _engine!.setEnableSpeakerphone(_isSpeakerOn);
      } catch (e) {
        debugPrint('Agora: Error setEnableSpeakerphone (ignored): $e');
      }

      // Join channel
      _callStateCtrl.add('Đang khởi tạo cuộc gọi...');
      // uid đã được generate ở trên

      // Validate token before joining
      if (token.isEmpty) {
        debugPrint('ERROR: Token is empty, cannot join channel');
        _callStateCtrl.add('Token không hợp lệ');
        return false;
      }

      debugPrint(
        'Joining channel with uid=$uid, channel=$channelName, token length=${token.length}',
      );

      try {
        // Ensure local tracks are in a known-good state for a new call.
        _isMuted = false;
        _isSpeakerOn = true;
        _isVideoEnabled = true;

        await _engine!.joinChannel(
          token: token,
          channelId: channelName,
          uid: uid,
          options: ChannelMediaOptions(
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            channelProfile: ChannelProfileType.channelProfileCommunication,
            // Explicitly publish/subscribe tracks. Defaults can differ by SDK
            // version and may result in "connected but can't hear" symptoms.
            publishMicrophoneTrack: true,
            publishCameraTrack: isVideo,
            autoSubscribeAudio: true,
            autoSubscribeVideo: isVideo,
          ),
        );
        _localUid = uid;

        // Start preview sau khi join channel thành công (cho video call)
        if (isVideo) {
          await _engine!.startPreview();
        }

        // Re-apply speaker/mute after join (defensive).
        try {
          await _engine!.setDefaultAudioRouteToSpeakerphone(_isSpeakerOn);
        } catch (_) {}
        try {
          await _engine!.setEnableSpeakerphone(_isSpeakerOn);
        } catch (_) {}
        try {
          await _engine!.muteLocalAudioStream(_isMuted);
        } catch (_) {}

        debugPrint(
          'Call initiated successfully (uid=$uid, channel=$channelName)',
        );
      } on AgoraRtcException catch (e) {
        // Nếu đã join channel rồi thì không coi là lỗi "kết nối thất bại"
        if (e.code == -17) {
          debugPrint(
            'Agora joinChannel returned -17 (already joined); treating as success',
          );
          _callStateCtrl.add('Đang trong cuộc gọi');
          return true;
        }
        final msg = _getErrorString(e.code);
        debugPrint(
          'Agora joinChannel failed: code=${e.code}, message=$msg, reason=${e.message}',
        );
        debugPrint(
          'Token used: ${token.substring(0, token.length > 20 ? 20 : token.length)}...',
        );
        _callStateCtrl.add('Kết nối thất bại: $msg');
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint('Error in call method: $e');
      debugPrint('Stack trace: $stackTrace');
      _callStateCtrl.add('Lỗi khi gọi: $e');
      return false;
    }
  }

  Future<bool> joinChannel({
    required String userId,
    required String channelName,
    required String token,
    bool isVideo = false,
  }) async {
    try {
      // Kiểm tra permissions
      final hasPermissions = await ensurePermissions(isVideo);
      if (!hasPermissions) {
        return false;
      }

      // Khởi tạo engine nếu chưa có
      if (_engine == null) {
        await init();
      }

      if (_engine == null) {
        _callStateCtrl.add('Không thể khởi tạo Agora engine');
        return false;
      }

      _isVideo = isVideo;

      // Enable video/audio
      if (isVideo) {
        await _engine!.enableVideo();
        await _engine!.startPreview();
      } else {
        await _engine!.disableVideo();
      }
      await _engine!.enableAudio();
      try {
        await _engine!.setDefaultAudioRouteToSpeakerphone(_isSpeakerOn);
        await _engine!.setEnableSpeakerphone(_isSpeakerOn);
      } catch (e) {
        debugPrint('Agora: Error setEnableSpeakerphone (ignored): $e');
      }

      // Join channel
      _callStateCtrl.add('Đang kết nối...');
      final uid = _generateUid(userId);
      // Ensure local tracks are in a known-good state when answering.
      _isMuted = false;
      _isVideoEnabled = true;
      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          publishCameraTrack: isVideo,
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideo,
        ),
      );

      _localUid = uid;

      // Start preview sau khi join channel thành công (cho video call)
      if (isVideo) {
        await _engine!.startPreview();
      }

      // Re-apply speaker/mute after join (defensive).
      try {
        await _engine!.setDefaultAudioRouteToSpeakerphone(_isSpeakerOn);
      } catch (_) {}
      try {
        await _engine!.setEnableSpeakerphone(_isSpeakerOn);
      } catch (_) {}
      try {
        await _engine!.muteLocalAudioStream(_isMuted);
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('Error joining channel: $e');
      _callStateCtrl.add('Lỗi khi kết nối: $e');
      return false;
    }
  }

  Future<void> answer() async {
    // Với Agora, không có khái niệm "answer" như Stringee
    // Người nhận chỉ cần join vào channel
    _callStateCtrl.add('Đang kết nối...');
  }

  Future<void> hangup() async {
    try {
      if (_engine != null) {
        await _engine!.leaveChannel();
        if (_isVideo) {
          await _engine!.stopPreview();
        }
      }
      _callStateCtrl.add('Đã kết thúc');
      _localUid = null;
      _remoteUid = null;
    } catch (e) {
      debugPrint('Error hanging up: $e');
    }
  }

  Future<void> reject() async {
    await hangup();
    _callStateCtrl.add('Đã từ chối');
  }

  Future<void> toggleMute() async {
    try {
      if (_engine != null) {
        // Đảo trạng thái mute trước rồi apply vào engine
        _isMuted = !_isMuted;
        await _engine!.muteLocalAudioStream(_isMuted);
      }
    } catch (e) {
      debugPrint('Error toggling mute: $e');
    }
  }

  Future<void> toggleVideo() async {
    try {
      if (_engine != null && _isVideo) {
        // Đảo trạng thái video trước rồi apply vào engine
        _isVideoEnabled = !_isVideoEnabled;
        await _engine!.muteLocalVideoStream(!_isVideoEnabled);
      }
    } catch (e) {
      debugPrint('Error toggling video: $e');
    }
  }

  Future<void> toggleSpeaker() async {
    try {
      if (_engine != null) {
        _isSpeakerOn = !_isSpeakerOn;
        try {
          await _engine!.setDefaultAudioRouteToSpeakerphone(_isSpeakerOn);
        } catch (_) {}
        await _engine!.setEnableSpeakerphone(_isSpeakerOn);
      }
    } catch (e) {
      debugPrint('Error toggling speaker: $e');
    }
  }

  // Tạo channel name từ 2 userIds (đảm bảo thứ tự nhất quán)
  String _generateChannelName(String userId1, String userId2) {
    final sorted = [userId1, userId2]..sort();
    return 'call_${sorted[0]}_${sorted[1]}';
  }

  // Tạo UID từ userId (Agora yêu cầu UID là số)
  // Phải match với thuật toán hash trong server (server.js)
  int _generateUid(String userId) {
    // Nếu userId là số, dùng trực tiếp (KHÔNG mod, giống server)
    if (RegExp(r'^\d+$').hasMatch(userId)) {
      return int.parse(userId);
    }

    // Hash string userId thành số (giống hệt logic trong server.js với Int32)
    int hash = 0;
    for (int i = 0; i < userId.length; i++) {
      hash = ((hash << 5) - hash) + userId.codeUnitAt(i);

      // JS: a & a  ==> ép về signed 32-bit Int32
      // Dart: cần mask 0xFFFFFFFF để mô phỏng Int32
      hash &= 0xFFFFFFFF;
    }

    // Chuyển về signed 32-bit giống như JS Int32
    if ((hash & 0x80000000) != 0) {
      hash = hash - 0x100000000;
    }

    return hash.abs() % 2147483647; // Max int32
  }

  String _getErrorString(int errorCode) {
    switch (errorCode) {
      case -1:
        return 'Lỗi không xác định';
      case -2:
        return 'Tham số không hợp lệ';
      case -3:
        return 'SDK chưa được khởi tạo';
      case -4:
        return 'Không có quyền';
      case -5:
        return 'Đã bị từ chối';
      case -6:
        return 'Kích thước quá lớn';
      case -7:
        return 'Không tìm thấy';
      case -8:
        return 'Token không hợp lệ';
      case -9:
        return 'Token đã hết hạn';
      case -10:
        return 'Đã tồn tại';
      case -11:
        return 'Quá nhiều yêu cầu';
      case -17:
        return 'Đã join channel';
      case -101:
        return 'App ID không hợp lệ';
      default:
        return 'Lỗi: $errorCode';
    }
  }

  void dispose() {
    try {
      // Leave channel nếu đang trong channel
      try {
        _engine?.leaveChannel();
      } catch (e) {
        debugPrint('AgoraCallService: Error leaving channel during dispose: $e');
      }
      
      // Release engine
      try {
        _engine?.release();
      } catch (e) {
        debugPrint('AgoraCallService: Error releasing engine during dispose: $e');
      }
      
      _engine = null;
      
      // Close streams nếu chưa đóng
      try {
        if (!_connectionStateCtrl.isClosed) {
          _connectionStateCtrl.close();
        }
      } catch (e) {
        debugPrint('AgoraCallService: Error closing connectionStateCtrl: $e');
      }
      
      try {
        if (!_callStateCtrl.isClosed) {
          _callStateCtrl.close();
        }
      } catch (e) {
        debugPrint('AgoraCallService: Error closing callStateCtrl: $e');
      }
      
      try {
        if (!_incomingCallCtrl.isClosed) {
          _incomingCallCtrl.close();
        }
      } catch (e) {
        debugPrint('AgoraCallService: Error closing incomingCallCtrl: $e');
      }
    } catch (e) {
      debugPrint('AgoraCallService: Error in dispose: $e');
    }
  }
}
