import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/app_constants.dart';

/// Quản lý phiên đăng nhập / thiết bị của người dùng.
///
/// Mỗi user có subcollection `users/{uid}/sessions/{sessionId}` với:
/// - deviceId
/// - platform
/// - model
/// - createdAt
/// - lastActiveAt
/// - fcmToken (tùy chọn)
class SessionService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Ghi nhận (hoặc cập nhật) phiên đăng nhập hiện tại của user.
  /// Nên được gọi ngay sau khi đăng nhập thành công.
  Future<void> registerCurrentSession({String? fcmToken}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final deviceInfo = await getDeviceInfo();
    final deviceId = deviceInfo['deviceId'] ?? 'unknown-device';

    final sessionDoc = _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('sessions')
        .doc(deviceId);

    final now = DateTime.now().toIso8601String();

    await sessionDoc.set({
      'deviceId': deviceId,
      'platform': deviceInfo['platform'],
      'model': deviceInfo['model'],
      'osVersion': deviceInfo['osVersion'],
      'fcmToken': fcmToken,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActiveAt': now,
    }, SetOptions(merge: true));
  }

  /// Cập nhật `lastActiveAt` cho phiên hiện tại (gọi định kỳ hoặc khi mở app).
  Future<void> touchCurrentSession() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final deviceInfo = await getDeviceInfo();
    final deviceId = deviceInfo['deviceId'] ?? 'unknown-device';

    final sessionDoc = _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('sessions')
        .doc(deviceId);

    await sessionDoc.set({
      'lastActiveAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Lấy danh sách tất cả phiên đăng nhập của user hiện tại.
  Future<List<Map<String, dynamic>>> getSessions() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    // Lấy tất cả sessions, sau đó sort trên client để tránh cần index
    final snapshot = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('sessions')
        .get();

    final sessions = snapshot.docs
        .map((d) => ({'id': d.id, ...d.data()}))
        .toList(growable: false);

    // Sort theo lastActiveAt (mới nhất trước)
    sessions.sort((a, b) {
      final aTime = a['lastActiveAt'] as String?;
      final bTime = b['lastActiveAt'] as String?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      try {
        return DateTime.parse(bTime).compareTo(DateTime.parse(aTime));
      } catch (_) {
        return 0;
      }
    });

    return sessions;
  }

  /// Đăng xuất từ xa / xóa một phiên theo `sessionId` (ví dụ deviceId).
  Future<void> revokeSession(String sessionId) async {
    final user = _auth.currentUser;
    if (user == null || sessionId.isEmpty) return;

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('sessions')
        .doc(sessionId)
        .delete();
  }

  /// Xóa toàn bộ sessions (dùng cho "Đăng xuất khỏi tất cả thiết bị").
  Future<void> revokeAllSessions() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final sessionsRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .collection('sessions');

    final snapshot = await sessionsRef.get();
    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  /// Thu thập thông tin thiết bị cơ bản, không nhạy cảm.
  /// Public để có thể dùng từ UI (ví dụ AccountSecurityScreen).
  Future<Map<String, String>> getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        final deviceId = info.id.isNotEmpty
            ? info.id
            : 'android-${info.model.isNotEmpty ? info.model : 'unknown'}-${info.device.isNotEmpty ? info.device : 'unknown'}';
        return {
          'deviceId': deviceId,
          'platform': 'android',
          'model': info.model.isNotEmpty ? info.model : 'android',
          'osVersion': 'Android ${info.version.release}',
        };
      }
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        final deviceId =
            info.identifierForVendor ??
            'ios-${info.model.isNotEmpty ? info.model : 'unknown'}-${info.name.isNotEmpty ? info.name : 'unknown'}';
        return {
          'deviceId': deviceId,
          'platform': 'ios',
          'model': info.model.isNotEmpty ? info.model : 'ios',
          'osVersion': 'iOS ${info.systemVersion}',
        };
      }
    } catch (_) {
      // ignore
    }

    return {
      'deviceId': 'unknown',
      'platform': Platform.operatingSystem,
      'model': 'unknown',
      'osVersion': 'unknown',
    };
  }
}
