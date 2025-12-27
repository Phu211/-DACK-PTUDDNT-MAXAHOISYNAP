import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/privacy_model.dart';
import '../../../data/models/story_privacy_settings.dart';
import '../../../data/services/friend_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';

class StoryPrivacyScreen extends StatefulWidget {
  final PrivacyType initialPrivacy;
  final List<String> initialHiddenUsers;
  final List<String> initialAllowedUsers;

  const StoryPrivacyScreen({
    super.key,
    required this.initialPrivacy,
    this.initialHiddenUsers = const [],
    this.initialAllowedUsers = const [],
  });

  @override
  State<StoryPrivacyScreen> createState() => _StoryPrivacyScreenState();
}

enum _StoryPrivacyOption { public, friends, hidden, allowed }

class _StoryPrivacyScreenState extends State<StoryPrivacyScreen> {
  late PrivacyType _selectedPrivacy;
  late List<String> _hiddenUsers;
  late List<String> _allowedUsers;
  late _StoryPrivacyOption _selectedOption;
  final FriendService _friendService = FriendService();
  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    // Không hỗ trợ "Chỉ mình tôi" cho Story đã đăng; fallback về Bạn bè
    _selectedPrivacy = widget.initialPrivacy == PrivacyType.onlyMe
        ? PrivacyType.friends
        : widget.initialPrivacy;
    _hiddenUsers = List.from(widget.initialHiddenUsers);
    _allowedUsers = List.from(widget.initialAllowedUsers);

