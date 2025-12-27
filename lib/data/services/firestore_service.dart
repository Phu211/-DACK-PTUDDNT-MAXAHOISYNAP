import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../models/comment_model.dart';
import '../models/notification_model.dart';
import '../models/post_model.dart';
import '../models/privacy_model.dart';
import '../models/reaction_model.dart';
import '../models/user_interaction_model.dart';
import 'friend_service.dart';
import 'notification_service.dart';
import 'block_service.dart';
import 'activity_log_service.dart';
import '../models/activity_log_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  // =====================
  // Lightweight in-memory caches (reduce repeated Firestore reads)
  // =====================

  static const Duration _countsTtl = Duration(seconds: 20);

  static final Map<String, bool> _savedCache = <String, bool>{};
  static final Map<String, Future<bool>> _savedInflight = <String, Future<bool>>{};

  static final Map<String, ReactionType?> _postUserReactionCache = <String, ReactionType?>{};
  static final Map<String, Future<ReactionType?>> _postUserReactionInflight = <String, Future<ReactionType?>>{};

  static final Map<String, Map<ReactionType, int>> _postReactionsCache = <String, Map<ReactionType, int>>{};
  static final Map<String, DateTime> _postReactionsCacheAt = <String, DateTime>{};
  static final Map<String, Future<Map<ReactionType, int>>> _postReactionsInflight =
      <String, Future<Map<ReactionType, int>>>{};

  static final Map<String, ReactionType?> _commentUserReactionCache = <String, ReactionType?>{};
  static final Map<String, Future<ReactionType?>> _commentUserReactionInflight = <String, Future<ReactionType?>>{};

  static final Map<String, Map<ReactionType, int>> _commentReactionsCache = <String, Map<ReactionType, int>>{};
  static final Map<String, DateTime> _commentReactionsCacheAt = <String, DateTime>{};
  static final Map<String, Future<Map<ReactionType, int>>> _commentReactionsInflight =
      <String, Future<Map<ReactionType, int>>>{};

  static String _savedKey(String userId, String postId) => '$userId|$postId';
  static String _postReactionKey(String userId, String postId) => '$userId|$postId';
  static String _commentReactionKey(String userId, String commentId) => '$userId|$commentId';

  // =====================
  // Posts
  // =====================

  Future<String> createPost(PostModel post) async {
    try {
      final docRef = await _firestore.collection(AppConstants.postsCollection).add(post.toMap());

      // Update post with generated ID
      await docRef.update({'id': docRef.id});

      // Update user's postsCount
      await _firestore.collection(AppConstants.usersCollection).doc(post.userId).update({
        'postsCount': FieldValue.increment(1),
      });

      // Log activity: user tạo post
      unawaited(
        ActivityLogService().logActivity(
          ActivityLogModel(
            id: '',
            userId: post.userId, // User tạo post
            type: ActivityType.postCreated,
            targetPostId: docRef.id,
            createdAt: DateTime.now(),
          ),
        ),
      );

      return docRef.id;
    } catch (e) {
      throw Exception('Create post failed: $e');
    }
  }

  Future<void> updatePost(PostModel post) async {
    try {
      if (post.id.isEmpty) throw Exception('Post id is empty');
      await _firestore.collection(AppConstants.postsCollection).doc(post.id).update(post.toMap());
    } catch (e) {
      throw Exception('Update post failed: $e');
    }
  }

  Future<void> deletePost(String postId) async {
    try {
      if (postId.isEmpty) return;
      await _firestore.collection(AppConstants.postsCollection).doc(postId).delete();
    } catch (e) {
      throw Exception('Delete post failed: $e');
    }
  }

  /// Fetch a post and optionally apply privacy rules for viewer.
  Future<PostModel?> getPost(String postId, {String? viewerId}) async {
    try {
      if (postId.isEmpty) return null;
      final doc = await _firestore.collection(AppConstants.postsCollection).doc(postId).get();
      if (!doc.exists) return null;

      final post = PostModel.fromMap(doc.id, doc.data()!);

      // Apply basic privacy rules
      if (viewerId == null) {
        return post.privacy == PrivacyType.public ? post : null;
      }
      if (viewerId == post.userId) return post;
      if (post.privacy == PrivacyType.public) return post;
      if (post.privacy == PrivacyType.friends) {
        final friends = await FriendService().getFriends(viewerId);
        return friends.contains(post.userId) ? post : null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Stream posts for feed (real-time) with privacy + hide filtering and simple ranking.
  Stream<List<PostModel>> getPostsStream({int limit = 20, String? currentUserId}) {
    if (kDebugMode) {
      print('=== getPostsStream ===');
      print('currentUserId: $currentUserId');
      print('limit: $limit');
    }

    if (currentUserId == null) {
      // If not logged in -> only public posts
      if (kDebugMode) {
        print('No user ID, fetching public posts only');
      }
      return _firestore
          .collection(AppConstants.postsCollection)
          .where('privacy', isEqualTo: PrivacyType.public.toValue())
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) {
            if (kDebugMode) {
              print('Public posts snapshot: ${snapshot.docs.length} documents');
            }
            return snapshot.docs.map((doc) => PostModel.fromMap(doc.id, doc.data())).toList();
          })
          .handleError((error) {
            if (kDebugMode) {
              print('ERROR in getPostsStream (public): $error');
            }
            return <PostModel>[];
          });
    }

    if (kDebugMode) {
      print('User logged in, fetching all posts with filtering');
    }

    // Use a simpler approach: fetch hidden posts once, then stream posts
    // This avoids StreamZip issues on Windows
    Future<Set<String>> getHiddenData() async {
      try {
        final hiddenSnapshot = await _firestore
            .collection(AppConstants.hiddenPostsCollection)
            .where('userId', isEqualTo: currentUserId)
            .get();

        if (kDebugMode) {
          print('Hidden posts fetched: ${hiddenSnapshot.docs.length} documents');
        }

        final hiddenPostIds = <String>{};
        final hiddenUserIds = <String>{};
        final unfollowedUserIds = <String>{};
        final now = DateTime.now();

        for (final doc in hiddenSnapshot.docs) {
          final data = doc.data();
          final postId = data['postId'] as String?;
          final hiddenUserId = data['hiddenUserId'] as String?;
          final hideUntilStr = data['hideUntil'] as String?;
          final type = data['type'] as String?;

          if (postId != null && postId.isNotEmpty) {
            hiddenPostIds.add(postId);
          }

          if (hiddenUserId != null && hiddenUserId.isNotEmpty) {
            if (type == 'unfollow') {
              unfollowedUserIds.add(hiddenUserId);
            } else if (hideUntilStr == null) {
              hiddenUserIds.add(hiddenUserId);
            } else {
              final hideUntil = DateTime.tryParse(hideUntilStr);
              if (hideUntil != null && hideUntil.isAfter(now)) {
                hiddenUserIds.add(hiddenUserId);
              }
            }
          }
        }

        return {
          ...hiddenPostIds,
          ...hiddenUserIds.map((id) => 'user_$id'),
          ...unfollowedUserIds.map((id) => 'unfollow_$id'),
        };
      } catch (e) {
        if (kDebugMode) {
          print('ERROR fetching hidden posts: $e');
        }
        return <String>{};
      }
    }

    // Test query first to check if Firestore is accessible
    if (kDebugMode) {
      _firestore
          .collection(AppConstants.postsCollection)
          .limit(1)
          .get()
          .then((snapshot) {
            print('TEST QUERY: Found ${snapshot.docs.length} posts (test query)');
            if (snapshot.docs.isNotEmpty) {
              print('TEST QUERY: First post ID: ${snapshot.docs.first.id}');
            }
          })
          .catchError((error) {
            print('TEST QUERY ERROR: $error');
            print('TEST QUERY ERROR type: ${error.runtimeType}');
          });
    }

    try {
      // On Windows, .snapshots() may not work properly, so use polling instead
      // Poll every 5 seconds to get fresh data
      if (kDebugMode) {
        print('Using polling approach for Windows compatibility');
      }

      // Fetch immediately first, then poll every 5 seconds
      Future<QuerySnapshot<Map<String, dynamic>>> fetchPosts() async {
        if (kDebugMode) {
          print('Fetching posts from Firestore...');
        }

        final postsSnapshot = await _firestore
            .collection(AppConstants.postsCollection)
            .orderBy('createdAt', descending: true)
            .limit(limit * 3) // pull more to filter
            .get();

        if (kDebugMode) {
          print('Fetched posts: ${postsSnapshot.docs.length} documents');
        }

        return postsSnapshot;
      }

      // Emit immediately, then poll every 5 seconds
      // Use StreamController to combine immediate fetch with periodic polling
      final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();

      // Fetch immediately
      fetchPosts()
          .then((snapshot) {
            if (kDebugMode) {
              print('Initial fetch completed: ${snapshot.docs.length} documents');
            }
            if (!controller.isClosed) {
              controller.add(snapshot);
            }
          })
          .catchError((error) {
            // Nếu có permission error (user đã signOut), không emit error để tránh crash
            if (kDebugMode) {
              print('ERROR in initial fetch: $error');
              if (error.toString().contains('permission-denied') || error.toString().contains('permission denied')) {
                print('Permission denied - user may have signed out, ignoring error');
                // Không emit error để tránh crash app
                return;
              }
            }
            if (!controller.isClosed) {
              controller.addError(error);
            }
          });

      // Then poll every 5 seconds
      Timer? periodicTimer;
      periodicTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        fetchPosts()
            .then((snapshot) {
              if (!controller.isClosed) {
                if (kDebugMode) {
                  print('Periodic fetch completed: ${snapshot.docs.length} documents');
                }
                controller.add(snapshot);
              } else {
                timer.cancel();
              }
            })
            .catchError((error) {
              // Nếu có permission error (user đã signOut), chỉ log và không emit error
              // để tránh crash app
              if (kDebugMode) {
                print('ERROR in periodic fetch: $error');
                if (error.toString().contains('permission-denied') || error.toString().contains('permission denied')) {
                  print('Permission denied - user may have signed out, ignoring error');
                  return; // Không emit error để tránh crash
                }
              }
              if (!controller.isClosed) {
                controller.addError(error);
              } else {
                timer.cancel();
              }
            });
      });

      // Cancel timer khi stream bị dispose
      controller.onCancel = () {
        if (kDebugMode) {
          print('getPostsStream: Stream cancelled, cancelling timer');
        }
        periodicTimer?.cancel();
      };

      return controller.stream
          .asyncMap((postsSnapshot) async {
            if (kDebugMode) {
              print('Posts stream emitted: ${postsSnapshot.docs.length} documents');
              if (postsSnapshot.docs.isEmpty) {
                print('WARNING: Posts snapshot is empty!');
              }
              // Log first few post IDs for debugging
              if (postsSnapshot.docs.isNotEmpty) {
                print('First post IDs: ${postsSnapshot.docs.take(3).map((d) => d.id).toList()}');
              }
            }

            final hiddenData = await getHiddenData();
            final hiddenPostIds = hiddenData
                .where((id) => !id.startsWith('user_') && !id.startsWith('unfollow_'))
                .toSet();
            final hiddenUserIds = hiddenData.where((id) => id.startsWith('user_')).map((id) => id.substring(5)).toSet();
            final unfollowedUserIds = hiddenData
                .where((id) => id.startsWith('unfollow_'))
                .map((id) => id.substring(9))
                .toSet();

            // Lấy danh sách người bị chặn
            final blockService = BlockService();
            final blockedUserIds = await blockService.getBlockedUsers(currentUserId).first;

            if (kDebugMode) {
              print(
                'Hidden postIds: ${hiddenPostIds.length}, hiddenUserIds: ${hiddenUserIds.length}, unfollowedUserIds: ${unfollowedUserIds.length}',
              );
            }

            final friendIds = await FriendService().getFriends(currentUserId);

            // Filter posts by privacy, hidden/unfollow, blocked, and friend status
            final filtered = <PostModel>[];
            for (final doc in postsSnapshot.docs) {
              final post = PostModel.fromMap(doc.id, doc.data());

              if (hiddenPostIds.contains(post.id)) continue;
              if (hiddenUserIds.contains(post.userId)) continue;
              if (unfollowedUserIds.contains(post.userId)) continue;
              if (blockedUserIds.contains(post.userId)) continue; // Filter người bị chặn

              if (post.privacy == PrivacyType.public) {
                filtered.add(post);
                continue;
              }

              if (post.userId == currentUserId) {
                filtered.add(post);
                continue;
              }

              if (post.privacy == PrivacyType.friends) {
                if (friendIds.contains(post.userId)) {
                  filtered.add(post);
                }
                continue;
              }

              // Private -> only owner (already handled)
            }

            final ranked = await _rankPosts(filtered, currentUserId: currentUserId, friendIds: friendIds);

            if (kDebugMode) {
              print(
                'Filtered posts: ${filtered.length}, Ranked: ${ranked.length}, Returning: ${ranked.take(limit).length}',
              );
            }

            return ranked.take(limit).toList();
          })
          .handleError((error, stackTrace) {
            if (kDebugMode) {
              print('ERROR in getPostsStream (logged in): $error');
              print('Error type: ${error.runtimeType}');
              print('Error details: ${error.toString()}');
              print('Stack trace: $stackTrace');
            }
            return <PostModel>[];
          })
          .timeout(
            const Duration(seconds: 30),
            onTimeout: (sink) {
              if (kDebugMode) {
                print('TIMEOUT: Posts stream timed out after 30 seconds');
              }
              sink.add(<PostModel>[]);
              sink.close();
            },
          );
    } catch (e) {
      if (kDebugMode) {
        print('ERROR creating posts stream: $e');
        print('Error type: ${e.runtimeType}');
      }
      // Fallback: return empty stream
      return Stream.value(<PostModel>[]);
    }
  }

  /// Stream posts by group ID
  Stream<List<PostModel>> getPostsByGroupId(String groupId, {int limit = 50}) {
    if (groupId.isEmpty) return Stream.value(const <PostModel>[]);

    return _firestore
        .collection(AppConstants.postsCollection)
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .asyncMap((snapshot) async {
      final posts = snapshot.docs
          .map((doc) => PostModel.fromMap(doc.id, doc.data()))
          .toList();
      
      // Sort by createdAt descending
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return posts.length > limit ? posts.take(limit).toList() : posts;
    });
  }

  /// Stream posts by user and apply basic privacy based on viewer.
  Stream<List<PostModel>> getPostsByUserId(String userId, {String? viewerId, int limit = 50}) {
    if (userId.isEmpty) return Stream.value(const <PostModel>[]);

    // NOTE:
    // Query dạng where(userId == X) + orderBy(createdAt) yêu cầu composite index.
    // Để tránh lỗi [cloud_firestore/failed-precondition] trên máy chưa tạo index,
    // ta bỏ orderBy ở Firestore và sort trên client.
    return _firestore.collection(AppConstants.postsCollection).where('userId', isEqualTo: userId).snapshots().asyncMap((
      snapshot,
    ) async {
      final posts = snapshot.docs.map((doc) => PostModel.fromMap(doc.id, doc.data())).toList();

      // Sort newest first locally
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (viewerId == null) {
        final visible = posts.where((p) => p.privacy == PrivacyType.public).toList();
        return visible.length > limit ? visible.take(limit).toList() : visible;
      }
      if (viewerId == userId) {
        return posts.length > limit ? posts.take(limit).toList() : posts;
      }

      final viewerFriends = await FriendService().getFriends(viewerId);
      final isFriend = viewerFriends.contains(userId);

      // Kiểm tra xem có bị chặn không
      final blockService = BlockService();
      final isBlocked = await blockService.isBlocked(userId1: viewerId, userId2: userId);
      if (isBlocked) {
        return <PostModel>[]; // Không hiển thị bài viết nếu bị chặn
      }

      final visible = posts.where((p) {
        if (p.privacy == PrivacyType.public) return true;
        if (p.privacy == PrivacyType.friends) return isFriend;
        return false;
      }).toList();

      return visible.length > limit ? visible.take(limit).toList() : visible;
    });
  }

  /// Stream all posts for a user: both posts created by user and posts where user is tagged.
  Stream<List<PostModel>> getAllPostsForUser(String userId, {String? viewerId, int limit = 100}) {
    if (userId.isEmpty) return Stream.value(const <PostModel>[]);

    // Use StreamController to combine two streams
    final controller = StreamController<List<PostModel>>();
    List<PostModel>? ownPosts;
    List<PostModel>? taggedPosts;

    void emitIfReady() {
      if (ownPosts != null && taggedPosts != null) {
        // Combine and remove duplicates (same post ID)
        final allPosts = <String, PostModel>{};

        // Add own posts first
        for (final post in ownPosts!) {
          allPosts[post.id] = post;
        }

        // Add tagged posts (will not override if already exists)
        for (final post in taggedPosts!) {
          if (!allPosts.containsKey(post.id)) {
            allPosts[post.id] = post;
          }
        }

        // Convert to list and sort by createdAt
        final combined = allPosts.values.toList();
        combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final result = combined.length > limit ? combined.take(limit).toList() : combined;
        if (!controller.isClosed) {
          controller.add(result);
        }
      }
    }

    // Stream 1: User's own posts
    final ownPostsSubscription = getPostsByUserId(userId, viewerId: viewerId, limit: limit).listen(
      (posts) {
        ownPosts = posts;
        emitIfReady();
      },
      onError: (error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );

    // Stream 2: Tagged posts
    final taggedPostsStream = _firestore.collection(AppConstants.postsCollection).snapshots().asyncMap((
      snapshot,
    ) async {
      final posts = <PostModel>[];

      for (final doc in snapshot.docs) {
        try {
          final post = PostModel.fromMap(doc.id, doc.data());
          // Check if user is tagged and not removed
          if (post.taggedUserIds.contains(userId) && !post.removedTaggedUserIds.contains(userId)) {
            // Apply privacy rules
            if (viewerId == null) {
              if (post.privacy == PrivacyType.public) {
                posts.add(post);
              }
            } else if (viewerId == userId) {
              // User viewing their own tagged posts - show all
              posts.add(post);
            } else {
              // Check privacy for other viewers
              if (post.privacy == PrivacyType.public) {
                posts.add(post);
              } else if (post.privacy == PrivacyType.friends) {
                final viewerFriends = await FriendService().getFriends(viewerId);
                if (viewerFriends.contains(post.userId)) {
                  posts.add(post);
                }
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error parsing tagged post ${doc.id}: $e');
          }
        }
      }

      // Sort by createdAt descending
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    });

    final taggedPostsSubscription = taggedPostsStream.listen(
      (posts) {
        taggedPosts = posts;
        emitIfReady();
      },
      onError: (error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );

    // Clean up subscriptions when controller is closed
    controller.onCancel = () {
      ownPostsSubscription.cancel();
      taggedPostsSubscription.cancel();
    };

    return controller.stream;
  }

  Future<List<PostModel>> _rankPosts(
    List<PostModel> posts, {
    required String currentUserId,
    required List<String> friendIds,
  }) async {
    // Minimal ranking: newest first.
    // If RecommendationService is ready, you can upgrade here.
    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts;
  }

  // =====================
  // Viewed posts
  // =====================

  Future<Set<String>> getViewedPostIds(String userId) async {
    try {
      if (userId.isEmpty) return <String>{};
      final snapshot = await _firestore
          .collection(AppConstants.viewedPostsCollection)
          .where('userId', isEqualTo: userId)
          .limit(2000)
          .get();
      final set = <String>{};
      for (final doc in snapshot.docs) {
        final postId = (doc.data()['postId'] as String?) ?? '';
        if (postId.isNotEmpty) set.add(postId);
      }
      return set;
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> markPostAsViewed(String postId, String userId) async {
    try {
      if (postId.isEmpty || userId.isEmpty) return;
      final docId = '${userId}_$postId';
      await _firestore.collection(AppConstants.viewedPostsCollection).doc(docId).set({
        'userId': userId,
        'postId': postId,
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // =====================
  // Saved posts
  // =====================

  Future<bool> isPostSaved(String postId, String userId) async {
    try {
      if (postId.isEmpty || userId.isEmpty) return false;
      final key = _savedKey(userId, postId);
      if (_savedCache.containsKey(key)) return _savedCache[key] == true;
      final inflight = _savedInflight[key];
      if (inflight != null) return await inflight;

      final docId = '${userId}_$postId';
      final future = _firestore
          .collection(AppConstants.savedPostsCollection)
          .doc(docId)
          .get()
          .then((doc) => doc.exists);

      _savedInflight[key] = future;
      final exists = await future;
      _savedInflight.remove(key);
      _savedCache[key] = exists;
      return exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> savePost(String postId, String userId) async {
    try {
      if (postId.isEmpty || userId.isEmpty) return;
      final docId = '${userId}_$postId';
      await _firestore.collection(AppConstants.savedPostsCollection).doc(docId).set({
        'userId': userId,
        'postId': postId,
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      _savedCache[_savedKey(userId, postId)] = true;
    } catch (e) {
      throw Exception('Save post failed: $e');
    }
  }

  Future<void> unsavePost(String postId, String userId) async {
    try {
      if (postId.isEmpty || userId.isEmpty) return;
      final docId = '${userId}_$postId';
      await _firestore.collection(AppConstants.savedPostsCollection).doc(docId).delete();

      _savedCache[_savedKey(userId, postId)] = false;
    } catch (e) {
      throw Exception('Unsave post failed: $e');
    }
  }

  Stream<List<PostModel>> getSavedPosts(String userId) {
    if (userId.isEmpty) return Stream.value(const <PostModel>[]);

    return _firestore
        .collection(AppConstants.savedPostsCollection)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
          final docs = snapshot.docs;

          // Sort client-side by createdAt desc to avoid Firestore composite index
          docs.sort((a, b) {
            final ta = a.data()['createdAt'];
            final tb = b.data()['createdAt'];
            if (ta is Timestamp && tb is Timestamp) {
              return tb.compareTo(ta);
            }
            return 0;
          });

          final postIds = docs.map((d) => (d.data()['postId'] as String?) ?? '').where((id) => id.isNotEmpty).toList();

          if (postIds.isEmpty) return <PostModel>[];

          // Batch fetch posts by ids (whereIn <= 10)
          final byId = <String, PostModel>{};
          for (var i = 0; i < postIds.length; i += 10) {
            final batch = postIds.sublist(i, i + 10 > postIds.length ? postIds.length : i + 10);
            final postsSnap = await _firestore
                .collection(AppConstants.postsCollection)
                .where(FieldPath.documentId, whereIn: batch)
                .get();
            for (final doc in postsSnap.docs) {
              byId[doc.id] = PostModel.fromMap(doc.id, doc.data());
            }
          }

          // Keep saved order
          return postIds.map((id) => byId[id]).whereType<PostModel>().toList();
        });
  }

  // =====================
  // Comments
  // =====================

  Future<String> createComment(CommentModel comment) async {
    try {
      final ref = await _firestore.collection(AppConstants.commentsCollection).add(comment.toMap());

      // Keep id inside document for easier client usage
      await ref.update({'id': ref.id});

      // Update post comments count
      await _firestore.collection(AppConstants.postsCollection).doc(comment.postId).update({
        'commentsCount': FieldValue.increment(1),
      });

      // 🔔 App notifications for comments / replies
      try {
        final now = DateTime.now();
        String? targetUserId;
        NotificationType? notificationType;

        if (comment.parentId != null && comment.parentId!.isNotEmpty) {
          // Reply to another comment -> notify comment owner
          final parentSnap = await _firestore.collection(AppConstants.commentsCollection).doc(comment.parentId!).get();
          final parentUserId = parentSnap.data()?['userId']?.toString();
          if (parentUserId != null && parentUserId.isNotEmpty && parentUserId != comment.userId) {
            targetUserId = parentUserId;
            notificationType = NotificationType.reply;
          }
        } else {
          // Top-level comment -> notify post owner
          final postSnap = await _firestore.collection(AppConstants.postsCollection).doc(comment.postId).get();
          final postUserId = postSnap.data()?['userId']?.toString();
          if (postUserId != null && postUserId.isNotEmpty && postUserId != comment.userId) {
            targetUserId = postUserId;
            notificationType = NotificationType.comment;
          }
        }

        if (targetUserId != null && notificationType != null) {
          unawaited(
            _notificationService.createNotification(
              NotificationModel(
                id: '',
                userId: targetUserId,
                actorId: comment.userId,
                type: notificationType,
                postId: comment.postId,
                commentId: ref.id,
                createdAt: now,
              ),
            ),
          );

          // Log activity: user comment bài viết của targetUserId
          if (notificationType == NotificationType.comment) {
            unawaited(
              ActivityLogService().logActivity(
                ActivityLogModel(
                  id: '',
                  userId: comment.userId, // User thực hiện hành động (người comment)
                  type: ActivityType.comment,
                  targetUserId: targetUserId, // Chủ bài viết
                  targetPostId: comment.postId,
                  commentId: ref.id,
                  createdAt: now,
                ),
              ),
            );
          }
        }
      } catch (_) {
        // Ignore notification failures to avoid breaking comment flow
      }

      // Interaction (optional)
      unawaited(
        _logInteraction(
          UserInteractionModel(
            userId: comment.userId,
            targetId: comment.postId,
            targetType: 'post',
            type: InteractionType.comment,
            timestamp: DateTime.now(),
          ),
        ),
      );

      return ref.id;
    } catch (e) {
      throw Exception('Create comment failed: $e');
    }
  }

  Stream<List<CommentModel>> getCommentsStream(String postId) {
    if (postId.isEmpty) return Stream.value(const <CommentModel>[]);

    return _firestore
        .collection(AppConstants.commentsCollection)
        .where('postId', isEqualTo: postId)
        .where('parentId', isNull: true)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => CommentModel.fromMap(doc.id, doc.data())).toList();
        });
  }

  Stream<List<CommentModel>> getRepliesStream(String parentCommentId) {
    if (parentCommentId.isEmpty) return Stream.value(const <CommentModel>[]);

    return _firestore
        .collection(AppConstants.commentsCollection)
        .where('parentId', isEqualTo: parentCommentId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => CommentModel.fromMap(doc.id, doc.data())).toList();
        });
  }

  Future<void> updateComment(CommentModel comment) async {
    try {
      if (comment.id.isEmpty) {
        throw Exception('Comment ID is required for update');
      }
      await _firestore.collection(AppConstants.commentsCollection).doc(comment.id).update(comment.toMap());
    } catch (e) {
      throw Exception('Update comment failed: $e');
    }
  }

  Future<void> deleteComment(String commentId) async {
    try {
      if (commentId.isEmpty) return;
      
      // Get comment to update post comments count
      final commentDoc = await _firestore.collection(AppConstants.commentsCollection).doc(commentId).get();
      if (commentDoc.exists) {
        final commentData = commentDoc.data();
        final postId = commentData?['postId'] as String?;
        
        // Delete comment
        await _firestore.collection(AppConstants.commentsCollection).doc(commentId).delete();
        
        // Update post comments count
        if (postId != null && postId.isNotEmpty) {
          await _firestore.collection(AppConstants.postsCollection).doc(postId).update({
            'commentsCount': FieldValue.increment(-1),
          });
        }
      }
    } catch (e) {
      throw Exception('Delete comment failed: $e');
    }
  }

  // =====================
  // Reactions (posts)
  // =====================

  String _postReactionDocId(String postId, String userId) => 'post_${postId}_$userId';
  String _commentReactionDocId(String commentId, String userId) => 'comment_${commentId}_$userId';

  Future<ReactionType?> getUserReaction(String postId, String userId) async {
    try {
      if (postId.isEmpty || userId.isEmpty) return null;
      final key = _postReactionKey(userId, postId);
      if (_postUserReactionCache.containsKey(key)) {
        return _postUserReactionCache[key];
      }
      final inflight = _postUserReactionInflight[key];
      if (inflight != null) return await inflight;

      final future = _firestore
          .collection(AppConstants.likesCollection)
          .doc(_postReactionDocId(postId, userId))
          .get()
          .then<ReactionType?>((doc) {
            if (!doc.exists) return null;
            final typeStr = doc.data()?['type']?.toString();
            if (typeStr == null) return null;
            return ReactionTypeExtension.fromString(typeStr);
          });

      _postUserReactionInflight[key] = future;
      final result = await future;
      _postUserReactionInflight.remove(key);
      _postUserReactionCache[key] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<Map<ReactionType, int>> getPostReactions(String postId) async {
    try {
      if (postId.isEmpty) return <ReactionType, int>{};

      final cachedAt = _postReactionsCacheAt[postId];
      final cached = _postReactionsCache[postId];
      if (cachedAt != null && cached != null && DateTime.now().difference(cachedAt) <= _countsTtl) {
        return cached;
      }
      final inflight = _postReactionsInflight[postId];
      if (inflight != null) return await inflight;

      final future = _firestore
          .collection(AppConstants.likesCollection)
          .where('targetType', isEqualTo: 'post')
          .where('postId', isEqualTo: postId)
          .limit(2000)
          .get()
          .then<Map<ReactionType, int>>((snapshot) {
            final counts = <ReactionType, int>{};
            for (final doc in snapshot.docs) {
              final typeStr = doc.data()['type']?.toString();
              final type = typeStr == null ? null : ReactionTypeExtension.fromString(typeStr);
              if (type == null) continue;
              counts[type] = (counts[type] ?? 0) + 1;
            }
            return counts;
          });

      _postReactionsInflight[postId] = future;
      final counts = await future;
      _postReactionsInflight.remove(postId);
      _postReactionsCache[postId] = counts;
      _postReactionsCacheAt[postId] = DateTime.now();
      return counts;
    } catch (_) {
      return <ReactionType, int>{};
    }
  }

  Future<void> reactToPost(String postId, String userId, ReactionType type) async {
    if (postId.isEmpty || userId.isEmpty) return;

    final docId = _postReactionDocId(postId, userId);
    final ref = _firestore.collection(AppConstants.likesCollection).doc(docId);

    var shouldNotify = false;

    // Retry transaction up to 3 times in case of conflicts
    int retries = 0;
    const maxRetries = 3;

    while (retries < maxRetries) {
      try {
        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(ref);

          if (snap.exists) {
            final existingType = snap.data()?['type']?.toString();
            if (existingType == type.toValue()) {
              // toggle off
              tx.delete(ref);
              tx.update(_firestore.collection(AppConstants.postsCollection).doc(postId), {
                'likesCount': FieldValue.increment(-1),
              });
            } else {
              // change type
              tx.update(ref, {'type': type.toValue(), 'updatedAt': DateTime.now().toIso8601String()});
              shouldNotify = true;
            }
          } else {
            // create new reaction
            tx.set(ref, {
              'targetType': 'post',
              'postId': postId,
              'userId': userId,
              'type': type.toValue(),
              'createdAt': DateTime.now().toIso8601String(),
            });
            tx.update(_firestore.collection(AppConstants.postsCollection).doc(postId), {
              'likesCount': FieldValue.increment(1),
            });
            shouldNotify = true;
          }
        });

        // Transaction succeeded, break out of retry loop
        break;
      } catch (e, stackTrace) {
        retries++;
        if (kDebugMode) {
          print('ERROR in reactToPost transaction (attempt $retries/$maxRetries): $e');
          print('Error type: ${e.runtimeType}');
        }

        // If it's the last retry or a non-retryable error, throw
        if (retries >= maxRetries || e.toString().contains('permission-denied') || e.toString().contains('not-found')) {
          if (kDebugMode) {
            print('Stack trace: $stackTrace');
          }
          rethrow; // Re-throw để UI có thể handle
        }

        // Wait a bit before retrying (exponential backoff)
        await Future.delayed(Duration(milliseconds: 100 * retries));
      }
    }

    // 🔔 App notification for post reactions (any ReactionType treated as "like")
    if (shouldNotify) {
      try {
        final postSnap = await _firestore.collection(AppConstants.postsCollection).doc(postId).get();
        final postUserId = postSnap.data()?['userId']?.toString();

        if (postUserId != null && postUserId.isNotEmpty && postUserId != userId) {
          unawaited(
            _notificationService.createNotification(
              NotificationModel(
                id: '',
                userId: postUserId,
                actorId: userId,
                // Backend text uses "like" for post reactions
                type: NotificationType.like,
                postId: postId,
                createdAt: DateTime.now(),
              ),
            ),
          );

          // Log activity: user like bài viết của postUserId
          final activityLogService = ActivityLogService();
          unawaited(
            activityLogService.logActivity(
              ActivityLogModel(
                id: '',
                userId: userId, // User thực hiện hành động (người like)
                type: ActivityType.like,
                targetUserId: postUserId, // Chủ bài viết
                targetPostId: postId,
                createdAt: DateTime.now(),
              ),
            ),
          );
          if (kDebugMode) {
            print('reactToPost: Logging activity - user $userId liked post $postId of user $postUserId');
          }
        } else {
          if (kDebugMode) {
            print('reactToPost: Skipping activity log - postUserId: $postUserId, userId: $userId');
          }
        }
      } catch (e) {
        // Ignore notification failures
        if (kDebugMode) {
          print('reactToPost: Error creating notification/activity log: $e');
        }
      }
    } else {
      if (kDebugMode) {
        print('reactToPost: shouldNotify is false, skipping activity log');
      }
    }

    // Invalidate caches for this user/post to reduce follow-up reads.
    final key = _postReactionKey(userId, postId);
    _postUserReactionCache.remove(key);
    _postUserReactionInflight.remove(key);
    _postReactionsCache.remove(postId);
    _postReactionsCacheAt.remove(postId);
    _postReactionsInflight.remove(postId);

    // Interaction (optional)
    unawaited(
      _logInteraction(
        UserInteractionModel(
          userId: userId,
          targetId: postId,
          targetType: 'post',
          type: InteractionType.like,
          timestamp: DateTime.now(),
        ),
      ),
    );
  }

  Future<List<String>> getPostReactionUsers(String postId, ReactionType type) async {
    try {
      if (postId.isEmpty) return <String>[];
      final snapshot = await _firestore
          .collection(AppConstants.likesCollection)
          .where('targetType', isEqualTo: 'post')
          .where('postId', isEqualTo: postId)
          .where('type', isEqualTo: type.toValue())
          .limit(200)
          .get();
      return snapshot.docs.map((d) => (d.data()['userId'] as String?) ?? '').where((id) => id.isNotEmpty).toList();
    } catch (_) {
      return <String>[];
    }
  }

  // =====================
  // Reactions (comments)
  // =====================

  Future<ReactionType?> getUserCommentReaction(String commentId, String userId) async {
    try {
      if (commentId.isEmpty || userId.isEmpty) return null;
      final key = _commentReactionKey(userId, commentId);
      if (_commentUserReactionCache.containsKey(key)) {
        return _commentUserReactionCache[key];
      }
      final inflight = _commentUserReactionInflight[key];
      if (inflight != null) return await inflight;

      final future = _firestore
          .collection(AppConstants.likesCollection)
          .doc(_commentReactionDocId(commentId, userId))
          .get()
          .then<ReactionType?>((doc) {
            if (!doc.exists) return null;
            final typeStr = doc.data()?['type']?.toString();
            if (typeStr == null) return null;
            return ReactionTypeExtension.fromString(typeStr);
          });

      _commentUserReactionInflight[key] = future;
      final result = await future;
      _commentUserReactionInflight.remove(key);
      _commentUserReactionCache[key] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<Map<ReactionType, int>> getCommentReactions(String commentId) async {
    try {
      if (commentId.isEmpty) return <ReactionType, int>{};

      final cachedAt = _commentReactionsCacheAt[commentId];
      final cached = _commentReactionsCache[commentId];
      if (cachedAt != null && cached != null && DateTime.now().difference(cachedAt) <= _countsTtl) {
        return cached;
      }
      final inflight = _commentReactionsInflight[commentId];
      if (inflight != null) return await inflight;

      final future = _firestore
          .collection(AppConstants.likesCollection)
          .where('targetType', isEqualTo: 'comment')
          .where('commentId', isEqualTo: commentId)
          .limit(2000)
          .get()
          .then<Map<ReactionType, int>>((snapshot) {
            final counts = <ReactionType, int>{};
            for (final doc in snapshot.docs) {
              final typeStr = doc.data()['type']?.toString();
              final type = typeStr == null ? null : ReactionTypeExtension.fromString(typeStr);
              if (type == null) continue;
              counts[type] = (counts[type] ?? 0) + 1;
            }
            return counts;
          });

      _commentReactionsInflight[commentId] = future;
      final counts = await future;
      _commentReactionsInflight.remove(commentId);
      _commentReactionsCache[commentId] = counts;
      _commentReactionsCacheAt[commentId] = DateTime.now();
      return counts;
    } catch (_) {
      return <ReactionType, int>{};
    }
  }

  Future<void> reactToComment(String commentId, String userId, ReactionType type) async {
    if (commentId.isEmpty || userId.isEmpty) return;

    final docId = _commentReactionDocId(commentId, userId);
    final ref = _firestore.collection(AppConstants.likesCollection).doc(docId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);

      if (snap.exists) {
        final existingType = snap.data()?['type']?.toString();
        if (existingType == type.toValue()) {
          tx.delete(ref);
          tx.update(_firestore.collection(AppConstants.commentsCollection).doc(commentId), {
            'likesCount': FieldValue.increment(-1),
          });
        } else {
          tx.update(ref, {'type': type.toValue(), 'updatedAt': DateTime.now().toIso8601String()});
        }
      } else {
        tx.set(ref, {
          'targetType': 'comment',
          'commentId': commentId,
          'userId': userId,
          'type': type.toValue(),
          'createdAt': DateTime.now().toIso8601String(),
        });
        tx.update(_firestore.collection(AppConstants.commentsCollection).doc(commentId), {
          'likesCount': FieldValue.increment(1),
        });
      }
    });

    // Invalidate caches
    final key = _commentReactionKey(userId, commentId);
    _commentUserReactionCache.remove(key);
    _commentUserReactionInflight.remove(key);
    _commentReactionsCache.remove(commentId);
    _commentReactionsCacheAt.remove(commentId);
    _commentReactionsInflight.remove(commentId);
  }

  // =====================
  // Hide / Report / Block
  // =====================

  Future<void> hidePost(String postId, String userId) async {
    try {
      if (postId.isEmpty || userId.isEmpty) return;
      final docId = '${userId}_post_$postId';
      await _firestore.collection(AppConstants.hiddenPostsCollection).doc(docId).set({
        'userId': userId,
        'postId': postId,
        'type': 'post',
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Hide post failed: $e');
    }
  }

  /// Temporarily hide a user for 30 days.
  /// Params order matches UI calls: (viewerId, hiddenUserId)
  Future<void> temporarilyHideUser(String userId, String hiddenUserId) async {
    try {
      if (userId.isEmpty || hiddenUserId.isEmpty) return;
      final until = DateTime.now().add(const Duration(days: 30));
      final docId = '${userId}_user_$hiddenUserId';
      await _firestore.collection(AppConstants.hiddenPostsCollection).doc(docId).set({
        'userId': userId,
        'hiddenUserId': hiddenUserId,
        'hideUntil': until.toIso8601String(),
        'type': 'user',
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Temporarily hide user failed: $e');
    }
  }

  /// Unhide a temporarily hidden user
  Future<void> unhideUser(String userId, String hiddenUserId) async {
    try {
      if (userId.isEmpty || hiddenUserId.isEmpty) return;
      final docId = '${userId}_user_$hiddenUserId';
      await _firestore.collection(AppConstants.hiddenPostsCollection).doc(docId).delete();
    } catch (e) {
      throw Exception('Unhide user failed: $e');
    }
  }

  /// Get list of temporarily hidden users
  Future<List<Map<String, dynamic>>> getTemporarilyHiddenUsers(String userId) async {
    try {
      if (userId.isEmpty) return [];
      
      final now = DateTime.now();
      final snapshot = await _firestore
          .collection(AppConstants.hiddenPostsCollection)
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'user')
          .get();

      final hiddenUsers = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final hideUntilStr = data['hideUntil'] as String?;
        if (hideUntilStr != null) {
          final hideUntil = DateTime.tryParse(hideUntilStr);
          if (hideUntil != null && hideUntil.isAfter(now)) {
            hiddenUsers.add({
              'hiddenUserId': data['hiddenUserId'] as String? ?? '',
              'hideUntil': hideUntil,
              'createdAt': DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
            });
          }
        }
      }
      
      return hiddenUsers;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting temporarily hidden users: $e');
      }
      return [];
    }
  }

  /// Check if a user is temporarily hidden
  Future<bool> isUserTemporarilyHidden(String userId, String hiddenUserId) async {
    try {
      if (userId.isEmpty || hiddenUserId.isEmpty) return false;
      
      final docId = '${userId}_user_$hiddenUserId';
      final doc = await _firestore.collection(AppConstants.hiddenPostsCollection).doc(docId).get();
      
      if (!doc.exists) return false;
      
      final data = doc.data();
      final hideUntilStr = data?['hideUntil'] as String?;
      if (hideUntilStr == null) return false;
      
      final hideUntil = DateTime.tryParse(hideUntilStr);
      if (hideUntil == null) return false;
      
      return hideUntil.isAfter(DateTime.now());
    } catch (e) {
      if (kDebugMode) {
        print('Error checking if user is hidden: $e');
      }
      return false;
    }
  }

  /// Get list of hidden posts
  Future<List<Map<String, dynamic>>> getHiddenPosts(String userId) async {
    try {
      if (userId.isEmpty) return [];
      
      final snapshot = await _firestore
          .collection(AppConstants.hiddenPostsCollection)
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'post')
          .get();

      final hiddenPosts = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        hiddenPosts.add({
          'postId': data['postId'] as String? ?? '',
          'createdAt': DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
        });
      }
      
      return hiddenPosts;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting hidden posts: $e');
      }
      return [];
    }
  }

  /// Unhide a post
  Future<void> unhidePost(String postId, String userId) async {
    try {
      if (postId.isEmpty || userId.isEmpty) return;
      final docId = '${userId}_post_$postId';
      await _firestore.collection(AppConstants.hiddenPostsCollection).doc(docId).delete();
    } catch (e) {
      throw Exception('Unhide post failed: $e');
    }
  }

  Future<void> reportPost(String postId, String reporterId, String reason) async {
    try {
      if (postId.isEmpty || reporterId.isEmpty) return;
      await _firestore.collection(AppConstants.reportsCollection).add({
        'postId': postId,
        'reporterId': reporterId,
        'reason': reason,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Report post failed: $e');
    }
  }

  /// Remove tag from post - add user to removedTaggedUserIds array
  Future<void> removeTagFromPost(String postId, String userId) async {
    try {
      if (postId.isEmpty || userId.isEmpty) return;
      
      // Use FieldValue.arrayUnion to add userId to removedTaggedUserIds array
      await _firestore.collection(AppConstants.postsCollection).doc(postId).update({
        'removedTaggedUserIds': FieldValue.arrayUnion([userId]),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Remove tag from post failed: $e');
    }
  }

  Future<void> blockUser(String blockedUserId, String blockerId) async {
    try {
      if (blockedUserId.isEmpty || blockerId.isEmpty) return;
      final docId = '${blockerId}_$blockedUserId';
      await _firestore.collection(AppConstants.blocksCollection).doc(docId).set({
        'blockerId': blockerId,
        'blockedId': blockedUserId,
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Block user failed: $e');
    }
  }

  // =====================
  // Share
  // =====================

  Future<void> sharePost(String originalPostId, String userId) async {
    try {
      if (originalPostId.isEmpty || userId.isEmpty) return;

      final original = await getPost(originalPostId, viewerId: userId);
      if (original == null) {
        throw Exception('Bài viết gốc không tồn tại hoặc không thể truy cập');
      }

      // Create a new post that references the original
      final now = DateTime.now();
      final originalUserId = original.userId;
      final shared = PostModel(
        id: '',
        userId: userId,
        content: '',
        sharedPostId: originalPostId,
        privacy: PrivacyType.public,
        createdAt: now,
        updatedAt: now,
      );
      await createPost(shared);

      // Increment sharesCount on original
      await _firestore.collection(AppConstants.postsCollection).doc(originalPostId).update({
        'sharesCount': FieldValue.increment(1),
      });

      // Optional notification/event
      if (originalUserId != userId) {
        unawaited(
          _notificationService.createNotification(
            NotificationModel(
              id: '',
              userId: originalUserId,
              actorId: userId,
              type: NotificationType.share,
              postId: originalPostId,
              createdAt: now,
            ),
          ),
        );

        // Log activity: user share bài viết của originalUserId
        unawaited(
          ActivityLogService().logActivity(
            ActivityLogModel(
              id: '',
              userId: userId, // User thực hiện hành động (người share)
              type: ActivityType.share,
              targetUserId: originalUserId, // Chủ bài viết
              targetPostId: originalPostId,
              createdAt: now,
            ),
          ),
        );
      }
    } catch (e) {
      throw Exception('Share post failed: $e');
    }
  }

  // =====================
  // Interactions (optional)
  // =====================

  Future<void> _logInteraction(UserInteractionModel interaction) async {
    try {
      await _firestore.collection(AppConstants.userInteractionsCollection).add(interaction.toMap());
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Log interaction ignored: $e');
      }
    }
  }
}
