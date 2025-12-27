import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../models/activity_log_model.dart';

class ActivityLogService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Ghi log hoạt động
  Future<void> logActivity(ActivityLogModel activity) async {
    try {
      await _firestore
          .collection(AppConstants.activityLogsCollection)
          .add(activity.toMap());
      if (kDebugMode) {
        print(
          'Activity logged: ${activity.type.name} by ${activity.userId} for ${activity.targetUserId}',
        );
      }
    } catch (e) {
      // Ignore errors - logging không nên làm crash app
      if (kDebugMode) {
        print('Failed to log activity: $e');
      }
    }
  }

  /// Lấy nhật ký hoạt động của user (chỉ các activity của chính user đó)
  Stream<List<ActivityLogModel>> getActivityLogs(
    String userId, {
    int limit = 50,
  }) {
    // Chỉ lấy các activity của chính user (userId == userId)
    // Không dùng orderBy để tránh yêu cầu composite index, sẽ sort ở client
    return _firestore
        .collection(AppConstants.activityLogsCollection)
        .where('userId', isEqualTo: userId)
        .limit(limit * 2) // Lấy nhiều hơn để có đủ sau khi filter
        .snapshots()
        .map((snapshot) {
      if (kDebugMode) {
        print(
          'ActivityLogService: Received ${snapshot.docs.length} activities for userId=$userId',
        );
      }
      
      final logs = snapshot.docs
          .map((doc) {
            try {
              return ActivityLogModel.fromMap(doc.id, doc.data());
            } catch (e) {
              if (kDebugMode) {
                print(
                  'ActivityLogService: Error parsing activity log ${doc.id}: $e',
                );
              }
              return null;
            }
          })
          .whereType<ActivityLogModel>()
          .where((log) => !log.isHidden) // Loại bỏ các activity đã bị ẩn
          .toList();
      
      // Sort theo thời gian tạo (mới nhất trước)
      logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      // Giới hạn số lượng kết quả
      final result = logs.take(limit).toList();
      
      if (kDebugMode) {
        print(
          'ActivityLogService: Emitting ${result.length} activities (filtered from ${snapshot.docs.length})',
        );
      }
      
      return result;
    });
  }

  /// Ẩn một hoạt động
  Future<void> hideActivity(String activityId) async {
    try {
      await _firestore
          .collection(AppConstants.activityLogsCollection)
          .doc(activityId)
          .update({'isHidden': true});
    } catch (e) {
      throw Exception('Hide activity failed: $e');
    }
  }

  /// Hiển thị lại một hoạt động
  Future<void> showActivity(String activityId) async {
    try {
      await _firestore
          .collection(AppConstants.activityLogsCollection)
          .doc(activityId)
          .update({'isHidden': false});
    } catch (e) {
      throw Exception('Show activity failed: $e');
    }
  }
}
