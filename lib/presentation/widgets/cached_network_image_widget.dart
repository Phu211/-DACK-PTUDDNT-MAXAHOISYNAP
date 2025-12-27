import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/services/settings_service.dart';

class CachedNetworkImageWidget extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const CachedNetworkImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<CachedNetworkImageWidget> createState() => _CachedNetworkImageWidgetState();
}

class _CachedNetworkImageWidgetState extends State<CachedNetworkImageWidget> {
  bool _dataSaverEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDataSaverSetting();
  }

  Future<void> _loadDataSaverSetting() async {
    final enabled = await SettingsService.isDataSaverEnabled();
    if (mounted) {
      setState(() {
        _dataSaverEnabled = enabled;
        _isLoading = false;
      });
    }
  }

  String _getImageUrl() {
    // Nếu data saver enabled, có thể thêm query params để giảm chất lượng
    // (nếu backend hỗ trợ). Hiện tại chỉ return URL gốc.
    // Có thể mở rộng sau để thêm ?quality=low hoặc tương tự
    return widget.imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[300],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: _getImageUrl(),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: _dataSaverEnabled && widget.width != null 
          ? (widget.width! * 0.7).toInt() 
          : null,
      memCacheHeight: _dataSaverEnabled && widget.height != null 
          ? (widget.height! * 0.7).toInt() 
          : null,
      placeholder: (context, url) => Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[300],
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[300],
        child: const Icon(Icons.error),
      ),
    );
  }
}


