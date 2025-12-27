import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

/// Service quản lý Security Questions để khôi phục tài khoản.
///
/// Câu hỏi và câu trả lời được mã hóa trước khi lưu vào Firestore.
class SecurityQuestionsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _sha256 = Sha256();

  // Danh sách câu hỏi bảo mật mặc định
  static const List<String> defaultQuestions = [
    'Tên thú cưng đầu tiên của bạn là gì?',
    'Tên trường tiểu học của bạn là gì?',
    'Tên người bạn thân nhất thời thơ ấu là gì?',
    'Thành phố bạn sinh ra là gì?',
    'Tên mẹ bạn trước khi kết hôn là gì?',
    'Món ăn yêu thích của bạn là gì?',
    'Tên giáo viên yêu thích của bạn là gì?',
    'Số điện thoại đầu tiên của bạn là gì?',
  ];

  /// Thiết lập security questions cho user.
  /// 
  /// questions: Map với key là question ID và value là answer (plain text)
  Future<void> setupSecurityQuestions(
    String userId,
    Map<String, String> questions, // questionId -> answer
  ) async {
    try {
      if (questions.length < 2) {
        throw Exception('Cần ít nhất 2 câu hỏi bảo mật.');
      }

      final batch = _firestore.batch();
      final questionsRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('securityQuestions');

      for (final entry in questions.entries) {
        final questionId = entry.key;
        final answer = entry.value.trim().toLowerCase();

        // Hash answer trước khi lưu
        final hashedAnswer = await _hashAnswer(answer);

        batch.set(questionsRef.doc(questionId), {
          'questionId': questionId,
          'hashedAnswer': hashedAnswer,
          'setupAt': DateTime.now().toIso8601String(),
        });
      }

      // Đánh dấu đã setup
      batch.set(
          _firestore
              .collection(AppConstants.usersCollection)
              .doc(userId)
              .collection('securitySettings')
              .doc('securityQuestions'),
          {
            'isSetup': true,
            'setupAt': DateTime.now().toIso8601String(),
            'questionsCount': questions.length,
          });

      await batch.commit();
    } catch (e) {
      debugPrint('Error setting up security questions: $e');
      rethrow;
    }
  }

  /// Xác thực câu trả lời cho security questions.
  /// 
  /// answers: Map với key là questionId và value là answer (plain text)
  /// Trả về true nếu tất cả câu trả lời đúng.
  Future<bool> verifySecurityQuestions(
    String userId,
    Map<String, String> answers, // questionId -> answer
  ) async {
    try {
      if (answers.isEmpty) return false;

      // Lấy tất cả security questions của user
      final questionsSnapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('securityQuestions')
          .get();

      if (questionsSnapshot.docs.isEmpty) return false;

      // Kiểm tra từng câu trả lời
      int correctCount = 0;
      for (final doc in questionsSnapshot.docs) {
        final questionId = doc.id;
        final userAnswer = answers[questionId]?.trim().toLowerCase();

        if (userAnswer == null) continue;

        final hashedUserAnswer = await _hashAnswer(userAnswer);
        final storedHashedAnswer = doc.data()['hashedAnswer'] as String?;

        if (hashedUserAnswer == storedHashedAnswer) {
          correctCount++;
        }
      }

      // Cần trả lời đúng ít nhất 2/3 số câu hỏi
      final requiredCorrect = (questionsSnapshot.docs.length * 2 / 3).ceil();
      return correctCount >= requiredCorrect;
    } catch (e) {
      debugPrint('Error verifying security questions: $e');
      return false;
    }
  }

  /// Kiểm tra xem user đã setup security questions chưa.
  Future<bool> isSecurityQuestionsSetup(String userId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('securitySettings')
          .doc('securityQuestions')
          .get();

      return doc.exists && doc.data()?['isSetup'] == true;
    } catch (e) {
      debugPrint('Error checking security questions setup: $e');
      return false;
    }
  }

  /// Lấy danh sách security questions của user (chỉ question IDs).
  Future<List<String>> getUserSecurityQuestionIds(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('securityQuestions')
          .get();

      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint('Error getting user security question IDs: $e');
      return [];
    }
  }

  /// Xóa security questions của user.
  Future<void> deleteSecurityQuestions(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('securityQuestions')
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      // Xóa settings
      batch.delete(
          _firestore
              .collection(AppConstants.usersCollection)
              .doc(userId)
              .collection('securitySettings')
              .doc('securityQuestions'));

      await batch.commit();
    } catch (e) {
      debugPrint('Error deleting security questions: $e');
      rethrow;
    }
  }

  /// Hash câu trả lời bằng SHA-256.
  Future<String> _hashAnswer(String answer) async {
    final hash = await _sha256.hash(utf8.encode(answer.toLowerCase().trim()));
    return base64Encode(hash.bytes);
  }
}
