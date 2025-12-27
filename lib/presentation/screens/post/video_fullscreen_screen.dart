import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoFullscreenScreen extends StatefulWidget {
  final VideoPlayerController controller;
  final String videoUrl;

  const VideoFullscreenScreen({
    super.key,
    required this.controller,
    required this.videoUrl,
  });

  @override
  State<VideoFullscreenScreen> createState() => _VideoFullscreenScreenState();
}

class _VideoFullscreenScreenState extends State<VideoFullscreenScreen> {
  bool _isPlaying = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.controller.value.isPlaying;
    _position = widget.controller.value.position;
    _duration = widget.controller.value.duration;
    widget.controller.addListener(_updateVideoState);
    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    widget.controller.removeListener(_updateVideoState);
    super.dispose();
  }

  void _updateVideoState() {
    if (mounted) {
      setState(() {
        _isPlaying = widget.controller.value.isPlaying;
        _position = widget.controller.value.position;
        _duration = widget.controller.value.duration;
      });
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_isPlaying) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  Future<void> _seekVideo(Duration position) async {
    await widget.controller.seekTo(position);
  }

  void _togglePlayPause() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
      } else {
        widget.controller.play();
      }
    });
    _startHideControlsTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Video player
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            // Controls overlay
            if (_showControls)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: SafeArea(
                  child: Column(
                    children: [
                      // Top bar with close button
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const Spacer(),
                            // Video time info
                            if (_duration.inMilliseconds > 0)
                              Text(
                                '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Center play/pause button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Rewind 10 seconds
                          IconButton(
                            iconSize: 40,
                            color: Colors.white,
                            icon: const Icon(Icons.replay_10),
                            onPressed: () async {
                              final newPosition =
                                  _position - const Duration(seconds: 10);
                              await _seekVideo(
                                newPosition < Duration.zero
                                    ? Duration.zero
                                    : newPosition,
                              );
                              _startHideControlsTimer();
                            },
                          ),
                          const SizedBox(width: 16),
                          // Play/Pause
                          IconButton(
                            iconSize: 64,
                            color: Colors.white,
                            icon: Icon(
                              _isPlaying
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                            ),
                            onPressed: _togglePlayPause,
                          ),
                          const SizedBox(width: 16),
                          // Forward 10 seconds
                          IconButton(
                            iconSize: 40,
                            color: Colors.white,
                            icon: const Icon(Icons.forward_10),
                            onPressed: () async {
                              final newPosition =
                                  _position + const Duration(seconds: 10);
                              await _seekVideo(
                                newPosition > _duration
                                    ? _duration
                                    : newPosition,
                              );
                              _startHideControlsTimer();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Progress bar
                      if (_duration.inMilliseconds > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: GestureDetector(
                            onTapDown: (details) async {
                              final RenderBox? renderBox =
                                  context.findRenderObject() as RenderBox?;
                              if (renderBox != null) {
                                final localPosition = renderBox.globalToLocal(
                                  details.globalPosition,
                                );
                                final double progress =
                                    (localPosition.dx / renderBox.size.width)
                                        .clamp(0.0, 1.0);
                                final newPosition = Duration(
                                  milliseconds:
                                      (_duration.inMilliseconds * progress)
                                          .round(),
                                );
                                await _seekVideo(newPosition);
                                _startHideControlsTimer();
                              }
                            },
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Stack(
                                children: [
                                  FractionallySizedBox(
                                    widthFactor: _duration.inMilliseconds > 0
                                        ? (_position.inMilliseconds /
                                                  _duration.inMilliseconds)
                                              .clamp(0.0, 1.0)
                                        : 0.0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
