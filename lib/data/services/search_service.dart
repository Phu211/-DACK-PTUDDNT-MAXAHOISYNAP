import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_constants.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import 'friend_service.dart';

class SearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FriendService _friendService = FriendService();

  // Search users, ưu tiên bạn bè và match tên
  Stream<List<UserModel>> searchUsers(String query, {String? currentUserId}) {
    if (query.isEmpty) {
      return Stream.value([]);
    }

    final normalizedQuery = _normalizeQuery(query);
    final lowerQuery = query.toLowerCase();

    // Tìm kiếm theo cả searchName và searchUsername
    // Vì Firestore không hỗ trợ OR query, ta sẽ query theo searchName (cho tên đầy đủ)
    // và searchUsername (cho username), sau đó merge kết quả bằng StreamController
    final controller = StreamController<List<UserModel>>();
    
    final nameStream = _firestore
        .collection(AppConstants.usersCollection)
        .where('searchName', isGreaterThanOrEqualTo: normalizedQuery)
        .where('searchName', isLessThanOrEqualTo: '$normalizedQuery\uf8ff')
        .limit(50)
        .snapshots();

    final usernameStream = _firestore
        .collection(AppConstants.usersCollection)
        .where('searchUsername', isGreaterThanOrEqualTo: lowerQuery)
        .where('searchUsername', isLessThanOrEqualTo: '$lowerQuery\uf8ff')
        .limit(50)
        .snapshots();

    // Combine 2 streams bằng cách listen cả 2 và merge
    final allUsers = <String, UserModel>{};
    bool nameDone = false;
    bool usernameDone = false;
    bool emitted = false;

    void checkAndEmit() {
      if (nameDone && usernameDone && !emitted) {
        emitted = true;
        var users = allUsers.values.toList();

        // Lọc lại để đảm bảo match với query (cả tên và username)
        users = users.where((user) {
          final nameMatch = user.searchName.contains(normalizedQuery);
          final usernameMatch = user.searchUsername.contains(lowerQuery);
          return nameMatch || usernameMatch;
        }).toList();

        // Sort và emit
        if (currentUserId != null) {
          _friendService.getFriends(currentUserId).then((friendIds) {
            users.sort((a, b) {
              int score(UserModel u) {
                int s = 0;
                if (u.id == currentUserId) s += 100;
                if (friendIds.contains(u.id)) s += 50;
                if (u.searchName.startsWith(normalizedQuery) || u.searchUsername.startsWith(lowerQuery)) {
                  s += 10;
                } else if (u.searchName.contains(normalizedQuery) || u.searchUsername.contains(lowerQuery)) {
                  s += 5;
                }
                return s;
              }
              return score(b).compareTo(score(a));
            });
            controller.add(users);
            controller.close();
          });
        } else {
          controller.add(users);
          controller.close();
        }
      }
    }

    nameStream.listen((snapshot) {
      for (var doc in snapshot.docs) {
        final user = UserModel.fromMap(doc.id, doc.data());
        allUsers[user.id] = user;
      }
      nameDone = true;
      checkAndEmit();
    }, onError: (error) {
      if (!emitted) {
        emitted = true;
        controller.addError(error);
        controller.close();
      }
    });

    usernameStream.listen((snapshot) {
      for (var doc in snapshot.docs) {
        final user = UserModel.fromMap(doc.id, doc.data());
        allUsers[user.id] = user;
      }
      usernameDone = true;
      checkAndEmit();
    }, onError: (error) {
      if (!emitted) {
        emitted = true;
        controller.addError(error);
        controller.close();
      }
    });

    return controller.stream.asyncMap((users) async {
      // Nếu có currentUserId, ưu tiên bạn bè + chính mình
      if (currentUserId != null) {
        final friendIds = await _friendService.getFriends(currentUserId);

        users.sort((a, b) {
          int score(UserModel u) {
            int s = 0;
            if (u.id == currentUserId) s += 100;
            if (friendIds.contains(u.id)) s += 50;

            // match mạnh hơn nếu tên bắt đầu bằng từ khóa
            if (u.searchName.startsWith(normalizedQuery) || u.searchUsername.startsWith(lowerQuery)) {
              s += 10;
            } else if (u.searchName.contains(normalizedQuery) || u.searchUsername.contains(lowerQuery)) {
              s += 5;
            }
            return s;
          }

          return score(b).compareTo(score(a));
        });
      }

      return users;
    });
  }

  // Search posts by content (chỉ hiển thị public posts trong search)
  Stream<List<PostModel>> searchPosts(String query, {String? currentUserId}) {
    if (query.isEmpty) {
      return Stream.value([]);
    }

    final normalizedQuery = _normalizeQuery(query);
    
    return _firestore
        .collection(AppConstants.postsCollection)
        .where('privacy', isEqualTo: 'public') // Chỉ tìm kiếm public posts
        .limit(100)
        .snapshots()
        .asyncMap((snapshot) async {
      var posts = snapshot.docs
          .map((doc) => PostModel.fromMap(doc.id, doc.data()))
          .where((post) => post.searchContent.contains(normalizedQuery))
          .toList();

      // Nếu có currentUserId, có thể thêm friends posts (tùy chọn)
      if (currentUserId != null) {
        // Có thể mở rộng để bao gồm friends posts nếu cần
        // Nhưng theo nguyên tắc, search chỉ nên hiển thị public
        // await _friendService.getFriends(currentUserId);
      }

      // Tạm xếp theo thời gian mới nhất trước (score nâng cao có thể thêm sau)
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    });
  }

  // Normalize query để search (lowercase + bỏ dấu)
  static String _normalizeQuery(String input) {
    final lower = input.toLowerCase();
    const withDiacritics = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
    const withoutDiacritics = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuu-yyyyyd';
    var result = '';
    for (var i = 0; i < lower.length; i++) {
      final char = lower[i];
      final index = withDiacritics.indexOf(char);
      result += index >= 0 ? withoutDiacritics[index] : char;
    }
    return result;
  }

  // Search posts by hashtag (chỉ hiển thị public posts)
  Stream<List<PostModel>> searchPostsByHashtag(String hashtag, {String? currentUserId}) {
    if (hashtag.isEmpty) {
      return Stream.value([]);
    }

    final cleanHashtag = hashtag.startsWith('#') ? hashtag.substring(1) : hashtag;
    
    return _firestore
        .collection(AppConstants.postsCollection)
        .where('privacy', isEqualTo: 'public') // Chỉ tìm kiếm public posts
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => PostModel.fromMap(doc.id, doc.data()))
          .where((post) => post.hashtags.any((tag) => 
            tag.toLowerCase() == cleanHashtag.toLowerCase()))
          .toList();
    });
  }
}


