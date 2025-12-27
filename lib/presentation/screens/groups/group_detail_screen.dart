import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/models/group_model.dart';
import '../../../data/models/post_model.dart';
import '../../../data/services/group_service.dart';
import '../../../data/services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/post_card.dart';
import 'group_settings_screen.dart';
import 'create_group_post_screen.dart';
import 'invite_friends_to_group_screen.dart';

class GroupDetailScreen extends StatelessWidget {
  final GroupModel group;

  const GroupDetailScreen({super.key, required this.group});

  void _shareGroup(BuildContext context, GroupModel group) {
    // Tạo link chia sẻ nhóm
    // Có thể dùng deep link hoặc web link
    // Ví dụ: https://yourapp.com/group/{groupId}
    // Hoặc: yourapp://group/{groupId}
    final shareLink = 'https://synap.app/group/${group.id}';
    final shareText = 'Tham gia nhóm "${group.name}" trên Synap!\n\n$shareLink';
    
    Share.share(
      shareText,
      subject: 'Mời bạn tham gia nhóm ${group.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final groupService = GroupService();
    final firestoreService = FirestoreService();
    final isMember =
        currentUser != null && group.memberIds.contains(currentUser.id);
    final userRole = currentUser != null
        ? group.memberRoles[currentUser.id]
        : null;
    final isAdmin =
        userRole == GroupRole.admin || group.creatorId == currentUser?.id;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(group.name, style: const TextStyle(color: Colors.black)),
        actions: [
          // Nút đăng bài (chỉ hiển thị nếu là thành viên)
          if (isMember)
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.black),
              tooltip: 'Đăng bài',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CreateGroupPostScreen(group: group),
                  ),
                );
              },
            ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.black),
              onPressed: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupSettingsScreen(group: group),
                  ),
                );
                if (result == true) {
                  // Refresh group data if needed
                  Navigator.of(context).pop();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => GroupDetailScreen(group: group),
                    ),
                );
                }
              },
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Group header
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (group.coverUrl != null)
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: NetworkImage(group.coverUrl!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.group,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    group.name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (group.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      group.description!,
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '${group.memberIds.length} thành viên',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      const SizedBox(width: 16),
                      if (isMember)
                        ElevatedButton(
                          onPressed: () async {
                            try {
                              await groupService.leaveGroup(
                                group.id,
                                currentUser.id,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Đã rời nhóm')),
                                );
                                Navigator.of(context).pop();
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Lỗi: $e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                          ),
                          child: const Text('Rời nhóm'),
                        )
                      else
                        ElevatedButton(
                          onPressed: () async {
                            try {
                              await groupService.joinGroup(
                                group.id,
                                currentUser!.id,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã tham gia nhóm'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Lỗi: $e')),
                                );
                              }
                            }
                          },
                          child: const Text('Tham gia'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action buttons: Mời bạn bè và Chia sẻ
                  if (isMember)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final result = await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => InviteFriendsToGroupScreen(
                                    group: group,
                                    currentUserId: currentUser.id,
                                  ),
                                ),
                              );
                              if (result == true && context.mounted) {
                                // Refresh group data
                                Navigator.of(context).pop();
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => GroupDetailScreen(group: group),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.person_add, color: Colors.blue),
                            label: const Text(
                              'Mời bạn bè',
                              style: TextStyle(color: Colors.blue),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.blue),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _shareGroup(context, group),
                            icon: const Icon(Icons.share, color: Colors.blue),
                            label: const Text(
                              'Chia sẻ',
                              style: TextStyle(color: Colors.blue),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.blue),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          // Group posts
          StreamBuilder<List<PostModel>>(
            stream: firestoreService.getPostsByGroupId(group.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  ),
                );
              }

              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.black),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text(
                        'Chưa có bài viết nào trong nhóm',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ),
                );
              }

              final posts = snapshot.data!;

              return SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                    return PostCard(post: posts[index]);
                }, childCount: posts.length),
              );
            },
          ),
        ],
      ),
    );
  }
}

