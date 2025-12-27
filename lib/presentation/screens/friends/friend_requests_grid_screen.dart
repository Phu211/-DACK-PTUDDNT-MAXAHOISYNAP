import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/friend_request_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/user_service.dart';
import '../../providers/auth_provider.dart';
import '../profile/other_user_profile_screen.dart';
import 'friend_requests_screen.dart';

class FriendRequestsGridScreen extends StatelessWidget {
  const FriendRequestsGridScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final friendService = FriendService();
    final userService = UserService();

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Vui lòng đăng nhập')),
      );
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Lời mời kết bạn',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FriendRequestsScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Xem tất cả',
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
          // Friend requests grid
          Expanded(
            child: StreamBuilder<List<FriendRequestModel>>(
              stream: friendService.getFriendRequests(currentUser.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Lỗi: ${snapshot.error}',
                      style: const TextStyle(color: Colors.black),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text(
                      'Chưa có lời mời kết bạn nào',
                      style: TextStyle(color: Colors.black87),
                    ),
                  );
                }

                final requests = snapshot.data!;

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    return FutureBuilder<UserModel?>(
                      future: userService.getUserById(request.senderId),
                      builder: (context, userSnapshot) {
                        final sender = userSnapshot.data;
                        if (sender == null) {
                          return const SizedBox.shrink();
                        }

                        return FutureBuilder<int>(
                          future: friendService.getMutualFriendsCount(
                            currentUser.id,
                            sender.id,
                          ),
                          builder: (context, mutualSnapshot) {
                            final mutualCount = mutualSnapshot.data ?? 0;

                            return _FriendRequestCard(
                              sender: sender,
                              mutualCount: mutualCount,
                              onAccept: () async {
                                try {
                                  await friendService.acceptFriendRequest(
                                    request.id,
                                    request.senderId,
                                    request.receiverId,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Đã chấp nhận lời mời kết bạn'),
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
                              onDelete: () async {
                                try {
                                  await friendService.rejectFriendRequest(request.id);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Đã từ chối lời mời')),
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
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendRequestCard extends StatelessWidget {
  final UserModel sender;
  final int mutualCount;
  final VoidCallback onAccept;
  final VoidCallback onDelete;

  const _FriendRequestCard({
    required this.sender,
    required this.mutualCount,
    required this.onAccept,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OtherUserProfileScreen(user: sender),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      image: sender.avatarUrl != null
                          ? DecorationImage(
                              image: NetworkImage(sender.avatarUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: sender.avatarUrl == null
                          ? Colors.grey[800]
                          : null,
                    ),
                    child: sender.avatarUrl == null
                        ? Center(
                            child: Text(
                              sender.fullName[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                  ),
                  // Edit icon (optional)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.black,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sender.fullName,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (mutualCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$mutualCount bạn chung',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Buttons
                    ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        minimumSize: const Size(double.infinity, 0),
                      ),
                      child: const Text(
                        'Xác nhận',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: onDelete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.grey),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        minimumSize: const Size(double.infinity, 0),
                      ),
                      child: const Text(
                        'Xóa',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


