import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

/// Service quản lý Recovery Codes (Backup Codes) cho tài khoản.
///
/// Recovery codes được dùng để khôi phục tài khoản khi mất quyền truy cập.
/// Codes được hash trước khi lưu vào Firestore để bảo mật.
class RecoveryCodesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _sha256 = Sha256();

  // Cấu hình
  static const int codesPerSet = 10; // Số mã trong mỗi bộ
  static const int codeLength = 8; // Độ dài mỗi mã (sẽ format thành XXXX-XXXX)

  /// Tạo một bộ recovery codes mới cho user.
  /// Trả về danh sách codes dạng plain text (chỉ hiển thị 1 lần).
  /// Codes cũ sẽ bị vô hiệu hóa.
  Future<List<String>> generateRecoveryCodes(String userId) async {
    try {
      // Vô hiệu hóa tất cả codes cũ
      await _invalidateAllCodes(userId);

      // Tạo codes mới
      final codes = <String>[];
      final hashedCodes = <String>[];

      for (int i = 0; i < codesPerSet; i++) {
        final code = _generateCode();
        codes.add(code);
        final hashed = await _hashCode(code);
        hashedCodes.add(hashed);
      }

      // Lưu hashed codes vào Firestore
      final batch = _firestore.batch();
      final createdAt = DateTime.now().toIso8601String();

      for (int i = 0; i < hashedCodes.length; i++) {
        final codeRef = _firestore
            .collection(AppConstants.usersCollection)
            .doc(userId)
            .collection('recoveryCodes')
            .doc();

        batch.set(codeRef, {
          'hashedCode': hashedCodes[i],
          'isUsed': false,
          'createdAt': createdAt,
          'usedAt': null,
        });
      }

      await batch.commit();

      return codes;
    } catch (e) {
      debugPrint('Error generating recovery codes: $e');
      rethrow;
    }
  }

  /// Xác thực một recovery code.
  /// Trả về true nếu code hợp lệ và chưa được sử dụng.
  Future<bool> verifyRecoveryCode(String userId, String code) async {
    try {
      final hashedCode = await _hashCode(code.trim().toUpperCase());

      // Tìm code trong Firestore
      final codesSnapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('recoveryCodes')
          .where('hashedCode', isEqualTo: hashedCode)
          .where('isUsed', isEqualTo: false)
          .limit(1)
          .get();

      if (codesSnapshot.docs.isEmpty) {
        return false;
      }

      // Đánh dấu code đã được sử dụng
      await codesSnapshot.docs.first.reference.update({
        'isUsed': true,
        'usedAt': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Error verifying recovery code: $e');
      return false;
    }
  }

  /// Lấy số lượng recovery codes còn lại (chưa sử dụng).
  Future<int> getRemainingCodesCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('recoveryCodes')
          .where('isUsed', isEqualTo: false)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      debugPrint('Error getting remaining codes count: $e');
      return 0;
    }
  }

  /// Lấy danh sách recovery codes (chỉ metadata, không có code thật).
  Future<List<Map<String, dynamic>>> getRecoveryCodesMetadata(
      String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('recoveryCodes')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'isUsed': data['isUsed'] ?? false,
          'createdAt': data['createdAt'],
          'usedAt': data['usedAt'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting recovery codes metadata: $e');
      return [];
    }
  }

  /// Vô hiệu hóa tất cả recovery codes của user.
  Future<void> _invalidateAllCodes(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('recoveryCodes')
          .where('isUsed', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isUsed': true,
          'usedAt': DateTime.now().toIso8601String(),
        });
      }

      if (snapshot.docs.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error invalidating codes: $e');
    }
  }

  /// Tạo một recovery code ngẫu nhiên.
  /// Format: XXXX-XXXX (8 ký tự, chia thành 2 nhóm 4 ký tự)
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Loại bỏ I, O, 0, 1 để tránh nhầm lẫn
    final random = Random.secure();
    final code = StringBuffer();

    for (int i = 0; i < codeLength; i++) {
      if (i == 4) {
        code.write('-');
      }
      code.write(chars[random.nextInt(chars.length)]);
    }

    return code.toString();
  }

  /// Hash một recovery code bằng SHA-256.
  Future<String> _hashCode(String code) async {
    final hash = await _sha256.hash(utf8.encode(code.toUpperCase()));
    return base64Encode(hash.bytes);
  }
}
