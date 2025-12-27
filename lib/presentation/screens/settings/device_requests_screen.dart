import 'package:flutter/material.dart';

class DeviceRequestsScreen extends StatelessWidget {
  const DeviceRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yêu cầu từ thiết bị'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Xem và quản lý các yêu cầu đăng nhập từ thiết bị khác',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Thiết bị hiện tại'),
            subtitle: const Text('Điện thoại này'),
            trailing: const Icon(Icons.check, color: Colors.green),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Không có yêu cầu nào'),
            subtitle: const Text('Tất cả các yêu cầu đăng nhập đã được xử lý'),
          ),
        ],
      ),
    );
  }
}


