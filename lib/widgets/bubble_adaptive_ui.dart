// lib/widgets/bubble_adaptive_ui.dart
// Contextual Bubble Universe - Adaptive Bubble UI
// Giao diện bong bóng thích ứng theo Mode ngữ cảnh

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/contextual_bubble_service.dart';

// ─── CONSTANTS ────────────────────────────────────────────────────────────────

const _kBlue = Color(0xFF2196F3);
const _kDark = Color(0xFF1A2340);
const _kSurface = Color(0xFFF8F9FE);

// ─── MAIN ADAPTIVE BUBBLE ─────────────────────────────────────────────────────

/// Lớp bao ngoài MiniChatOverlayWidget, inject adaptive header theo BubbleMode
class BubbleAdaptiveHeader extends StatefulWidget {
  final BubbleContext context;
  final String peerName;
  final String peerAvatar;
  final String conversationId;
  final String currentUserId;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const BubbleAdaptiveHeader({
    super.key,
    required this.context,
    required this.peerName,
    required this.peerAvatar,
    required this.conversationId,
    required this.currentUserId,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  State<BubbleAdaptiveHeader> createState() => _BubbleAdaptiveHeaderState();
}

class _BubbleAdaptiveHeaderState extends State<BubbleAdaptiveHeader>
    with TickerProviderStateMixin {
  late AnimationController _modeAnim;
  late AnimationController _pulseAnim;
  BubbleMode _prevMode = BubbleMode.normal;

  // Media player state (giả lập)
  bool _isMediaPlaying = false;
  Duration _mediaDuration = const Duration(minutes: 3, seconds: 42);
  Duration _mediaPosition = const Duration(minutes: 1, seconds: 15);
  Timer? _mediaTimer;

  @override
  void initState() {
    super.initState();
    _modeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(BubbleAdaptiveHeader old) {
    super.didUpdateWidget(old);
    if (old.context.mode != widget.context.mode) {
      _prevMode = old.context.mode;
      _modeAnim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _modeAnim.dispose();
    _pulseAnim.dispose();
    _mediaTimer?.cancel();
    super.dispose();
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _modeAnim,
      builder: (ctx, _) {
        return FadeTransition(
          opacity: _modeAnim,
          child: _buildHeader(widget.context.mode),
        );
      },
    );
  }

  Widget _buildHeader(BubbleMode mode) {
    switch (mode) {
      case BubbleMode.work:
        return _WorkModeHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          topic: widget.context.detectedTopic,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
        );
      case BubbleMode.media:
        return _MediaModeHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          isPlaying: _isMediaPlaying,
          onPlayPause: () => setState(() => _isMediaPlaying = !_isMediaPlaying),
          position: _mediaPosition,
          duration: _mediaDuration,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
        );
      case BubbleMode.location:
        final distance =
        widget.context.extraData?['distance'] as double?;
        return _LocationModeHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          distance: distance,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
          pulseAnim: _pulseAnim,
        );
      case BubbleMode.shared:
        return _SharedModeHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
        );
      case BubbleMode.secure:
        return _SecureModeHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
          pulseAnim: _pulseAnim,
        );
      default:
        return _NormalModeHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
        );
    }
  }
}

// ─── BASE HEADER MIXIN ────────────────────────────────────────────────────────

mixin _HeaderActions {
  Widget buildCloseButtons({
    required VoidCallback onMinimize,
    required VoidCallback onClose,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderBtn(icon: Icons.remove, onTap: onMinimize),
        const SizedBox(width: 2),
        _HeaderBtn(icon: Icons.close, onTap: onClose),
      ],
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

// ─── NORMAL MODE HEADER ───────────────────────────────────────────────────────

class _NormalModeHeader extends StatelessWidget with _HeaderActions {
  final String peerName;
  final String peerAvatar;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _NormalModeHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2196F3), Color(0xFF1565C0)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          _Avatar(url: peerAvatar, name: peerName),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peerName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const Text('💬 Chat',
                    style:
                    TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
          buildCloseButtons(onMinimize: onMinimize, onClose: onClose),
        ],
      ),
    );
  }
}

// ─── WORK MODE HEADER ─────────────────────────────────────────────────────────

