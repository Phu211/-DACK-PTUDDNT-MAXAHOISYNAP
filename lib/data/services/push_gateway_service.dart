import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';

/// Gửi push notification qua server riêng (Render) thay vì Firebase Functions.
///
/// Server sẽ dùng Firebase Admin SDK để đọc token từ Firestore và gửi FCM.
class PushGatewayService {
  PushGatewayService._();
  static final PushGatewayService instance = PushGatewayService._();

  final http.Client _client = http.Client();

  Uri _uri(String path) => Uri.parse('${AppConstants.backendBaseUrl}$path');

  Future<String?> _idToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) return;

    try {
      final resp = await _client
          .post(
            _uri(path),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 400) {
        debugPrint('PushGateway error ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      // Không throw để tránh ảnh hưởng luồng gửi tin nhắn/cuộc gọi.
      debugPrint('PushGateway request failed: $e');
    }
  }

  Future<void> notifyChatMessage({
    required String messageId,
    required String senderId,
    required String receiverId,
    required String conversationId,
  }) {
    return _post('/notify/message', {
      'messageId': messageId,
      'senderId': senderId,
      'receiverId': receiverId,
      'conversationId': conversationId,
    });
  }

  Future<void> notifyGroupMessage({
    required String messageId,
    required String senderId,
    required String groupId,
    required String conversationId,
  }) {
    return _post('/notify/group-message', {
      'messageId': messageId,
      'senderId': senderId,
      'groupId': groupId,
      'conversationId': conversationId,
    });
  }

  Future<void> notifyIncomingCall({
    required String callId,
    required String callerId,
    required String recipientUserId,
    required String channelName,
    required bool isVideo,
    String? callerName,
  }) {
    return _post('/notify/call', {
      'callId': callId,
      'callerId': callerId,
      'recipientUserId': recipientUserId,
      'channelName': channelName,
      'isVideo': isVideo,
      if (callerName != null) 'callerName': callerName,
    });
  }

  Future<void> notifyAppNotification({
    required String notificationId,
    required String userId,
    required String actorId,
    required String notificationType,
    String? postId,
    String? commentId,
  }) {
    return _post('/notify/app-notification', {
      'notificationId': notificationId,
      'userId': userId,
      'actorId': actorId,
      'notificationType': notificationType,
      if (postId != null) 'postId': postId,
      if (commentId != null) 'commentId': commentId,
    });
  }

  /// Gửi email cảnh báo bảo mật qua SendGrid
  Future<void> notifySecurityAlert({
    required String userId,
    required String activityType,
    required String details,
  }) {
    return _post('/notify/security-alert', {
      'userId': userId,
      'activityType': activityType,
      'details': details,
      'detectedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Gửi email chào mừng sau khi đăng ký
  /// Không cần auth token vì đây là khi user mới đăng ký
  Future<void> sendWelcomeEmail({
    required String userId,
    required String email,
    String? fullName,
    String? username,
  }) async {
    try {
      final resp = await _client
          .post(
            _uri('/notify/welcome-email'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'userId': userId,
              'email': email,
              'fullName': fullName,
              'username': username,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 400) {
        debugPrint('Welcome email error ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      // Không throw để không chặn quá trình đăng ký
      debugPrint('Welcome email request failed: $e');
    }
  }
}
