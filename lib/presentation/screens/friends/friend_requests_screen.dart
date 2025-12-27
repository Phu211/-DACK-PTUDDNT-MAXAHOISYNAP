import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/friend_request_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/services/settings_service.dart';
import '../../providers/auth_provider.dart';
import '../profile/other_user_profile_screen.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  bool _suggestFriendsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestFriendsSetting();
  }

  Future<void> _loadSuggestFriendsSetting() async {
    final enabled = await SettingsService.isSuggestFriendsEnabled();
    if (mounted) {
      setState(() {
        _suggestFriendsEnabled = enabled;
      });
    }
  }

  Future<List<_SuggestedFriend>> _loadSuggestedFriends({
    required String currentUserId,
    required FriendService friendService,
    required UserService userService,
    required List<FriendRequestModel> incomingRequests,
  }) async {
    try {
      // Danh sách bạn bè hiện tại của user
      final currentFriends = await friendService.getFriends(currentUserId);
      final currentFriendsSet = currentFriends.toSet();

      // Những user đã gửi lời mời đến mình (đã hiển thị ở trên)
      final incomingRequestUserIds = incomingRequests
          .map((r) => r.senderId)
          .toSet();

      // Đếm số bạn chung: userId -> mutualCount
      final Map<String, int> mutualCounts = {};

      // Với mỗi bạn của mình, lấy friend list của họ để tìm "bạn của bạn"
      for (final friendId in currentFriendsSet) {
        final friendsOfFriend = await friendService.getFriends(friendId);
        for (final candidateId in friendsOfFriend) {
          if (candidateId == currentUserId) continue;
          if (currentFriendsSet.contains(candidateId)) continue;
          if (incomingRequestUserIds.contains(candidateId)) continue;

          mutualCounts.update(candidateId, (v) => v + 1, ifAbsent: () => 1);
        }
      }

      // Chuyển sang list và sort theo số bạn chung (giảm dần)
      final sortedEntries = mutualCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Giới hạn số gợi ý
      final limitedEntries = sortedEntries.take(10).toList();

      final List<_SuggestedFriend> suggestions = [];
      for (final entry in limitedEntries) {
        final user = await userService.getUserById(entry.key);
        if (user == null) continue;
        // Bỏ qua nếu đã có pending request hai chiều
        final hasPending = await friendService.hasPendingRequestBetween(
          currentUserId,
          user.id,
        );
        if (hasPending) continue;
        suggestions.add(
          _SuggestedFriend(user: user, mutualFriends: entry.value),
        );
      }

      return suggestions;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final friendService = FriendService();
    final userService = UserService();

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập')));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        title: Text(
          'Lời mời kết bạn',
          style: TextStyle(color: theme.textTheme.titleLarge?.color),
        ),
      ),
      body: StreamBuilder<List<FriendRequestModel>>(
        stream: friendService.getFriendRequests(currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: theme.primaryColor),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text(
                'Chưa có lời mời kết bạn nào',
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              ),
            );
          }

          final requests = snapshot.data!;

          // Chỉ load gợi ý nếu setting được bật
          return FutureBuilder<List<_SuggestedFriend>>(
            future: _suggestFriendsEnabled
                ? _loadSuggestedFriends(
                    currentUserId: currentUser.id,
                    friendService: friendService,
                    userService: userService,
                    incomingRequests: requests,
                  )
                : Future.value(const <_SuggestedFriend>[]),
            builder: (context, suggSnapshot) {
              final suggestions =
                  suggSnapshot.data ?? const <_SuggestedFriend>[];

              return ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  // Gợi ý bạn bè (nếu có và setting được bật)
                  if (_suggestFriendsEnabled && suggestions.isNotEmpty) ...[
                    Text(
                      'Bạn bè gợi ý',
                      style: TextStyle(
                        color: theme.textTheme.titleMedium?.color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...suggestions.map(
                      (s) => _SuggestedFriendItem(
                        friend: s,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  OtherUserProfileScreen(user: s.user),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 24),
                  ],

                  // Danh sách lời mời kết bạn
                  Text(
                    'Lời mời kết bạn',
                    style: TextStyle(
                      color: theme.textTheme.titleMedium?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...requests.map(
                    (request) => FutureBuilder<UserModel?>(
                      future: userService.getUserById(request.senderId),
                      builder: (context, userSnapshot) {
                        final sender = userSnapshot.data;
                        if (sender == null) {
                          return const SizedBox.shrink();
                        }

                        return _FriendRequestItem(
                          request: request,
                          sender: sender,
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
                                    content: Text(
                                      'Đã chấp nhận lời mời kết bạn',
                                    ),
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
                          onReject: () async {
                            try {
                              await friendService.rejectFriendRequest(
                                request.id,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã từ chối lời mời'),
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
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FriendRequestItem extends StatelessWidget {
  final FriendRequestModel request;
  final UserModel sender;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _FriendRequestItem({
    required this.request,
    required this.sender,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OtherUserProfileScreen(user: sender),
                ),
              );
            },
            child: CircleAvatar(
              radius: 30,
              backgroundImage: sender.avatarUrl != null
                  ? NetworkImage(sender.avatarUrl!)
                  : null,
              child: sender.avatarUrl == null
                  ? Text(
                      sender.fullName[0].toUpperCase(),
                      style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OtherUserProfileScreen(user: sender),
                      ),
                    );
                  },
                  child: Text(
                    sender.fullName,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text(
                          'Chấp nhận',
                          style: TextStyle(color: theme.colorScheme.onPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.textTheme.bodyLarge?.color,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: const Text('Từ chối'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedFriend {
  final UserModel user;
  final int mutualFriends;

  const _SuggestedFriend({required this.user, required this.mutualFriends});
}

class _SuggestedFriendItem extends StatelessWidget {
  final _SuggestedFriend friend;
  final VoidCallback onTap;

  const _SuggestedFriendItem({required this.friend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundImage: friend.user.avatarUrl != null
            ? NetworkImage(friend.user.avatarUrl!)
            : null,
        child: friend.user.avatarUrl == null
            ? Text(
                friend.user.fullName[0].toUpperCase(),
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
              )
            : null,
      ),
      title: Text(
        friend.user.fullName,
        style: TextStyle(color: theme.textTheme.bodyLarge?.color),
      ),
      subtitle: Text(
        '${friend.mutualFriends} bạn chung',
        style: TextStyle(color: theme.textTheme.bodySmall?.color),
      ),
      onTap: onTap,
    );
  }
}
