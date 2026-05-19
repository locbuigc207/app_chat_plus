
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);

    try {
      if (_isPlaying) {
        await widget.voiceProvider.pausePlayback();
        setState(() => _isPlaying = false);
      } else {
        if (widget.voiceProvider.isPaused) {
          await widget.voiceProvider.resumePlayback();
        } else {
          await widget.voiceProvider.playVoiceMessage(widget.voiceUrl);
        }
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      print('❌ Error toggling playback: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to play voice message')),
        );
      }
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
    final bool isMe = widget.isMyMessage;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        gradient: isMe
            ? const LinearGradient(
                colors: [Color(0xFF007AFF), Color(0xFF0056D6)],
              )
            : null,
        color: isMe ? null : Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: isMe
            ? [
                BoxShadow(
                  color: const Color(0xFF007AFF).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          
          _isLoading
              ? SizedBox(
                  width: 36,
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isMe ? Colors.white : const Color(0xFF007AFF),
                      ),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: _togglePlayback,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withOpacity(0.2)
                          : const Color(0xFFF2F2F7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: isMe ? Colors.white : const Color(0xFF007AFF),
                      size: 22,
                    ),
                  ),
                ),

          const SizedBox(width: 12),

          
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 24,
                  child: CustomPaint(
                    painter: WaveformPainter(
                      progress: _totalDuration > 0
                          ? _currentPosition / _totalDuration
                          : 0,
                      activeColor:
                          isMe ? Colors.white : const Color(0xFF007AFF),
                      inactiveColor: isMe
                          ? Colors.white.withOpacity(0.3)
                          : const Color(0xFFE5E5EA),
                    ),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDuration(
                    _isPlaying ? _currentPosition : _totalDuration,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: isMe
                        ? Colors.white.withOpacity(0.8)
                        : const Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
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
    const barCount = 30;
    final barWidth = size.width / (barCount * 1.8);
    final maxHeight = size.height * 0.9;

    for (int i = 0; i < barCount; i++) {
      final seed = (i * 7 + 3) % 10;
      final height = maxHeight * (0.3 + (seed / 10) * 0.7);
      final x = i * barWidth * 1.8 + barWidth / 2;
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
      padding: const EdgeInsets.all(12),
      color: Colors.red.withOpacity(0.1),
      child: Row(
        children: [
          
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(
                    0.5 + _animationController.value * 0.5,
                  ),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),

          const SizedBox(width: 12),

          
          Text(
            'Recording... ${widget.duration}',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),

          const Spacer(),

          
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: widget.onCancel,
            tooltip: 'Cancel recording',
          ),

          
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
