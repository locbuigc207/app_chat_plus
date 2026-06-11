import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/agora_rtc_manager.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallStatsOverlay
// Real-time stats panel with animated bars and network quality indicators
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallStatsOverlay extends StatefulWidget {
  final RtcCallStats stats;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const GroupCallStatsOverlay({
    super.key,
    required this.stats,
    this.isExpanded = false,
    this.onToggle,
  });

  @override
  State<GroupCallStatsOverlay> createState() => _GroupCallStatsOverlayState();
}

class _GroupCallStatsOverlayState extends State<GroupCallStatsOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;

  static const _bg = Color(0xFF0A0E1A);
  static const _surface = Color(0xFF111827);
  static const _border = Color(0xFF1E2D40);
  static const _text = Color(0xFFF8FAFC);
  static const _sub = Color(0xFF94A3B8);
  static const _muted = Color(0xFF475569);
  static const _green = Color(0xFF22C55E);
  static const _amber = Color(0xFFF59E0B);
  static const _red = Color(0xFFEF4444);
  static const _blue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _expandAnim =
        CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    if (widget.isExpanded) _expandCtrl.value = 1.0;
  }

  @override
  void didUpdateWidget(GroupCallStatsOverlay old) {
    super.didUpdateWidget(old);
    if (widget.isExpanded != old.isExpanded) {
      widget.isExpanded ? _expandCtrl.forward() : _expandCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  int get _qualityLevel {
    final s = widget.stats;
    if (s.rtt == 0 && s.txBitrate == 0) return 4;
    if (s.rtt < 80 && s.txPacketLoss < 2) return 4;
    if (s.rtt < 160 && s.txPacketLoss < 5) return 3;
    if (s.rtt < 300 && s.txPacketLoss < 12) return 2;
    return 1;
  }

  Color _qualityColor(int level) {
    switch (level) {
      case 4:
        return _green;
      case 3:
        return const Color(0xFFAED581);
      case 2:
        return _amber;
      default:
        return _red;
    }
  }

  String _qualityLabel(int level) {
    switch (level) {
      case 4:
        return 'Xuất sắc';
      case 3:
        return 'Tốt';
      case 2:
        return 'Yếu';
      default:
        return 'Kém';
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = _qualityLevel;
    final color = _qualityColor(level);

    return GestureDetector(
      onTap: widget.onToggle,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.2), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compact badge
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AnimatedSignalBars(level: level, color: color),
                      const SizedBox(width: 6),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                        child: Text(_qualityLabel(level)),
                      ),
                      if (widget.onToggle != null) ...[
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: widget.isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 300),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: color.withOpacity(0.7),
                            size: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Expanded panel
                SizeTransition(
                  sizeFactor: _expandAnim,
                  child: _buildExpandedPanel(color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel(Color accentColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: Colors.white.withOpacity(0.08), height: 8),

          // Bitrate chart preview
          _BitrateBar(
            label: 'Gửi',
            value: widget.stats.txBitrate,
            maxValue: 2000,
            color: _blue,
          ),
          const SizedBox(height: 5),
          _BitrateBar(
            label: 'Nhận',
            value: widget.stats.rxBitrate,
            maxValue: 2000,
            color: _green,
          ),
          const SizedBox(height: 8),

          // Stat rows
          _statRow(
              'RTT', '${widget.stats.rtt} ms', _rttColor(widget.stats.rtt)),
          const SizedBox(height: 3),
          _statRow('Mất gói', '${widget.stats.txPacketLoss}%',
              _lossColor(widget.stats.txPacketLoss)),
          const SizedBox(height: 3),
          _statRow('Thời gian', _formatDuration(widget.stats.duration),
              Colors.white54),
        ],
      ),
    );
  }

  Color _rttColor(int rtt) {
    if (rtt < 80) return _green;
    if (rtt < 200) return _amber;
    return _red;
  }

  Color _lossColor(int loss) {
    if (loss < 2) return _green;
    if (loss < 10) return _amber;
    return _red;
  }

  String _formatDuration(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return s >= 3600 ? '${s ~/ 3600}:$m:$sec' : '$m:$sec';
  }

  Widget _statRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: _muted, fontSize: 10, fontWeight: FontWeight.w500)),
        const SizedBox(width: 5),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ─── Animated signal bars ─────────────────────────────────────────────────────
