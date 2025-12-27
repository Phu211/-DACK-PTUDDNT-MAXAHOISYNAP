import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../../../data/services/user_service.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import 'change_password_screen.dart';

/// Màn hình quản lý tài khoản người dùng:
/// - Đổi mật khẩu
/// - Cập nhật thông tin cá nhân
/// - Xóa tài khoản
class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() => _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final UserService _userService = UserService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isUpdating = false;

  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final userData = await _userService.getUserById(user.id);
      if (userData != null && mounted) {
        setState(() {
          _currentUser = userData;
          _fullNameController.text = userData.fullName;
          _usernameController.text = userData.username;
          _emailController.text = userData.email;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải thông tin: $e')),
        );
      }
    }
  }

  Future<void> _updateProfile() async {
    if (_currentUser == null) return;

    final newFullName = _fullNameController.text.trim();
    final newUsername = _usernameController.text.trim();
    final newEmail = _emailController.text.trim();

    if (newFullName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tên không được để trống')),
      );
      return;
    }

    if (newUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tên người dùng không được để trống')),
      );
      return;
    }

    if (newEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email không được để trống')),
      );
      return;
    }

    setState(() => _isUpdating = true);

    try {
      // Kiểm tra username đã tồn tại chưa (nếu thay đổi)
      if (newUsername != _currentUser!.username) {
        final existingUser = await _userService.getUserByUsername(newUsername);
        if (existingUser != null && existingUser.id != _currentUser!.id) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tên người dùng đã tồn tại')),
            );
            setState(() => _isUpdating = false);
            return;
          }
        }
      }

      // Kiểm tra email đã tồn tại chưa (nếu thay đổi)
      if (newEmail != _currentUser!.email) {
        final existingUser = await _userService.getUserByEmail(newEmail);
        if (existingUser != null && existingUser.id != _currentUser!.id) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Email đã được sử dụng')),
            );
            setState(() => _isUpdating = false);
            return;
          }
        }
      }

      // Cập nhật Firestore
      await _firestore.collection('users').doc(_currentUser!.id).update({
        'fullName': newFullName,
        'username': newUsername,
        'email': newEmail,
        'updatedAt': FieldValue.serverTimestamp(),
        // Cập nhật search fields
        'searchName': _normalizeForSearch(newFullName),
        'searchUsername': newUsername.toLowerCase(),
      });

      // Cập nhật email trong Firebase Auth (nếu thay đổi)
      // Lưu ý: Để đổi email trong Firebase Auth, cần re-authenticate trước
      // Ở đây chỉ cập nhật trong Firestore, user cần đổi email thủ công qua Firebase Console
      // hoặc implement re-authentication flow
      if (newEmail != _currentUser!.email) {
        final firebaseUser = _auth.currentUser;
        if (firebaseUser != null) {
          // Gửi email xác thực cho email mới
          // Note: updateEmail requires recent authentication, 
          // so we'll just update Firestore and notify user to verify new email
          try {
            await firebaseUser.verifyBeforeUpdateEmail(newEmail);
          } catch (e) {
            // Nếu không thể verify, chỉ cập nhật Firestore
            debugPrint('Cannot update email in Firebase Auth: $e');
          }
        }
      }

      // Reload user data
      await _loadUserData();

      if (mounted) {
        // Reload user data trong AuthProvider (nếu có method)
        // AuthProvider sẽ tự động cập nhật khi user data thay đổi trong Firestore

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cập nhật thông tin thành công'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi cập nhật: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  String _normalizeForSearch(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
        .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
        .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
        .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
        .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
        .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
        .replaceAll(RegExp(r'[đ]'), 'd')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim();
  }

  Future<void> _deleteAccount() async {
    if (_currentUser == null) return;

    // Xác nhận xóa tài khoản
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa tài khoản'),
        content: const Text(
          'Bạn có chắc chắn muốn xóa tài khoản? '
          'Hành động này không thể hoàn tác. '
          'Tất cả dữ liệu của bạn sẽ bị xóa vĩnh viễn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Xác nhận lại bằng cách nhập email
    final emailController = TextEditingController();
    final confirmEmail = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa tài khoản'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nhập email của bạn để xác nhận:'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              emailController.dispose();
              Navigator.of(ctx).pop(false);
            },
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              final email = emailController.text.trim();
              emailController.dispose();
              Navigator.of(ctx).pop(email == _currentUser!.email);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (confirmEmail != true || !mounted) return;

    // Hiển thị loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Đang xóa tài khoản...'),
          ],
        ),
      ),
    );

    try {
      // Xóa user document trong Firestore
      await _firestore.collection('users').doc(_currentUser!.id).delete();

      // Xóa Firebase Auth user
      final firebaseUser = _auth.currentUser;
      if (firebaseUser != null) {
        await firebaseUser.delete();
      }

      if (mounted) {
        Navigator.of(context).pop(); // Đóng loading dialog
        // Đăng xuất và quay về màn hình đăng nhập
        final authProvider = context.read<AuthProvider>();
        await authProvider.signOut();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Đóng loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa tài khoản: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý tài khoản'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentUser == null
              ? const Center(child: Text('Không tìm thấy thông tin người dùng'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Thông tin cá nhân
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thông tin cá nhân',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _fullNameController,
                              decoration: const InputDecoration(
                                labelText: 'Họ và tên',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _usernameController,
                              decoration: const InputDecoration(
                                labelText: 'Tên người dùng',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.alternate_email),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email),
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isUpdating ? null : _updateProfile,
                                child: _isUpdating
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Cập nhật thông tin'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Đổi mật khẩu
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.lock),
                        title: const Text('Đổi mật khẩu'),
                        subtitle: const Text('Thay đổi mật khẩu đăng nhập'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ChangePasswordScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Xóa tài khoản
                    Card(
                      color: Colors.red.shade50,
                      child: ListTile(
                        leading: Icon(Icons.delete_forever, color: Colors.red),
                        title: const Text(
                          'Xóa tài khoản',
                          style: TextStyle(color: Colors.red),
                        ),
                        subtitle: const Text(
                          'Xóa vĩnh viễn tài khoản và tất cả dữ liệu',
                          style: TextStyle(color: Colors.red),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.red),
                        onTap: _deleteAccount,
                      ),
                    ),
                  ],
                ),
    );
  }
}

