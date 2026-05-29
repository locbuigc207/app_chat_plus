import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/voice_message_provider.dart';

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

class _VoiceMessageWidgetState extends State<VoiceMessageWidget>
    with SingleTickerProviderStateMixin {
  late PlayerController _playerController;
  late AnimationController _appearCtrl;
  late Animation<double> _scaleAnim;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<void>? _completionSub;
  StreamSubscription<int>? _currentPosSub;

  bool _isPlaying = false;
  bool _isLoading = true;
  bool _hasError = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _playerController = PlayerController();

    _appearCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scaleAnim = CurvedAnimation(
      parent: _appearCtrl,
      curve: Curves.easeOutBack,
    );
    _appearCtrl.forward();

    _preparePlayer();
  }

  Future<void> _preparePlayer() async {
    try {
      final localPath = await widget.voiceProvider.downloadVoiceMessage(widget.voiceUrl);

      if (localPath == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
        return;
      }

      await _playerController.preparePlayer(
        path: localPath,
        shouldExtractWaveform: true,
        volume: 1.0,
      );

      final ms = _playerController.maxDuration;
      if (ms > 0) {
        _totalDuration = Duration(milliseconds: ms);
      }

      _playerStateSub = _playerController.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        setState(() => _isPlaying = state == PlayerState.playing);
      });

      _completionSub = _playerController.onCompletion.listen((_) {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _currentPosition = Duration.zero;
        });
      });

      _currentPosSub = _playerController.onCurrentDurationChanged.listen((ms) {
        if (!mounted) return;
        setState(() => _currentPosition = Duration(milliseconds: ms));
      });

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('❌ VoiceMessageWidget._preparePlayer: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
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
      debugPrint('❌ VoiceMessageWidget._togglePlay: $e');
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _completionSub?.cancel();
    _currentPosSub?.cancel();
    _playerController.dispose();
    _appearCtrl.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.isMyMessage;

    return ScaleTransition(
      scale: _scaleAnim,
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280, minWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF007AFF), Color(0xFF0056D6)],
                )
              : null,
          color: isMe ? null : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(isMe ? 22 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 22),
          ),
          boxShadow: [
            BoxShadow(
              color: isMe
                  ? const Color(0xFF007AFF).withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PlayButton(
              isPlaying: _isPlaying,
              isLoading: _isLoading,
              hasError: _hasError,
              isMe: isMe,
              onTap: (_isLoading || _hasError) ? null : _togglePlay,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoading)
                  _WaveformPlaceholder(isMe: isMe)
                else if (_hasError)
                  _ErrorWaveform(isMe: isMe)
                else
                  AudioFileWaveforms(
                    size: const Size(150, 28),
                    playerController: _playerController,
                    enableSeekGesture: true,
                    waveformType: WaveformType.fitWidth,
                    playerWaveStyle: PlayerWaveStyle(
                      fixedWaveColor:
                          isMe ? Colors.white.withValues(alpha: 0.35) : const Color(0xFFD1D5DB),
                      liveWaveColor: isMe ? Colors.white : const Color(0xFF007AFF),
                      spacing: 3.5,
                      waveThickness: 2.5,
                      seekLineColor: isMe
                          ? Colors.white.withValues(alpha: 0.6)
                          : const Color(0xFF007AFF).withValues(alpha: 0.5),
                      seekLineThickness: 1.5,
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  _isLoading
                      ? '--:--'
                      : (_totalDuration > Duration.zero
                          ? '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}'
                          : _formatDuration(_currentPosition)),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isMe ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatefulWidget {
  final bool isPlaying;
  final bool isLoading;
  final bool hasError;
  final bool isMe;
  final VoidCallback? onTap;

  const _PlayButton({
    required this.isPlaying,
    required this.isLoading,
    required this.hasError,
    required this.isMe,
    this.onTap,
  });

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0.9,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isMe ? Colors.white.withValues(alpha: 0.22) : const Color(0xFFF0F0F5);
    final iconColor = widget.isMe ? Colors.white : const Color(0xFF007AFF);

    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => _ctrl.reverse() : null,
      onTapUp: widget.onTap != null
          ? (_) {
              _ctrl.forward();
              widget.onTap!();
            }
          : null,
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _ctrl,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
          ),
          child: widget.isLoading
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(iconColor),
                  ),
                )
              : widget.hasError
                  ? Icon(Icons.error_outline_rounded,
                      color: iconColor.withValues(alpha: 0.6), size: 22)
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: child,
                      ),
                      child: Icon(
                        widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey(widget.isPlaying),
                        color: iconColor,
                        size: 24,
                      ),
                    ),
        ),
      ),
    );
  }
}

class _WaveformPlaceholder extends StatefulWidget {
  final bool isMe;
  const _WaveformPlaceholder({required this.isMe});

  @override
  State<_WaveformPlaceholder> createState() => _WaveformPlaceholderState();
}

class _WaveformPlaceholderState extends State<_WaveformPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final base = widget.isMe ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFE8EBF0);
        final highlight =
            widget.isMe ? Colors.white.withValues(alpha: 0.45) : const Color(0xFFF5F5F5);
        return Container(
          width: 150,
          height: 28,
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, _anim.value),
            borderRadius: BorderRadius.circular(6),
          ),
        );
      },
    );
  }
}

class _ErrorWaveform extends StatelessWidget {
  final bool isMe;
  const _ErrorWaveform({required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.wifi_off_rounded,
          size: 14,
          color: isMe ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF9CA3AF),
        ),
        const SizedBox(width: 6),
        Text(
          'Không tải được',
          style: TextStyle(
            fontSize: 12,
            color: isMe ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
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
  State<VoiceRecordingIndicator> createState() => _VoiceRecordingIndicatorState();
}

class _VoiceRecordingIndicatorState extends State<VoiceRecordingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _dotCtrl;
  late AnimationController _barsCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();

    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _barsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnim = CurvedAnimation(
      parent: _slideCtrl,
      curve: Curves.easeOutCubic,
    );
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    _barsCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(_slideAnim),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.red.withValues(alpha: 0.15), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _dotCtrl,
              builder: (_, __) => Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.5 + _dotCtrl.value * 0.5),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.4 * _dotCtrl.value),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.duration,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            _AnimatedBars(controller: _barsCtrl),
            const Spacer(),
            _IconBtn(
              icon: Icons.delete_rounded,
              color: Colors.red,
              tooltip: 'Huỷ',
              onTap: widget.onCancel,
            ),
            const SizedBox(width: 8),
            _SendVoiceButton(onTap: widget.onSend),
          ],
        ),
      ),
    );
  }
}

class _AnimatedBars extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedBars({required this.controller});

  static const List<double> _phases = [0.0, 0.33, 0.66, 0.2, 0.5];
  static const List<double> _heights = [8, 16, 12, 20, 10];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(5, (i) {
            final t = ((controller.value + _phases[i]) % 1.0);
            final h = 4.0 + (_heights[i] * (t < 0.5 ? t * 2 : 2 - t * 2));
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _SendVoiceButton extends StatefulWidget {
  final VoidCallback onTap;
  const _SendVoiceButton({required this.onTap});

  @override
  State<_SendVoiceButton> createState() => _SendVoiceButtonState();
}

class _SendVoiceButtonState extends State<_SendVoiceButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.88,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) {
        _ctrl.forward();
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _ctrl,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                ColorConstants.primaryColor,
                ColorConstants.primaryColor.withValues(alpha: 0.8),
              ],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: ColorConstants.primaryColor.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.send_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
