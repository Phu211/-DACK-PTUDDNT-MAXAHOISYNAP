import 'package:flutter/material.dart';

class AdActivityScreen extends StatelessWidget {
  const AdActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoạt động gần đây với quảng cáo'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Xem thông tin về cách bạn tương tác với quảng cáo',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.ads_click),
            title: const Text('Quảng cáo bạn đã nhấp'),
            subtitle: const Text('Xem các quảng cáo bạn đã tương tác'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng đang phát triển')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('Sở thích quảng cáo'),
            subtitle: const Text('Xem và quản lý sở thích quảng cáo của bạn'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng đang phát triển')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Cài đặt quảng cáo'),
            subtitle: const Text('Kiểm soát quảng cáo bạn nhìn thấy'),
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


