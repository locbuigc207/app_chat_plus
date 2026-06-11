// ignore_for_file: deprecated_member_use
import 'dart:math' as math;

import 'package:flutter/material.dart';

class _K {
  static const green = Color(0xFF4ADE80);
  static const accent = Color(0xFF3B82F6);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// WaveformVisualizer
// Horizontal waveform bars that animate with audio level.
// ══════════════════════════════════════════════════════════════════════════════
class WaveformVisualizer extends StatefulWidget {
  final double level; // 0.0–1.0
  final Color? color;
  final double width;
  final double height;
  final int barCount;
  final bool symmetric; // mirror left-right
  final bool rounded;

  const WaveformVisualizer({
    super.key,
    required this.level,
    this.color,
    this.width = 64,
    this.height = 28,
    this.barCount = 9,
    this.symmetric = true,
    this.rounded = true,
  });

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _rng = math.Random();
  late List<double> _bars;

  @override
  void initState() {
    super.initState();
    _bars = _idle();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 90))
      ..addListener(_tick)
      ..repeat(reverse: true);
  }

  List<double> _idle() => List.generate(widget.barCount, (_) => 0.15);

  void _tick() {
    if (!mounted) return;
    final lv = widget.level;
    if (lv < 0.04) {
      setState(() => _bars = _idle());
      return;
    }
    setState(() {
      _bars = List.generate(widget.barCount, (i) {
        // Centre bars taller
        final mid = widget.barCount / 2;
        final dist = (i - mid).abs() / mid;
        final base = lv * (1.0 - dist * 0.55) + 0.12;
        final jit = (_rng.nextDouble() - 0.5) * 0.28 * lv;
        return (base + jit).clamp(0.08, 1.0);
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? _K.green;
    final actualBars = widget.symmetric ? _symmetricBars() : _bars;
    final spacing = 2.0;
    final barW =
        (widget.width - spacing * (actualBars.length - 1)) / actualBars.length;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: actualBars.asMap().entries.map((e) {
          final h = (e.value * widget.height).clamp(3.0, widget.height);
          return Padding(
            padding: EdgeInsets.only(
                right: e.key < actualBars.length - 1 ? spacing : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              width: barW.clamp(2.0, 8.0),
              height: h,
              decoration: BoxDecoration(
                color: color.withOpacity(0.55 + e.value * 0.45),
                borderRadius:
                    widget.rounded ? BorderRadius.circular(barW / 2) : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<double> _symmetricBars() {
    final half = (_bars.length / 2).ceil();
    final left = _bars.take(half).toList();
    final right = left.reversed.toList();
    return [...left, ...right];
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SpeakingRing
// Animated glow ring that pulsates around a widget when speaking.
// ══════════════════════════════════════════════════════════════════════════════
class SpeakingRing extends StatefulWidget {
  final bool isSpeaking;
  final double audioLevel; // 0.0–1.0
  final Color color;
  final double borderWidth;
  final Widget child;

  const SpeakingRing({
    super.key,
    required this.isSpeaking,
    this.audioLevel = 0,
    this.color = _K.green,
    this.borderWidth = 2.5,
    required this.child,
  });

  @override
  State<SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends State<SpeakingRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSpeaking) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final spread = widget.audioLevel * 5 * _pulse.value;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color:
                    widget.color.withOpacity(0.25 + widget.audioLevel * 0.35),
                blurRadius: 14 + spread * 2,
                spreadRadius: spread,
              )
            ],
          ),
          child: Container(
            padding: EdgeInsets.all(widget.borderWidth),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color.withOpacity(0.65 + _pulse.value * 0.35),
                width: widget.borderWidth + widget.audioLevel * 1.5,
              ),
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AudioLevelBar
// Single vertical bar showing mic level (used in setup screen).
// ══════════════════════════════════════════════════════════════════════════════
class AudioLevelBar extends StatelessWidget {
  final double level; // 0.0–1.0
  final Color? color;
  final double width;
  final double maxHeight;

  const AudioLevelBar({
    super.key,
    required this.level,
    this.color,
    this.width = 6,
    this.maxHeight = 48,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? _K.green;
    final h = (level * maxHeight).clamp(4.0, maxHeight);
    return Container(
      width: width,
      height: maxHeight,
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: width,
        height: h,
        decoration: BoxDecoration(
          color: c.withOpacity(0.5 + level * 0.5),
          borderRadius: BorderRadius.circular(width / 2),
          boxShadow: level > 0.3
              ? [BoxShadow(color: c.withOpacity(level * 0.4), blurRadius: 8)]
              : null,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MicTestWidget
// Interactive mic level tester for the pre-call setup screen.
// ══════════════════════════════════════════════════════════════════════════════
class MicTestWidget extends StatelessWidget {
  final double micLevel; // 0.0–1.0
  final bool isMuted;
  final VoidCallback onToggle;

  const MicTestWidget({
    super.key,
    required this.micLevel,
    required this.isMuted,
    required this.onToggle,
  });

  Color get _color {
    if (isMuted) return _K.red;
    if (micLevel > 0.7) return _K.green;
    if (micLevel > 0.3) return _K.accent;
    return _K.muted;
  }

  String get _label {
    if (isMuted) return 'Micro đang tắt';
    if (micLevel > 0.6) return 'Tốt! Micro hoạt động';
    if (micLevel > 0.15) return 'Micro đang hoạt động';
    return 'Nói gì đó để kiểm tra…';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _color.withOpacity(0.22)),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: _color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                    color: _color, fontSize: 12, fontWeight: FontWeight.w600),
                child: Text(_label),
              ),
              const SizedBox(height: 6),
              // Level bars
              Row(
                  children: List.generate(12, (i) {
                final threshold = (i + 1) / 12;
                final active = !isMuted && micLevel >= threshold;
                return Expanded(
                    child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: active
                        ? _color.withOpacity(0.7 + threshold * 0.3)
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ));
              })),
            ],
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// VoiceActivityIndicator
// Compact badge shown on avatar when user is actively speaking.
// ══════════════════════════════════════════════════════════════════════════════
class VoiceActivityIndicator extends StatefulWidget {
  final bool isActive;
  final double level;
  final Color? color;
  final double size;

  const VoiceActivityIndicator({
    super.key,
    required this.isActive,
    this.level = 0,
    this.color,
    this.size = 14,
  });

  @override
  State<VoiceActivityIndicator> createState() => _VoiceActivityIndicatorState();
}

class _VoiceActivityIndicatorState extends State<VoiceActivityIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();
    final color = widget.color ?? _K.green;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(_anim.value * 0.6),
              blurRadius: 8 + widget.level * 6,
              spreadRadius: widget.level * 3,
            )
          ],
        ),
        child: Icon(Icons.mic_rounded,
            color: Colors.white, size: widget.size * 0.62),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ParticipantAudioCard
// Card showing a participant's avatar + waveform (voice-only mode)
// ══════════════════════════════════════════════════════════════════════════════
class ParticipantAudioCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final bool isMuted;
  final bool isSpeaking;
  final double audioLevel;
  final bool isAdmin;
  final bool isCurrentUser;

  const ParticipantAudioCard({
    super.key,
    required this.name,
    this.avatarUrl,
    required this.isMuted,
    required this.isSpeaking,
    this.audioLevel = 0,
    this.isAdmin = false,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final nameColor = isCurrentUser ? _K.accent : Colors.white;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Avatar with speaking ring
      SpeakingRing(
        isSpeaking: isSpeaking && !isMuted,
        audioLevel: audioLevel,
        color: _K.green,
        child: Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(
            radius: 32,
            backgroundImage:
                avatarUrl?.isNotEmpty == true ? NetworkImage(avatarUrl!) : null,
            backgroundColor: const Color(0xFF1C2333),
            child: avatarUrl?.isNotEmpty != true
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700))
                : null,
          ),
          // Mic status badge
          Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isMuted ? _K.red : _K.green,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: const Color(0xFF080E1C), width: 1.5),
                ),
                child: Icon(isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    size: 10, color: Colors.white),
              )),
          // Admin star
          if (isAdmin)
            Positioned(
                left: -2,
                top: -2,
                child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _K.amber,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF080E1C), width: 1.5),
                    ),
                    child: const Icon(Icons.star_rounded,
                        size: 8, color: Colors.white))),
        ]),
      ),
      const SizedBox(height: 7),
      // Name
      Text(isCurrentUser ? 'Bạn' : name,
          style: TextStyle(
              color: nameColor, fontSize: 11, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center),
      // Waveform
      const SizedBox(height: 4),
      isSpeaking && !isMuted
          ? WaveformVisualizer(
              level: audioLevel,
              width: 36,
              height: 12,
              barCount: 5,
              color: _K.green)
          : SizedBox(
              height: 12,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      5,
                      (_) => Container(
                            width: 3,
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.12)),
                          ))),
            ),
    ]);
  }
}