class _WorkModeHeader extends StatelessWidget with _HeaderActions {
  final String peerName;
  final String peerAvatar;
  final String? topic;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _WorkModeHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.topic,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final label = _topicLabel(topic);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A2340), Color(0xFF263159)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Avatar(url: peerAvatar, name: peerName),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peerName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withOpacity(0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '💼 Work Mode',
                            style: const TextStyle(
                                color: Color(0xFF81C784),
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              buildCloseButtons(onMinimize: onMinimize, onClose: onClose),
            ],
          ),
          const SizedBox(height: 6),
          // Quick action bar
          Row(
            children: [
              _QuickAction(
                icon: Icons.task_alt_rounded,
                label: 'Task',
                color: const Color(0xFF4CAF50),
                onTap: () => HapticFeedback.lightImpact(),
              ),
              const SizedBox(width: 6),
              _QuickAction(
                icon: Icons.attach_file_rounded,
                label: 'File',
                color: const Color(0xFFFF9800),
                onTap: () => HapticFeedback.lightImpact(),
              ),
              const SizedBox(width: 6),
              _QuickAction(
                icon: Icons.event_rounded,
                label: 'Lịch',
                color: const Color(0xFF9C27B0),
                onTap: () => HapticFeedback.lightImpact(),
              ),
              const SizedBox(width: 6),
              _QuickAction(
                icon: Icons.checklist_rounded,
                label: 'Todo',
                color: const Color(0xFF00BCD4),
                onTap: () => HapticFeedback.lightImpact(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _topicLabel(String? topic) {
    switch (topic) {
      case 'task':
        return '📋 Task detected';
      case 'meeting':
        return '📅 Meeting detected';
      case 'deadline':
        return '⏰ Deadline mentioned';
      case 'file':
        return '📎 File discussion';
      default:
        return '💼 Work topic';
    }
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Column(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 9, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── MEDIA MODE HEADER ────────────────────────────────────────────────────────

class _MediaModeHeader extends StatelessWidget with _HeaderActions {
  final String peerName;
  final String peerAvatar;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final Duration position;
  final Duration duration;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _MediaModeHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.isPlaying,
    required this.onPlayPause,
    required this.position,
    required this.duration,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final progress = duration.inSeconds > 0
        ? position.inSeconds / duration.inSeconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF880E4F), Color(0xFFAD1457)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Avatar(url: peerAvatar, name: peerName, radius: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(peerName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
              // Mini player controls
              GestureDetector(
                onTap: onPlayPause,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              buildCloseButtons(onMinimize: onMinimize, onClose: onClose),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          Row(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '🎵 Media Mode',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                    minHeight: 3,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _fmt(position),
                style:
                const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ─── LOCATION MODE HEADER ─────────────────────────────────────────────────────

class _LocationModeHeader extends StatelessWidget with _HeaderActions {
  final String peerName;
  final String peerAvatar;
  final double? distance;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final AnimationController pulseAnim;

  const _LocationModeHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.distance,
    required this.onMinimize,
    required this.onClose,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final distStr = distance != null
        ? distance! < 1
        ? '${(distance! * 1000).round()} m'
        : '${distance!.toStringAsFixed(1)} km'
        : '...';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // Pulsing location icon
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, __) {
              return Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white
                      .withOpacity(0.1 + pulseAnim.value * 0.15),
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: Colors.white, size: 20),
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peerName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Row(
                  children: [
                    const Text('📍 ',
                        style: TextStyle(fontSize: 10)),
                    Text('Cách $distStr',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          // Mini map button
          GestureDetector(
            onTap: () => HapticFeedback.lightImpact(),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.map_rounded,
                      color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Bản đồ',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          buildCloseButtons(onMinimize: onMinimize, onClose: onClose),
        ],
      ),
    );
  }
}

// ─── SHARED MODE HEADER ───────────────────────────────────────────────────────

class _SharedModeHeader extends StatelessWidget with _HeaderActions {
  final String peerName;
  final String peerAvatar;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _SharedModeHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.onMinimize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4527A0), Color(0xFF5E35B1)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.palette_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peerName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const Text('🎨 Shared Space',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
          buildCloseButtons(onMinimize: onMinimize, onClose: onClose),
        ],
      ),
    );
  }
}

// ─── SECURE MODE HEADER ───────────────────────────────────────────────────────

class _SecureModeHeader extends StatelessWidget with _HeaderActions {
  final String peerName;
  final String peerAvatar;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final AnimationController pulseAnim;

  const _SecureModeHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.onMinimize,
    required this.onClose,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(const Color(0xFF212121), const Color(0xFF1A237E),
                    pulseAnim.value * 0.3)!,
                const Color(0xFF283593),
              ],
            ),
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peerName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const Text('🔒 Secure Mode - Anti-Shoulder-Surf',
                        style: TextStyle(
                            color: Colors.white60, fontSize: 9)),
                  ],
                ),
              ),
              buildCloseButtons(onMinimize: onMinimize, onClose: onClose),
            ],
          ),
        );
      },
    );
  }
}

// ─── AVATAR WIDGET ────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double radius;

  const _Avatar({required this.url, required this.name, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      backgroundColor: Colors.white24,
      child: url.isEmpty
          ? Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
        ),
      )
          : null,
    );
  }
}