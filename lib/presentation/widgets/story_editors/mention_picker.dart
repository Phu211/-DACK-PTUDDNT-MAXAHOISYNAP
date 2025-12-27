import 'package:flutter/material.dart';
import '../../../data/models/story_element_model.dart';
import '../../../data/services/user_service.dart';
import '../../../data/models/user_model.dart';

class MentionPicker extends StatefulWidget {
  final Function(StoryMention) onMentionSelected;

  const MentionPicker({super.key, required this.onMentionSelected});

  @override
  State<MentionPicker> createState() => _MentionPickerState();
}

class _MentionPickerState extends State<MentionPicker> {
  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _users = [];
  List<UserModel> _filteredUsers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get all users (in production, you'd want to limit this)
      // searchUsers returns a Stream, so we need to get the first value
      final usersStream = _userService.searchUsers('');
      final users = await usersStream.first;
      setState(() {
        _users = users;
        _filteredUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _users.where((user) {
        return user.fullName.toLowerCase().contains(query) || user.email.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm người dùng...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              style: const TextStyle(color: Colors.black87),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                ? const Center(
                    child: Text('Không tìm thấy người dùng', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                          child: user.avatarUrl == null ? Text(user.fullName[0].toUpperCase()) : null,
                        ),
                        title: Text(user.fullName, style: const TextStyle(color: Colors.black87)),
                        subtitle: Text(user.email, style: const TextStyle(color: Colors.grey)),
                        onTap: () {
                          final mention = StoryMention(
                            userId: user.id,
                            userName: user.fullName,
                            x: 0.5,
                            y: 0.5,
                            scale: 1.0,
                          );
                          widget.onMentionSelected(mention);
                          Navigator.pop(context);
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
