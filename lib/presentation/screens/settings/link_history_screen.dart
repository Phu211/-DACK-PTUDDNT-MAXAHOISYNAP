import 'package:flutter/material.dart';

class LinkHistoryScreen extends StatelessWidget {
  const LinkHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử liên kết'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Xem các liên kết bạn đã chia sẻ hoặc đã mở',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Liên kết đã chia sẻ'),
            subtitle: const Text('Xem các liên kết bạn đã chia sẻ'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng đang phát triển')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Lịch sử duyệt web'),
            subtitle: const Text('Xem các trang web bạn đã truy cập'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng đang phát triển')),
              );
            },
          ),
        ],
      ),
    );
  }
}


