import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../core/constants/app_constants.dart';

/// Service quản lý chia sẻ vị trí trong messages.
///
/// Hỗ trợ:
/// - Chia sẻ vị trí một lần (static)
/// - Chia sẻ vị trí real-time (live tracking)
/// - Chia sẻ có thời hạn (auto-expire)
class LocationSharingService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _expirationTimer;

  /// Kiểm tra và yêu cầu quyền location
  Future<bool> requestLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Kiểm tra dịch vụ location có bật không
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return false;
    }

    // Kiểm tra quyền
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
      return false;
    }

    return true;
  }

  /// Lấy vị trí hiện tại một lần
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestLocationPermission();
    if (!hasPermission) {
      debugPrint('Location permission denied');
      return null;
    }

    try {
      // Thêm timeout cho Android (30 giây)
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('Timeout getting current position');
          throw TimeoutException('Getting location timed out');
        },
      );
    } on TimeoutException catch (e) {
      debugPrint('Timeout getting current position: $e');
      return null;
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return null;
    }
  }

  /// Lấy địa chỉ từ tọa độ (reverse geocoding)
  Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      // Thêm timeout cho Android (15 giây)
      final placemarks = await placemarkFromCoordinates(latitude, longitude)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              debugPrint('Timeout getting address from coordinates');
              throw TimeoutException('Getting address timed out');
            },
          );

      if (placemarks.isNotEmpty) {
        final place = placemarks[0];
        final addressParts = <String>[];
        if (place.street != null && place.street!.isNotEmpty) {
          addressParts.add(place.street!);
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          addressParts.add(place.subLocality!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }
        if (place.country != null && place.country!.isNotEmpty) {
          addressParts.add(place.country!);
        }
        return addressParts.isNotEmpty ? addressParts.join(', ') : null;
      }
    } on TimeoutException catch (e) {
      debugPrint('Timeout getting address from coordinates: $e');
      return null;
    } catch (e) {
      debugPrint('Error getting address from coordinates: $e');
      return null;
    }
    return null;
  }

  /// Bắt đầu theo dõi vị trí real-time và cập nhật vào Firestore
  ///
  /// [messageId]: ID của message chứa location sharing
  /// [conversationId]: ID của conversation
  /// [receiverId]: ID của người nhận
  /// [durationMinutes]: Thời gian tracking (null = vô thời hạn)
  Future<void> startLiveLocationTracking({
    required String messageId,
    required String conversationId,
    required String receiverId,
    int? durationMinutes,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final hasPermission = await requestLocationPermission();
    if (!hasPermission) {
      throw Exception('Location permission denied');
    }

    // Tính thời gian hết hạn
    DateTime? expiresAt;
    if (durationMinutes != null) {
      expiresAt = DateTime.now().add(Duration(minutes: durationMinutes));
    }

    // Cập nhật message với thông tin live location
    // Chỉ update nếu các trường này chưa được set hoặc cần thay đổi
    try {
      final messageDoc = await _firestore
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .get();

      if (!messageDoc.exists) {
        throw Exception('Message not found: $messageId');
      }

      final currentData = messageDoc.data()!;
      final currentSenderId = currentData['senderId'] as String?;

      if (currentSenderId != user.uid) {
        throw Exception(
          'Permission denied: You are not the sender of this message',
        );
      }

      if (kDebugMode) {
        debugPrint('Updating live location fields for message: $messageId');
        debugPrint('Current isLiveLocation: ${currentData['isLiveLocation']}');
        debugPrint('Setting isLiveLocation: true');
        debugPrint(
          'Setting locationExpiresAt: ${expiresAt?.toIso8601String()}',
        );
      }

      try {
        await _firestore
            .collection(AppConstants.messagesCollection)
            .doc(messageId)
            .update({
              'isLiveLocation': true,
              if (expiresAt != null)
                'locationExpiresAt': expiresAt.toIso8601String(),
            });

        if (kDebugMode) {
          debugPrint('Live location fields updated successfully');
        }
      } catch (updateError) {
        if (kDebugMode) {
          debugPrint('Error updating live location fields: $updateError');
          debugPrint('Attempting to use set with merge instead...');
        }
        // Fallback: use set with merge if update fails
        try {
          await _firestore
              .collection(AppConstants.messagesCollection)
              .doc(messageId)
              .set({
                'isLiveLocation': true,
                if (expiresAt != null)
                  'locationExpiresAt': expiresAt.toIso8601String(),
              }, SetOptions(merge: true));
          if (kDebugMode) {
            debugPrint('Live location fields updated using set(merge: true)');
          }
        } catch (setError) {
          if (kDebugMode) {
            debugPrint('Error using set(merge: true): $setError');
          }
          rethrow;
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('Error updating live location fields: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      rethrow;
    }

    // Bắt đầu theo dõi vị trí
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10, // Cập nhật khi di chuyển 10m
          ),
        ).listen(
          (Position position) async {
            // Cập nhật vị trí vào message
            try {
              final address = await getAddressFromCoordinates(
                position.latitude,
                position.longitude,
              );

              // Verify message exists and user is sender before updating
              final messageDoc = await _firestore
                  .collection(AppConstants.messagesCollection)
                  .doc(messageId)
                  .get();

              if (!messageDoc.exists) {
                if (kDebugMode) {
                  debugPrint(
                    'Message not found during live location update: $messageId',
                  );
                }
                return;
              }

              final messageData = messageDoc.data()!;
              final messageSenderId = messageData['senderId'] as String?;

              if (messageSenderId != user.uid) {
                if (kDebugMode) {
                  debugPrint(
                    'Permission denied: User $user.uid is not sender $messageSenderId',
                  );
                }
                return;
              }

              if (kDebugMode) {
                debugPrint(
                  'Updating live location position: lat=${position.latitude}, lng=${position.longitude}',
                );
              }

              await _firestore
                  .collection(AppConstants.messagesCollection)
                  .doc(messageId)
                  .update({
                    'latitude': position.latitude,
                    'longitude': position.longitude,
                    if (address != null && address.isNotEmpty)
                      'locationAddress': address,
                  });
            } catch (e) {
              debugPrint('Error updating live location: $e');
            }
          },
          onError: (error) {
            debugPrint('Error in position stream: $error');
          },
        );

    // Nếu có thời hạn, dừng tracking sau khi hết hạn
    if (expiresAt != null) {
      final remainingSeconds = expiresAt.difference(DateTime.now()).inSeconds;
      if (remainingSeconds > 0) {
        _expirationTimer = Timer(Duration(seconds: remainingSeconds), () {
          stopLiveLocationTracking(messageId);
        });
      }
    }
  }

  /// Dừng theo dõi vị trí real-time
  Future<void> stopLiveLocationTracking(String messageId) async {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _expirationTimer?.cancel();
    _expirationTimer = null;

    // Cập nhật message để đánh dấu không còn live
    try {
      await _firestore
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .update({'isLiveLocation': false});
    } catch (e) {
      debugPrint('Error stopping live location tracking: $e');
    }
  }

  /// Kiểm tra xem location sharing có còn hợp lệ không (chưa hết hạn)
  bool isLocationValid(DateTime? expiresAt) {
    if (expiresAt == null) return true; // Vô thời hạn
    return DateTime.now().isBefore(expiresAt);
  }

  /// Cleanup khi dispose
  void dispose() {
    _positionSubscription?.cancel();
    _expirationTimer?.cancel();
  }
}
