import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import 'user_settings_service.dart';
import 'friend_service.dart';
import 'encryption_service.dart';
import 'push_gateway_service.dart';

class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserSettingsService _userSettingsService = UserSettingsService();
  final FriendService _friendService = FriendService();
  final EncryptionService _encryptionService = EncryptionService();

  // Get or create group conversation
  Future<String> getOrCreateGroupConversation(String groupId) async {
    try {
      // Conversation ID cho group là groupId
      final conversationId = 'group_$groupId';

      // Kiểm tra conversation đã tồn tại
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (conversationDoc.exists) {
        return conversationId;
      }

      // Lấy thông tin group để lấy danh sách members
      final groupDoc = await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .get();

      if (!groupDoc.exists) {
        throw Exception('Group not found');
      }

      final groupData = groupDoc.data()!;
      final memberIds = List<String>.from(groupData['memberIds'] ?? []);

      if (memberIds.isEmpty) {
        throw Exception('Group has no members');
      }

      // Tạo conversation mới cho group
      final now = DateTime.now();
      final unreadCounts = <String, int>{};
      for (final memberId in memberIds) {
        unreadCounts[memberId] = 0;
      }

      final conversation = ConversationModel(
        id: conversationId,
        participantIds: memberIds,
        lastMessageTime: now,
        createdAt: now,
        updatedAt: now,
        unreadCounts: unreadCounts,
        groupId: groupId,
        type: 'group',
      );

      await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .set(conversation.toMap());
      return conversationId;
    } catch (e) {
      throw Exception('Get or create group conversation failed: $e');
    }
  }

  // Get or create conversation between two users
  Future<String> getOrCreateConversation(String userId1, String userId2) async {
    try {
      // Tạo conversation ID từ participant IDs (sắp xếp để đảm bảo unique)
      final participants = [userId1, userId2]..sort();
      final conversationId = participants.join('_');

      // Kiểm tra conversation đã tồn tại
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (conversationDoc.exists) {
        // CRITICAL: Nếu conversation có deletedBy chứa userId1 hoặc userId2,
        // xóa deletedBy để restore conversation khi gửi tin nhắn mới
        final data = conversationDoc.data() as Map<String, dynamic>? ?? {};
        final deletedBy = List<String>.from(data['deletedBy'] ?? []);

        if (deletedBy.contains(userId1) || deletedBy.contains(userId2)) {
          if (kDebugMode) {
            print(
              '=== Conversation $conversationId has deletedBy: $deletedBy, clearing it to restore',
            );
          }

          // Xóa deletedBy khỏi conversation để restore conversation
          await conversationDoc.reference.update({
            'deletedBy': [],
            'updatedAt': DateTime.now().toIso8601String(),
          });

          if (kDebugMode) {
            print('=== Conversation restored successfully');
          }
        }

        return conversationId;
      }

      // Tạo conversation mới với đầy đủ các trường cần thiết
      final now = DateTime.now();
      final conversation = ConversationModel(
        id: conversationId,
        participantIds: participants,
        lastMessageTime: now,
        createdAt: now,
        updatedAt: now,
        unreadCounts: {userId1: 0, userId2: 0},
        type:
            'direct', // CRITICAL: Set type để đảm bảo conversation được tạo đúng
      );

      try {
        await _firestore
            .collection(AppConstants.conversationsCollection)
            .doc(conversationId)
            .set(conversation.toMap());

        if (kDebugMode) {
          print(
            '=== Conversation created successfully in getOrCreateConversation: $conversationId',
          );
        }

        // Đợi một chút để Firestore index conversation mới
        await Future.delayed(const Duration(milliseconds: 200));

        return conversationId;
      } catch (e, stackTrace) {
        // Nếu tạo conversation thất bại, log lỗi nhưng vẫn trả về conversationId
        // Conversation sẽ được tạo lại trong sendMessage hoặc fetchMessages
        if (kDebugMode) {
          print(
            '=== WARNING: Failed to create conversation in getOrCreateConversation: $e',
          );
          print('=== Stack trace: $stackTrace');
          print('=== ConversationId: $conversationId');
          print(
            '=== This may be due to Firestore security rules or network issues',
          );
          print('=== Will retry in sendMessage...');
        }
        // Vẫn trả về conversationId để không làm gián đoạn việc gửi message
        // Conversation sẽ được tạo lại trong sendMessage
        return conversationId;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('=== ERROR in getOrCreateConversation: $e');
        print('=== Stack trace: $stackTrace');
      }
      // Tạo conversationId ngay cả khi có lỗi để không làm gián đoạn việc gửi message
      final participants = [userId1, userId2]..sort();
      final conversationId = participants.join('_');
      return conversationId;
    }
  }

  // Send a message - Bảo mật: validate trước khi gửi
  Future<String> sendMessage(MessageModel message) async {
    try {
      // Validation: đảm bảo senderId và receiverId hợp lệ
      if (message.senderId.isEmpty ||
          message.receiverId.isEmpty ||
          message.senderId == message.receiverId) {
        throw Exception('Invalid sender or receiver ID');
      }

      // Validation: đảm bảo có nội dung hoặc media hoặc location
      if (message.content.trim().isEmpty &&
          message.imageUrl == null &&
          message.videoUrl == null &&
          message.audioUrl == null &&
          message.gifUrl == null &&
          (message.latitude == null || message.longitude == null)) {
        throw Exception('Message content cannot be empty');
      }

      // Chặn nếu bị block
      final blocked = await _isBlocked(
        senderId: message.senderId,
        receiverId: message.receiverId,
      );
      if (blocked) {
        throw Exception('Bạn không thể nhắn tin tới người này.');
      }

      // Kiểm tra quyền nhắn tin của người nhận
      final receiverSettings = await _userSettingsService.getSettings(
        message.receiverId,
      );
      // TẠM THỜI: Bỏ chặn theo setting messageWhoCanMessage để tránh bị đẩy vào messageRequests
      // Nếu muốn bật lại logic lọc sau này, dùng lại _canSendDirect ở đây.
      if (kDebugMode) {
        print('=== MESSAGE PERMISSION CHECK (DISABLED) ===');
        print('ReceiverId: ${message.receiverId}');
        print('Receiver setting: ${receiverSettings.messageWhoCanMessage}');
        print(
          'messageRequestsEnabled: ${receiverSettings.messageRequestsEnabled}',
        );
        print('Tạm thời cho phép gửi trực tiếp mọi tin nhắn 1-1');
      }

      // Tạo hoặc lấy conversation
      final conversationId = await getOrCreateConversation(
        message.senderId,
        message.receiverId,
      );

      // Lưu message (tạm thời không mã hóa để tránh hiển thị sai chữ)
      final messageMap = message.toMap();
      messageMap['conversationId'] = conversationId;
      messageMap['content'] = message.content;
      messageMap['nonce'] = null;
      // Đảm bảo status khởi tạo là sent
      messageMap['status'] = 'sent';

      // CRITICAL FIX: Đảm bảo các trường media/location được giữ lại sau khi modify messageMap
      // Trên Android, Firestore có thể không lưu các trường null, nên cần đảm bảo các trường này được set rõ ràng
      if (message.audioUrl != null && message.audioUrl!.isNotEmpty) {
        messageMap['audioUrl'] = message.audioUrl;
        messageMap['audioDuration'] = message.audioDuration;
      }
      if (message.latitude != null && message.longitude != null) {
        messageMap['latitude'] = message.latitude;
        messageMap['longitude'] = message.longitude;
        messageMap['locationAddress'] = message.locationAddress;
        messageMap['isLiveLocation'] = message.isLiveLocation ?? false;
        if (message.locationExpiresAt != null) {
          messageMap['locationExpiresAt'] = message.locationExpiresAt!
              .toIso8601String();
        }
      }

      // Debug: log message data trước khi lưu
      if (kDebugMode) {
        print('=== PREPARING MESSAGE FOR FIRESTORE ===');
        print('Message object fields:');
        print('  audioUrl: ${message.audioUrl}');
        print('  latitude: ${message.latitude}');
        print('  longitude: ${message.longitude}');
        print('  locationAddress: ${message.locationAddress}');
        print('  isLiveLocation: ${message.isLiveLocation}');
        print('MessageMap after toMap() and explicit field setting:');
        print('  audioUrl: ${messageMap['audioUrl']}');
        print('  audioDuration: ${messageMap['audioDuration']}');
        print('  latitude: ${messageMap['latitude']}');
        print('  longitude: ${messageMap['longitude']}');
        print('  locationAddress: ${messageMap['locationAddress']}');
        print('  isLiveLocation: ${messageMap['isLiveLocation']}');
        print('  senderId: ${messageMap['senderId']}');
        print('  receiverId: ${messageMap['receiverId']}');
        print('  conversationId: $conversationId');
        print('All messageMap keys: ${messageMap.keys.toList()}');
        print('Full messageMap: $messageMap');
      }

      String messageId;
      try {
        // Debug: log full messageMap before saving
        if (kDebugMode) {
          print('=== SENDING MESSAGE ===');
          print('Full messageMap keys: ${messageMap.keys.toList()}');
          print('Full messageMap: $messageMap');
          print('Collection: ${AppConstants.messagesCollection}');
          print('ConversationId: $conversationId');
        }

        DocumentReference docRef;
        try {
          if (kDebugMode) {
            print('=== ATTEMPTING TO SAVE MESSAGE TO FIRESTORE ===');
            print('Collection: ${AppConstants.messagesCollection}');
            print('MessageMap keys: ${messageMap.keys.toList()}');
          }

          docRef = await _firestore
              .collection(AppConstants.messagesCollection)
              .add(messageMap);
          messageId = docRef.id;

          if (kDebugMode) {
            print('=== ✅ MESSAGE SAVED TO FIRESTORE ===');
            print('Message ID: $messageId');
            print('Document Reference Path: ${docRef.path}');
            print('ConversationId: $conversationId');
            print('SenderId: ${messageMap['senderId']}');
            print('ReceiverId: ${messageMap['receiverId']}');
            print('Content: "${messageMap['content']}"');
            print('CreatedAt: ${messageMap['createdAt']}');
            print('=== 🔍 CHECK FIRESTORE CONSOLE ===');
            print(
              '1. Go to: https://console.firebase.google.com/project/dack-3040b/firestore',
            );
            print('2. Open collection: messages');
            print('3. Find document with ID: $messageId');
            print('4. Verify conversationId field matches: $conversationId');
            print('5. Verify senderId: ${messageMap['senderId']}');
            print('6. Verify receiverId: ${messageMap['receiverId']}');
          }

          // CRITICAL: Verify message was actually saved immediately
          try {
            final immediateCheck = await docRef.get();
            if (!immediateCheck.exists) {
              if (kDebugMode) {
                print(
                  '=== ⚠️ CRITICAL: Message ID generated but document does not exist! ===',
                );
                print('Message ID: $messageId');
                print('This indicates a Firestore write failure');
              }
              throw Exception(
                'Message was not saved to Firestore - document does not exist',
              );
            }
            if (kDebugMode) {
              print(
                '=== ✅ IMMEDIATE VERIFICATION: Document exists in Firestore ===',
              );
            }
          } catch (verifyError) {
            if (kDebugMode) {
              print('=== ❌ IMMEDIATE VERIFICATION FAILED ===');
              print('Error: $verifyError');
            }
            rethrow;
          }
        } catch (addError, addStack) {
          if (kDebugMode) {
            print('=== ❌ ERROR SAVING MESSAGE TO FIRESTORE ===');
            print('Error: $addError');
            print('Stack trace: $addStack');
            print('MessageMap: $messageMap');
            print('ConversationId: $conversationId');
          }
          rethrow; // Re-throw để được catch ở try-catch bên ngoài
        }

        // CRITICAL: Verify message was saved correctly (for ALL messages)
        // Verify ngay sau khi lưu để đảm bảo tin nhắn được lưu đúng
        try {
          await Future.delayed(const Duration(milliseconds: 300));
          final verifyDoc = await docRef.get();
          if (verifyDoc.exists) {
            final verifyDataRaw = verifyDoc.data();
            if (verifyDataRaw != null) {
              final dataMap = verifyDataRaw is Map<String, dynamic>
                  ? verifyDataRaw
                  : Map<String, dynamic>.from(verifyDataRaw as Map);
              if (kDebugMode) {
                print('=== ✅ VERIFICATION: Message exists in Firestore ===');
                print('Verified Message ID: ${verifyDoc.id}');
                print('Verified ConversationId: ${dataMap['conversationId']}');
                print('Verified SenderId: ${dataMap['senderId']}');
                print('Verified ReceiverId: ${dataMap['receiverId']}');
                print('Verified Content: "${dataMap['content']}"');
                if (dataMap['conversationId'] != conversationId) {
                  print('⚠️ WARNING: ConversationId mismatch!');
                  print('Expected: $conversationId');
                  print('Actual: ${dataMap['conversationId']}');
                }
              }
            }
          } else {
            if (kDebugMode) {
              print('⚠️ WARNING: Message not found in Firestore after save!');
              print('⚠️ Message ID: $messageId');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Verification failed (non-critical): $e');
          }
        }

        // CRITICAL: Verify and fix data persistence issues on Android
        // On Android, Firestore may drop fields during .add(), so we verify and fix immediately
        // Simplified verification: only one quick check, no aggressive retries to avoid hanging
        bool needsVerification =
            (message.audioUrl != null && message.audioUrl!.isNotEmpty) ||
            (message.latitude != null && message.longitude != null);

        if (needsVerification) {
          try {
            // Wait briefly for Firestore to sync
            await Future.delayed(const Duration(milliseconds: 500));

            // Single verification attempt with timeout protection
            final verifyDoc = await docRef.get().timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                if (kDebugMode) {
                  print('Verification timeout - skipping');
                }
                return docRef.get();
              },
            );

            if (verifyDoc.exists) {
              final verifyDataRaw = verifyDoc.data()!;
              final verifyData = verifyDataRaw is Map<String, dynamic>
                  ? verifyDataRaw
                  : Map<String, dynamic>.from(
                      verifyDataRaw as Map<dynamic, dynamic>,
                    );
              final updateData = <String, dynamic>{};

              // Check and fix audioUrl
              if (messageMap['audioUrl'] != null &&
                  messageMap['audioUrl'].toString().isNotEmpty &&
                  (verifyData['audioUrl'] == null ||
                      verifyData['audioUrl'].toString().isEmpty)) {
                updateData['audioUrl'] = messageMap['audioUrl'];
                updateData['audioDuration'] = messageMap['audioDuration'];
              }

              // Check and fix location fields
              if (messageMap['latitude'] != null &&
                  verifyData['latitude'] == null) {
                updateData['latitude'] = messageMap['latitude'];
              }
              if (messageMap['longitude'] != null &&
                  verifyData['longitude'] == null) {
                updateData['longitude'] = messageMap['longitude'];
              }
              if (messageMap['locationAddress'] != null &&
                  messageMap['locationAddress'].toString().isNotEmpty &&
                  (verifyData['locationAddress'] == null ||
                      verifyData['locationAddress'].toString().isEmpty)) {
                updateData['locationAddress'] = messageMap['locationAddress'];
              }
              if (messageMap['isLiveLocation'] != null &&
                  verifyData['isLiveLocation'] == null) {
                updateData['isLiveLocation'] = messageMap['isLiveLocation'];
              }
              if (messageMap['locationExpiresAt'] != null &&
                  verifyData['locationExpiresAt'] == null) {
                updateData['locationExpiresAt'] =
                    messageMap['locationExpiresAt'];
              }

              // Apply fix if needed (single attempt, no retries)
              if (updateData.isNotEmpty) {
                try {
                  await docRef
                      .set(updateData, SetOptions(merge: true))
                      .timeout(const Duration(seconds: 3));
                  if (kDebugMode) {
                    print('Fixed missing fields in message document');
                  }
                } catch (updateError) {
                  if (kDebugMode) {
                    print(
                      'Failed to fix document (non-critical): $updateError',
                    );
                  }
                  // Don't throw - message was already saved successfully
                }
              }
            }
          } catch (verifyError) {
            if (kDebugMode) {
              print('Verification error (non-critical): $verifyError');
            }
            // Don't throw - message was already saved successfully
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('ERROR saving message to Firestore: $e');
          print('Message data that failed to save:');
          print('  audioUrl: ${messageMap['audioUrl']}');
          print('  latitude: ${messageMap['latitude']}');
          print('  longitude: ${messageMap['longitude']}');
          print('  senderId: ${messageMap['senderId']}');
          print('  receiverId: ${messageMap['receiverId']}');
          print('  groupId: ${messageMap['groupId']}');
        }
        rethrow;
      }

      // Cập nhật hoặc tạo conversation
      try {
        final conversationDoc = await _firestore
            .collection(AppConstants.conversationsCollection)
            .doc(conversationId)
            .get();

        if (conversationDoc.exists) {
          try {
            final data = conversationDoc.data()!;
            final currentUnreadCounts = Map<String, int>.from(
              data['unreadCounts'] ?? {},
            );
            // Tăng unread count cho receiver
            currentUnreadCounts[message.receiverId] =
                (currentUnreadCounts[message.receiverId] ?? 0) + 1;

            await conversationDoc.reference.update({
              'lastMessageId': messageId,
              'lastMessageContent': message.content.isNotEmpty
                  ? message.content
                  : (message.imageUrl != null
                        ? '[Ảnh]'
                        : (message.videoUrl != null
                              ? '[Video]'
                              : (message.audioUrl != null
                                    ? '[Voice]'
                                    : (message.gifUrl != null
                                          ? '[GIF]'
                                          : (message.latitude != null &&
                                                    message.longitude != null
                                                ? (message.isLiveLocation ==
                                                          true
                                                      ? '[Live Location]'
                                                      : '[Location]')
                                                : ''))))),
              'lastMessageNonce': null,
              'lastMessageSenderId': message.senderId,
              'lastMessageTime': message.createdAt.toIso8601String(),
              'unreadCounts': currentUnreadCounts,
              'updatedAt': DateTime.now().toIso8601String(),
            });
          } catch (e, stackTrace) {
            if (kDebugMode) {
              print('=== ERROR updating conversation: $e');
              print('=== Stack trace: $stackTrace');
            }
            // Tiếp tục với việc tạo conversation mới nếu update thất bại
          }
        } else {
          // CRITICAL FIX: Tạo conversation nếu không tồn tại (có thể đã bị xóa trước đó)
          // Điều này đảm bảo conversation luôn tồn tại khi có tin nhắn mới
          if (kDebugMode) {
            print(
              '=== WARNING: Conversation $conversationId does not exist, creating...',
            );
          }

          // Retry logic để xử lý race condition và transient errors
          bool conversationCreated = false;
          int retryCount = 0;
          const maxRetries = 3;

          while (!conversationCreated && retryCount < maxRetries) {
            try {
              // Kiểm tra lại xem conversation đã được tạo bởi user khác chưa
              final checkDoc = await _firestore
                  .collection(AppConstants.conversationsCollection)
                  .doc(conversationId)
                  .get();

              if (checkDoc.exists) {
                // Conversation đã được tạo bởi user khác hoặc trong lần retry trước
                if (kDebugMode) {
                  print(
                    '=== Conversation already exists (created by another user or retry), updating...',
                  );
                }
                // Cập nhật conversation với thông tin message mới
                try {
                  final data = checkDoc.data()!;
                  final currentUnreadCounts = Map<String, int>.from(
                    data['unreadCounts'] ?? {},
                  );
                  currentUnreadCounts[message.receiverId] =
                      (currentUnreadCounts[message.receiverId] ?? 0) + 1;

                  await checkDoc.reference.update({
                    'lastMessageId': messageId,
                    'lastMessageContent': message.content.isNotEmpty
                        ? message.content
                        : (message.imageUrl != null
                              ? '[Ảnh]'
                              : (message.videoUrl != null
                                    ? '[Video]'
                                    : (message.audioUrl != null
                                          ? '[Voice]'
                                          : (message.gifUrl != null
                                                ? '[GIF]'
                                                : (message.latitude != null &&
                                                          message.longitude !=
                                                              null
                                                      ? (message.isLiveLocation ==
                                                                true
                                                            ? '[Live Location]'
                                                            : '[Location]')
                                                      : ''))))),
                    'lastMessageNonce': null,
                    'lastMessageSenderId': message.senderId,
                    'lastMessageTime': message.createdAt.toIso8601String(),
                    'unreadCounts': currentUnreadCounts,
                    'updatedAt': DateTime.now().toIso8601String(),
                  });
                } catch (updateError) {
                  if (kDebugMode) {
                    print(
                      '=== ERROR updating existing conversation: $updateError',
                    );
                  }
                }
                conversationCreated = true;
                break;
              }

              // Tạo conversation mới
              final participants = [message.senderId, message.receiverId]
                ..sort();
              final now = DateTime.now();
              final conversation = ConversationModel(
                id: conversationId,
                participantIds: participants,
                lastMessageId: messageId,
                lastMessageContent: message.content.isNotEmpty
                    ? message.content
                    : (message.imageUrl != null
                          ? '[Ảnh]'
                          : (message.videoUrl != null
                                ? '[Video]'
                                : (message.audioUrl != null
                                      ? '[Voice]'
                                      : (message.gifUrl != null
                                            ? '[GIF]'
                                            : (message.latitude != null &&
                                                      message.longitude != null
                                                  ? (message.isLiveLocation ==
                                                            true
                                                        ? '[Live Location]'
                                                        : '[Location]')
                                                  : ''))))),
                lastMessageSenderId: message.senderId,
                lastMessageTime: message.createdAt,
                createdAt: now,
                updatedAt: now,
                unreadCounts: {
                  message.senderId: 0,
                  message.receiverId: 1,
                }, // Receiver có 1 unread
                type: 'direct',
              );

              // CRITICAL FIX: Không dùng merge khi tạo conversation mới
              // Merge chỉ dùng khi document đã tồn tại, nếu không sẽ gây lỗi permission
              await _firestore
                  .collection(AppConstants.conversationsCollection)
                  .doc(conversationId)
                  .set(conversation.toMap());

              conversationCreated = true;
              if (kDebugMode) {
                print(
                  '=== Conversation created successfully (attempt ${retryCount + 1})',
                );
              }
              // Đợi một chút để Firestore index conversation mới
              await Future.delayed(const Duration(milliseconds: 300));
            } catch (e, stackTrace) {
              retryCount++;
              if (kDebugMode) {
                print(
                  '=== ERROR creating conversation (attempt $retryCount/$maxRetries): $e',
                );
                print('=== Stack trace: $stackTrace');
              }

              if (retryCount < maxRetries) {
                // Đợi một chút trước khi retry
                await Future.delayed(Duration(milliseconds: 200 * retryCount));
              } else {
                // Đã hết số lần retry, log lỗi nhưng không throw
                if (kDebugMode) {
                  print(
                    '=== Failed to create conversation after $maxRetries attempts',
                  );
                  print(
                    '=== Message was saved successfully, conversation will be recreated in fetchMessages',
                  );
                }
              }
            }
          }
        }
      } catch (e, stackTrace) {
        if (kDebugMode) {
          print('=== ERROR accessing conversation document: $e');
          print('=== Stack trace: $stackTrace');
        }
        // Không throw error - message đã được lưu thành công
        // Conversation sẽ được tạo lại khi fetchMessages được gọi
      }

      // 🔔 Push notification qua server riêng (Render)
      unawaited(
        PushGatewayService.instance.notifyChatMessage(
          messageId: messageId,
          senderId: message.senderId,
          receiverId: message.receiverId,
          conversationId: conversationId,
        ),
      );

      if (kDebugMode) {
        print('=== ✅ sendMessage() RETURNING MESSAGE ID ===');
        print('Message ID: $messageId');
        print('ConversationId: $conversationId');
        print('This ID will be returned to UI');
      }

      return messageId;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('=== ❌ sendMessage() FAILED ===');
        print('Error: $e');
        print('Stack trace: $stackTrace');
        print('Message senderId: ${message.senderId}');
        print('Message receiverId: ${message.receiverId}');
        print('Message content: ${message.content}');
      }
      throw Exception('Send message failed: $e');
    }
  }

  // Send a group message
  Future<String> sendGroupMessage(MessageModel message) async {
    try {
      // Validation: đảm bảo senderId và groupId hợp lệ
      if (message.senderId.isEmpty ||
          message.groupId == null ||
          message.groupId!.isEmpty) {
        throw Exception('Invalid sender ID or group ID');
      }

      // Validation: đảm bảo có nội dung hoặc media hoặc location
      if (message.content.trim().isEmpty &&
          message.imageUrl == null &&
          message.videoUrl == null &&
          message.audioUrl == null &&
          message.gifUrl == null &&
          (message.latitude == null || message.longitude == null)) {
        throw Exception('Message content cannot be empty');
      }

      // Kiểm tra user có trong group không
      final groupDoc = await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(message.groupId!)
          .get();

      if (!groupDoc.exists) {
        throw Exception('Group not found');
      }

      final groupData = groupDoc.data()!;

      // Normalize tất cả IDs để so sánh chính xác
      final normalizeId = (dynamic id) => id.toString().trim();

      // Normalize memberIds to String list to ensure proper comparison
      final rawMemberIds = groupData['memberIds'] ?? [];
      final memberIds = (rawMemberIds as List)
          .map(normalizeId)
          .where((id) => id.isNotEmpty)
          .toList();

      // Normalize senderId and creatorId for comparison
      final normalizedSenderId = normalizeId(message.senderId);
      final rawCreatorId = groupData['creatorId'];
      final creatorId = rawCreatorId != null ? normalizeId(rawCreatorId) : '';

      // Debug logging để kiểm tra
      if (kDebugMode) {
        print('=== Group Message Validation ===');
        print('GroupId: ${message.groupId}');
        print('Raw memberIds: $rawMemberIds');
        print('Normalized memberIds: $memberIds');
        print('Raw senderId: ${message.senderId}');
        print('Normalized senderId: $normalizedSenderId');
        print('Raw creatorId: $rawCreatorId');
        print('Normalized creatorId: $creatorId');
      }

      // Kiểm tra bằng cách so sánh từng phần tử (tránh vấn đề type mismatch)
      bool isMember = false;
      for (final memberId in memberIds) {
        if (normalizeId(memberId) == normalizedSenderId) {
          isMember = true;
          break;
        }
      }

      // Kiểm tra creator
      final isCreator =
          creatorId.isNotEmpty && normalizeId(creatorId) == normalizedSenderId;

      if (kDebugMode) {
        print('IsMember: $isMember');
        print('IsCreator: $isCreator');
        print('===============================');
      }

      if (!isMember && !isCreator) {
        throw Exception('Bạn không phải là thành viên của nhóm này');
      }

      // Nếu creator không có trong memberIds, tự động thêm vào (fix cho nhóm cũ)
      if (isCreator && !isMember) {
        if (kDebugMode) {
          print(
            'Auto-adding creator to memberIds for group ${message.groupId}',
          );
        }
        try {
          await groupDoc.reference.update({
            'memberIds': FieldValue.arrayUnion([normalizedSenderId]),
          });
          if (kDebugMode) {
            print('Successfully added creator to memberIds');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Failed to add creator to memberIds: $e');
          }
          // Không throw error ở đây vì user vẫn là creator và có quyền gửi
        }
      }

      // Tạo hoặc lấy group conversation
      final conversationId = await getOrCreateGroupConversation(
        message.groupId!,
      );

      // Lưu message
      final messageMap = message.toMap();
      messageMap['conversationId'] = conversationId;
      messageMap['content'] = message.content;
      messageMap['nonce'] = null;
      messageMap['status'] = 'sent';

      // CRITICAL FIX: Đảm bảo các trường media/location được giữ lại sau khi modify messageMap
      // Trên Android, Firestore có thể không lưu các trường null, nên cần đảm bảo các trường này được set rõ ràng
      if (message.audioUrl != null && message.audioUrl!.isNotEmpty) {
        messageMap['audioUrl'] = message.audioUrl;
        messageMap['audioDuration'] = message.audioDuration;
      }
      if (message.latitude != null && message.longitude != null) {
        messageMap['latitude'] = message.latitude;
        messageMap['longitude'] = message.longitude;
        messageMap['locationAddress'] = message.locationAddress;
        messageMap['isLiveLocation'] = message.isLiveLocation ?? false;
        if (message.locationExpiresAt != null) {
          messageMap['locationExpiresAt'] = message.locationExpiresAt!
              .toIso8601String();
        }
      }

      // Debug: log message data trước khi lưu
      if (kDebugMode) {
        print('=== PREPARING GROUP MESSAGE FOR FIRESTORE ===');
        print('Message object fields:');
        print('  audioUrl: ${message.audioUrl}');
        print('  latitude: ${message.latitude}');
        print('  longitude: ${message.longitude}');
        print('  locationAddress: ${message.locationAddress}');
        print('  isLiveLocation: ${message.isLiveLocation}');
        print('MessageMap after toMap() and explicit field setting:');
        print('  audioUrl: ${messageMap['audioUrl']}');
        print('  audioDuration: ${messageMap['audioDuration']}');
        print('  latitude: ${messageMap['latitude']}');
        print('  longitude: ${messageMap['longitude']}');
        print('  locationAddress: ${messageMap['locationAddress']}');
        print('  isLiveLocation: ${messageMap['isLiveLocation']}');
        print('  senderId: ${messageMap['senderId']}');
        print('  receiverId: ${messageMap['receiverId']}');
        print('  groupId: ${messageMap['groupId']}');
        print('  conversationId: $conversationId');
        print('All messageMap keys: ${messageMap.keys.toList()}');
        print('Full messageMap: $messageMap');
      }

      String messageId;
      try {
        final docRef = await _firestore
            .collection(AppConstants.messagesCollection)
            .add(messageMap);
        messageId = docRef.id;

        // Debug: log message ID sau khi lưu
        if (kDebugMode) {
          print('Group message saved successfully with ID: $messageId');
        }

        // CRITICAL: Verify and fix data persistence issues on Android
        // On Android, Firestore may drop fields during .add(), so we verify and fix immediately
        // Simplified verification: only one quick check, no aggressive retries to avoid hanging
        bool needsVerification =
            (message.audioUrl != null && message.audioUrl!.isNotEmpty) ||
            (message.latitude != null && message.longitude != null);

        if (needsVerification) {
          try {
            // Wait briefly for Firestore to sync
            await Future.delayed(const Duration(milliseconds: 500));

            // Single verification attempt with timeout protection
            final verifyDoc = await docRef.get().timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                if (kDebugMode) {
                  print('Group message verification timeout - skipping');
                }
                return docRef.get();
              },
            );

            if (verifyDoc.exists) {
              final verifyData = verifyDoc.data()!;
              final updateData = <String, dynamic>{};

              // Check and fix audioUrl
              if (messageMap['audioUrl'] != null &&
                  messageMap['audioUrl'].toString().isNotEmpty &&
                  (verifyData['audioUrl'] == null ||
                      verifyData['audioUrl'].toString().isEmpty)) {
                updateData['audioUrl'] = messageMap['audioUrl'];
                updateData['audioDuration'] = messageMap['audioDuration'];
              }

              // Check and fix location fields
              if (messageMap['latitude'] != null &&
                  verifyData['latitude'] == null) {
                updateData['latitude'] = messageMap['latitude'];
              }
              if (messageMap['longitude'] != null &&
                  verifyData['longitude'] == null) {
                updateData['longitude'] = messageMap['longitude'];
              }
              if (messageMap['locationAddress'] != null &&
                  messageMap['locationAddress'].toString().isNotEmpty &&
                  (verifyData['locationAddress'] == null ||
                      verifyData['locationAddress'].toString().isEmpty)) {
                updateData['locationAddress'] = messageMap['locationAddress'];
              }
              if (messageMap['isLiveLocation'] != null &&
                  verifyData['isLiveLocation'] == null) {
                updateData['isLiveLocation'] = messageMap['isLiveLocation'];
              }
              if (messageMap['locationExpiresAt'] != null &&
                  verifyData['locationExpiresAt'] == null) {
                updateData['locationExpiresAt'] =
                    messageMap['locationExpiresAt'];
              }

              // Apply fix if needed (single attempt, no retries)
              if (updateData.isNotEmpty) {
                try {
                  await docRef
                      .set(updateData, SetOptions(merge: true))
                      .timeout(const Duration(seconds: 3));
                  if (kDebugMode) {
                    print('Fixed missing fields in group message document');
                  }
                } catch (updateError) {
                  if (kDebugMode) {
                    print(
                      'Failed to fix group message document (non-critical): $updateError',
                    );
                  }
                  // Don't throw - message was already saved successfully
                }
              }
            }
          } catch (verifyError) {
            if (kDebugMode) {
              print(
                'Group message verification error (non-critical): $verifyError',
              );
            }
            // Don't throw - message was already saved successfully
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('ERROR saving group message to Firestore: $e');
          print('Message data that failed to save:');
          print('  audioUrl: ${messageMap['audioUrl']}');
          print('  latitude: ${messageMap['latitude']}');
          print('  longitude: ${messageMap['longitude']}');
          print('  senderId: ${messageMap['senderId']}');
          print('  receiverId: ${messageMap['receiverId']}');
          print('  groupId: ${messageMap['groupId']}');
        }
        rethrow;
      }

      // Cập nhật conversation
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (conversationDoc.exists) {
        final data = conversationDoc.data()!;
        final currentUnreadCounts = Map<String, int>.from(
          data['unreadCounts'] ?? {},
        );

        // Tăng unread count cho tất cả members trừ sender
        for (final memberId in memberIds) {
          if (memberId != message.senderId) {
            currentUnreadCounts[memberId] =
                (currentUnreadCounts[memberId] ?? 0) + 1;
          }
        }

        await conversationDoc.reference.update({
          'lastMessageId': messageId,
          'lastMessageContent': message.content.isNotEmpty
              ? message.content
              : (message.imageUrl != null
                    ? '[Ảnh]'
                    : (message.videoUrl != null
                          ? '[Video]'
                          : (message.audioUrl != null
                                ? '[Voice]'
                                : (message.gifUrl != null
                                      ? '[GIF]'
                                      : (message.latitude != null &&
                                                message.longitude != null
                                            ? (message.isLiveLocation == true
                                                  ? '[Live Location]'
                                                  : '[Location]')
                                            : ''))))),
          'lastMessageNonce': null,
          'lastMessageSenderId': message.senderId,
          'lastMessageTime': message.createdAt.toIso8601String(),
          'unreadCounts': currentUnreadCounts,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }

      // 🔔 Push notification group qua server riêng (Render)
      unawaited(
        PushGatewayService.instance.notifyGroupMessage(
          messageId: messageId,
          senderId: message.senderId,
          groupId: message.groupId!,
          conversationId: conversationId,
        ),
      );

      return messageId;
    } catch (e) {
      throw Exception('Send group message failed: $e');
    }
  }

  Future<bool> _canSendDirect({
    required String senderId,
    required String receiverId,
    required String receiverSetting,
  }) async {
    if (receiverSetting == 'everyone') return true;

    // Kiểm tra bạn bè
    final friends = await _friendService.getFriends(receiverId);
    final isFriend = friends.contains(senderId);

    if (receiverSetting == 'friends') {
      return isFriend;
    }

    if (receiverSetting == 'friends_of_friends') {
      // MVP: coi như chỉ bạn bè; có thể mở rộng friend-of-friend sau
      return isFriend;
    }

    // custom -> không cho direct
    return false;
  }

  Future<bool> _isBlocked({
    required String senderId,
    required String receiverId,
  }) async {
    // check if receiver blocked sender or sender blocked receiver
    final blocks = _firestore.collection(AppConstants.blocksCollection);
    final incoming = await blocks
        .where('blockerId', isEqualTo: receiverId)
        .where('blockedId', isEqualTo: senderId)
        .limit(1)
        .get();
    if (incoming.docs.isNotEmpty) return true;

    final outgoing = await blocks
        .where('blockerId', isEqualTo: senderId)
        .where('blockedId', isEqualTo: receiverId)
        .limit(1)
        .get();
    return outgoing.docs.isNotEmpty;
  }

  Future<MessageModel> _mapDecrypted(
    String id,
    Map<String, dynamic> data, {
    required String keyId,
  }) async {
    try {
      // Không giải mã nữa, vì đang lưu plaintext (nonce = null)
      return MessageModel.fromMap(id, data);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('ERROR in _mapDecrypted for message $id: $e');
        print('Stack trace: $stackTrace');
      }
      // Re-throw to be handled by caller
      rethrow;
    }
  }

  // Typing indicator: set typing status for current user
  Future<void> setTyping({
    required String conversationId,
    required String userId,
    required bool isTyping,
  }) async {
    if (conversationId.isEmpty || userId.isEmpty) return;
    try {
      final ref = _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .collection('typing')
          .doc(userId);
      await ref.set({
        'isTyping': isTyping,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {
      // không throw để tránh gián đoạn UI
    }
  }

  // Listen typing status of a user in a conversation
  Stream<bool> typingStatus(String conversationId, String userId) {
    if (conversationId.isEmpty || userId.isEmpty) {
      return const Stream<bool>.empty();
    }
    return _firestore
        .collection(AppConstants.conversationsCollection)
        .doc(conversationId)
        .collection('typing')
        .doc(userId)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return false;
          final data = snap.data();
          return (data?['isTyping'] as bool?) ?? false;
        });
  }

  // Stream tin nhắn đến mới nhất cho user (dùng để hiển thị toast in-app)
  Stream<MessageModel?> latestIncoming(
    String userId, {
    String? excludeConversationId,
  }) {
    if (userId.isEmpty) return const Stream<MessageModel?>.empty();

    return _firestore
        .collection(AppConstants.messagesCollection)
        .where('receiverId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final conversationId = data['conversationId'] as String?;
            if (excludeConversationId != null &&
                conversationId == excludeConversationId) {
              continue;
            }
            // Bỏ qua nếu đã thu hồi
            final isRecalled = data['isRecalled'] as bool? ?? false;
            if (isRecalled) continue;
            return MessageModel.fromMap(doc.id, data);
          }
          return null;
        });
  }

  // Tìm kiếm tin nhắn trong một conversation (lọc client sau khi lấy về)
  Future<List<MessageModel>> searchMessages({
    required String conversationId,
    required String query,
    int limit = 100,
  }) async {
    if (conversationId.isEmpty || query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();

    final snapshot = await _firestore
        .collection(AppConstants.messagesCollection)
        .where('conversationId', isEqualTo: conversationId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    final matches = <MessageModel>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final msg = MessageModel.fromMap(doc.id, data);
      if (msg.isRecalled) continue;
      final text = msg.content.toLowerCase();
      final hasText = text.contains(q);
      final isImage = msg.imageUrl != null && '[ảnh]'.contains(q);
      final isVideo = msg.videoUrl != null && '[video]'.contains(q);
      final isAudio = msg.audioUrl != null && '[voice]'.contains(q);
      if (hasText || isImage || isVideo || isAudio) {
        matches.add(msg);
      }
    }
    return matches;
  }

  String _requestKey(String a, String b) {
    final parts = [a, b]..sort();
    return 'request_${parts.join('_')}';
  }

  // Verify that a message exists in Firestore (for ensuring persistence)
  // Also verifies that the message can be queried by conversationId (critical for persistence)
  Future<bool> verifyMessageExists(
    String messageId, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 500),
    String? conversationId,
  }) async {
    if (messageId.isEmpty) return false;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // First check: verify document exists
        final doc = await _firestore
            .collection(AppConstants.messagesCollection)
            .doc(messageId)
            .get();

        if (!doc.exists) {
          if (attempt < maxRetries) {
            await Future.delayed(retryDelay);
            continue;
          }
          if (kDebugMode) {
            print(
              '=== WARNING: Message $messageId not found in Firestore after $maxRetries attempts',
            );
          }
          return false;
        }

        // Second check: if conversationId is provided, verify message can be queried by it
        // This is critical because messages might exist but not be queryable if conversation was recreated
        if (conversationId != null && conversationId.isNotEmpty) {
          final data = doc.data();
          final msgConversationId = data?['conversationId'] as String?;

          if (msgConversationId != conversationId) {
            if (kDebugMode) {
              print(
                '=== WARNING: Message $messageId has conversationId mismatch: expected $conversationId, got $msgConversationId',
              );
            }
            // This is a critical issue - message exists but conversationId doesn't match
            // Try to fix it by updating the message
            try {
              await doc.reference.update({'conversationId': conversationId});
              if (kDebugMode) {
                print(
                  '=== Fixed conversationId mismatch for message $messageId',
                );
              }
            } catch (e) {
              if (kDebugMode) {
                print('=== ERROR fixing conversationId mismatch: $e');
              }
            }
          }

          // Verify message can be queried by conversationId
          // This ensures the message will be found when fetching messages
          final querySnapshot = await _firestore
              .collection(AppConstants.messagesCollection)
              .where('conversationId', isEqualTo: conversationId)
              .where(FieldPath.documentId, isEqualTo: messageId)
              .limit(1)
              .get();

          if (querySnapshot.docs.isEmpty) {
            if (kDebugMode) {
              print(
                '=== WARNING: Message $messageId exists but cannot be queried by conversationId $conversationId',
              );
              print(
                '=== This may indicate a Firestore indexing delay - will retry',
              );
            }
            if (attempt < maxRetries) {
              await Future.delayed(retryDelay);
              continue;
            }
            // Even if query fails, document exists, so return true
            // The backup query in fetchMessages should find it
            if (kDebugMode) {
              print(
                '=== Message exists but query failed - backup query should find it',
              );
            }
            return true;
          }
        }

        if (kDebugMode && attempt > 1) {
          print('=== Message verified after $attempt attempts: $messageId');
        }
        return true;
      } catch (e) {
        if (kDebugMode) {
          print(
            '=== Error verifying message $messageId (attempt $attempt/$maxRetries): $e',
          );
        }
        if (attempt < maxRetries) {
          await Future.delayed(retryDelay);
        }
      }
    }

    if (kDebugMode) {
      print(
        '=== WARNING: Message $messageId not found in Firestore after $maxRetries attempts',
      );
    }
    return false;
  }

  // Get messages between two users - Bảo mật: chỉ trả về tin nhắn của user hiện tại
  Stream<List<MessageModel>> getMessages(String userId1, String userId2) {
    // Validate: cả 2 userId phải khác null và không rỗng
    if (userId1.isEmpty || userId2.isEmpty || userId1 == userId2) {
      return Stream.value([]);
    }

    final participants = [userId1, userId2]..sort();
    final conversationId = participants.join('_');

    if (kDebugMode) {
      print('=== GETTING MESSAGES ===');
      print('ConversationId: $conversationId');
      print('UserId1: $userId1');
      print('UserId2: $userId2');
      print('Using real-time stream from Firestore');
    }

    // Helper function để đảm bảo conversation tồn tại
    Future<void> ensureConversationExists() async {
      try {
        final conversationDoc = await _firestore
            .collection(AppConstants.conversationsCollection)
            .doc(conversationId)
            .get();

        if (!conversationDoc.exists) {
          if (kDebugMode) {
            print(
              '=== WARNING: Conversation $conversationId does not exist, recreating...',
            );
            print('=== UserId1: $userId1, UserId2: $userId2');
          }

          int retryCount = 0;
          const maxRetries = 2;

          while (retryCount < maxRetries) {
            try {
              // Kiểm tra lại xem conversation đã được tạo bởi user khác chưa
              final checkDoc = await _firestore
                  .collection(AppConstants.conversationsCollection)
                  .doc(conversationId)
                  .get();

              if (checkDoc.exists) {
                if (kDebugMode) {
                  print(
                    '=== Conversation already exists (created by another user or retry)',
                  );
                }

                // CRITICAL: Nếu conversation đã tồn tại và có deletedBy,
                // xóa deletedBy để người dùng có thể thấy lại conversation và messages
                final existingData =
                    checkDoc.data() as Map<String, dynamic>? ?? {};
                final deletedBy = List<String>.from(
                  existingData['deletedBy'] ?? [],
                );

                if (deletedBy.isNotEmpty) {
                  if (kDebugMode) {
                    print(
                      '=== Conversation has deletedBy: $deletedBy, clearing it to restore conversation',
                    );
                  }

                  // CRITICAL: Chỉ xóa deletedBy khỏi conversation để người dùng có thể thấy lại conversation
                  // KHÔNG xóa deletedBy khỏi messages để messages cũ vẫn bị ẩn
                  // Điều này đảm bảo khi tạo lại conversation, người dùng không thấy messages cũ
                  await checkDoc.reference.update({
                    'deletedBy': [],
                    'updatedAt': DateTime.now().toIso8601String(),
                  });

                  if (kDebugMode) {
                    print(
                      '=== Cleared deletedBy from conversation (messages keep their deletedBy)',
                    );
                  }
                }

                break;
              }

              // Tạo conversation mới
              final now = DateTime.now();
              final participants = [userId1, userId2]..sort();
              final conversation = ConversationModel(
                id: conversationId,
                participantIds: participants,
                lastMessageTime: now,
                createdAt: now,
                updatedAt: now,
                unreadCounts: {userId1: 0, userId2: 0},
                type: 'direct',
              );

              // CRITICAL FIX: Không dùng merge khi tạo conversation mới
              // Merge chỉ dùng khi document đã tồn tại, nếu không sẽ gây lỗi permission
              await _firestore
                  .collection(AppConstants.conversationsCollection)
                  .doc(conversationId)
                  .set(conversation.toMap());

              if (kDebugMode) {
                print(
                  '=== Conversation recreated successfully (attempt ${retryCount + 1})',
                );
              }
              break;
            } catch (e, stackTrace) {
              retryCount++;
              if (kDebugMode) {
                print(
                  '=== ERROR recreating conversation (attempt $retryCount/$maxRetries): $e',
                );
                print('=== Stack trace: $stackTrace');
              }

              if (retryCount < maxRetries) {
                await Future.delayed(Duration(milliseconds: 200 * retryCount));
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('=== ERROR ensuring conversation exists: $e');
        }
      }
    }

    // Helper function để process messages từ snapshot
    Future<List<MessageModel>> processMessages(
      List<QueryDocumentSnapshot> docs,
    ) async {
      // Filter: chỉ trả về tin nhắn mà user hiện tại là sender hoặc receiver
      final filtered = docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final senderId = data['senderId'] as String? ?? '';
        final receiverId = data['receiverId'] as String? ?? '';

        final isValid =
            (senderId == userId1 || senderId == userId2) &&
            (receiverId == userId1 || receiverId == userId2) &&
            senderId != receiverId;

        return isValid;
      });

      final result = <MessageModel>[];
      for (final doc in filtered) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        try {
          final message = await _mapDecrypted(
            doc.id,
            data,
            keyId: conversationId,
          );

          // CRITICAL: Ẩn tin nhắn đã bị xóa bởi user đang xem (currentUserId = userId1)
          // ChatScreen luôn gọi getMessages(currentUser.id, otherUser.id)
          // nên userId1 chính là user đang xem màn hình chat hiện tại.
          final deletedBy = message.deletedBy;
          if (deletedBy.contains(userId1)) {
            // Message đã bị user hiện tại xóa, không hiển thị cho user này
            continue;
          }

          // User còn lại (userId2) vẫn sẽ thấy message nếu họ không nằm trong deletedBy
          result.add(message);
        } catch (e, stackTrace) {
          if (kDebugMode) {
            print('ERROR parsing message ${doc.id}: $e');
            print('Stack trace: $stackTrace');
          }
        }
      }

      // Sort by createdAt descending (most recent first)
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return result;
    }

    // Helper function để fetch messages bằng backup query (khi stream không hoạt động)
    Future<List<MessageModel>> fetchMessagesBackup() async {
      try {
        // Đảm bảo conversation tồn tại trước khi query messages
        // CRITICAL: Gọi ensureConversationExists() trước khi query để tránh PERMISSION_DENIED
        await ensureConversationExists();

        // Query bằng conversationId (chính)
        QuerySnapshot? snapshot;
        try {
          snapshot = await _firestore
              .collection(AppConstants.messagesCollection)
              .where('conversationId', isEqualTo: conversationId)
              .get();
        } catch (e) {
          if (kDebugMode) {
            print('=== BACKUP: Query by conversationId failed: $e');
          }
          snapshot = null;
        }

        // Backup query: nếu không có kết quả, thử query bằng senderId và receiverId
        List<QueryDocumentSnapshot> allDocs =
            snapshot?.docs ?? <QueryDocumentSnapshot>[];
        if (allDocs.isEmpty || snapshot == null) {
          try {
            final query1 = await _firestore
                .collection(AppConstants.messagesCollection)
                .where('senderId', isEqualTo: userId1)
                .where('receiverId', isEqualTo: userId2)
                .get();

            final query2 = await _firestore
                .collection(AppConstants.messagesCollection)
                .where('senderId', isEqualTo: userId2)
                .where('receiverId', isEqualTo: userId1)
                .get();

            allDocs = <QueryDocumentSnapshot>[];
            allDocs.addAll(query1.docs);
            allDocs.addAll(query2.docs);

            // Remove duplicates
            final uniqueDocs = <String, QueryDocumentSnapshot>{};
            for (final doc in allDocs) {
              uniqueDocs[doc.id] = doc;
            }
            allDocs = uniqueDocs.values.toList();
          } catch (e) {
            if (kDebugMode) {
              print('=== BACKUP: Backup query failed: $e');
            }
            allDocs = <QueryDocumentSnapshot>[];
          }
        }

        return await processMessages(allDocs);
      } catch (e) {
        if (kDebugMode) {
          print('=== BACKUP ERROR: $e');
        }
        return <MessageModel>[];
      }
    }

    if (kDebugMode) {
      print(
        '=== STREAM SETUP: Creating stream for conversationId: $conversationId',
      );
      print('=== STREAM SETUP: UserId1: $userId1, UserId2: $userId2');
    }

    // Sử dụng stream thực từ Firestore thay vì polling
    // Không dùng orderBy để tránh lỗi index, sẽ sort ở client-side
    // CRITICAL: Sử dụng .listen() để đảm bảo stream được listen đúng cách
    final streamController = StreamController<List<MessageModel>>();

    // CRITICAL FIX: Đảm bảo conversation tồn tại trước khi listen stream
    // Gọi ensureConversationExists() và đợi nó hoàn thành trước khi listen
    ensureConversationExists()
        .then((_) {
          if (kDebugMode) {
            print('=== Conversation ensured, starting stream listener');
          }
        })
        .catchError((e) {
          if (kDebugMode) {
            print('=== ERROR ensuring conversation before stream: $e');
          }
        });

    // Listen stream và forward events
    // CRITICAL: Stream sẽ được listen ngay, nhưng conversation đã được đảm bảo tồn tại
    // Nếu conversation chưa tồn tại, ensureConversationExists() sẽ tạo nó
    final subscription = _firestore
        .collection(AppConstants.messagesCollection)
        .where('conversationId', isEqualTo: conversationId)
        .snapshots()
        .listen(
          (snapshot) async {
            try {
              if (kDebugMode) {
                print('=== STREAM: Received snapshot update');
                print(
                  '=== STREAM: Snapshot metadata - hasPendingWrites: ${snapshot.metadata.hasPendingWrites}, isFromCache: ${snapshot.metadata.isFromCache}',
                );
                print(
                  '=== STREAM: Document changes - ${snapshot.docChanges.length} changes',
                );
                for (final change in snapshot.docChanges) {
                  print(
                    '=== STREAM: Change type: ${change.type}, docId: ${change.doc.id}',
                  );
                  if (change.type == DocumentChangeType.added) {
                    final data = change.doc.data();
                    if (data is Map<String, dynamic>) {
                      print(
                        '=== STREAM: Added message - senderId: ${data['senderId']}, receiverId: ${data['receiverId']}, conversationId: ${data['conversationId']}',
                      );
                    }
                  }
                }
                print('=== STREAM: Total documents: ${snapshot.docs.length}');
                if (snapshot.docs.isNotEmpty) {
                  print(
                    '=== STREAM: Message IDs: ${snapshot.docs.map((d) => d.id).toList()}',
                  );
                }
              }

              // Process messages từ snapshot
              final messages = await processMessages(snapshot.docs);

              if (kDebugMode) {
                print('=== STREAM: Processed ${messages.length} messages');
                if (messages.isNotEmpty) {
                  print(
                    '=== STREAM: Latest message - ID: ${messages.first.id}, content: "${messages.first.content.length > 30 ? messages.first.content.substring(0, 30) + "..." : messages.first.content}", createdAt: ${messages.first.createdAt}',
                  );
                  print(
                    '=== STREAM: All message IDs in this update: ${messages.map((m) => m.id).toList()}',
                  );
                } else {
                  print('=== STREAM: ⚠️ No messages found in snapshot!');
                  print('=== STREAM: Query conversationId: $conversationId');
                  print(
                    '=== STREAM: Snapshot docs count: ${snapshot.docs.length}',
                  );
                  if (snapshot.docs.isNotEmpty) {
                    print(
                      '=== STREAM: Raw docs conversationIds: ${snapshot.docs.map((d) => (d.data() as Map<String, dynamic>?)?['conversationId']).toList()}',
                    );
                  }
                }
              }

              if (!streamController.isClosed) {
                if (kDebugMode) {
                  print(
                    '=== STREAM: ✅ Emitting ${messages.length} messages to UI',
                  );
                }
                streamController.add(messages);
              } else {
                if (kDebugMode) {
                  print(
                    '=== STREAM: ⚠️ Controller is closed, cannot emit messages',
                  );
                }
              }
            } catch (error, stackTrace) {
              if (kDebugMode) {
                print('=== STREAM ERROR in listener: $error');
                print('=== Stack trace: $stackTrace');
                print('=== Falling back to backup query');
              }
              // Fallback: nếu xử lý snapshot thất bại, thử backup query
              try {
                final backupMessages = await fetchMessagesBackup();
                if (!streamController.isClosed) {
                  streamController.add(backupMessages);
                }
              } catch (e) {
                if (kDebugMode) {
                  print('=== BACKUP QUERY ALSO FAILED: $e');
                }
                if (!streamController.isClosed) {
                  streamController.addError(e);
                }
              }
            }
          },
          onError: (error) {
            if (kDebugMode) {
              print('=== STREAM ERROR in snapshots(): $error');
            }
            if (!streamController.isClosed) {
              streamController.addError(error);
            }
          },
          cancelOnError: false, // Không tự động cancel khi có lỗi
        );

    // Cleanup khi stream controller đóng
    streamController.onCancel = () {
      if (kDebugMode) {
        print('=== STREAM: Controller cancelled, cancelling subscription');
      }
      subscription.cancel();
    };

    return streamController.stream;
  }

  /// Stream một message theo id - dùng cho Live Location UI
  Stream<MessageModel?> watchMessageById(String messageId) {
    if (messageId.isEmpty) {
      return const Stream.empty();
    }

    return _firestore
        .collection(AppConstants.messagesCollection)
        .doc(messageId)
        .snapshots()
        .asyncMap((snapshot) async {
          if (!snapshot.exists) return null;
          final data = snapshot.data();
          if (data == null) return null;

          try {
            final conversationId = (data['conversationId'] as String?) ?? '';
            final msg = await _mapDecrypted(
              snapshot.id,
              data,
              keyId: conversationId,
            );
            return msg;
          } catch (e, stackTrace) {
            if (kDebugMode) {
              print('ERROR parsing message in watchMessageById: $e');
              print('Stack trace: $stackTrace');
            }
            return null;
          }
        });
  }

  // Remove member from group conversation
  Future<void> removeMemberFromGroupConversation(
    String groupId,
    String memberId,
  ) async {
    try {
      final conversationId = 'group_$groupId';
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) return;

      final data = conversationDoc.data()!;
      final participantIds = List<String>.from(data['participantIds'] ?? []);
      final unreadCounts = Map<String, int>.from(data['unreadCounts'] ?? {});

      // Xóa member khỏi participantIds và unreadCounts
      participantIds.remove(memberId);
      unreadCounts.remove(memberId);

      await conversationDoc.reference.update({
        'participantIds': participantIds,
        'unreadCounts': unreadCounts,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Log error nhưng không throw để tránh ảnh hưởng đến việc xóa member
      print('Error updating conversation after member removal: $e');
    }
  }

  // Add member to group conversation
  Future<void> addMemberToGroupConversation(
    String groupId,
    String memberId,
  ) async {
    try {
      final conversationId = 'group_$groupId';
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        // Nếu conversation chưa tồn tại, tạo mới
        await getOrCreateGroupConversation(groupId);
        return;
      }

      final data = conversationDoc.data()!;
      final participantIds = List<String>.from(data['participantIds'] ?? []);
      final unreadCounts = Map<String, int>.from(data['unreadCounts'] ?? {});

      // Thêm member vào participantIds và unreadCounts nếu chưa có
      if (!participantIds.contains(memberId)) {
        participantIds.add(memberId);
        unreadCounts[memberId] = 0;
      }

      await conversationDoc.reference.update({
        'participantIds': participantIds,
        'unreadCounts': unreadCounts,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Log error nhưng không throw để tránh ảnh hưởng đến việc thêm member
      print('Error updating conversation after member addition: $e');
    }
  }

  // Get group messages
  Stream<List<MessageModel>> getGroupMessages(
    String groupId,
    String currentUserId,
  ) {
    if (groupId.isEmpty || currentUserId.isEmpty) {
      return Stream.value([]);
    }

    final conversationId = 'group_$groupId';

    // On Windows, use polling instead of .snapshots() for better compatibility
    if (kDebugMode) {
      print('=== getGroupMessages ===');
      print('Using polling approach for Windows compatibility');
    }

    Future<List<MessageModel>> fetchGroupMessages() async {
      try {
        // Validation: chỉ trả về tin nhắn của group mà user là member
        final groupDoc = await _firestore
            .collection(AppConstants.groupsCollection)
            .doc(groupId)
            .get();

        if (!groupDoc.exists) {
          if (kDebugMode) {
            print('Group not found: $groupId');
          }
          return [];
        }

        final groupData = groupDoc.data()!;
        final memberIds = List<String>.from(groupData['memberIds'] ?? []);

        if (!memberIds.contains(currentUserId)) {
          if (kDebugMode) {
            print('User $currentUserId is not a member of group $groupId');
          }
          return [];
        }

        // Query messages with orderBy to ensure proper ordering
        // Note: This requires a Firestore composite index on (groupId, createdAt)
        // If index doesn't exist, fallback to query without orderBy
        QuerySnapshot snapshot;
        try {
          snapshot = await _firestore
              .collection(AppConstants.messagesCollection)
              .where('groupId', isEqualTo: groupId)
              .orderBy('createdAt', descending: true)
              .limit(100) // Limit to most recent 100 messages
              .get();
        } catch (e) {
          // Fallback if composite index doesn't exist
          if (kDebugMode) {
            print('OrderBy query failed (likely missing index), using fallback: $e');
          }
          snapshot = await _firestore
              .collection(AppConstants.messagesCollection)
              .where('groupId', isEqualTo: groupId)
              .get();
        }

        if (kDebugMode) {
          print('Fetched group messages: ${snapshot.docs.length} documents');
        }

        final result = <MessageModel>[];
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) continue;
          
          // Debug: log raw data từ Firestore
          if (kDebugMode) {
            print('Reading group message from Firestore: id=${doc.id}');
            print('  audioUrl: ${data['audioUrl']}');
            print('  latitude: ${data['latitude']}');
            print('  longitude: ${data['longitude']}');
            print('  locationAddress: ${data['locationAddress']}');
          }
          try {
            final message = await _mapDecrypted(doc.id, data, keyId: conversationId);
            // Skip messages that are recalled or deleted by current user
            if (!message.isRecalled && 
                !message.deletedBy.contains(currentUserId)) {
              result.add(message);
            }
          } catch (e, stackTrace) {
            // Skip messages that fail to parse instead of crashing
            if (kDebugMode) {
              print('ERROR parsing group message ${doc.id}: $e');
              print('Stack trace: $stackTrace');
            }
            // Continue processing other messages
          }
        }

        // Messages are already sorted by orderBy (descending), but reverse to show oldest first in UI
        // (UI displays in reverse order with ListView.reverse: true)
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        return result;
      } catch (e) {
        if (kDebugMode) {
          print('ERROR fetching group messages: $e');
        }
        return <MessageModel>[];
      }
    }

    // Use StreamController for polling
    final controller = StreamController<List<MessageModel>>();
    List<String>?
    _lastGroupMessageIds; // Cache để so sánh và tránh emit không cần thiết

    // Helper function để check nếu messages thay đổi
    bool _hasGroupMessagesChanged(List<MessageModel> newMessages) {
      final newIds = newMessages.map((m) => m.id).toList()..sort();
      if (_lastGroupMessageIds == null) return true;
      if (newIds.length != _lastGroupMessageIds!.length) return true;
      for (int i = 0; i < newIds.length; i++) {
        if (newIds[i] != _lastGroupMessageIds![i]) return true;
      }
      return false;
    }

    // Fetch immediately
    fetchGroupMessages()
        .then((messages) {
          if (!controller.isClosed) {
            _lastGroupMessageIds = messages.map((m) => m.id).toList()..sort();
            controller.add(messages);
          }
        })
        .catchError((error) {
          if (!controller.isClosed) {
            if (kDebugMode) {
              print('ERROR in initial group messages fetch: $error');
            }
            controller.addError(error);
          }
        });

    // Then poll every 500ms for messages (more responsive for new messages)
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      fetchGroupMessages()
          .then((messages) {
            if (!controller.isClosed) {
              // Chỉ emit nếu messages thực sự thay đổi
              if (_hasGroupMessagesChanged(messages)) {
                _lastGroupMessageIds = messages.map((m) => m.id).toList()
                  ..sort();
                controller.add(messages);
              }
            } else {
              timer.cancel();
            }
          })
          .catchError((error) {
            if (!controller.isClosed) {
              if (kDebugMode) {
                print('ERROR in periodic group messages fetch: $error');
              }
              controller.addError(error);
            } else {
              timer.cancel();
            }
          });
    });

    return controller.stream;
  }

  // Get messages by conversation ID - Bảo mật: cần userId để validate
  Stream<List<MessageModel>> getMessagesByConversationId(
    String conversationId,
    String currentUserId,
  ) {
    if (conversationId.isEmpty || currentUserId.isEmpty) {
      return Stream.value([]);
    }

    return _firestore
        .collection(AppConstants.messagesCollection)
        .where('conversationId', isEqualTo: conversationId)
        .snapshots()
        .asyncMap((snapshot) async {
          // Validation: chỉ trả về tin nhắn mà currentUserId là sender hoặc receiver
          final filtered = snapshot.docs.where((doc) {
            final data = doc.data();
            final senderId = data['senderId'] as String? ?? '';
            final receiverId = data['receiverId'] as String? ?? '';
            return senderId == currentUserId || receiverId == currentUserId;
          });
          final result = <MessageModel>[];
          for (final doc in filtered) {
            final data = doc.data();
            // Debug: log raw data từ Firestore
            if (kDebugMode) {
              print(
                'Reading message by conversationId from Firestore: id=${doc.id}',
              );
              print('  audioUrl: ${data['audioUrl']}');
              print('  latitude: ${data['latitude']}');
              print('  longitude: ${data['longitude']}');
              print('  locationAddress: ${data['locationAddress']}');
            }
            try {
              result.add(
                await _mapDecrypted(doc.id, data, keyId: conversationId),
              );
            } catch (e, stackTrace) {
              // Skip messages that fail to parse instead of crashing
              if (kDebugMode) {
                print('ERROR parsing message ${doc.id}: $e');
                print('Stack trace: $stackTrace');
              }
              // Continue processing other messages
            }
          }

          // Sort by createdAt descending (most recent first)
          result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          // Limit to 50 most recent messages
          if (result.length > 50) {
            return result.take(50).toList();
          }

          return result;
        });
  }

  // Get conversations for a user - Bảo mật: chỉ trả về conversations của user hiện tại
  Stream<List<ConversationModel>> getConversations(String userId) {
    if (userId.isEmpty) {
      return Stream.value([]);
    }

    // On Windows, use polling instead of .snapshots() for better compatibility
    if (kDebugMode) {
      print('=== getConversations ===');
      print('Using polling approach for Windows compatibility');
    }

    Future<List<ConversationModel>> fetchConversations() async {
      try {
        final snapshot = await _firestore
            .collection(AppConstants.conversationsCollection)
            .where('participantIds', arrayContains: userId)
            .orderBy('lastMessageTime', descending: true)
            .get();

        if (kDebugMode) {
          print('Fetched conversations: ${snapshot.docs.length} documents');
        }

        final result = <ConversationModel>[];
        for (final doc in snapshot.docs) {
          final data = doc.data();

          // CRITICAL: Filter ra những conversation đã bị user hiện tại xóa
          final deletedBy = List<String>.from(data['deletedBy'] ?? []);
          if (deletedBy.contains(userId)) {
            // Conversation đã bị user này xóa, bỏ qua
            if (kDebugMode) {
              print('=== Skipping conversation ${doc.id} - deleted by $userId');
            }
            continue;
          }

          final cipher = data['lastMessageContent'] as String?;
          final nonce = data['lastMessageNonce'] as String?;
          if (cipher != null && nonce != null) {
            try {
              final plain = await _encryptionService.decrypt(
                cipherText: cipher,
                nonce: nonce,
                keyId: doc.id,
              );
              final cloned = Map<String, dynamic>.from(data);
              cloned['lastMessageContent'] = plain;
              result.add(ConversationModel.fromMap(doc.id, cloned));
              continue;
            } catch (_) {
              // fallback: dùng ciphertext nếu lỗi
            }
          }
          result.add(ConversationModel.fromMap(doc.id, data));
        }
        return result;
      } catch (e) {
        if (kDebugMode) {
          print('ERROR fetching conversations: $e');
        }
        return <ConversationModel>[];
      }
    }

    // Use StreamController for polling
    final controller = StreamController<List<ConversationModel>>();

    // Fetch immediately
    fetchConversations()
        .then((conversations) {
          if (!controller.isClosed) {
            controller.add(conversations);
          }
        })
        .catchError((error) {
          if (!controller.isClosed) {
            if (kDebugMode) {
              print('ERROR in initial conversations fetch: $error');
            }
            controller.addError(error);
          }
        });

    // Then poll every 3 seconds
    Timer.periodic(const Duration(seconds: 3), (timer) {
      fetchConversations()
          .then((conversations) {
            if (!controller.isClosed) {
              controller.add(conversations);
            } else {
              timer.cancel();
            }
          })
          .catchError((error) {
            if (!controller.isClosed) {
              if (kDebugMode) {
                print('ERROR in periodic conversations fetch: $error');
              }
              controller.addError(error);
            } else {
              timer.cancel();
            }
          });
    });

    return controller.stream;
  }

  // Mark messages as read in a conversation - Bảo mật: chỉ user nhận mới đánh dấu
  Future<void> markConversationAsRead(
    String conversationId,
    String userId,
  ) async {
    try {
      // Validation
      if (conversationId.isEmpty || userId.isEmpty) {
        return;
      }

      // Reset unread count - chỉ nếu user là participant
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (conversationDoc.exists) {
        final data = conversationDoc.data()!;
        final participants = List<String>.from(data['participantIds'] ?? []);

        // Chỉ cho phép nếu userId là participant
        if (participants.contains(userId)) {
          final unreadCounts = Map<String, int>.from(
            data['unreadCounts'] ?? {},
          );
          unreadCounts[userId] = 0;

          await conversationDoc.reference.update({
            'unreadCounts': unreadCounts,
          });
        }
      }

      // Mark all messages as read - chỉ tin nhắn mà user là receiver
      final messagesQuery = await _firestore
          .collection(AppConstants.messagesCollection)
          .where('conversationId', isEqualTo: conversationId)
          .where('receiverId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in messagesQuery.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Mark conversation as read failed: $e');
    }
  }

  // Mark message as read - Bảo mật: chỉ receiver mới đánh dấu được
  Future<void> markAsRead(String messageId, String userId) async {
    try {
      if (messageId.isEmpty || userId.isEmpty) {
        return;
      }

      // Kiểm tra message tồn tại và user là receiver
      final messageDoc = await _firestore
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .get();

      if (messageDoc.exists) {
        final data = messageDoc.data()!;
        final receiverId = data['receiverId'] as String? ?? '';

        // Chỉ cho phép nếu userId là receiver
        if (receiverId == userId) {
          await messageDoc.reference.update({
            'isRead': true,
            'status': 'read',
            'readAt': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (e) {
      throw Exception('Mark as read failed: $e');
    }
  }

  // Đánh dấu đã nhận (delivered) cho tin nhắn - chỉ receiver có thể đánh dấu
  Future<void> markAsDelivered(String messageId, String userId) async {
    try {
      if (messageId.isEmpty || userId.isEmpty) return;

      final messageDoc = await _firestore
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .get();

      if (!messageDoc.exists) return;
      final data = messageDoc.data()!;
      final receiverId = data['receiverId'] as String? ?? '';
      final status = data['status'] as String? ?? 'sent';

      if (receiverId == userId && status == 'sent') {
        await messageDoc.reference.update({
          'status': 'delivered',
          'deliveredAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      // không throw để tránh gián đoạn hiển thị
    }
  }

  // Thêm reaction cho tin nhắn (toggle: nếu đã chọn emoji đó thì bỏ)
  Future<void> reactToMessage({
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    if (messageId.isEmpty || userId.isEmpty || emoji.isEmpty) return;

    await _firestore.runTransaction((transaction) async {
      final ref = _firestore
          .collection(AppConstants.messagesCollection)
          .doc(messageId);
      final snap = await transaction.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final senderId = data['senderId'] as String? ?? '';
      final receiverId = data['receiverId'] as String? ?? '';

      // Chỉ sender hoặc receiver mới được reaction
      if (userId != senderId && userId != receiverId) return;

      final reactionsRaw = Map<String, dynamic>.from(data['reactions'] ?? {});
      final currentList = (reactionsRaw[emoji] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      if (currentList.contains(userId)) {
        currentList.remove(userId);
      } else {
        currentList.add(userId);
      }
      reactionsRaw[emoji] = currentList;

      transaction.update(ref, {'reactions': reactionsRaw});
    });
  }

  // Get unread messages count for a user - Bảo mật: chỉ đếm tin nhắn của user
  Future<int> getUnreadCount(String userId) async {
    try {
      if (userId.isEmpty) {
        return 0;
      }

      // Chỉ lấy các conversation mà user đang tham gia (khớp rule)
      final conversations = await _firestore
          .collection(AppConstants.conversationsCollection)
          .where('participantIds', arrayContains: userId)
          .get();

      int total = 0;
      for (final doc in conversations.docs) {
        final data = doc.data();
        final participants = List<String>.from(data['participantIds'] ?? []);

        // Chỉ đếm nếu userId là participant
        if (!participants.contains(userId)) continue;
        final unreadCounts = Map<String, int>.from(data['unreadCounts'] ?? {});
        total += unreadCounts[userId] ?? 0;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  // Delete a message - Bảo mật: chỉ sender mới được xóa
  Future<void> deleteMessage(String messageId, String userId) async {
    try {
      if (messageId.isEmpty || userId.isEmpty) {
        throw Exception('Message ID and User ID cannot be empty');
      }

      // Kiểm tra message tồn tại và user là sender
      final messageDoc = await _firestore
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .get();

      if (!messageDoc.exists) {
        throw Exception('Message not found');
      }

      final messageData = messageDoc.data()!;
      final senderId = messageData['senderId'] as String? ?? '';

      // Chỉ cho phép nếu userId là sender
      if (senderId != userId) {
        throw Exception('Bạn chỉ có thể xóa tin nhắn của chính mình');
      }

      final conversationId = messageData['conversationId'] as String?;

      // Kiểm tra xem tin nhắn này có phải là tin nhắn cuối trong conversation không
      bool isLastMessage = false;
      if (conversationId != null) {
        final conversationDoc = await _firestore
            .collection(AppConstants.conversationsCollection)
            .doc(conversationId)
            .get();

        if (conversationDoc.exists) {
          final conversationData = conversationDoc.data()!;
          final lastMessageId = conversationData['lastMessageId'] as String?;
          isLastMessage = (lastMessageId == messageId);
        }
      }

      // Xóa message
      await messageDoc.reference.delete();

      // Cập nhật conversation nếu tin nhắn bị xóa là tin nhắn cuối
      if (conversationId != null && isLastMessage) {
        await _updateConversationAfterDelete(conversationId);
      }
    } catch (e) {
      throw Exception('Delete message failed: $e');
    }
  }

  // Recall a message - Thu hồi tin nhắn
  // Nguyên tắc: chỉ sender được thu hồi trong 24 giờ, không cho thu hồi nếu đã bị report
  Future<void> recallMessage(String messageId, String userId) async {
    try {
      if (messageId.isEmpty || userId.isEmpty) {
        throw Exception('Message ID and User ID cannot be empty');
      }

      // Kiểm tra message tồn tại và user là sender
      final messageDoc = await _firestore
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .get();

      if (!messageDoc.exists) {
        throw Exception('Message not found');
      }

      final messageData = messageDoc.data()!;
      final senderId = messageData['senderId'] as String? ?? '';

      // Nguyên tắc 2: Chỉ cho phép nếu userId là sender
      if (senderId != userId) {
        throw Exception('Bạn chỉ có thể thu hồi tin nhắn của chính mình');
      }

      // Kiểm tra tin nhắn đã bị thu hồi chưa
      final isRecalled = messageData['isRecalled'] as bool? ?? false;
      if (isRecalled) {
        throw Exception('Tin nhắn đã được thu hồi');
      }

      // Nguyên tắc 1: Kiểm tra thời gian cho phép thu hồi (24 giờ)
      final createdAt = DateTime.parse(messageData['createdAt'] as String);
      final now = DateTime.now();
      final timeDifference = now.difference(createdAt);
      const recallTimeLimit = Duration(hours: 24);

      if (timeDifference > recallTimeLimit) {
        throw Exception(
          'Chỉ có thể thu hồi tin nhắn trong vòng 24 giờ sau khi gửi',
        );
      }

      // Nguyên tắc 8: Kiểm tra tin nhắn có bị report không
      final reportsQuery = await _firestore
          .collection(AppConstants.reportsCollection)
          .where('messageId', isEqualTo: messageId)
          .limit(1)
          .get();

      if (reportsQuery.docs.isNotEmpty) {
        throw Exception('Không thể thu hồi tin nhắn đã bị báo cáo');
      }

      final conversationId = messageData['conversationId'] as String?;

      // Nguyên tắc 3 & 4: Đánh dấu tin nhắn đã được thu hồi (không xóa dữ liệu để giữ log)
      // Ẩn nội dung gốc nhưng vẫn giữ trong database
      await messageDoc.reference.update({
        'isRecalled': true,
        'recalledAt': now.toIso8601String(),
        'content': '[Tin nhắn đã được thu hồi]',
        'imageUrl': null,
        'videoUrl': null,
        'audioUrl': null,
      });

      // Nguyên tắc 5: Cập nhật conversation nếu tin nhắn bị thu hồi là tin nhắn cuối
      if (conversationId != null) {
        final conversationDoc = await _firestore
            .collection(AppConstants.conversationsCollection)
            .doc(conversationId)
            .get();

        if (conversationDoc.exists) {
          final conversationData = conversationDoc.data()!;
          final convLastMessageId =
              conversationData['lastMessageId'] as String?;

          if (convLastMessageId == messageId) {
            // Tin nhắn cuối bị thu hồi, cập nhật với tin nhắn mới nhất còn lại
            await _updateConversationAfterRecall(conversationId);
          } else {
            // Cập nhật lastMessageContent nếu có đề cập đến tin nhắn này
            await conversationDoc.reference.update({
              'lastMessageContent': '[Tin nhắn đã được thu hồi]',
              'updatedAt': now.toIso8601String(),
            });
          }
        }
      }
    } catch (e) {
      throw Exception('Recall message failed: $e');
    }
  }

  // Cập nhật conversation sau khi thu hồi tin nhắn cuối
  Future<void> _updateConversationAfterRecall(String conversationId) async {
    try {
      // Lấy tin nhắn mới nhất còn lại (chưa bị thu hồi)
      final remainingMessages = await _firestore
          .collection(AppConstants.messagesCollection)
          .where('conversationId', isEqualTo: conversationId)
          .where('isRecalled', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) return;

      if (remainingMessages.docs.isEmpty) {
        // Không còn tin nhắn nào, cập nhật với thông báo thu hồi
        await conversationDoc.reference.update({
          'lastMessageContent': '[Tin nhắn đã được thu hồi]',
          'updatedAt': DateTime.now().toIso8601String(),
        });
      } else {
        // Cập nhật với tin nhắn mới nhất
        final lastMessage = remainingMessages.docs.first;
        final lastMessageData = lastMessage.data();
        final lastMessageContent = lastMessageData['content'] as String? ?? '';
        final lastMessageSenderId =
            lastMessageData['senderId'] as String? ?? '';
        final lastMessageTime = lastMessageData['createdAt'] as String? ?? '';

        await conversationDoc.reference.update({
          'lastMessageId': lastMessage.id,
          'lastMessageContent': lastMessageContent.isNotEmpty
              ? lastMessageContent
              : (lastMessageData['imageUrl'] != null
                    ? '[Ảnh]'
                    : (lastMessageData['videoUrl'] != null
                          ? '[Video]'
                          : (lastMessageData['audioUrl'] != null
                                ? '[Voice]'
                                : ''))),
          'lastMessageNonce': null,
          'lastMessageSenderId': lastMessageSenderId,
          'lastMessageTime': lastMessageTime,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      // Log error nhưng không throw để tránh ảnh hưởng đến việc thu hồi message
      print('Error updating conversation after recall: $e');
    }
  }

  // Cập nhật conversation sau khi xóa tin nhắn cuối
  Future<void> _updateConversationAfterDelete(String conversationId) async {
    try {
      // Lấy tin nhắn mới nhất còn lại
      final remainingMessages = await _firestore
          .collection(AppConstants.messagesCollection)
          .where('conversationId', isEqualTo: conversationId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) return;

      if (remainingMessages.docs.isEmpty) {
        // Không còn tin nhắn nào, xóa conversation
        await conversationDoc.reference.delete();
      } else {
        // Cập nhật với tin nhắn mới nhất
        final lastMessage = remainingMessages.docs.first;
        final lastMessageData = lastMessage.data();
        final lastMessageContent = lastMessageData['content'] as String? ?? '';
        final lastMessageSenderId =
            lastMessageData['senderId'] as String? ?? '';
        final lastMessageTime = lastMessageData['createdAt'] as String? ?? '';

        await conversationDoc.reference.update({
          'lastMessageId': lastMessage.id,
          'lastMessageContent': lastMessageContent.isNotEmpty
              ? lastMessageContent
              : (lastMessageData['imageUrl'] != null
                    ? '[Ảnh]'
                    : (lastMessageData['videoUrl'] != null
                          ? '[Video]'
                          : (lastMessageData['audioUrl'] != null
                                ? '[Voice]'
                                : ''))),
          'lastMessageNonce': null,
          'lastMessageSenderId': lastMessageSenderId,
          'lastMessageTime': lastMessageTime,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      // Log error nhưng không throw để tránh ảnh hưởng đến việc xóa message
      print('Error updating conversation after delete: $e');
    }
  }

  // Pin a message - Ghim tin nhắn
  // Cho phép cả sender và receiver đều có thể ghim tin nhắn
  Future<void> pinMessage(String messageId, String userId) async {
    try {
      if (messageId.isEmpty || userId.isEmpty) {
        throw Exception('Message ID and User ID cannot be empty');
      }

      // Kiểm tra message tồn tại
      final messageDoc = await _firestore
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .get();

      if (!messageDoc.exists) {
        throw Exception('Message not found');
      }

      final messageData = messageDoc.data()!;
      final senderId = messageData['senderId'] as String? ?? '';
      final receiverId = messageData['receiverId'] as String? ?? '';

      // Chỉ cho phép sender hoặc receiver ghim tin nhắn
      if (userId != senderId && userId != receiverId) {
        throw Exception('Bạn không có quyền ghim tin nhắn này');
      }

      // Kiểm tra tin nhắn đã bị ghim chưa
      final isPinned = messageData['isPinned'] as bool? ?? false;
      if (isPinned) {
        throw Exception('Tin nhắn đã được ghim');
      }

      // Ghim tin nhắn
      await messageDoc.reference.update({
        'isPinned': true,
        'pinnedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Pin message failed: $e');
    }
  }

  // Unpin a message - Bỏ ghim tin nhắn
  Future<void> unpinMessage(String messageId, String userId) async {
    try {
      if (messageId.isEmpty || userId.isEmpty) {
        throw Exception('Message ID and User ID cannot be empty');
      }

      // Kiểm tra message tồn tại
      final messageDoc = await _firestore
          .collection(AppConstants.messagesCollection)
          .doc(messageId)
          .get();

      if (!messageDoc.exists) {
        throw Exception('Message not found');
      }

      final messageData = messageDoc.data()!;
      final senderId = messageData['senderId'] as String? ?? '';
      final receiverId = messageData['receiverId'] as String? ?? '';

      // Chỉ cho phép sender hoặc receiver bỏ ghim tin nhắn
      if (userId != senderId && userId != receiverId) {
        throw Exception('Bạn không có quyền bỏ ghim tin nhắn này');
      }

      // Kiểm tra tin nhắn đã bị ghim chưa
      final isPinned = messageData['isPinned'] as bool? ?? false;
      if (!isPinned) {
        throw Exception('Tin nhắn chưa được ghim');
      }

      // Bỏ ghim tin nhắn
      await messageDoc.reference.update({'isPinned': false, 'pinnedAt': null});
    } catch (e) {
      throw Exception('Unpin message failed: $e');
    }
  }

  // Delete group conversation - Xóa toàn bộ đoạn chat nhóm
  // Xóa conversation và tất cả messages trong conversation đó
  Future<void> deleteGroupConversation(String groupId, String userId) async {
    try {
      if (groupId.isEmpty || userId.isEmpty) {
        throw Exception('Group ID and User ID cannot be empty');
      }

      // Kiểm tra user có trong group không
      final groupDoc = await _firestore
          .collection(AppConstants.groupsCollection)
          .doc(groupId)
          .get();

      if (!groupDoc.exists) {
        throw Exception('Group not found');
      }

      final groupData = groupDoc.data()!;
      final memberIds = List<String>.from(groupData['memberIds'] ?? []);

      // Chỉ cho phép member của group xóa conversation
      if (!memberIds.contains(userId)) {
        throw Exception('Bạn không có quyền xóa đoạn chat này');
      }

      // Tạo conversation ID cho group
      final conversationId = 'group_$groupId';

      // Kiểm tra conversation tồn tại
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      // Xóa tất cả messages trong conversation
      // Firestore rules đã cho phép participant xóa messages trong conversation
      final messagesQuery = await _firestore
          .collection(AppConstants.messagesCollection)
          .where('conversationId', isEqualTo: conversationId)
          .get();

      final batch = _firestore.batch();
      for (final doc in messagesQuery.docs) {
        batch.delete(doc.reference);
      }

      // Xóa conversation (user có quyền vì là participant)
      batch.delete(conversationDoc.reference);

      // Commit tất cả các thao tác xóa
      await batch.commit();
    } catch (e) {
      throw Exception('Delete group conversation failed: $e');
    }
  }

  // Delete conversation - Xóa cuộc trò chuyện (chỉ ẩn ở phía người xóa)
  // CHỈ XÓA Ở PHÍA NGƯỜI XÓA: Thêm userId vào deletedBy, không xóa conversation và messages
  // Người còn lại vẫn thấy conversation và messages bình thường
  Future<void> deleteConversation(
    String userId1,
    String userId2,
    String userId,
  ) async {
    try {
      if (userId1.isEmpty || userId2.isEmpty || userId.isEmpty) {
        throw Exception('User IDs cannot be empty');
      }

      // Chỉ cho phép một trong hai người tham gia xóa conversation
      if (userId != userId1 && userId != userId2) {
        throw Exception('Bạn không có quyền xóa đoạn chat này');
      }

      // Tạo conversation ID
      final participants = [userId1, userId2]..sort();
      final conversationId = participants.join('_');

      // Kiểm tra conversation tồn tại
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      // CRITICAL CHANGE: Thay vì xóa conversation và messages,
      // chỉ thêm userId vào deletedBy để ẩn conversation ở phía người xóa
      final data = conversationDoc.data()!;
      final deletedBy = List<String>.from(data['deletedBy'] ?? []);

      // Nếu userId chưa có trong deletedBy, thêm vào
      if (!deletedBy.contains(userId)) {
        deletedBy.add(userId);
        await conversationDoc.reference.update({
          'deletedBy': deletedBy,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        // CRITICAL: Chỉ đánh dấu messages CŨ (trước khi xóa) là đã bị xóa bởi user này
        // Messages mới sau khi restore conversation sẽ không có deletedBy, nên sẽ hiển thị bình thường
        try {
          final deleteTime = DateTime.now();

          final messagesQuery = await _firestore
              .collection(AppConstants.messagesCollection)
              .where('conversationId', isEqualTo: conversationId)
              .get();

          final batch = _firestore.batch();
          int batchCount = 0;
          const maxBatchSize = 500;
          int markedCount = 0;

          for (final msgDoc in messagesQuery.docs) {
            final msgData = msgDoc.data();
            final msgDeletedBy = List<String>.from(msgData['deletedBy'] ?? []);

            // CHỈ đánh dấu messages CŨ (có createdAt trước thời điểm xóa)
            // Messages mới sau khi restore sẽ không bị đánh dấu
            final createdAtStr = msgData['createdAt'] as String?;
            if (createdAtStr != null) {
              try {
                final createdAt = DateTime.parse(createdAtStr);
                // Chỉ đánh dấu messages có createdAt trước thời điểm xóa
                if (createdAt.isBefore(deleteTime)) {
                  // Thêm userId vào deletedBy của message nếu chưa có
                  if (!msgDeletedBy.contains(userId)) {
                    msgDeletedBy.add(userId);
                    batch.update(msgDoc.reference, {'deletedBy': msgDeletedBy});
                    batchCount++;
                    markedCount++;

                    if (batchCount >= maxBatchSize) {
                      await batch.commit();
                      batchCount = 0;
                    }
                  }
                }
              } catch (e) {
                // Nếu không parse được createdAt, đánh dấu an toàn (giả sử là message cũ)
                if (!msgDeletedBy.contains(userId)) {
                  msgDeletedBy.add(userId);
                  batch.update(msgDoc.reference, {'deletedBy': msgDeletedBy});
                  batchCount++;
                  markedCount++;

                  if (batchCount >= maxBatchSize) {
                    await batch.commit();
                    batchCount = 0;
                  }
                }
              }
            }
          }

          if (batchCount > 0) {
            await batch.commit();
          }

          if (kDebugMode) {
            print(
              '=== Marked $markedCount old messages (before delete time) as deleted by $userId',
            );
            print(
              '=== Total messages in conversation: ${messagesQuery.docs.length}',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('=== ERROR marking messages as deleted: $e');
          }
          // Không throw error để conversation vẫn được đánh dấu là đã xóa
        }

        if (kDebugMode) {
          print(
            '=== Conversation $conversationId marked as deleted by $userId',
          );
          print('=== Other user can still see the conversation');
        }
      }
    } catch (e) {
      throw Exception('Delete conversation failed: $e');
    }
  }

  // Pin conversation - Ghim đoạn chat
  Future<void> pinConversation(
    String userId1,
    String userId2,
    String userId,
  ) async {
    try {
      if (userId1.isEmpty || userId2.isEmpty || userId.isEmpty) {
        throw Exception('User IDs cannot be empty');
      }

      // Chỉ cho phép một trong hai người tham gia ghim conversation
      if (userId != userId1 && userId != userId2) {
        throw Exception('Bạn không có quyền ghim đoạn chat này');
      }

      // Tạo conversation ID
      final participants = [userId1, userId2]..sort();
      final conversationId = participants.join('_');

      // Kiểm tra conversation tồn tại
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      final conversationData = conversationDoc.data()!;
      final isPinned = conversationData['isPinned'] as bool? ?? false;

      if (isPinned) {
        throw Exception('Đoạn chat đã được ghim');
      }

      // Ghim conversation
      await conversationDoc.reference.update({
        'isPinned': true,
        'pinnedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Pin conversation failed: $e');
    }
  }

  // Unpin conversation - Bỏ ghim đoạn chat
  Future<void> unpinConversation(
    String userId1,
    String userId2,
    String userId,
  ) async {
    try {
      if (userId1.isEmpty || userId2.isEmpty || userId.isEmpty) {
        throw Exception('User IDs cannot be empty');
      }

      // Chỉ cho phép một trong hai người tham gia bỏ ghim conversation
      if (userId != userId1 && userId != userId2) {
        throw Exception('Bạn không có quyền bỏ ghim đoạn chat này');
      }

      // Tạo conversation ID
      final participants = [userId1, userId2]..sort();
      final conversationId = participants.join('_');

      // Kiểm tra conversation tồn tại
      final conversationDoc = await _firestore
          .collection(AppConstants.conversationsCollection)
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        throw Exception('Conversation not found');
      }

      final conversationData = conversationDoc.data()!;
      final isPinned = conversationData['isPinned'] as bool? ?? false;

      if (!isPinned) {
        throw Exception('Đoạn chat chưa được ghim');
      }

      // Bỏ ghim conversation
      await conversationDoc.reference.update({
        'isPinned': false,
        'pinnedAt': null,
      });
    } catch (e) {
      throw Exception('Unpin conversation failed: $e');
    }
  }

  // ==== Nickname per conversation ====
  Future<void> setNickname({
    required String conversationId,
    required String targetUserId,
    required String nickname,
  }) async {
    if (conversationId.isEmpty || targetUserId.isEmpty) return;
    final trimmed = nickname.trim();
    final ref = _firestore
        .collection(AppConstants.conversationsCollection)
        .doc(conversationId);
    await ref.set({
      'nicknames': trimmed.isEmpty
          ? {targetUserId: FieldValue.delete()}
          : {targetUserId: trimmed},
    }, SetOptions(merge: true));
  }

  Stream<String?> watchNickname(String conversationId, String targetUserId) {
    if (conversationId.isEmpty || targetUserId.isEmpty) {
      return const Stream<String?>.empty();
    }
    return _firestore
        .collection(AppConstants.conversationsCollection)
        .doc(conversationId)
        .snapshots()
        .map((snap) {
          final data = snap.data();
          if (data == null) return null;
          final map = Map<String, dynamic>.from(data['nicknames'] ?? {});
          return map[targetUserId]?.toString();
        });
  }

  // ==== Mute per conversation/user ====
  Future<void> muteConversation({
    required String conversationId,
    required String userId,
    Duration? duration,
  }) async {
    if (conversationId.isEmpty || userId.isEmpty) return;
    final ref = _firestore
        .collection(AppConstants.conversationsCollection)
        .doc(conversationId)
        .collection('mutes')
        .doc(userId);
    if (duration == null) {
      // Xóa document khi unmute
      await ref.delete();
    } else {
      final until = DateTime.now().add(duration);
      await ref.set({
        'mutedUntil': until.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<DateTime?> getMuteUntil(String conversationId, String userId) async {
    if (conversationId.isEmpty || userId.isEmpty) return null;
    final doc = await _firestore
        .collection(AppConstants.conversationsCollection)
        .doc(conversationId)
        .collection('mutes')
        .doc(userId)
        .get();
    if (!doc.exists) return null;
    final data = doc.data();
    final value = data?['mutedUntil'] as String?;
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
