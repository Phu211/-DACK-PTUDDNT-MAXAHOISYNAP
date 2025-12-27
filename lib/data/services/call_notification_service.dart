import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'user_service.dart';
import 'push_gateway_service.dart';

/// Service để xử lý incoming call notifications và background calls
class CallNotificationService {
  CallNotificationService._();
  static final CallNotificationService instance = CallNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final UserService _userService = UserService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Function(String callerId, bool isVideo, String callId, String channelName)?
  _onIncomingCall;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _callNotificationsSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  // Tránh register listener nhiều lần khi init() bị gọi lặp
  bool _fcmHandlersRegistered = false;
  String? _currentUserId;

  // Tránh xử lý trùng callNotifications (do snapshot replay)
  final Set<String> _handledCallNotificationIds = <String>{};

  // Nếu listener Firestore bắn trước khi UI set callback, ta buffer lại
  final List<Map<String, dynamic>> _pendingIncomingCalls =
      <Map<String, dynamic>>[];

  // 🔔 Incoming ringtone (khi có cuộc gọi đến)
  bool _isIncomingRingtonePlaying = false;
  String? _activeIncomingCallId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _activeIncomingCallDocSub;

  String _generateChannelName(String userId1, String userId2) {
    final sorted = [userId1, userId2]..sort();
    return 'call_${sorted[0]}_${sorted[1]}';
  }

  /// Initialize notification service (chỉ trên mobile)
  Future<void> init(String userId) async {
    // Skip trên web
    if (kIsWeb) {
      debugPrint('CallNotificationService: Skipping init on web platform');
      return;
    }

    _currentUserId = userId;

    // ✅ Luôn lắng nghe Firestore để nhận cuộc gọi khi app đang mở.
    // Trên Windows/Desktop, firebase_messaging có thể không có implementation,
    // nhưng Firestore listener vẫn hoạt động để nhận cuộc gọi (khi app đang chạy).
    debugPrint(
      'CallNotificationService: Start Firestore listener for user=$userId',
    );
    _startFirestoreIncomingCallListener(userId);

    // Chỉ khởi tạo FCM trên Android/iOS.
    if (!(Platform.isAndroid || Platform.isIOS)) {
      debugPrint('CallNotificationService: Skip FCM init on this platform');
      return;
    }

    try {
      // Request permission for notifications
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint(
        'Notification permission status: ${settings.authorizationStatus}',
      );

      // Get FCM token and save to Firestore
      // Retry logic để đảm bảo token được lưu ngay cả khi có vấn đề về mạng
      String? token;
      int retryCount = 0;
      const maxRetries = 3;
      
      while (retryCount < maxRetries && (token == null || token.isEmpty)) {
        try {
          token = await _messaging.getToken();
          if (token != null && token.isNotEmpty) {
            await _saveFCMToken(userId, token);
            debugPrint(
              'FCM Token saved for user $userId: ${token.substring(0, 20)}...',
            );
            break;
          }
        } catch (e) {
          debugPrint('Error getting FCM token (attempt ${retryCount + 1}/$maxRetries): $e');
        }
        
        if (token == null || token.isEmpty) {
          retryCount++;
          if (retryCount < maxRetries) {
            // Đợi trước khi retry: 2s, 4s, 8s
            await Future.delayed(Duration(seconds: 2 * retryCount));
          }
        }
      }
      
      if (token == null || token.isEmpty) {
        debugPrint('WARNING: FCM token is null or empty for user: $userId after $maxRetries attempts');
        // Thử lấy lại token sau một khoảng thời gian dài hơn (30s)
        Future.delayed(const Duration(seconds: 30), () async {
          try {
            final retryToken = await _messaging.getToken();
            if (retryToken != null && retryToken.isNotEmpty) {
              await _saveFCMToken(userId, retryToken);
              debugPrint('FCM Token saved on delayed retry for user $userId');
            }
          } catch (e) {
            debugPrint('Error retrying FCM token: $e');
          }
        });
      }

      // Listen for token refresh
      _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((
        newToken,
      ) {
        final uid = _currentUserId;
        if (uid == null) return;
        _saveFCMToken(uid, newToken);
        debugPrint('FCM Token refreshed: $newToken');
      });

      // Handle foreground messages (when app is open)
      if (!_fcmHandlersRegistered) {
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        _fcmHandlersRegistered = true;
      }
    } catch (e) {
      debugPrint('Error initializing CallNotificationService: $e');
      // Không throw error để app vẫn chạy được
    }
  }

