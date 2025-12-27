import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';
import '../../../data/models/post_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/post_card.dart';

class SavedPostsScreen extends StatelessWidget {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.appBarTheme.backgroundColor,
          title: Text(
            AppLocalizations.of(context)?.savedTitle ?? 'Đã lưu',
            style: TextStyle(color: theme.textTheme.titleLarge?.color),
          ),
        ),
        body: Center(
          child: Text(
            AppLocalizations.of(context)?.loginRequired ?? 'Vui lòng đăng nhập',
            style: TextStyle(color: theme.textTheme.bodyLarge?.color),
          ),
        ),
      );
    }

    final firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        title: Text(
          AppLocalizations.of(context)?.savedTitle ?? 'Đã lưu',
          style: TextStyle(color: theme.textTheme.titleLarge?.color),
        ),
      ),
      body: StreamBuilder<List<PostModel>>(
        stream: firestoreService.getSavedPosts(currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: theme.primaryColor),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Lỗi: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        // Force rebuild
                        (context as Element).markNeedsBuild();
                      },
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bookmark_border,
                      size: 64,
                      color: theme.iconTheme.color?.withOpacity(0.6),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)?.savedEmptyTitle ??
                          'Chưa có bài viết nào được lưu',
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)?.savedEmptyDesc ??
                          'Lưu bài viết để xem lại sau',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final posts = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              return PostCard(post: posts[index]);
            },
          );
        },
      ),
    );
  }
}


