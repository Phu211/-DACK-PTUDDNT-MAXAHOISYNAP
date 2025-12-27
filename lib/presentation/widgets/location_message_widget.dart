import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/message_model.dart';
import '../../data/services/location_sharing_service.dart';
// Nếu muốn hiển thị live location trong app, có thể import LiveLocationScreen.
// Hiện tại, tap vào tin nhắn sẽ luôn mở Google Maps bên ngoài.
// import '../screens/messages/live_location_screen.dart';

/// Widget hiển thị location message với map preview
class LocationMessageWidget extends StatefulWidget {
  final MessageModel message;
  final bool isSentByMe;

  const LocationMessageWidget({
    super.key,
    required this.message,
    required this.isSentByMe,
  });

  @override
  State<LocationMessageWidget> createState() => _LocationMessageWidgetState();
}

class _LocationMessageWidgetState extends State<LocationMessageWidget> {
  final LocationSharingService _locationService = LocationSharingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  MessageModel? _currentMessage;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _messageSubscription;

  @override
  void initState() {
    super.initState();
    _currentMessage = widget.message;
    _listenToMessageUpdates();
  }

  @override
  void didUpdateWidget(covariant LocationMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nếu message khác (ví dụ list rebuild với tin nhắn khác), lắng nghe lại
    if (oldWidget.message.id != widget.message.id) {
      _currentMessage = widget.message;
      _listenToMessageUpdates();
    }
  }

  void _listenToMessageUpdates() {
    _messageSubscription?.cancel();

    _messageSubscription = _firestore
        .collection(AppConstants.messagesCollection)
        .doc(widget.message.id)
        .snapshots()
        .listen(
          (doc) {
            if (!doc.exists) return;
            final data = doc.data();
            if (data == null) return;

            try {
              final updated = MessageModel.fromMap(doc.id, data);
              if (!mounted) return;

              setState(() {
                _currentMessage = updated;
              });
            } catch (e, stackTrace) {
              if (kDebugMode) {
                debugPrint(
                  'Error parsing live location message ${doc.id}: $e\n$stackTrace',
                );
              }
            }
          },
          onError: (error, stackTrace) {
            if (kDebugMode) {
              debugPrint(
                'Error listening to live location message ${widget.message.id}: $error\n$stackTrace',
              );
            }
          },
        );
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _locationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ưu tiên dùng message mới nhất từ Firestore (live update),
    // fallback sang message ban đầu nếu chưa có cập nhật.
    final message = _currentMessage ?? widget.message;

    final latitude = message.latitude;
    final longitude = message.longitude;
    final address = message.locationAddress;
    final isLive = message.isLiveLocation ?? false;
    final expiresAt = message.locationExpiresAt;
    final isValid = _locationService.isLocationValid(expiresAt);

    if (latitude == null || longitude == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Invalid location data'),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        // Người dùng muốn mở trực tiếp Google Maps → luôn gọi _openInMaps
        onTap: () => _openInMaps(latitude, longitude),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Map preview - sử dụng OpenStreetMap static image (miễn phí, không cần API key)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Image.network(
                  // Sử dụng OpenStreetMap static tile (miễn phí, không cần API key)
                  // Format: https://tile.openstreetmap.org/{z}/{x}/{y}.png
                  // Hoặc dùng staticmap từ OpenStreetMap service
                  _getStaticMapUrl(latitude, longitude),
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    // Nếu không load được map, hiển thị placeholder với icon
                    return Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 48,
                            color: widget.isSentByMe ? Colors.blue : Colors.red,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 12,
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
            // Address and info
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLive)
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Live Location',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isValid ? Colors.red : Colors.grey,
                          ),
                        ),
                        if (expiresAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _getTimeRemaining(expiresAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    const Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.blue),
                        SizedBox(width: 4),
                        Text(
                          'Location',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  if (address != null && address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      address,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Tap to open in Maps',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tạo URL cho static map image - sử dụng các service MIỄN PHÍ
  // Ưu tiên: OpenStreetMap (hoàn toàn miễn phí, không cần API key)
  String _getStaticMapUrl(double latitude, double longitude) {
    final zoom = 15;
    final width = 400;
    final height = 200;
    final markerColor = widget.isSentByMe ? 'blue' : 'red';

    // Option 1: OpenStreetMap Static Map (MIỄN PHÍ, không giới hạn)
    // Service: staticmap.openstreetmap.de
    return 'https://staticmap.openstreetmap.de/staticmap.php?center=$latitude,$longitude&zoom=$zoom&size=${width}x$height&markers=$latitude,$longitude,$markerColor';

    // Option 2: Mapbox Static Images (MIỄN PHÍ 50,000 requests/tháng)
    // Cần đăng ký tại https://www.mapbox.com/ và lấy access token
    // Uncomment và thay YOUR_MAPBOX_ACCESS_TOKEN nếu muốn dùng:
    // final mapboxToken = 'YOUR_MAPBOX_ACCESS_TOKEN';
    // if (mapboxToken != 'YOUR_MAPBOX_ACCESS_TOKEN' && mapboxToken.isNotEmpty) {
    //   return 'https://api.mapbox.com/styles/v1/mapbox/streets-v11/static/pin-s+$markerColor($longitude,$latitude)/$longitude,$latitude,$zoom,0/$width}x$height?access_token=$mapboxToken';
    // }

    // Option 3: Google Maps Static API (MIỄN PHÍ 28,000 requests/tháng, sau đó $2/1000)
    // Chỉ dùng nếu có API key và muốn chất lượng cao hơn
    // final apiKey = AppConstants.googleMapsApiKey;
    // if (apiKey != 'YOUR_GOOGLE_MAPS_API_KEY' && apiKey.isNotEmpty) {
    //   final marker = 'color:$markerColor|$latitude,$longitude';
    //   return 'https://maps.googleapis.com/maps/api/staticmap?center=$latitude,$longitude&zoom=$zoom&size=${width}x$height&markers=$marker&key=$apiKey';
    // }
  }

  String _getTimeRemaining(DateTime expiresAt) {
    final now = DateTime.now();
    if (now.isAfter(expiresAt)) {
      return 'Expired';
    }

    final difference = expiresAt.difference(now);
    if (difference.inHours > 0) {
      return '${difference.inHours}h ${difference.inMinutes % 60}m remaining';
    } else {
      return '${difference.inMinutes}m remaining';
    }
  }

  Future<void> _openInMaps(double latitude, double longitude) async {
    // Try Google Maps first
    final googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
    final appleMapsUrl = 'https://maps.apple.com/?q=$latitude,$longitude';

    try {
      final uri = Uri.parse(googleMapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      debugPrint('Error launching Google Maps: $e');
    }

    // Fallback to Apple Maps
    try {
      final uri = Uri.parse(appleMapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching Apple Maps: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open maps')));
      }
    }
  }
}
