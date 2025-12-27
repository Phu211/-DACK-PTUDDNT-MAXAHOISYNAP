import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

/// Service quản lý IP Whitelisting.
///
/// Cho phép user chỉ cho phép đăng nhập từ các IP đã đăng ký.
class IPWhitelistingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Thêm IP vào whitelist.
  Future<void> addIPToWhitelist(String userId, String ipAddress) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('ipWhitelist')
          .doc(ipAddress)
          .set({
        'ipAddress': ipAddress,
        'addedAt': DateTime.now().toIso8601String(),
        'lastUsedAt': null,
      });
    } catch (e) {
      debugPrint('Error adding IP to whitelist: $e');
      rethrow;
    }
  }

  /// Xóa IP khỏi whitelist.
  Future<void> removeIPFromWhitelist(String userId, String ipAddress) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('ipWhitelist')
          .doc(ipAddress)
          .delete();
    } catch (e) {
      debugPrint('Error removing IP from whitelist: $e');
      rethrow;
    }
  }

  /// Kiểm tra xem IP có trong whitelist không.
  Future<bool> isIPWhitelisted(String userId, String ipAddress) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('ipWhitelist')
          .doc(ipAddress)
          .get();

      if (!doc.exists) return false;

      // Cập nhật lastUsedAt
      await doc.reference.update({
        'lastUsedAt': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Error checking IP whitelist: $e');
      return false;
    }
  }

  /// Lấy danh sách IPs trong whitelist.
  Future<List<Map<String, dynamic>>> getWhitelistedIPs(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('ipWhitelist')
          .orderBy('addedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'ipAddress': data['ipAddress'],
          'addedAt': data['addedAt'],
          'lastUsedAt': data['lastUsedAt'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting whitelisted IPs: $e');
      return [];
    }
  }

  /// Kiểm tra xem user có bật IP whitelisting không.
  Future<bool> isIPWhitelistingEnabled(String userId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('securitySettings')
          .doc('ipWhitelisting')
          .get();

      if (!doc.exists) return false;

      return doc.data()?['enabled'] == true;
    } catch (e) {
      debugPrint('Error checking IP whitelisting status: $e');
      return false;
    }
  }

  /// Bật/tắt IP whitelisting.
  Future<void> setIPWhitelistingEnabled(String userId, bool enabled) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('securitySettings')
          .doc('ipWhitelisting')
          .set({
        'enabled': enabled,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error setting IP whitelisting: $e');
      rethrow;
    }
  }
}