    if (_allowedUsers.isNotEmpty) {
      _selectedOption = _StoryPrivacyOption.allowed;
    } else if (_hiddenUsers.isNotEmpty) {
      _selectedOption = _StoryPrivacyOption.hidden;
    } else if (_selectedPrivacy == PrivacyType.public) {
      _selectedOption = _StoryPrivacyOption.public;
    } else {
      _selectedOption = _StoryPrivacyOption.friends;
    }
  }

  Future<void> _selectHiddenUsers() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final friendIds = await _friendService.getFriends(currentUser.id);
    final friends = await Future.wait(
      friendIds.map((id) => _userService.getUserById(id)),
    );

    final selected = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => _UserSelectionScreen(
          title: 'Ẩn tin với',
          users: friends.whereType<UserModel>().toList(),
          selectedIds: _hiddenUsers,
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _hiddenUsers = List.from(selected); // Tạo copy mới để đảm bảo không bị thay đổi
        // Nếu có hidden users, đảm bảo privacy là friends
        if (_hiddenUsers.isNotEmpty) {
          _selectedPrivacy = PrivacyType.friends;
        }
      });
      debugPrint('StoryPrivacyScreen: Updated hiddenUsers - count: ${_hiddenUsers.length}');
      // Lưu ngay sau khi chọn users - nhưng không pop màn hình privacy
      // Chỉ cập nhật state, khi người dùng back sẽ trả về result đã cập nhật
    }
  }

  Future<void> _selectAllowedUsers() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    final friendIds = await _friendService.getFriends(currentUser.id);
    final friends = await Future.wait(
      friendIds.map((id) => _userService.getUserById(id)),
    );

    final selected = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => _UserSelectionScreen(
          title: 'Chỉ chia sẻ với',
          users: friends.whereType<UserModel>().toList(),
          selectedIds: _allowedUsers,
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _allowedUsers = List.from(selected); // Tạo copy mới để đảm bảo không bị thay đổi
        // Nếu có allowed users, đảm bảo privacy là friends
        if (_allowedUsers.isNotEmpty) {
          _selectedPrivacy = PrivacyType.friends;
        }
      });
      debugPrint('StoryPrivacyScreen: Updated allowedUsers - count: ${_allowedUsers.length}');
      // Lưu ngay sau khi chọn users - nhưng không pop màn hình privacy
      // Chỉ cập nhật state, khi người dùng back sẽ trả về result đã cập nhật
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _saveAndReturn();
        return false; // Không pop tự động, để _saveAndReturn() xử lý
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Quyền riêng tư của tin'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _saveAndReturn();
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Tìm kiếm'),
                    content: const Text('Sử dụng thanh tìm kiếm trong màn hình chọn người dùng'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Description
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Tin của bạn sẽ hiển thị trên Facebook và Messenger trong 24 giờ.',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),

            // Privacy options
            _buildPrivacyOption(
              title: 'Công khai',
              description: 'Bất kỳ ai trên Facebook hoặc Messenger',
              icon: Icons.public,
              option: _StoryPrivacyOption.public,
            ),
            _buildPrivacyOption(
              title: 'Bạn bè',
              description: 'Chỉ bạn bè của bạn trên Facebook',
              icon: Icons.people,
              option: _StoryPrivacyOption.friends,
            ),
            _buildPrivacyOption(
              title: 'Ẩn tin với',
              description: _hiddenUsers.isEmpty
                  ? 'Chọn người bạn muốn ẩn tin'
                  : '${_hiddenUsers.length} người đã chọn',
              icon: Icons.person_remove,
              option: _StoryPrivacyOption.hidden,
              onTap: _selectHiddenUsers,
            ),
            _buildPrivacyOption(
              title: 'Chỉ chia sẻ với (Close Friends)',
              description: _allowedUsers.isEmpty
                  ? 'Chọn bạn bè thân thiết'
                  : '${_allowedUsers.length} người đã chọn',
              icon: Icons.favorite,
              option: _StoryPrivacyOption.allowed,
              onTap: _selectAllowedUsers,
            ),

            const Divider(),

            // Other settings
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Tin bạn đã tắt'),
              subtitle: const Text('Xem danh sách người dùng đã tắt tin'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tính năng đang phát triển'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Cài đặt thư viện ảnh'),
              subtitle: const Text(
                'Quản lý cách Facebook dùng thư viện ảnh và dữ liệu liên quan của bạn',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tính năng đang phát triển'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.music_note),
              title: const Text('Tạm ẩn gợi ý nhạc tự động'),
              subtitle: const Text(
                'Chúng tôi sẽ dừng thêm gợi ý nhạc vào tin của bạn trong 30 ngày.',
              ),
              trailing: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã tạm ẩn gợi ý nhạc trong 30 ngày'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: const Text('Tạm ẩn'),
              ),
            ),

            // Info text
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chỉ bạn bè và các quan hệ kết nối của bạn mới có thể trực tiếp trả lời tin bạn đăng.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildPrivacyOption({
    required String title,
    required String description,
    required IconData icon,
    required _StoryPrivacyOption option,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(description),
      trailing: Radio<_StoryPrivacyOption>(
        value: option,
        groupValue: _selectedOption,
        onChanged: (_) {
          _handleOptionSelect(option);
        },
      ),
      onTap: onTap != null
          ? () {
              _handleOptionSelect(option);
              onTap();
            }
          : () => _handleOptionSelect(option),
    );
  }

  void _handleOptionSelect(_StoryPrivacyOption option) {
    setState(() {
      _selectedOption = option;
      switch (option) {
        case _StoryPrivacyOption.public:
          _selectedPrivacy = PrivacyType.public;
          _hiddenUsers = [];
          _allowedUsers = [];
          break;
        case _StoryPrivacyOption.friends:
          _selectedPrivacy = PrivacyType.friends;
          _hiddenUsers = [];
          _allowedUsers = [];
          break;
        case _StoryPrivacyOption.hidden:
          _selectedPrivacy = PrivacyType.friends;
          _allowedUsers = []; // chỉ chọn một chế độ -> clear allowed
          break;
        case _StoryPrivacyOption.allowed:
          _selectedPrivacy = PrivacyType.friends;
          _hiddenUsers = []; // chỉ chọn một chế độ -> clear hidden
          break;
      }
    });
  }

  void _saveAndReturn() {
    final settings = StoryPrivacySettings(
      privacy: _selectedPrivacy,
      hiddenUsers: List.from(_hiddenUsers), // Tạo copy để đảm bảo không bị thay đổi
      allowedUsers: List.from(_allowedUsers), // Tạo copy để đảm bảo không bị thay đổi
    );
    debugPrint('StoryPrivacyScreen: Saving settings - privacy: ${settings.privacy}, hiddenUsers: ${settings.hiddenUsers.length}, allowedUsers: ${settings.allowedUsers.length}');
    
    // Hiển thị thông báo lưu thành công
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã lưu cài đặt quyền riêng tư'),
        duration: Duration(seconds: 1),
      ),
    );
    
    Navigator.of(context).pop(settings);
  }
}

// Màn hình chọn users
class _UserSelectionScreen extends StatefulWidget {
  final String title;
  final List<UserModel> users;
  final List<String> selectedIds;

  const _UserSelectionScreen({
    required this.title,
    required this.users,
    required this.selectedIds,
  });

  @override
  State<_UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<_UserSelectionScreen> {
  late Set<String> _selectedIds;
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.selectedIds);
    _filteredUsers = widget.users;
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = widget.users.where((user) {
        return user.fullName.toLowerCase().contains(query) ||
            user.email.toLowerCase().contains(query) ||
            (user.username?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(_selectedIds.toList());
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(
            child: _filteredUsers.isEmpty
                ? const Center(
                    child: Text('Không tìm thấy người dùng'),
                  )
                : ListView.builder(
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final isSelected = _selectedIds.contains(user.id);

                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedIds.add(user.id);
                      } else {
                        _selectedIds.remove(user.id);
                      }
                    });
                  },
                  title: Text(user.fullName),
                  subtitle: Text('@${user.username}'),
                  secondary: CircleAvatar(
                    backgroundColor: Colors.grey[300],
                    backgroundImage: user.avatarUrl != null
                        ? NetworkImage(user.avatarUrl!)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(user.fullName[0].toUpperCase())
                        : null,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(_selectedIds.toList());
                  },
                  child: const Text('Lưu'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


