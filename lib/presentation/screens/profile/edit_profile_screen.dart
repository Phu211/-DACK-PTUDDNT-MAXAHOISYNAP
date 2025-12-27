import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../../core/utils/error_message_helper.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _usernameController = TextEditingController();
  // Info Cards
  final _workplaceController = TextEditingController();
  final _educationController = TextEditingController();
  final _locationController = TextEditingController();
  final _hometownController = TextEditingController();
  final _relationshipStatusController = TextEditingController();
  // Social Links
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _twitterController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _websiteController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();
  final AuthService _authService = AuthService();
  final StorageService _storageService = StorageService();

  File? _avatarFile;
  File? _coverFile;
  DateTime? _birthday;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user != null) {
      _fullNameController.text = user.fullName;
      _bioController.text = user.bio ?? '';
      _usernameController.text = user.username;
      _workplaceController.text = user.workplace ?? '';
      _educationController.text = user.education ?? '';
      _locationController.text = user.location ?? '';
      _hometownController.text = user.hometown ?? '';
      _relationshipStatusController.text = user.relationshipStatus ?? '';
      _facebookController.text = user.facebookLink ?? '';
      _instagramController.text = user.instagramLink ?? '';
      _twitterController.text = user.twitterLink ?? '';
      _tiktokController.text = user.tiktokLink ?? '';
      _websiteController.text = user.websiteLink ?? '';
      _birthday = user.birthday;
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _bioController.dispose();
    _usernameController.dispose();
    _workplaceController.dispose();
    _educationController.dispose();
    _locationController.dispose();
    _hometownController.dispose();
    _relationshipStatusController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _tiktokController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isAvatar) async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image != null) {
        setState(() {
          if (isAvatar) {
            _avatarFile = File(image.path);
          } else {
            _coverFile = File(image.path);
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        ErrorMessageHelper.createErrorSnackBar(
          e,
          defaultMessage: 'Không thể chọn ảnh',
        ),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      String? avatarUrl = currentUser.avatarUrl;
      String? coverUrl = currentUser.coverUrl;

      // Upload avatar if changed
      if (_avatarFile != null) {
        avatarUrl = await _storageService.uploadAvatar(
          _avatarFile!,
          currentUser.id,
        );
      }

      // Upload cover if changed
      if (_coverFile != null) {
        coverUrl = await _storageService.uploadCover(
          _coverFile!,
          currentUser.id,
        );
      }

      // Update user model
      final updatedUser = currentUser.copyWith(
        fullName: _fullNameController.text.trim(),
        username: _usernameController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
        avatarUrl: avatarUrl,
        coverUrl: coverUrl,
        workplace: _workplaceController.text.trim().isEmpty
            ? null
            : _workplaceController.text.trim(),
        education: _educationController.text.trim().isEmpty
            ? null
            : _educationController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        hometown: _hometownController.text.trim().isEmpty
            ? null
            : _hometownController.text.trim(),
        birthday: _birthday,
        relationshipStatus: _relationshipStatusController.text.trim().isEmpty
            ? null
            : _relationshipStatusController.text.trim(),
        facebookLink: _facebookController.text.trim().isEmpty
            ? null
            : _facebookController.text.trim(),
        instagramLink: _instagramController.text.trim().isEmpty
            ? null
            : _instagramController.text.trim(),
        twitterLink: _twitterController.text.trim().isEmpty
            ? null
            : _twitterController.text.trim(),
        tiktokLink: _tiktokController.text.trim().isEmpty
            ? null
            : _tiktokController.text.trim(),
        websiteLink: _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
        updatedAt: DateTime.now(),
      );

      await _authService.updateUserProfile(updatedUser);
      await authProvider.loadCurrentUser();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật thông tin'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(ErrorMessageHelper.createErrorSnackBar(e));
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
    final user = authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉnh sửa trang cá nhân'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _saveProfile,
              icon: const Icon(Icons.save),
              label: const Text(
                'Lưu',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Cover photo
              Stack(
                children: [
                  Container(
                    height: 200,
                    width: double.infinity,
                    color: Colors.blue[300],
                    child: _coverFile != null && !kIsWeb
                        ? Image.file(_coverFile!, fit: BoxFit.cover)
                        : user?.coverUrl != null
                        ? Image.network(user!.coverUrl!, fit: BoxFit.cover)
                        : null,
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.small(
                      onPressed: () => _pickImage(false),
                      child: const Icon(Icons.camera_alt),
                    ),
                  ),
                ],
              ),

              // Avatar
              Transform.translate(
                offset: const Offset(0, -50),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.black,
                      child: CircleAvatar(
                        radius: 48,
                        backgroundImage: _avatarFile != null && !kIsWeb
                            ? FileImage(_avatarFile!)
                            : user?.avatarUrl != null
                            ? NetworkImage(user!.avatarUrl!)
                            : null,
                        child: _avatarFile == null && user?.avatarUrl == null
                            ? Text(
                                user?.fullName[0].toUpperCase() ?? 'U',
                                style: const TextStyle(fontSize: 40),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.blue,
                        child: IconButton(
                          icon: const Icon(Icons.camera_alt, size: 18),
                          color: Colors.black,
                          onPressed: () => _pickImage(true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 60),

              // Form fields
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng nhập họ và tên';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên người dùng',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng nhập tên người dùng';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bioController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Giới thiệu',
                        prefixIcon: Icon(Icons.info_outline),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Info Cards Section
                    _buildSectionHeader('Thông tin cá nhân'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _workplaceController,
                      decoration: const InputDecoration(
                        labelText: 'Nơi làm việc',
                        prefixIcon: Icon(Icons.work),
                        hintText: 'Ví dụ: Công ty ABC',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _educationController,
                      decoration: const InputDecoration(
                        labelText: 'Học vấn',
                        prefixIcon: Icon(Icons.school),
                        hintText: 'Ví dụ: Đại học XYZ',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Nơi sống',
                        prefixIcon: Icon(Icons.location_on),
                        hintText: 'Ví dụ: Hà Nội, Việt Nam',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _hometownController,
                      decoration: const InputDecoration(
                        labelText: 'Quê quán',
                        prefixIcon: Icon(Icons.home),
                        hintText: 'Ví dụ: Hải Phòng, Việt Nam',
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () => _selectBirthday(context),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Ngày sinh',
                          prefixIcon: Icon(Icons.cake),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _birthday != null
                              ? DateFormat('dd/MM/yyyy').format(_birthday!)
                              : 'Chọn ngày sinh',
                          style: TextStyle(
                            color: _birthday != null
                                ? Theme.of(context).textTheme.bodyLarge?.color
                                : Theme.of(context).hintColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _relationshipStatusController.text.isEmpty
                          ? null
                          : _relationshipStatusController.text,
                      decoration: const InputDecoration(
                        labelText: 'Mối quan hệ',
                        prefixIcon: Icon(Icons.favorite),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Độc thân',
                          child: Text('Độc thân'),
                        ),
                        DropdownMenuItem(
                          value: 'Đang hẹn hò',
                          child: Text('Đang hẹn hò'),
                        ),
                        DropdownMenuItem(
                          value: 'Đã kết hôn',
                          child: Text('Đã kết hôn'),
                        ),
                        DropdownMenuItem(
                          value: 'Phức tạp',
                          child: Text('Phức tạp'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _relationshipStatusController.text = value ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    // Social Links Section
                    _buildSectionHeader('Liên kết mạng xã hội'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _facebookController,
                      decoration: const InputDecoration(
                        labelText: 'Facebook',
                        prefixIcon: Icon(Icons.facebook),
                        hintText: 'https://facebook.com/...',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _instagramController,
                      decoration: const InputDecoration(
                        labelText: 'Instagram',
                        prefixIcon: Icon(Icons.camera_alt),
                        hintText: 'https://instagram.com/...',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _twitterController,
                      decoration: const InputDecoration(
                        labelText: 'Twitter',
                        prefixIcon: Icon(Icons.alternate_email),
                        hintText: 'https://twitter.com/...',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _tiktokController,
                      decoration: const InputDecoration(
                        labelText: 'TikTok',
                        prefixIcon: Icon(Icons.music_note),
                        hintText: 'https://tiktok.com/@...',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _websiteController,
                      decoration: const InputDecoration(
                        labelText: 'Website',
                        prefixIcon: Icon(Icons.language),
                        hintText: 'https://...',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 32),
                    // Nút lưu nổi bật
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Lưu thay đổi',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Expanded(
          child: Divider(color: Theme.of(context).dividerColor, thickness: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
        ),
        Expanded(
          child: Divider(color: Theme.of(context).dividerColor, thickness: 1),
        ),
      ],
    );
  }

  Future<void> _selectBirthday(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _birthday ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('vi', 'VN'),
    );
    if (picked != null && picked != _birthday) {
      setState(() {
        _birthday = picked;
      });
    }
  }
}
