import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/models/message_model.dart';
import '../../../data/services/message_service.dart';

/// Màn hình hiển thị live location theo thời gian thực bên trong app
class LiveLocationScreen extends StatefulWidget {
  final String messageId;
  final bool isSentByMe;

  const LiveLocationScreen({
    super.key,
    required this.messageId,
    required this.isSentByMe,
  });

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  final MessageService _messageService = MessageService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Location')),
      body: StreamBuilder<MessageModel?>(
        stream: _messageService.watchMessageById(widget.messageId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Lỗi tải vị trí: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final message = snapshot.data;

          if (message == null) {
            return const Center(
              child: Text(
                'Không tìm thấy tin nhắn vị trí.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final lat = message.latitude;
          final lng = message.longitude;
          final isLive = message.isLiveLocation ?? false;

          if (lat == null || lng == null) {
            return const Center(
              child: Text(
                'Tin nhắn này không còn dữ liệu vị trí hợp lệ.',
                textAlign: TextAlign.center,
              ),
            );
          }

          if (kDebugMode) {
            debugPrint(
              'LiveLocationScreen update: id=${message.id}, '
              'lat=$lat, lng=$lng, isLiveLocation=$isLive',
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLive
                          ? 'Đang chia sẻ vị trí theo thời gian thực'
                          : 'Vị trí',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  // Không dùng GoogleMap để tránh crash vì thiếu API key.
                  // Thay vào đó dùng static map OSM; vì bọc trong StreamBuilder nên
                  // khi lat/lng thay đổi, URL đổi và ảnh sẽ được load lại (giả lập live).
                  child: Image.network(
                    _getStaticMapUrl(lat, lng, widget.isSentByMe),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 64,
                              color: widget.isSentByMe
                                  ? Colors.blue
                                  : Colors.red,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getStaticMapUrl(double latitude, double longitude, bool isSentByMe) {
    const zoom = 15;
    const width = 600;
    const height = 400;
    final markerColor = isSentByMe ? 'blue' : 'red';

    return 'https://staticmap.openstreetmap.de/staticmap.php'
        '?center=$latitude,$longitude'
        '&zoom=$zoom'
        '&size=${width}x$height'
        '&markers=$latitude,$longitude,$markerColor';
  }
}
