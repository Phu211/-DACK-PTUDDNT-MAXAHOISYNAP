import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../models/notification_model.dart';
import 'session_service.dart';
import 'notification_service.dart';
import 'push_gateway_service.dart';

/// Service quản lý lịch sử đăng nhập và cảnh báo đăng nhập mới.
///
/// Lưu lịch sử đăng nhập vào `users/{uid}/loginHistory/{loginId}` với:
/// - deviceId
/// - platform
/// - model
/// - ipAddress (tùy chọn, có thể thêm sau)
/// - location (tùy chọn, có thể thêm sau)
/// - loginTime
/// - isNewDevice (true nếu đây là thiết bị mới)
class LoginHistoryService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SessionService _sessionService = SessionService();

  /// Ghi lại lịch sử đăng nhập và phát hiện thiết bị mới.
  /// Trả về true nếu đây là thiết bị mới.
  Future<bool> recordLogin() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final deviceInfo = await _sessionService.getDeviceInfo();
    final deviceId = deviceInfo['deviceId'] ?? 'unknown-device';

    // Kiểm tra xem thiết bị này đã từng đăng nhập chưa
    final existingSessions = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('sessions')
        .doc(deviceId)
        .get();

    final isNewDevice = !existingSessions.exists;

    final now = DateTime.now();
    final nowStr = now.toIso8601String();

    // Kiểm tra xem đã có entry với cùng deviceId và loginTime gần đây (trong vòng 5 giây) chưa
    // Để tránh duplicate entries khi recordLogin() được gọi nhiều lần
    final recentHistory = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('loginHistory')
        .where('deviceId', isEqualTo: deviceId)
        .orderBy('loginTime', descending: true)
        .limit(1)
        .get();

    if (recentHistory.docs.isNotEmpty) {
      final lastEntry = recentHistory.docs.first.data();
      final lastLoginTimeStr = lastEntry['loginTime'] as String?;
      if (lastLoginTimeStr != null) {
        try {
          final lastLoginTime = DateTime.parse(lastLoginTimeStr);
          final timeDiff = now.difference(lastLoginTime).inSeconds;
          // Nếu có entry trong vòng 5 giây gần đây với cùng deviceId, bỏ qua
          if (timeDiff < 5) {
            debugPrint('Login history entry already exists for device $deviceId within 5 seconds, skipping duplicate');
            return isNewDevice;
          }
        } catch (e) {
          debugPrint('Error parsing last login time: $e');
        }
      }
    }

    // Lưu vào login history
    final loginHistoryRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('loginHistory')
        .doc();

    await loginHistoryRef.set({
      'deviceId': deviceId,
      'platform': deviceInfo['platform'],
      'model': deviceInfo['model'],
      'osVersion': deviceInfo['osVersion'],
      'loginTime': nowStr,
      'isNewDevice': isNewDevice,
    });

    // Nếu là thiết bị mới, gửi thông báo
    if (isNewDevice) {
      await _sendNewLoginAlert(user.uid, deviceInfo);
    }

    return isNewDevice;
  }

  /// Gửi thông báo khi có đăng nhập từ thiết bị mới.
  Future<void> _sendNewLoginAlert(
    String userId,
    Map<String, String> deviceInfo,
  ) async {
    try {
      final deviceName = '${deviceInfo['platform']} - ${deviceInfo['model']}';

      debugPrint(
        'New login detected from device: $deviceName for user: $userId',
      );

      // Tạo notification trong app
      try {
        final notification = NotificationModel(
          id: '',
          userId: userId,
          actorId: userId, // Self notification
          type: NotificationType.friendRequest, // Dùng tạm type này
          createdAt: DateTime.now(),
          isRead: false,
        );

        final notificationService = NotificationService();
        await notificationService.createNotification(notification);

        // Gửi push notification qua backend
        unawaited(
          PushGatewayService.instance.notifySecurityAlert(
            userId: userId,
            activityType: 'newDevice',
            details:
                'Đăng nhập từ thiết bị mới: $deviceName. Nếu không phải bạn, vui lòng đổi mật khẩu ngay.',
          ),
        );
      } catch (e) {
        debugPrint('Error creating login alert notification: $e');
        // Fallback: chỉ gửi push notification
        unawaited(
          PushGatewayService.instance.notifySecurityAlert(
            userId: userId,
            activityType: 'newDevice',
            details:
                'Đăng nhập từ thiết bị mới: $deviceName. Nếu không phải bạn, vui lòng đổi mật khẩu ngay.',
          ),
        );
      }
    } catch (e) {
      // Không throw để không chặn luồng đăng nhập
      debugPrint('Error sending new login alert: $e');
    }
  }

  /// Lấy lịch sử đăng nhập (mới nhất trước).
  Future<List<Map<String, dynamic>>> getLoginHistory({int limit = 50}) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    // Lấy tất cả rồi sort trên client để tránh cần index
    final snapshot = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('loginHistory')
        .get();

    final history = snapshot.docs
        .map((d) => ({'id': d.id, ...d.data()}))
        .toList(growable: false);

    // Sort theo loginTime (mới nhất trước)
    history.sort((a, b) {
      final aTime = a['loginTime'] as String?;
      final bTime = b['loginTime'] as String?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      try {
        return DateTime.parse(bTime).compareTo(DateTime.parse(aTime));
      } catch (_) {
        return 0;
      }
    });

    // Loại bỏ duplicate entries (cùng deviceId và loginTime trong vòng 5 giây)
    final deduplicatedHistory = <Map<String, dynamic>>[];
    final seenEntries = <String>{};

    for (final entry in history) {
      final deviceId = entry['deviceId'] as String? ?? '';
      final loginTimeStr = entry['loginTime'] as String?;
      
      if (loginTimeStr != null) {
        try {
          final loginTime = DateTime.parse(loginTimeStr);
          // Tạo key từ deviceId và loginTime (làm tròn đến giây)
          final key = '$deviceId-${loginTime.millisecondsSinceEpoch ~/ 1000}';
          
          if (!seenEntries.contains(key)) {
            seenEntries.add(key);
            deduplicatedHistory.add(entry);
          }
        } catch (e) {
          debugPrint('Error parsing loginTime for deduplication: $e');
          // Nếu không parse được, vẫn thêm vào để không mất dữ liệu
          deduplicatedHistory.add(entry);
        }
      } else {
        // Nếu không có loginTime, vẫn thêm vào
        deduplicatedHistory.add(entry);
      }
    }

    // Limit sau khi deduplicate
    return deduplicatedHistory.take(limit).toList();
  }

  /// Xóa lịch sử đăng nhập cũ hơn N ngày.
  Future<void> cleanupOldHistory({int daysToKeep = 90}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    final cutoffStr = cutoffDate.toIso8601String();

    final snapshot = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('loginHistory')
        .where('loginTime', isLessThan: cutoffStr)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    if (snapshot.docs.isNotEmpty) {
      await batch.commit();
    }
  }
}
