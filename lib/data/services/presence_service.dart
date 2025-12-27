import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:async/async.dart';
import '../../core/constants/app_constants.dart';
import 'settings_service.dart';

class PresenceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Set user as online (chỉ khi activity status được bật)
  Future<void> setUserOnline(String userId) async {
    try {
      // Kiểm tra setting trước khi set online
      final isActivityStatusEnabled = await SettingsService.isActivityStatusEnabled();
      if (!isActivityStatusEnabled) {
        // Nếu tắt, chỉ update lastSeen, không set online
        await _firestore.collection(AppConstants.usersCollection).doc(userId).set(
          {'lastSeen': DateTime.now().toIso8601String()},
          SetOptions(merge: true),
        );
        return;
      }
      
      await _firestore.collection(AppConstants.usersCollection).doc(userId).set(
        {'isOnline': true, 'lastSeen': DateTime.now().toIso8601String()},
        SetOptions(merge: true),
      );
    } catch (e) {
      // Ignore error
    }
  }

  // Set user as offline (chỉ khi activity status được bật)
  Future<void> setUserOffline(String userId) async {
    try {
      // Kiểm tra setting trước khi set offline
      final isActivityStatusEnabled = await SettingsService.isActivityStatusEnabled();
      if (!isActivityStatusEnabled) {
        // Nếu tắt, chỉ update lastSeen, không set offline
        await _firestore.collection(AppConstants.usersCollection).doc(userId).set(
          {'lastSeen': DateTime.now().toIso8601String()},
          SetOptions(merge: true),
        );
        return;
      }
      
      await _firestore.collection(AppConstants.usersCollection).doc(userId).set(
        {'isOnline': false, 'lastSeen': DateTime.now().toIso8601String()},
        SetOptions(merge: true),
      );
    } catch (e) {
      // Ignore error
    }
  }

  // Update last seen timestamp
  Future<void> updateLastSeen(String userId) async {
    try {
      await _firestore.collection(AppConstants.usersCollection).doc(userId).set(
        {'lastSeen': DateTime.now().toIso8601String()},
        SetOptions(merge: true),
      );
    } catch (e) {
      // Ignore error
    }
  }

  // Get online users (friends only)
  // Firestore whereIn chỉ hỗ trợ tối đa 10 items, nên ta batch + combine.
  Stream<List<String>> getOnlineUsers(List<String> friendIds) {
    if (friendIds.isEmpty) {
      return Stream.value([]);
    }

    // Chia friendIds thành các batch 10 items
    final batches = <List<String>>[];
    for (var i = 0; i < friendIds.length; i += 10) {
      batches.add(
        friendIds.sublist(
          i,
          i + 10 > friendIds.length ? friendIds.length : i + 10,
        ),
      );
    }

    if (batches.isEmpty) {
      return Stream.value([]);
    }

    // Combine tất cả batches thành 1 stream: mỗi batch là 1 listener (tối ưu hơn
    // nhiều so với tạo 1 listener cho mỗi item UI).
    final streams = batches
        .map((batch) {
          return _firestore
              .collection(AppConstants.usersCollection)
              .where(FieldPath.documentId, whereIn: batch)
              .where('isOnline', isEqualTo: true)
              .snapshots()
              .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());
        })
        .toList(growable: false);

    return StreamZip<List<String>>(streams).map((lists) {
      final set = <String>{};
      for (final l in lists) {
        set.addAll(l);
      }
      return set.toList();
    });
  }

  // Check if user is online
  Stream<bool> isUserOnline(String userId) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return false;
          final data = doc.data();
          return data?['isOnline'] == true;
        });
  }

  // Get last seen timestamp
  Future<DateTime?> getLastSeen(String userId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get();

      if (!doc.exists) return null;
      final data = doc.data();
      final lastSeen = data?['lastSeen'];
      if (lastSeen == null) return null;
      return DateTime.parse(lastSeen);
    } catch (e) {
      return null;
    }
  }
}
