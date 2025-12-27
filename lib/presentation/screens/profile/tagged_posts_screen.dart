import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/models/post_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/post_card.dart';

class TaggedPostsScreen extends StatelessWidget {
  final String userId;

  const TaggedPostsScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<List<PostModel>>(
      stream: _getTaggedPosts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Lỗi: ${snapshot.error}',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.tag,
                  size: 64,
                  color: theme.iconTheme.color?.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Chưa có bài viết nào được gắn thẻ',
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
          );
        }

        final posts = snapshot.data!;
        return ListView.builder(
          itemCount: posts.length,
          itemBuilder: (context, index) {
            return PostCard(post: posts[index]);
          },
        );
      },
    );
  }

  Stream<List<PostModel>> _getTaggedPosts() {
    return FirebaseFirestore.instance
        .collection(AppConstants.postsCollection)
        .snapshots()
        .asyncMap((snapshot) async {
      final posts = <PostModel>[];

      for (final doc in snapshot.docs) {
        final post = PostModel.fromMap(doc.id, doc.data());
        // Kiểm tra xem user có trong taggedUserIds và không trong removedTaggedUserIds
        if (post.taggedUserIds.contains(userId) &&
            !post.removedTaggedUserIds.contains(userId)) {
          posts.add(post);
        }
      }

      // Sắp xếp mới nhất trước
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    });
  }
}