  /// Save FCM token to Firestore
  /// Retry logic để đảm bảo token được lưu ngay cả khi có vấn đề về mạng
  Future<void> _saveFCMToken(String userId, String token) async {
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
        // Sử dụng set với merge để đảm bảo token được lưu ngay cả khi document chưa tồn tại
        await _firestore.collection('users').doc(userId).set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('FCM token saved successfully for user: $userId');
        return; // Thành công, thoát khỏi vòng lặp
      } catch (e) {
        debugPrint('Error saving FCM token (attempt ${retryCount + 1}/$maxRetries): $e');
        retryCount++;
        
        if (retryCount < maxRetries) {
          // Thử lại với update nếu set thất bại
          try {
            await _firestore.collection('users').doc(userId).update({
              'fcmToken': token,
              'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
            });
            debugPrint('FCM token saved with update method for user: $userId');
            return; // Thành công với update
          } catch (e2) {
            debugPrint('Error saving FCM token with update method (attempt $retryCount): $e2');
            // Đợi trước khi retry: 1s, 2s, 3s
            if (retryCount < maxRetries) {
              await Future.delayed(Duration(seconds: retryCount));
            }
          }
        } else {
          debugPrint('Failed to save FCM token after $maxRetries attempts for user: $userId');
          // Lưu token vào local storage để retry sau (nếu cần)
          // Có thể implement sau nếu cần thiết
        }
      }
    }
  }

  /// Handle foreground message (app is open)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('Foreground message received: ${message.data}');

    if (message.data['type'] == 'incoming_call') {
      final callerId = message.data['callerId'] as String?;
      final isVideo = message.data['isVideo'] == 'true';
      final callId = message.data['callId'] as String?;
      final channelName = message.data['channelName'] as String?;

      if (callerId != null) {
        _emitIncomingCall(
          callerId,
          isVideo,
          callId: callId,
          channelName: channelName,
        );
      }
    }
  }

  /// Set callback for incoming calls
  void setIncomingCallCallback(
    Function(String callerId, bool isVideo, String callId, String channelName)
    callback,
  ) {
    _onIncomingCall = callback;
    debugPrint('CallNotificationService: Incoming call callback set');

    // Flush pending calls nếu có
    if (_pendingIncomingCalls.isNotEmpty) {
      final pending = List<Map<String, dynamic>>.from(_pendingIncomingCalls);
      _pendingIncomingCalls.clear();
      for (final item in pending) {
        final callerId = item['callerId'] as String?;
        final isVideo = item['isVideo'] as bool? ?? false;
        final callId = item['callId'] as String?;
        final channelName = item['channelName'] as String?;
        if (callerId != null &&
            callId != null &&
            callId.isNotEmpty &&
            channelName != null &&
            channelName.isNotEmpty) {
          _emitIncomingCall(
            callerId,
            isVideo,
            callId: callId,
            channelName: channelName,
          );
        }
      }
    }
  }

  void _emitIncomingCall(
    String callerId,
    bool isVideo, {
    required String? callId,
    required String? channelName,
  }) {
    final safeCallId = callId ?? '';
    final safeChannelName = channelName ?? '';

    // ✅ Phát chuông ngay khi nhận được cuộc gọi đến (foreground)
    if (safeCallId.isNotEmpty) {
      unawaited(startIncomingRingtone(callId: safeCallId));
    }

    final cb = _onIncomingCall;
    if (cb != null && safeCallId.isNotEmpty && safeChannelName.isNotEmpty) {
      cb(callerId, isVideo, safeCallId, safeChannelName);
    } else if (safeCallId.isNotEmpty && safeChannelName.isNotEmpty) {
      _pendingIncomingCalls.add({
        'callerId': callerId,
        'isVideo': isVideo,
        'callId': safeCallId,
        'channelName': safeChannelName,
      });
    }
  }

  void _startFirestoreIncomingCallListener(String userId) {
    // Restart listener theo userId mới
    _callNotificationsSubscription?.cancel();
    _handledCallNotificationIds.clear();

    _callNotificationsSubscription = _firestore
        .collection('callNotifications')
        // ✅ Tránh composite index: chỉ dùng equality filters
        .where('recipientUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen(
          (snapshot) async {
            if (snapshot.docChanges.isNotEmpty) {
              debugPrint(
                'CallNotificationService: callNotifications snapshot changes=${snapshot.docChanges.length}',
              );
            }
            for (final change in snapshot.docChanges) {
              if (change.type != DocumentChangeType.added) continue;

              final doc = change.doc;
              final docId = doc.id;
              if (_handledCallNotificationIds.contains(docId)) continue;

              final data = doc.data();
              if (data == null) continue;

              final callerId = data['callerId'] as String?;
              final isVideo = data['isVideo'] as bool? ?? false;
              final recipientUserId = data['recipientUserId'] as String?;
              final channelName =
                  (data['channelName'] as String?) ??
                  ((callerId != null && recipientUserId != null)
                      ? _generateChannelName(callerId, recipientUserId)
                      : null);
              if (callerId == null || callerId.isEmpty) continue;
              if (channelName == null || channelName.isEmpty) continue;

              _handledCallNotificationIds.add(docId);

              debugPrint(
                'CallNotificationService: Incoming call (ringing) via Firestore from=$callerId (video=$isVideo) callId=$docId channel=$channelName',
              );
              _emitIncomingCall(
                callerId,
                isVideo,
                callId: docId,
                channelName: channelName,
              );
            }
          },
          onError: (e) {
            debugPrint(
              'CallNotificationService: Firestore callNotifications listener error: $e',
            );
          },
        );
  }

  /// 🔔 Start ringtone for incoming call (foreground)
  Future<void> startIncomingRingtone({required String callId}) async {
    if (kIsWeb) return;
    // flutter_ringtone_player chỉ hỗ trợ Android/iOS.
    // Windows/Desktop vẫn nhận cuộc gọi qua Firestore, nhưng bỏ qua phần ringtone
    // để tránh MissingPluginException làm crash app.
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    // Nếu đang đổ chuông cho call khác, tắt cái cũ trước
    if (_activeIncomingCallId != null && _activeIncomingCallId != callId) {
      debugPrint(
        'CallNotificationService: stop previous incoming ringtone callId=$_activeIncomingCallId',
      );
      await stopIncomingRingtone();
    }

    _activeIncomingCallId = callId;

    // Theo dõi doc để tự tắt chuông khi status đổi
    _activeIncomingCallDocSub?.cancel();
    _activeIncomingCallDocSub = _firestore
        .collection('callNotifications')
        .doc(callId)
        .snapshots()
        .listen((snap) async {
          if (!snap.exists) {
            debugPrint(
              'CallNotificationService: callDoc deleted -> stopIncomingRingtone callId=$callId',
            );
            await stopIncomingRingtone();
            return;
          }
          final data = snap.data();
          final status = (data?['status'] as String?) ?? 'ringing';
          if (status != 'ringing') {
            debugPrint(
              'CallNotificationService: callDoc status=$status -> stopIncomingRingtone callId=$callId',
            );
            await stopIncomingRingtone();
          }
        });

    if (_isIncomingRingtonePlaying) return;
    _isIncomingRingtonePlaying = true;
    try {
      debugPrint(
        'CallNotificationService: 🔔 startIncomingRingtone callId=$callId',
      );
      await FlutterRingtonePlayer().play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.glass,
        looping: true,
        volume: 1.0,
        asAlarm: false,
      );
    } catch (e) {
      debugPrint('CallNotificationService: startIncomingRingtone error: $e');
      _isIncomingRingtonePlaying = false;
    }
  }

  /// 🔕 Stop ringtone for incoming call
  Future<void> stopIncomingRingtone() async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final prevCallId = _activeIncomingCallId;
    _activeIncomingCallId = null;
    await _activeIncomingCallDocSub?.cancel();
    _activeIncomingCallDocSub = null;

    if (!_isIncomingRingtonePlaying) return;
    _isIncomingRingtonePlaying = false;
    try {
      debugPrint(
        'CallNotificationService: 🔕 stopIncomingRingtone callId=$prevCallId',
      );
      await FlutterRingtonePlayer().stop();
    } catch (e) {
      debugPrint('CallNotificationService: stopIncomingRingtone error: $e');
    }
  }

  /// Send call notification to recipient
  Future<Map<String, String>?> createCallInvitation({
    required String recipientUserId,
    required String callerId,
    required bool isVideo,
  }) async {
    try {
      debugPrint(
        'Attempting to send call notification to user: $recipientUserId',
      );

      // Get recipient's FCM token
      final userDoc = await _firestore
          .collection('users')
          .doc(recipientUserId)
          .get();

      if (!userDoc.exists) {
        debugPrint(
          'WARNING: User document does not exist for: $recipientUserId. Cannot send call notification.',
        );
        return null;
      }

      final userData = userDoc.data();
      final fcmToken = userData?['fcmToken'] as String?;

      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint(
          'WARNING: No FCM token found for user: $recipientUserId. '
          'To receive calls when the app is in background, the recipient needs to log in to save their FCM token.',
        );
        // Không return ngay, vẫn thử gửi notification qua Firestore
        // để backend có thể xử lý (nếu có cloud function)
      }

      // Get caller info
      final caller = await _userService.getUserById(callerId);
      final callerName = caller?.fullName ?? 'Người gọi';
      final channelName = _generateChannelName(callerId, recipientUserId);

      // Send notification via Firestore (backend/cloud function sẽ xử lý)
      // Nếu có FCM token, backend sẽ gửi push notification
      final docRef = await _firestore.collection('callNotifications').add({
        'recipientUserId': recipientUserId,
        'callerId': callerId,
        'callerName': callerName,
        'isVideo': isVideo,
        'timestamp': FieldValue.serverTimestamp(),
        'fcmToken': fcmToken, // Có thể null, backend sẽ xử lý
        // ✅ trạng thái ban đầu: ringing (A đang gọi, B chưa nhận)
        'status': 'ringing',
        'channelName': channelName,
      });

      debugPrint(
        'CallNotificationService: Created call invitation callId=${docRef.id} channel=$channelName recipient=$recipientUserId',
      );

      // 🔔 Push incoming call qua server riêng (Render) - không phụ thuộc Cloud Functions.
      unawaited(
        PushGatewayService.instance.notifyIncomingCall(
          callId: docRef.id,
          callerId: callerId,
          recipientUserId: recipientUserId,
          channelName: channelName,
          isVideo: isVideo,
          callerName: callerName,
        ),
      );

      if (fcmToken != null) {
        debugPrint(
          'Call notification queued for user: $recipientUserId (FCM token available)',
        );
      } else {
        debugPrint(
          'Call notification queued for user: $recipientUserId (no FCM token available)',
        );
      }

      return {'callId': docRef.id, 'channelName': channelName};
    } catch (e, stackTrace) {
      debugPrint('Error sending call notification: $e');
      debugPrint('Stack trace: $stackTrace');
      // Không throw error để không làm gián đoạn cuộc gọi
      return null;
    }
  }

  /// Backwards-compatible wrapper
  Future<void> sendCallNotification({
    required String recipientUserId,
    required String callerId,
    required bool isVideo,
  }) async {
    await createCallInvitation(
      recipientUserId: recipientUserId,
      callerId: callerId,
      isVideo: isVideo,
    );
  }

  Future<void> updateCallStatus(String callId, Map<String, dynamic> updates) {
    return _firestore.collection('callNotifications').doc(callId).update({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cleanup
  void dispose() {
    try {
      // Stop ringtone
      try {
        unawaited(stopIncomingRingtone());
      } catch (e) {
        debugPrint('CallNotificationService: Error stopping ringtone during dispose: $e');
      }
      
      _onIncomingCall = null;
      _currentUserId = null;
      
      // Cancel subscriptions nếu chưa bị cancel
      try {
        _callNotificationsSubscription?.cancel();
      } catch (e) {
        debugPrint('CallNotificationService: Error canceling callNotificationsSubscription: $e');
      }
      _callNotificationsSubscription = null;
      
      try {
        _tokenRefreshSubscription?.cancel();
      } catch (e) {
        debugPrint('CallNotificationService: Error canceling tokenRefreshSubscription: $e');
      }
      _tokenRefreshSubscription = null;
      
      // Cancel active incoming call doc subscription
      try {
        _activeIncomingCallDocSub?.cancel();
      } catch (e) {
        debugPrint('CallNotificationService: Error canceling activeIncomingCallDocSub: $e');
      }
      _activeIncomingCallDocSub = null;
      
      _handledCallNotificationIds.clear();
      _pendingIncomingCalls.clear();
    } catch (e) {
      debugPrint('CallNotificationService: Error in dispose: $e');
    }
  }
}
