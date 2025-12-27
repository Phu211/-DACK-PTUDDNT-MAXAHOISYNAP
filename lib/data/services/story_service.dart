import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';
import '../models/story_model.dart';
import '../models/privacy_model.dart';
import 'friend_service.dart';

class StoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a story
  Future<String> createStory(StoryModel story) async {
    try {
      final docRef = await _firestore.collection(AppConstants.storiesCollection).add(story.toMap());
      return docRef.id;
    } catch (e) {
      throw Exception('Create story failed: $e');
    }
  }

  // Get active stories for friends with privacy filtering
  Stream<List<StoryModel>> getActiveStories(List<String> friendIds, {String? currentUserId}) {
    return _firestore
        .collection(AppConstants.storiesCollection)
        .snapshots()
        .asyncMap((snapshot) async {
          final stories = snapshot.docs
              .map((doc) => StoryModel.fromMap(doc.id, doc.data()))
              .where((story) => !story.isExpired)
              .toList();

          // Filter by privacy
          if (currentUserId != null) {
            final friendService = FriendService();
            final allFriendIds = await friendService.getFriends(currentUserId);

            // Lọc theo quyền riêng tư
            final visibleStories = stories.where((story) {
              // Own stories are always visible
              if (story.userId == currentUserId) return true;

              // Public stories are visible to everyone (trừ khi bị block)
              if (story.privacy == PrivacyType.public) {
                // Kiểm tra nếu viewer bị ẩn story
                if (story.hiddenUsers.contains(currentUserId)) return false;
                return true;
              }

              // Friends stories
              if (story.privacy == PrivacyType.friends) {
                // Kiểm tra nếu viewer bị ẩn story
                if (story.hiddenUsers.contains(currentUserId)) return false;

                // Nếu có allowedUsers (Close Friends), chỉ những người trong list mới xem được
                if (story.allowedUsers.isNotEmpty) {
                  return story.allowedUsers.contains(currentUserId);
                }

                // Nếu không có allowedUsers, chỉ bạn bè xem được
                return allFriendIds.contains(story.userId);
              }

              // Only me stories are not visible (story không nên có onlyMe, nhưng để an toàn)
              if (story.privacy == PrivacyType.onlyMe) return false;

              return false;
            }).toList();

            // Sắp xếp: mới nhất trước
            visibleStories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return visibleStories;
          } else {
            // Nếu chưa đăng nhập: chỉ hiện stories public, sắp xếp mới nhất trước
            final publicStories = stories.where((story) => story.privacy == PrivacyType.public).toList();
            publicStories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return publicStories;
          }
        })
        .handleError((error) {
          // Handle permission errors gracefully (user may have logged out)
          if (error.toString().contains('permission-denied') || error.toString().contains('permission denied')) {
            return <StoryModel>[];
          }
          // Re-throw other errors
          throw error;
        });
  }

  // Record a view on a story
  Future<void> addStoryView({required String storyId, required String storyOwnerId, required String viewerId}) async {
    try {
      await _firestore.collection(AppConstants.storyViewsCollection).doc('${storyId}_$viewerId').set({
        'storyId': storyId,
        'storyOwnerId': storyOwnerId,
        'viewerId': viewerId,
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      // Không throw để tránh làm hỏng trải nghiệm xem story
      print('Error adding story view: $e');
    }
  }

  // Get viewers for a story
  Stream<List<Map<String, dynamic>>> getStoryViews(String storyId) {
    return _firestore
        .collection(AppConstants.storyViewsCollection)
        .where('storyId', isEqualTo: storyId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => d.data()).toList(growable: false));
  }

  // Add / update reaction to a story
  Future<void> reactToStory({
    required String storyId,
    required String storyOwnerId,
    required String userId,
    required String emoji,
  }) async {
    try {
      await _firestore.collection(AppConstants.storyReactionsCollection).doc('${storyId}_$userId').set({
        'storyId': storyId,
        'storyOwnerId': storyOwnerId,
        'userId': userId,
        'emoji': emoji,
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('React to story failed: $e');
    }
  }

  // Get reactions for a story
  Stream<List<Map<String, dynamic>>> getStoryReactions(String storyId) {
    return _firestore
        .collection(AppConstants.storyReactionsCollection)
        .where('storyId', isEqualTo: storyId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => d.data()).toList(growable: false));
  }

  // Get stories by user with privacy check
  Stream<List<StoryModel>> getStoriesByUser(String userId, {String? viewerId}) {
    return _firestore
        .collection(AppConstants.storiesCollection)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
          var stories = snapshot.docs
              .map((doc) => StoryModel.fromMap(doc.id, doc.data()))
              .where((story) => !story.isExpired)
              .toList();

          // Filter by privacy nếu có viewerId
          if (viewerId != null && viewerId != userId) {
            final friendService = FriendService();
            final friendIds = await friendService.getFriends(viewerId);
            final isFriend = friendIds.contains(userId);

            stories = stories.where((story) {
              // Public stories
              if (story.privacy == PrivacyType.public) {
                if (story.hiddenUsers.contains(viewerId)) return false;
                return true;
              }

              // Friends stories
              if (story.privacy == PrivacyType.friends) {
                if (story.hiddenUsers.contains(viewerId)) return false;

                // Close Friends (allowedUsers)
                if (story.allowedUsers.isNotEmpty) {
                  return story.allowedUsers.contains(viewerId);
                }

                // Chỉ bạn bè xem được
                return isFriend;
              }

              // Only me (không nên có trong story, nhưng để an toàn)
              if (story.privacy == PrivacyType.onlyMe) return false;

              return false;
            }).toList();
          }

          // Sắp xếp mới nhất trước trên client để tránh cần composite index
          stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return stories;
        });
  }

  // Get all stories by user (including expired ones) - for memories
  Stream<List<StoryModel>> getAllStoriesByUser(String userId) {
    // On Windows, use polling instead of .snapshots() for better compatibility
    if (kDebugMode) {
      print('=== getAllStoriesByUser ===');
      print('Using polling approach for Windows compatibility');
    }

    Future<List<StoryModel>> fetchStories() async {
      try {
        final snapshot = await _firestore
            .collection(AppConstants.storiesCollection)
            .where('userId', isEqualTo: userId)
            .get();

        if (kDebugMode) {
          print('Fetched stories: ${snapshot.docs.length} documents');
          print('Current time: ${DateTime.now()}');
        }

        final stories = <StoryModel>[];
        for (var doc in snapshot.docs) {
          try {
            final story = StoryModel.fromMap(doc.id, doc.data());
            stories.add(story);
            if (kDebugMode) {
              print(
                'Story ${doc.id}: createdAt=${story.createdAt}, expiresAt=${story.expiresAt}, isExpired=${story.isExpired}',
              );
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error parsing story ${doc.id}: $e');
              print('Story data: ${doc.data()}');
            }
          }
        }

        // Sort by createdAt descending (newest first) on client side
        stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (kDebugMode) {
          print('Total stories parsed: ${stories.length}');
          print('Expired stories: ${stories.where((s) => s.isExpired).length}');
        }

        return stories;
      } catch (e) {
        if (kDebugMode) {
          print('ERROR fetching stories: $e');
        }
        rethrow;
      }
    }

    // Use StreamController to combine immediate fetch with periodic polling
    final controller = StreamController<List<StoryModel>>();

    // Fetch immediately
    fetchStories()
        .then((stories) {
          if (kDebugMode) {
            print('Initial fetch completed: ${stories.length} stories');
          }
          if (!controller.isClosed) {
            controller.add(stories);
          }
        })
        .catchError((error) {
          if (kDebugMode) {
            print('ERROR in initial fetch: $error');
          }
          if (!controller.isClosed) {
            controller.addError(error);
          }
        });

    // Then poll every 5 seconds
    Timer.periodic(const Duration(seconds: 5), (timer) {
      fetchStories()
          .then((stories) {
            if (!controller.isClosed) {
              controller.add(stories);
            } else {
              timer.cancel();
            }
          })
          .catchError((error) {
            if (!controller.isClosed) {
              if (kDebugMode) {
                print('ERROR in periodic stories fetch: $error');
              }
              controller.addError(error);
            } else {
              timer.cancel();
            }
          });
    });

    return controller.stream;
  }

  // One-time fetch stories by user with privacy check (tránh một số bug stream trên web)
  Future<List<StoryModel>> fetchStoriesByUserOnce(
    String userId, {
    String? viewerId,
    bool includeExpired = false, // Cho phép bao gồm expired stories (cho màn hình Kỷ niệm)
  }) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.storiesCollection)
          .where('userId', isEqualTo: userId)
          .get();

      var stories = snapshot.docs
          .map((doc) => StoryModel.fromMap(doc.id, doc.data()))
          .where((story) => includeExpired || !story.isExpired)
          .toList();

      // Filter by privacy nếu có viewerId và viewer không phải owner
      if (viewerId != null && viewerId != userId) {
        final friendService = FriendService();
        final friendIds = await friendService.getFriends(viewerId);
        final isFriend = friendIds.contains(userId);

        stories = stories.where((story) {
          // Public stories
          if (story.privacy == PrivacyType.public) {
            if (story.hiddenUsers.contains(viewerId)) return false;
            return true;
          }

          // Friends stories
          if (story.privacy == PrivacyType.friends) {
            if (story.hiddenUsers.contains(viewerId)) return false;

            // Close Friends (allowedUsers)
            if (story.allowedUsers.isNotEmpty) {
              return story.allowedUsers.contains(viewerId);
            }

            // Chỉ bạn bè xem được
            return isFriend;
          }

          // Only me (không nên có trong story, nhưng để an toàn)
          if (story.privacy == PrivacyType.onlyMe) return false;

          return false;
        }).toList();
      }

      stories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return stories;
    } catch (e) {
      throw Exception('Fetch stories failed: $e');
    }
  }

  // Fetch stories by IDs (for highlights)
  // LƯU Ý: Method này trả về TẤT CẢ stories (kể cả đã hết hạn) để cho phép dùng trong highlights
  Future<List<StoryModel>> fetchStoriesByIds(List<String> storyIds) async {
    if (storyIds.isEmpty) return [];

    try {
      // Firestore 'whereIn' supports up to 10 items, so we need to batch if more
      final List<StoryModel> allStories = [];

      // Split into batches of 10
      for (int i = 0; i < storyIds.length; i += 10) {
        final batch = storyIds.skip(i).take(10).toList();
        final snapshot = await _firestore
            .collection(AppConstants.storiesCollection)
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        final stories = snapshot.docs.map((doc) => StoryModel.fromMap(doc.id, doc.data())).toList();

        allStories.addAll(stories);
      }

      // Sort by createdAt descending (newest first)
      allStories.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (kDebugMode) {
        print('Fetched ${allStories.length} stories from ${storyIds.length} IDs');
        final expiredCount = allStories.where((s) => s.isExpired).length;
        if (expiredCount > 0) {
          print('  - Including $expiredCount expired stories (allowed for highlights)');
        }
      }

      return allStories; // Trả về TẤT CẢ stories, kể cả đã hết hạn
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching stories by IDs: $e');
      }
      throw Exception('Fetch stories by IDs failed: $e');
    }
  }

  // Delete expired stories - DISABLED
  // LƯU Ý: Không tự động xóa expired stories để user có thể xem lại vĩnh viễn trong mục "Kỉ niệm"
  // User có thể tự xóa story thủ công nếu muốn
  Future<void> deleteExpiredStories() async {
    // Disabled - không tự động xóa expired stories
    // Stories sẽ được giữ lại vĩnh viễn để user có thể xem lại trong mục "Kỉ niệm"
    if (kDebugMode) {
      print('deleteExpiredStories: Disabled - expired stories are kept permanently for memories');
    }
    // Không làm gì cả - stories sẽ được giữ lại vĩnh viễn
  }

  // Delete a single story by id (used when owner xóa story thủ công)
  Future<void> deleteStory(String storyId) async {
    try {
      // Xoá document story chính
      await _firestore.collection(AppConstants.storiesCollection).doc(storyId).delete();

      // Xoá các bản ghi views và reactions liên quan (fire-and-forget)
      _cleanupStoryMeta(storyId);
    } catch (e) {
      throw Exception('Delete story failed: $e');
    }
  }

  Future<void> _cleanupStoryMeta(String storyId) async {
    try {
      final views = await _firestore
          .collection(AppConstants.storyViewsCollection)
          .where('storyId', isEqualTo: storyId)
          .get();
      final reactions = await _firestore
          .collection(AppConstants.storyReactionsCollection)
          .where('storyId', isEqualTo: storyId)
          .get();

      final batch = _firestore.batch();
      for (final doc in views.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in reactions.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {
      // không throw để tránh crash; chỉ là dọn dẹp metadata
    }
  }

  // Save a story to user's saved stories
  Future<void> saveStory(String storyId, String userId) async {
    try {
      if (storyId.isEmpty || userId.isEmpty) return;
      final docId = '${userId}_$storyId';
      await _firestore.collection(AppConstants.savedStoriesCollection).doc(docId).set({
        'userId': userId,
        'storyId': storyId,
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Save story failed: $e');
    }
  }

  // Check if a story is saved
  Future<bool> isStorySaved(String storyId, String userId) async {
    try {
      if (storyId.isEmpty || userId.isEmpty) return false;
      final docId = '${userId}_$storyId';
      final doc = await _firestore.collection(AppConstants.savedStoriesCollection).doc(docId).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  // Unsave a story
  Future<void> unsaveStory(String storyId, String userId) async {
    try {
      if (storyId.isEmpty || userId.isEmpty) return;
      final docId = '${userId}_$storyId';
      await _firestore.collection(AppConstants.savedStoriesCollection).doc(docId).delete();
    } catch (e) {
      throw Exception('Unsave story failed: $e');
    }
  }
}
