import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/user_model.dart';
import '../../../data/models/post_model.dart';
import '../../../data/services/search_service.dart';
import '../../providers/auth_provider.dart';
import '../profile/other_user_profile_screen.dart';
import '../../widgets/post_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final SearchService _searchService = SearchService();
  String _searchQuery = ''; // Query để tìm kiếm (chỉ set khi nhấn tìm)
  String _inputText = ''; // Text đang gõ trong TextField
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _performSearch() {
    final query = _inputText.trim();
    if (query.isNotEmpty) {
      setState(() {
        _searchQuery = query; // Chỉ set query khi nhấn tìm kiếm
      });
      // Ẩn bàn phím
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Tìm kiếm...',
            border: InputBorder.none,
            suffixIcon: _inputText.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _inputText = '';
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() {
              _inputText = value; // Chỉ cập nhật text đang gõ, không tìm kiếm
            });
          },
          onSubmitted: (value) {
            // Khi nhấn Enter, thực hiện tìm kiếm
            _performSearch();
          },
        ),
        actions: [
          // Nút tìm kiếm
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              if (_inputText.trim().isNotEmpty) {
                _performSearch();
              } else {
                // Hiển thị thông báo nếu không có text
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vui lòng nhập từ khóa để tìm kiếm'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            tooltip: 'Tìm kiếm',
            color: _inputText.trim().isNotEmpty ? null : Colors.grey,
          ),
        ],
        bottom: _searchQuery.isNotEmpty
            ? TabBar(
                controller: _tabController,
                indicatorColor: Colors.green,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.black54,
                tabs: const [
                  Tab(text: 'Người dùng'),
                  Tab(text: 'Bài viết'),
                ],
              )
            : null,
      ),
      body: _searchQuery.isEmpty
          ? const Center(
              child: Text(
                'Nhập từ khóa để tìm kiếm',
                style: TextStyle(color: Colors.black),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // Users tab (ưu tiên)
                StreamBuilder<List<UserModel>>(
                  stream: _searchService.searchUsers(
                    _searchQuery,
                    currentUserId: currentUser?.id,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'Không thể tải kết quả tìm kiếm',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'Lỗi: ${snapshot.error}',
                                style: const TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text(
                          'Không tìm thấy người dùng',
                          style: TextStyle(color: Colors.black),
                        ),
                      );
                    }

                    final users = snapshot.data!
                        .where((user) => user.id != currentUser?.id)
                        .toList();

                    if (users.isEmpty) {
                      return const Center(
                        child: Text(
                          'Không tìm thấy người dùng',
                          style: TextStyle(color: Colors.black),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: user.avatarUrl != null
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(user.fullName[0].toUpperCase())
                                : null,
                          ),
                          title: Text(user.fullName),
                          subtitle: Text('@${user.username}'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => OtherUserProfileScreen(user: user),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
                // Posts tab
                StreamBuilder<List<PostModel>>(
                  stream: _searchService.searchPosts(
                    _searchQuery,
                    currentUserId: authProvider.currentUser?.id,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'Không thể tải kết quả tìm kiếm',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'Lỗi: ${snapshot.error}',
                                style: const TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text(
                          'Không tìm thấy bài viết',
                          style: TextStyle(color: Colors.black),
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
                ),
              ],
            ),
    );
  }
}

