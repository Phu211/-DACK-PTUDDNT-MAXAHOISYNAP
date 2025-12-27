import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/post_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/block_service.dart';
import '../../../data/services/profile_view_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/post_card.dart';
import '../../widgets/profile_highlights_widget.dart';
import '../messages/chat_screen.dart';
import '../../../core/utils/error_message_helper.dart';

class OtherUserProfileScreen extends StatefulWidget {
  final UserModel user;

  const OtherUserProfileScreen({super.key, required this.user});

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FriendService _friendService = FriendService();
  final BlockService _blockService = BlockService();
  ScaffoldMessengerState? _scaffoldMessenger;
  bool _isFriend = false;
  bool _hasPendingRequest = false;
  bool _isOutgoingRequest = false;
  bool _isLoading = false;
  bool _isBlocked = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      print('OtherUserProfileScreen: initState called for user: ${widget.user.id}');
    }
    _checkFriendship();
    _checkBlockStatus();
    // Track profile view khi mở profile của người khác
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kDebugMode) {
        print('OtherUserProfileScreen: PostFrameCallback executed, mounted: $mounted');
      }
      if (mounted) {
        _trackProfileView();
      } else {
        if (kDebugMode) {
          print('OtherUserProfileScreen: Widget not mounted, skipping track');
        }
      }
    });
  }

  void _trackProfileView() {
    try {
      if (kDebugMode) {
        print('OtherUserProfileScreen: _trackProfileView called - profileUserId: ${widget.user.id}');
      }

      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;

      if (kDebugMode) {
        print('OtherUserProfileScreen: currentUser: ${currentUser?.id}, profileUserId: ${widget.user.id}');
      }

      if (currentUser == null) {
        if (kDebugMode) {
          print('OtherUserProfileScreen: No current user, skipping track');
        }
        return;
      }

      if (currentUser.id == widget.user.id) {
        if (kDebugMode) {
          print('OtherUserProfileScreen: User viewing own profile, skipping');
        }
        return;
      }

      if (kDebugMode) {
        print(
          'OtherUserProfileScreen: Calling recordProfileView - profileUserId: ${widget.user.id}, viewerUserId: ${currentUser.id}',
        );
      }

      final profileViewService = ProfileViewService();
      // profileUserId: user được xem, viewerUserId: user đang xem
      profileViewService.recordProfileView(widget.user.id, currentUser.id).catchError((error) {
        if (kDebugMode) {
          print('OtherUserProfileScreen: Error recording profile view: $error');
        }
      });
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('OtherUserProfileScreen: Error in _trackProfileView: $e');
        print('OtherUserProfileScreen: Stack trace: $stackTrace');
      }
    }
  }

  Future<void> _checkBlockStatus() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    try {
      final blocked = await _blockService.isUserBlockedByMe(blockerId: currentUser.id, blockedId: widget.user.id);
      if (mounted) {
        setState(() {
          _isBlocked = blocked;
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the messenger while this State is active, so async callbacks don't
    // need to look up ancestors on a potentially deactivated context.
    _scaffoldMessenger ??= ScaffoldMessenger.maybeOf(context);
  }

  void _showSnackBar(SnackBar snackBar) {
    _scaffoldMessenger?.showSnackBar(snackBar);
  }

  Future<void> _checkFriendship() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser != null) {
      final isFriend = await _friendService.isFriendWith(currentUser.id, widget.user.id);

      // Check pending requests in both directions
      final outgoingRequest = await _friendService.getPendingRequest(currentUser.id, widget.user.id);
      final incomingRequest = await _friendService.getPendingRequest(widget.user.id, currentUser.id);

      if (mounted) {
        setState(() {
          _isFriend = isFriend;
          _isOutgoingRequest = outgoingRequest != null;
          _hasPendingRequest = outgoingRequest != null || incomingRequest != null;
        });
      }
    }
  }

  Future<void> _sendFriendRequest() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _friendService.sendFriendRequest(currentUser.id, widget.user.id);
      if (mounted) {
        setState(() {
          _hasPendingRequest = true;
          _isOutgoingRequest = true;
        });
        _showSnackBar(const SnackBar(content: Text('Đã gửi lời mời kết bạn')));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _cancelFriendRequest() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _friendService.cancelFriendRequest(currentUser.id, widget.user.id);
      if (mounted) {
        setState(() {
          _hasPendingRequest = false;
          _isOutgoingRequest = false;
        });
        _showSnackBar(const SnackBar(content: Text('Đã hủy lời mời kết bạn')));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _unfriend() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy kết bạn'),
        content: Text('Bạn có chắc chắn muốn hủy kết bạn với ${widget.user.fullName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hủy kết bạn'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _friendService.unfriend(currentUser.id, widget.user.id);
      if (mounted) {
        setState(() {
          _isFriend = false;
        });
        _showSnackBar(const SnackBar(content: Text('Đã hủy kết bạn')));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _blockUser() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chặn người dùng'),
        content: Text(
          'Bạn có chắc chắn muốn chặn ${widget.user.fullName}? Các bạn sẽ không thể nhìn thấy hoặc liên hệ với nhau.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Chặn'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _blockService.blockUser(currentUser.id, widget.user.id);
      if (mounted) {
        setState(() {
          _isBlocked = true;
        });
        _showSnackBar(const SnackBar(content: Text('Đã chặn người dùng'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _unblockUser() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bỏ chặn người dùng'),
        content: Text('Bạn có chắc chắn muốn bỏ chặn ${widget.user.fullName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bỏ chặn')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _blockService.unblockUser(currentUser.id, widget.user.id);
      if (mounted) {
        setState(() {
          _isBlocked = false;
        });
        _showSnackBar(const SnackBar(content: Text('Đã bỏ chặn người dùng')));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        title: Text(widget.user.fullName, style: TextStyle(color: theme.textTheme.titleLarge?.color)),
        iconTheme: theme.iconTheme,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
            onSelected: (value) {
              if (value == 'block') {
                _blockUser();
              } else if (value == 'unblock') {
                _unblockUser();
              }
            },
            itemBuilder: (context) => [
              if (_isBlocked)
                const PopupMenuItem(
                  value: 'unblock',
                  child: Row(
                    children: [
                      Icon(Icons.person_add, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Bỏ chặn'),
                    ],
                  ),
                )
              else
                PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, color: Colors.red),
                      const SizedBox(width: 8),
                      const Text('Chặn'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Cover photo with avatar overlay
          SliverToBoxAdapter(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Cover photo
                Container(
                  height: 200,
                  width: double.infinity,
                  color: Colors.blue[300],
                  child: widget.user.coverUrl != null
                      ? Image.network(
                          widget.user.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(color: Colors.blue[300]);
                          },
                        )
                      : null,
                ),
                // Avatar positioned to overlap cover photo
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -50,
                  child: Center(
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.black,
                      child: CircleAvatar(
                        radius: 48,
                        backgroundImage: widget.user.avatarUrl != null ? NetworkImage(widget.user.avatarUrl!) : null,
                        child: widget.user.avatarUrl == null
                            ? Text(widget.user.fullName[0].toUpperCase(), style: const TextStyle(fontSize: 40))
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Profile info below avatar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Text(widget.user.fullName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  if (widget.user.bio != null) ...[
                    const SizedBox(height: 8),
                    Text(widget.user.bio!, style: TextStyle(color: Colors.grey[600])),
                  ],
                  const SizedBox(height: 16),
                  // Stats - lấy số bài viết thực tế từ Firestore
                  StreamBuilder<List<PostModel>>(
                    stream: _firestoreService.getPostsByUserId(
                      widget.user.id,
                      viewerId: context.read<AuthProvider>().currentUser?.id,
                    ),
                    builder: (context, postsSnapshot) {
                      final actualPostsCount = postsSnapshot.hasData
                          ? postsSnapshot.data!.length
                          : widget.user.postsCount;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatItem(label: 'Bài viết', value: actualPostsCount.toString()),
                          _StatItem(label: 'Người theo dõi', value: widget.user.followersCount.toString()),
                          _StatItem(label: 'Đang theo dõi', value: widget.user.followingCount.toString()),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : _isFriend
                                ? _unfriend
                                : _hasPendingRequest && _isOutgoingRequest
                                ? _cancelFriendRequest
                                : _hasPendingRequest
                                ? null
                                : _sendFriendRequest,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isFriend
                                  ? Colors.grey
                                  : _hasPendingRequest && _isOutgoingRequest
                                  ? Colors.orange
                                  : _hasPendingRequest
                                  ? Colors.orange.withOpacity(0.5)
                                  : Colors.blue,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : Text(
                                    _isFriend
                                        ? 'Bạn bè'
                                        : _hasPendingRequest && _isOutgoingRequest
                                        ? 'Hủy lời mời'
                                        : _hasPendingRequest
                                        ? 'Đang chờ xác nhận'
                                        : 'Thêm bạn bè',
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).push(MaterialPageRoute(builder: (_) => ChatScreen(otherUser: widget.user)));
                          },
                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                          label: const Text('Nhắn tin'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: BorderSide(color: Colors.grey.shade400),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Highlights section (moved below profile info, above posts)
          SliverToBoxAdapter(
            child: ProfileHighlightsWidget(userId: widget.user.id, isOwnProfile: false),
          ),
          // Posts (including tagged posts)
          StreamBuilder<List<PostModel>>(
            stream: _firestoreService.getAllPostsForUser(
              widget.user.id,
              viewerId: context.read<AuthProvider>().currentUser?.id, // Viewer là current user
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
              }

              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Không thể tải thông tin người dùng',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Lỗi: ${snapshot.error}',
                            style: const TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(padding: EdgeInsets.all(32.0), child: Text('Chưa có bài viết nào')),
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

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      ],
    );
  }
}
