import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

/// Service quản lý khóa tài khoản sau nhiều lần đăng nhập sai.
///
/// Lưu thông tin vào `users/{uid}/failedLoginAttempts` document với:
/// - failedAttempts: số lần đăng nhập sai
/// - lockedUntil: thời gian khóa đến khi nào (null nếu không bị khóa)
/// - lastFailedAttempt: thời gian đăng nhập sai lần cuối
class AccountLockoutService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cấu hình
  static const int maxFailedAttempts = 5; // Số lần đăng nhập sai tối đa
  static const int lockoutDurationMinutes = 15; // Thời gian khóa (phút)

  /// Kiểm tra xem tài khoản có bị khóa không.
  /// Trả về null nếu không bị khóa, hoặc DateTime khi nào sẽ được mở khóa.
  Future<DateTime?> isAccountLocked(String email) async {
    try {
      // Tìm user theo email
      final usersSnapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (usersSnapshot.docs.isEmpty) return null;

      final userId = usersSnapshot.docs.first.id;
      final lockoutDoc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('failedLoginAttempts')
          .doc('lockout')
          .get();

      if (!lockoutDoc.exists) return null;

      final data = lockoutDoc.data();
      final lockedUntilStr = data?['lockedUntil'] as String?;

      if (lockedUntilStr == null) return null;

      final lockedUntil = DateTime.parse(lockedUntilStr);
      final now = DateTime.now();

      // Nếu đã hết thời gian khóa, xóa lockout
      if (now.isAfter(lockedUntil)) {
        await _clearLockout(userId);
        return null;
      }

      return lockedUntil;
    } catch (e) {
      debugPrint('Error checking account lockout: $e');
      return null;
    }
  }

  /// Ghi nhận một lần đăng nhập sai.
  /// Trả về true nếu tài khoản bị khóa sau lần này.
  Future<bool> recordFailedAttempt(String email) async {
    try {
      // Tìm user theo email
      final usersSnapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (usersSnapshot.docs.isEmpty) return false;

      final userId = usersSnapshot.docs.first.id;
      final lockoutRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('failedLoginAttempts')
          .doc('lockout');

      final lockoutDoc = await lockoutRef.get();
      final now = DateTime.now();

      int currentAttempts = 0;
      String? lockedUntilStr;

      if (lockoutDoc.exists) {
        final data = lockoutDoc.data()!;
        currentAttempts = data['failedAttempts'] ?? 0;
        lockedUntilStr = data['lockedUntil'] as String?;

        // Nếu đã hết thời gian khóa, reset
        if (lockedUntilStr != null) {
          final lockedUntil = DateTime.parse(lockedUntilStr);
          if (now.isAfter(lockedUntil)) {
            currentAttempts = 0;
            lockedUntilStr = null;
          }
        }
      }

      currentAttempts++;

      // Nếu đạt ngưỡng, khóa tài khoản
      if (currentAttempts >= maxFailedAttempts) {
        final lockedUntil = now.add(Duration(minutes: lockoutDurationMinutes));
        await lockoutRef.set({
          'failedAttempts': currentAttempts,
          'lockedUntil': lockedUntil.toIso8601String(),
          'lastFailedAttempt': now.toIso8601String(),
        }, SetOptions(merge: true));
        return true;
      } else {
        // Chỉ cập nhật số lần sai
        await lockoutRef.set({
          'failedAttempts': currentAttempts,
          'lastFailedAttempt': now.toIso8601String(),
        }, SetOptions(merge: true));
        return false;
      }
    } catch (e) {
      debugPrint('Error recording failed attempt: $e');
      return false;
    }
  }

  /// Xóa lockout và reset số lần đăng nhập sai (gọi khi đăng nhập thành công).
  Future<void> clearFailedAttempts(String email) async {
    try {
      final usersSnapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (usersSnapshot.docs.isEmpty) return;

      final userId = usersSnapshot.docs.first.id;
      await _clearLockout(userId);
    } catch (e) {
      debugPrint('Error clearing failed attempts: $e');
    }
  }

  /// Xóa lockout cho một user cụ thể.
  Future<void> _clearLockout(String userId) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('failedLoginAttempts')
          .doc('lockout')
          .delete();
    } catch (e) {
      debugPrint('Error clearing lockout: $e');
    }
  }

  /// Lấy số lần đăng nhập sai còn lại trước khi bị khóa.
  Future<int> getRemainingAttempts(String email) async {
    try {
      final usersSnapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (usersSnapshot.docs.isEmpty) return maxFailedAttempts;

      final userId = usersSnapshot.docs.first.id;
      final lockoutDoc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('failedLoginAttempts')
          .doc('lockout')
          .get();

      if (!lockoutDoc.exists) return maxFailedAttempts;

      final data = lockoutDoc.data()!;
      final attempts = (data['failedAttempts'] as int?) ?? 0;
      final lockedUntilStr = data['lockedUntil'] as String?;

      // Nếu đã hết thời gian khóa, reset
      if (lockedUntilStr != null) {
        final lockedUntil = DateTime.parse(lockedUntilStr);
        if (DateTime.now().isAfter(lockedUntil)) {
          return maxFailedAttempts;
        }
      }

      final remaining = maxFailedAttempts - attempts;
      return remaining.clamp(0, maxFailedAttempts);
    } catch (e) {
      debugPrint('Error getting remaining attempts: $e');
      return maxFailedAttempts;
    }
  }
}
