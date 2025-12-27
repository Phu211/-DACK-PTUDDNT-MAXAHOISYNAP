import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../models/notification_model.dart';
import 'push_gateway_service.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a notification
  Future<String> createNotification(NotificationModel notification) async {
    try {
      final docRef = await _firestore
          .collection(AppConstants.notificationsCollection)
          .add(notification.toMap());

      // 🔔 Push notification qua server riêng (Render)
      unawaited(
        PushGatewayService.instance.notifyAppNotification(
          notificationId: docRef.id,
          userId: notification.userId,
          actorId: notification.actorId,
          notificationType: notification.type.name,
          postId: notification.postId,
          commentId: notification.commentId,
        ),
      );
      return docRef.id;
    } catch (e) {
      throw Exception('Create notification failed: $e');
    }
  }

  // Get notifications for a user
  Stream<List<NotificationModel>> getNotifications(String userId) {
    return _firestore
        .collection(AppConstants.notificationsCollection)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => NotificationModel.fromMap(doc.id, doc.data()))
              .toList();
        })
        .handleError((error) {
          // Handle permission errors gracefully (user may have logged out)
          if (error.toString().contains('permission-denied') || 
              error.toString().contains('permission denied')) {
            return <NotificationModel>[];
          }
          // Re-throw other errors
          throw error;
        });
  }

  // Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore
          .collection(AppConstants.notificationsCollection)
          .doc(notificationId)
          .update({'isRead': true});
    } catch (e) {
      throw Exception('Mark as read failed: $e');
    }
  }

  // Get unread notifications count
  Future<int> getUnreadCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.notificationsCollection)
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  // Realtime unread notifications count
  Stream<int> getUnreadCountStream(String userId) {
    return _firestore
        .collection(AppConstants.notificationsCollection)
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Delete notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore
          .collection(AppConstants.notificationsCollection)
          .doc(notificationId)
          .delete();
    } catch (e) {
      throw Exception('Delete notification failed: $e');
    }
  }
}
