import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../data/models/message_model.dart';

/// Widget hiển thị voice message với waveform và playback controls.
class VoiceMessageWidget extends StatefulWidget {
  final MessageModel message;
  final bool isOwnMessage;
  final VoidCallback? onPlayStateChanged;

  const VoiceMessageWidget({
    super.key,
    required this.message,
    this.isOwnMessage = false,
    this.onPlayStateChanged,
  });

  @override
  State<VoiceMessageWidget> createState() => _VoiceMessageWidgetState();
}

class _VoiceMessageWidgetState extends State<VoiceMessageWidget> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    // Delay initialization slightly to prevent conflicts with other audio resources
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initPlayer();
      }
    });
  }

  void _initPlayer() {
    try {
      _positionSubscription = _player.onPositionChanged.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });

      _durationSubscription = _player.onDurationChanged.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      });

      _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
            // AudioPlayer không có loading state, chỉ có playing, paused, stopped, completed
            _isLoading = false;
          });
          widget.onPlayStateChanged?.call();
        }
      });

      // Load duration nếu có audioUrl và audioDuration chưa được set
      if (widget.message.audioUrl != null &&
          widget.message.audioUrl!.isNotEmpty &&
          widget.message.audioDuration == null) {
        _loadDuration();
      }
    } catch (e) {
      debugPrint('Error initializing voice player: $e');
    }
  }

  Future<void> _loadDuration() async {
    try {
      if (widget.message.audioUrl == null || widget.message.audioUrl!.isEmpty) {
        return;
      }
      // Set loading state khi bắt đầu load
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      await _player.setSource(UrlSource(widget.message.audioUrl!));
      // Duration sẽ được set qua onDurationChanged listener
      // Loading sẽ được tắt khi state thay đổi
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        // Ensure player is stopped before playing new source
        try {
          await _player.stop();
        } catch (e) {
          // Ignore errors from stop if already stopped
        }

        // Small delay to ensure resources are ready
        await Future.delayed(const Duration(milliseconds: 100));

        if (_position == Duration.zero || _position >= _duration) {
          // Start from beginning
          await _player.play(UrlSource(widget.message.audioUrl!));
        } else {
          // Resume from current position
          await _player.resume();
        }
      }
    } catch (e) {
      debugPrint('Error toggling voice play: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể phát voice: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  double _getProgress() {
    if (_duration == Duration.zero) return 0.0;
    return _position.inMilliseconds / _duration.inMilliseconds;
  }

  List<double> _generateWaveform() {
    // Generate fake waveform data (trong thực tế nên parse từ audio file)
    // Hoặc lưu waveform data khi record
    final duration = widget.message.audioDuration ?? _duration.inSeconds;
    final count = (duration * 10)
        .clamp(20, 100)
        .toInt(); // 10 samples per second

    return List.generate(count, (index) {
      // Random waveform values (0.1 to 1.0)
      return 0.1 + (index % 10) * 0.1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final waveform = _generateWaveform();
    final duration = widget.message.audioDuration != null
        ? Duration(seconds: widget.message.audioDuration!)
        : _duration;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isOwnMessage
            ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
            : Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isOwnMessage
                    ? Theme.of(context).primaryColor
                    : Colors.grey[600],
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Waveform
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Waveform visualization
                SizedBox(
                  height: 30,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: waveform.map((value) {
                      final height = value * 30;
                      final isActive =
                          _isPlaying &&
                          waveform.indexOf(value) <
                              (waveform.length * _getProgress()).round();
                      return Container(
                        width: 2,
                        height: height,
                        decoration: BoxDecoration(
                          color: isActive
                              ? (widget.isOwnMessage
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey[800])
                              : Colors.grey[400],
                          borderRadius: BorderRadius.circular(1),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 4),
                // Duration
                Text(
                  _formatDuration(
                    _duration != Duration.zero ? _position : duration,
                  ),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
