import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/group_model.dart';
import '../../../data/services/group_service.dart';
import '../../providers/auth_provider.dart';
import 'group_detail_screen.dart';
import 'create_group_screen.dart';

class GroupsListScreen extends StatelessWidget {
  const GroupsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final groupService = GroupService();

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Vui lòng đăng nhập')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Nhóm',
          style: TextStyle(color: Colors.black),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CreateGroupScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<GroupModel>>(
        stream: groupService.getUserGroups(currentUser.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.black),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.black),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Chưa có nhóm nào',
                    style: TextStyle(color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CreateGroupScreen(),
                        ),
                      );
                    },
                    child: const Text('Tạo nhóm mới'),
                  ),
                ],
              ),
            );
          }

          final groups = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return ListTile(
                leading: CircleAvatar(
                  radius: 30,
                  backgroundImage: group.coverUrl != null
                      ? NetworkImage(group.coverUrl!)
                      : null,
                  child: group.coverUrl == null
                      ? Text(group.name[0].toUpperCase())
                      : null,
                ),
                title: Text(
                  group.name,
                  style: const TextStyle(color: Colors.black),
                ),
                subtitle: Text(
                  '${group.memberIds.length} thành viên',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupDetailScreen(group: group),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}


