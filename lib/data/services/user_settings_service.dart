import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../models/user_settings.dart';

class UserSettingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<UserSettings> getSettings(String userId) async {
    if (userId.isEmpty) return const UserSettings();

    final doc = await _firestore
        .collection(AppConstants.userSettingsCollection)
        .doc(userId)
        .get();

    return UserSettings.fromMap(doc.data());
  }

  Future<void> upsertSettings(String userId, UserSettings settings) async {
    if (userId.isEmpty) return;

    await _firestore
        .collection(AppConstants.userSettingsCollection)
        .doc(userId)
        .set(settings.toMap(), SetOptions(merge: true));
  }

  Future<void> updateFields(
    String userId,
    Map<String, dynamic> data,
  ) async {
    if (userId.isEmpty) return;
    await _firestore
        .collection(AppConstants.userSettingsCollection)
        .doc(userId)
        .set(data, SetOptions(merge: true));
  }
}