class _AnimatedSignalBars extends StatefulWidget {
  final int level; // 1-4
  final Color color;
  const _AnimatedSignalBars({required this.level, required this.color});

  @override
  State<_AnimatedSignalBars> createState() => _AnimatedSignalBarsState();
}

class _AnimatedSignalBarsState extends State<_AnimatedSignalBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final filled = i < widget.level;
        final barH = 4.5 + i * 3.0;
        final isWeak = !filled && widget.level <= 1;

        return AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final opacity =
                filled ? 1.0 : (isWeak ? 0.25 + _ctrl.value * 0.25 : 0.18);
            return Opacity(
              opacity: opacity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                width: 3.5,
                height: barH,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: filled ? widget.color : Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ─── Bitrate bar ──────────────────────────────────────────────────────────────
class _BitrateBar extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final Color color;

  const _BitrateBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (value / maxValue).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              child: Text(label,
                  style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
            ),
            Text('$value kbps',
                style: TextStyle(
                    color: color, fontSize: 9, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: 140,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (_, v, __) => ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 3,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AudioLevelVisualizer
// Animated waveform bars showing speaker audio level in real time
// ══════════════════════════════════════════════════════════════════════════════
class AudioLevelVisualizer extends StatefulWidget {
  final double level; // 0.0 – 1.0
  final Color color;
  final double width;
  final double height;
  final int barCount;

  const AudioLevelVisualizer({
    super.key,
    required this.level,
    this.color = const Color(0xFF4ADE80),
    this.width = 48,
    this.height = 24,
    this.barCount = 7,
  });

  @override
  State<AudioLevelVisualizer> createState() => _AudioLevelVisualizerState();
}

class _AudioLevelVisualizerState extends State<AudioLevelVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _random = math.Random();
  late List<double> _heights;

  @override
  void initState() {
    super.initState();
    _heights =
        List.generate(widget.barCount, (i) => 0.3 + _random.nextDouble() * 0.4);
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120))
      ..addListener(_updateBars)
      ..repeat(reverse: true);
  }

  void _updateBars() {
    if (!mounted) return;
    if (widget.level < 0.05) {
      setState(() {
        _heights = List.generate(widget.barCount, (_) => 0.15);
      });
      return;
    }
    setState(() {
      _heights = List.generate(widget.barCount, (i) {
        // Middle bars taller
        final center = widget.barCount / 2;
        final dist = (i - center).abs() / center;
        final base = 0.2 + widget.level * (1.0 - dist * 0.5);
        final jitter = (_random.nextDouble() - 0.5) * 0.25 * widget.level;
        return (base + jitter).clamp(0.1, 1.0);
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
    final barW = (widget.width - (widget.barCount - 1) * 2) / widget.barCount;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(widget.barCount, (i) {
          final h = _heights[i] * widget.height;
          return Padding(
            padding: EdgeInsets.only(right: i < widget.barCount - 1 ? 2 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: barW,
              height: h.clamp(3.0, widget.height),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.5 + _heights[i] * 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SpeakingIndicatorRing
// Animated ring that pulses around an avatar when speaking
// ══════════════════════════════════════════════════════════════════════════════
class SpeakingIndicatorRing extends StatefulWidget {
  final bool isSpeaking;
  final double audioLevel; // 0-1
  final Color color;
  final double radius;
  final Widget child;

  const SpeakingIndicatorRing({
    super.key,
    required this.isSpeaking,
    this.audioLevel = 0,
    this.color = const Color(0xFF4ADE80),
    required this.radius,
    required this.child,
  });

  @override
  State<SpeakingIndicatorRing> createState() => _SpeakingIndicatorRingState();
}

class _SpeakingIndicatorRingState extends State<SpeakingIndicatorRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSpeaking) return widget.child;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        final spread = widget.audioLevel * 6 * _pulse.value;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.3 + widget.audioLevel * 0.3),
                blurRadius: 12 + spread * 2,
                spreadRadius: spread,
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color.withOpacity(0.7 + _pulse.value * 0.3),
                width: 2 + widget.audioLevel * 1.5,
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
// CallDurationBadge
// Live call duration with pulsing dot
// ══════════════════════════════════════════════════════════════════════════════
class CallDurationBadge extends StatefulWidget {
  final DateTime startTime;
  final bool compact;

  const CallDurationBadge({
    super.key,
    required this.startTime,
    this.compact = false,
  });

  @override
  State<CallDurationBadge> createState() => _CallDurationBadgeState();
}

class _CallDurationBadgeState extends State<CallDurationBadge>
    with SingleTickerProviderStateMixin {
  late Duration _elapsed;
  late final AnimationController _dotCtrl;
  late final Animation<double> _dotAnim;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.startTime);
    _dotCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _dotAnim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _dotCtrl, curve: Curves.easeInOut));

    // Update every second
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _elapsed = DateTime.now().difference(widget.startTime));
      return true;
    });
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  String get _formatted {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _dotAnim,
            builder: (_, __) => Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4ADE80).withOpacity(_dotAnim.value),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _formatted,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _dotAnim,
            builder: (_, __) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4ADE80).withOpacity(_dotAnim.value),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4ADE80)
                        .withOpacity(_dotAnim.value * 0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _formatted,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NetworkQualityWidget
// Full-featured network quality card
// ══════════════════════════════════════════════════════════════════════════════
class NetworkQualityWidget extends StatelessWidget {
  final int rtt;
  final int txLoss;
  final int rxLoss;
  final int txBitrate;
  final int rxBitrate;
  final bool showDetails;

  const NetworkQualityWidget({
    super.key,
    required this.rtt,
    required this.txLoss,
    required this.rxLoss,
    required this.txBitrate,
    required this.rxBitrate,
    this.showDetails = false,
  });

  int get _level {
    if (rtt == 0 && txBitrate == 0) return 4;
    if (rtt < 80 && txLoss < 2) return 4;
    if (rtt < 160 && txLoss < 5) return 3;
    if (rtt < 300 && txLoss < 12) return 2;
    return 1;
  }

  Color get _color {
    switch (_level) {
      case 4:
        return const Color(0xFF22C55E);
      case 3:
        return const Color(0xFFAED581);
      case 2:
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFEF4444);
    }
  }

  String get _label {
    switch (_level) {
      case 4:
        return 'Xuất sắc';
      case 3:
        return 'Tốt';
      case 2:
        return 'Yếu';
      default:
        return 'Kém';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!showDetails) {
      return Tooltip(
        message: 'Kết nối: $_label\nRTT: $rtt ms\nMất gói: $txLoss%',
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        textStyle: const TextStyle(color: Colors.white70, fontSize: 11),
        child: _buildCompact(),
      );
    }
    return _buildDetailed();
  }

  Widget _buildCompact() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _AnimatedSignalBars(level: _level, color: _color),
        if (_level < 3) ...[
          const SizedBox(width: 5),
          Text(_label,
              style: TextStyle(
                  color: _color, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }

  Widget _buildDetailed() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _AnimatedSignalBars(level: _level, color: _color),
            const SizedBox(width: 8),
            Text('Kết nối: $_label',
                style: TextStyle(
                    color: _color, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          _detailRow('RTT', '$rtt ms', _rttColor),
          const SizedBox(height: 4),
          _detailRow('Mất gói TX', '$txLoss%', _lossColor(txLoss)),
          const SizedBox(height: 4),
          _detailRow('Mất gói RX', '$rxLoss%', _lossColor(rxLoss)),
          const SizedBox(height: 4),
          _detailRow('Băng thông gửi', '$txBitrate kbps', Colors.white54),
          const SizedBox(height: 4),
          _detailRow('Băng thông nhận', '$rxBitrate kbps', Colors.white54),
        ],
      ),
    );
  }

  Color get _rttColor {
    if (rtt < 80) return const Color(0xFF22C55E);
    if (rtt < 200) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Color _lossColor(int loss) {
    if (loss < 2) return const Color(0xFF22C55E);
    if (loss < 10) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Widget _detailRow(String label, String value, Color valueColor) {
    return Row(children: [
      SizedBox(
        width: 100,
        child: Text(label,
            style: const TextStyle(color: Color(0xFF475569), fontSize: 11)),
      ),
      Text(value,
          style: TextStyle(
              color: valueColor, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }
}
