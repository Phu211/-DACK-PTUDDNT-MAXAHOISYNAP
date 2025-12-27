import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/group_model.dart';
import '../../../data/services/group_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/user_service.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class GroupSettingsScreen extends StatefulWidget {
  final GroupModel group;

  const GroupSettingsScreen({super.key, required this.group});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final GroupService _groupService = GroupService();
  final StorageService _storageService = StorageService();
  final UserService _userService = UserService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isPublic = true;
  bool _isLoading = false;
  File? _selectedCoverImage;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.group.name;
    _descriptionController.text = widget.group.description ?? '';
    _isPublic = widget.group.isPublic;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedCoverImage = File(picked.path);
      });
    }
  }

  Future<void> _saveSettings() async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    // Kiểm tra quyền admin
    final userRole = widget.group.memberRoles[currentUser.id];
    final isAdmin =
        userRole == GroupRole.admin || widget.group.creatorId == currentUser.id;

    if (!isAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bạn không có quyền chỉnh sửa nhóm'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? coverUrl = widget.group.coverUrl;

      // Upload ảnh cover mới nếu có
      if (_selectedCoverImage != null) {
        coverUrl = await _storageService.uploadPostImage(
          _selectedCoverImage!,
          'group_cover',
          0,
        );
      }

      // Cập nhật thông tin nhóm
      await _groupService.updateGroup(
        widget.group.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        coverUrl: coverUrl,
        isPublic: _isPublic,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã lưu cài đặt'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Trả về true để refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
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
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập')));
    }

    final userRole = widget.group.memberRoles[currentUser.id];
    final isAdmin =
        userRole == GroupRole.admin || widget.group.creatorId == currentUser.id;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Cài đặt nhóm',
          style: TextStyle(color: Colors.black),
        ),
        actions: [
          if (isAdmin)
            TextButton(
              onPressed: _isLoading ? null : _saveSettings,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Lưu',
                      style: TextStyle(color: Colors.blue, fontSize: 16),
                    ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            GestureDetector(
              onTap: isAdmin ? _pickCoverImage : null,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[800],
                  image: _selectedCoverImage != null
                      ? DecorationImage(
                          image: FileImage(_selectedCoverImage!),
                          fit: BoxFit.cover,
                        )
                      : (widget.group.coverUrl != null
                            ? DecorationImage(
                                image: NetworkImage(widget.group.coverUrl!),
                                fit: BoxFit.cover,
                              )
                            : null),
                ),
                child: Stack(
                  children: [
                    if (widget.group.coverUrl == null &&
                        _selectedCoverImage == null)
                      const Center(
                        child: Icon(
                          Icons.add_photo_alternate,
                          size: 64,
                          color: Colors.grey,
                        ),
                      ),
                    if (isAdmin)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Group name
            TextField(
              controller: _nameController,
              enabled: isAdmin,
              style: const TextStyle(color: Colors.black, fontSize: 20),
              decoration: InputDecoration(
                labelText: 'Tên nhóm',
                labelStyle: TextStyle(color: Colors.grey[400]),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Description
            TextField(
              controller: _descriptionController,
              enabled: isAdmin,
              maxLines: 3,
              style: const TextStyle(color: Colors.black),
              decoration: InputDecoration(
                labelText: 'Mô tả',
                labelStyle: TextStyle(color: Colors.grey[400]),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[800]!),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Privacy setting
            ListTile(
              title: const Text(
                'Nhóm công khai',
                style: TextStyle(color: Colors.black),
              ),
              subtitle: Text(
                'Mọi người có thể tìm thấy và tham gia nhóm này',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              trailing: Switch(
                value: _isPublic,
                onChanged: isAdmin
                    ? (value) {
                        setState(() {
                          _isPublic = value;
                        });
                      }
                    : null,
              ),
            ),

            const SizedBox(height: 24),

            // Members section
            const Text(
              'Thành viên',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<UserModel>>(
              future: Future.wait(
                widget.group.memberIds.map(
                  (id) => _userService.getUserById(id),
                ),
              ).then((users) => users.whereType<UserModel>().toList()),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }

                final members = snapshot.data ?? [];
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final memberRole = widget.group.memberRoles[member.id];
                    final isCreator = widget.group.creatorId == member.id;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: member.avatarUrl != null
                            ? NetworkImage(member.avatarUrl!)
                            : null,
                        child: member.avatarUrl == null
                            ? Text(member.fullName[0].toUpperCase())
                            : null,
                      ),
                      title: Text(
                        member.fullName,
                        style: const TextStyle(color: Colors.black),
                      ),
                      subtitle: Text(
                        isCreator
                            ? 'Trưởng nhóm'
                            : (memberRole == GroupRole.admin
                                  ? 'Quản trị viên'
                                  : 'Thành viên'),
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

