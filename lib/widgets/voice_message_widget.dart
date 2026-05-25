import 'dart:async';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/voice_message_provider.dart';

// ─────────────────────────────────────────────
// VoiceMessageWidget
// ─────────────────────────────────────────────

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
  late PlayerController _playerController;

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<void>? _completionSubscription;

  bool _isPlaying = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _playerController = PlayerController();

    _preparePlayer();
  }

  Future<void> _preparePlayer() async {
    try {
      final localPath = await widget.voiceProvider.downloadVoiceMessage(
        widget.voiceUrl,
      );

      if (localPath == null) {
        debugPrint('❌ Could not download voice message');

        if (mounted) {
          setState(() => _isLoading = false);
        }

        return;
      }

      await _playerController.preparePlayer(
        path: localPath,
        shouldExtractWaveform: true,
        volume: 1.0,
      );

      // Lắng nghe trạng thái player
      _playerStateSubscription =
          _playerController.onPlayerStateChanged.listen((state) {
        if (!mounted) return;

        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      });

      // Khi audio phát xong
      _completionSubscription = _playerController.onCompletion.listen((_) {
        if (!mounted) return;

        setState(() {
          _isPlaying = false;
        });
      });

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error preparing voice message: $e');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _togglePlay() async {
    HapticFeedback.lightImpact();

    try {
      if (_isPlaying) {
        await _playerController.pausePlayer();
      } else {
        await _playerController.startPlayer();
      }
    } catch (e) {
      debugPrint('❌ Error toggling player: $e');
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _completionSubscription?.cancel();

    _playerController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMe = widget.isMyMessage;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      constraints: const BoxConstraints(
        maxWidth: 260,
      ),
      decoration: BoxDecoration(
        gradient: isMe
            ? const LinearGradient(
                colors: [
                  Color(0xFF007AFF),
                  Color(0xFF0056D6),
                ],
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
          // ─────────────────────────────
          // Play / Pause button
          // ─────────────────────────────

          GestureDetector(
            onTap: _isLoading ? null : _togglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withOpacity(0.2)
                    : const Color(0xFFF2F2F7),
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isMe ? Colors.white : const Color(0xFF007AFF),
                        ),
                      ),
                    )
                  : Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: isMe ? Colors.white : const Color(0xFF007AFF),
                      size: 22,
                    ),
            ),
          ),

          const SizedBox(width: 12),

          // ─────────────────────────────
          // Waveform
          // ─────────────────────────────

          if (_isLoading)
            SizedBox(
              width: 160,
              height: 30,
              child: LinearProgressIndicator(
                color: isMe ? Colors.white54 : Colors.grey,
                backgroundColor: isMe ? Colors.white24 : Colors.grey.shade200,
              ),
            )
          else
            AudioFileWaveforms(
              size: const Size(160, 30),
              playerController: _playerController,
              enableSeekGesture: true,
              waveformType: WaveformType.fitWidth,
              playerWaveStyle: PlayerWaveStyle(
                fixedWaveColor: isMe
                    ? Colors.white.withOpacity(0.3)
                    : const Color(0xFFE5E5EA),
                liveWaveColor: isMe ? Colors.white : const Color(0xFF007AFF),
                spacing: 4,
                waveThickness: 2,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// VoiceRecordingIndicator
// ─────────────────────────────────────────────

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
          // ─────────────────────────────
          // Blinking dot
          // ─────────────────────────────

          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(
                    0.5 + (_animationController.value * 0.5),
                  ),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),

          const SizedBox(width: 12),

          // ─────────────────────────────
          // Duration label
          // ─────────────────────────────

          Text(
            'Recording... ${widget.duration}',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),

          const Spacer(),

          // ─────────────────────────────
          // Cancel button
          // ─────────────────────────────

          IconButton(
            icon: const Icon(
              Icons.delete,
              color: Colors.red,
            ),
            onPressed: widget.onCancel,
            tooltip: 'Cancel recording',
          ),

          // ─────────────────────────────
          // Send button
          // ─────────────────────────────

          IconButton(
            icon: Icon(
              Icons.send,
              color: ColorConstants.primaryColor,
            ),
            onPressed: widget.onSend,
            tooltip: 'Send voice message',
          ),
        ],
      ),
    );
  }
}
