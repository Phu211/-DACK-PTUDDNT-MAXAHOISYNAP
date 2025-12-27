import 'package:flutter/material.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sự kiện'),
      ),
      body: const Center(
        child: Text('Sự kiện đang phát triển'),
      ),
    );
  }
}


