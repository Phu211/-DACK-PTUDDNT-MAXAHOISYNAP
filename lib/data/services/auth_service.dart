import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../models/user_model.dart';
import 'push_gateway_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password
  Future<UserModel?> signUpWithEmail({
    required String email,
    required String password,
    required String username,
    required String fullName,
  }) async {
    try {
      // Create user account
      final userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);

      if (userCredential.user == null) return null;

      final user = userCredential.user!;

      // Gửi email xác thực (không chặn luồng đăng ký nếu lỗi)
      try {
        await user.sendEmailVerification();
      } catch (_) {
        // ignore
      }

      // Create user document in Firestore
      final userModel = UserModel(
        id: user.uid,
        email: email,
        username: username,
        fullName: fullName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      try {
        await _firestore.collection(AppConstants.usersCollection).doc(user.uid).set(userModel.toMap());
      } catch (firestoreError) {
        // If Firestore creation fails, delete the auth user to avoid orphaned accounts
        await user.delete();
        throw Exception('Failed to create user profile: $firestoreError');
      }

      // Gửi email chào mừng (không chặn luồng đăng ký nếu lỗi)
      try {
        await PushGatewayService.instance.sendWelcomeEmail(
          userId: user.uid,
          email: email,
          fullName: fullName,
          username: username,
        );
      } catch (e) {
        debugPrint('Error sending welcome email: $e');
        // ignore - không chặn quá trình đăng ký
      }

      return userModel;
    } on FirebaseAuthException catch (e) {
      // Re-throw Firebase Auth errors as-is
      throw e;
    } catch (e) {
      throw Exception('Sign up failed: $e');
    }
  }

  // Sign in with email and password
  Future<UserModel?> signInWithEmail({required String email, required String password}) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(email: email, password: password);

      if (userCredential.user == null) return null;

      // Get user data from Firestore
      final userDoc = await _firestore.collection(AppConstants.usersCollection).doc(userCredential.user!.uid).get();

      if (!userDoc.exists) return null;

      return UserModel.fromMap(userCredential.user!.uid, userDoc.data()!);
    } catch (e) {
      throw Exception('Sign in failed: $e');
    }
  }

  // Gửi lại email xác thực
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.sendEmailVerification();
    } catch (_) {
      rethrow;
    }
  }

  // Reload và trả về trạng thái email đã xác thực hay chưa
  Future<bool> refreshEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  // Sign out
  Future<void> signOut() async {
    try {
      debugPrint('AuthService: Starting Firebase Auth signOut...');
      final currentUserBefore = _auth.currentUser?.uid;
      debugPrint('AuthService: Current user before signOut: $currentUserBefore');

      await _auth.signOut();

      final currentUserAfter = _auth.currentUser?.uid;
      debugPrint('AuthService: Current user after signOut: $currentUserAfter');
      debugPrint('AuthService: Firebase Auth signOut completed successfully');
    } catch (e, stackTrace) {
      debugPrint('AuthService: ERROR during signOut: $e');
      debugPrint('AuthService: Error type: ${e.runtimeType}');
      debugPrint('AuthService: Stack trace: $stackTrace');
      // Re-throw để AuthProvider có thể xử lý
      rethrow;
    }
  }

  // Get current user data
  Future<UserModel?> getCurrentUserData() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final userDoc = await _firestore.collection(AppConstants.usersCollection).doc(user.uid).get();

      if (!userDoc.exists) return null;

      return UserModel.fromMap(user.uid, userDoc.data()!);
    } catch (e) {
      return null;
    }
  }

  // Update user profile
  Future<void> updateUserProfile(UserModel userModel) async {
    try {
      await _firestore.collection(AppConstants.usersCollection).doc(userModel.id).update(userModel.toMap());
    } catch (e) {
      throw Exception('Update profile failed: $e');
    }
  }
}
