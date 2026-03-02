// lib/widgets/voice_message_widget.dart - COMPLETE FIXED
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';

class VoiceMessageWidget extends StatefulWidget {
  final String voiceUrl;
  final bool isMyMessage;
  final VoiceMessageProvider voiceProvider;

  const VoiceMessageWidget({
    super.key,
    required this.voiceUrl,
    required this.isMyMessage,
    required this.voiceProvider,
  });

  @override
  State<VoiceMessageWidget> createState() => _VoiceMessageWidgetState();
}

class _VoiceMessageWidgetState extends State<VoiceMessageWidget> {
  bool _isPlaying = false;
  bool _isLoading = false;
  double _currentPosition = 0;
  double _totalDuration = 1;
  StreamSubscription? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _setupPlayer();
  }

  Future<void> _setupPlayer() async {
    try {
      await widget.voiceProvider.initPlayer();
      _listenToProgress();
    } catch (e) {
      print('❌ Error setting up player: $e');
    }
  }

  void _listenToProgress() {
    _progressSubscription?.cancel();
    _progressSubscription = widget.voiceProvider.playbackStream?.listen(
      (event) {
        if (mounted) {
          setState(() {
            _currentPosition = event.position.inMilliseconds.toDouble();
            _totalDuration = event.duration.inMilliseconds.toDouble();

            // Check if playback finished
            if (_totalDuration > 0 &&
                _currentPosition >= _totalDuration - 100) {
              _isPlaying = false;
              _currentPosition = 0;
            }
          });
        }
      },
      onError: (error) {
        print('❌ Playback stream error: $error');
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _isLoading = false;
          });
        }
      },
    );
  }

  Future<void> _togglePlayback() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_isPlaying) {
        await widget.voiceProvider.pausePlayback();
        setState(() => _isPlaying = false);
      } else {
        // If paused, resume; otherwise start from beginning
        if (widget.voiceProvider.isPaused) {
          await widget.voiceProvider.resumePlayback();
        } else {
          await widget.voiceProvider.playVoiceMessage(widget.voiceUrl);
        }
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      print('❌ Error toggling playback: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play voice message')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDuration(double milliseconds) {
    if (milliseconds <= 0) return '0:00';
    final duration = Duration(milliseconds: milliseconds.toInt());
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(maxWidth: 250),
      decoration: BoxDecoration(
        color: widget.isMyMessage
            ? ColorConstants.primaryColor
            : ColorConstants.greyColor2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          _isLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.isMyMessage
                          ? Colors.white
                          : ColorConstants.primaryColor,
                    ),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: widget.isMyMessage
                        ? Colors.white
                        : ColorConstants.primaryColor,
                    size: 32,
                  ),
                  onPressed: _togglePlayback,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),

          const SizedBox(width: 8),

          // Waveform/Progress
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform visualization (simplified)
                Container(
                  height: 30,
                  child: CustomPaint(
                    painter: WaveformPainter(
                      progress: _totalDuration > 0
                          ? _currentPosition / _totalDuration
                          : 0,
                      activeColor: widget.isMyMessage
                          ? Colors.white
                          : ColorConstants.primaryColor,
                      inactiveColor: widget.isMyMessage
                          ? Colors.white38
                          : ColorConstants.greyColor,
                    ),
                    size: Size.infinite,
                  ),
                ),

                const SizedBox(height: 4),

                // Duration
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_currentPosition),
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isMyMessage
                            ? Colors.white70
                            : ColorConstants.greyColor,
                      ),
                    ),
                    Text(
                      _formatDuration(_totalDuration),
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isMyMessage
                            ? Colors.white70
                            : ColorConstants.greyColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 4),

          // Voice icon
          Icon(
            Icons.mic,
            size: 16,
            color:
                widget.isMyMessage ? Colors.white70 : ColorConstants.greyColor,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    if (_isPlaying) {
      widget.voiceProvider.stopPlayback();
    }
    super.dispose();
  }
}

// Simple waveform painter
class WaveformPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  WaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = 30;
    final barWidth = size.width / (barCount * 2);
    final maxHeight = size.height * 0.8;

    for (int i = 0; i < barCount; i++) {
      // Generate pseudo-random heights for waveform visualization
      final seed = (i * 7 + 3) % 10;
      final height = maxHeight * (0.3 + (seed / 10) * 0.7);

      final x = i * barWidth * 2 + barWidth / 2;
      final isActive = (i / barCount) <= progress;

      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// Recording indicator widget
class VoiceRecordingIndicator extends StatefulWidget {
  final String duration;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const VoiceRecordingIndicator({
    super.key,
    required this.duration,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<VoiceRecordingIndicator> createState() =>
      _VoiceRecordingIndicatorState();
}

class _VoiceRecordingIndicatorState extends State<VoiceRecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      color: Colors.red.withOpacity(0.1),
      child: Row(
        children: [
          // Animated recording indicator
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red
                      .withOpacity(0.5 + _animationController.value * 0.5),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),

          SizedBox(width: 12),

          // Duration
          Text(
            'Recording... ${widget.duration}',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),

          Spacer(),

          // Cancel button
          IconButton(
            icon: Icon(Icons.delete, color: Colors.red),
            onPressed: widget.onCancel,
            tooltip: 'Cancel recording',
          ),

          // Send button
          IconButton(
            icon: Icon(Icons.send, color: ColorConstants.primaryColor),
            onPressed: widget.onSend,
            tooltip: 'Send voice message',
          ),
        ],
      ),
    );
  }
}
