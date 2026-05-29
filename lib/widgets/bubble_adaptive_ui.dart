import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/models/bubble_models.dart';


class _C {
  
  static const blue500 = Color(0xFF2196F3);
  static const blue700 = Color(0xFF1976D2);
  static const blue900 = Color(0xFF0D47A1);
  
  static const dark900 = Color(0xFF0D1B2A);
  static const dark800 = Color(0xFF162032);
  static const dark700 = Color(0xFF1E2D40);
  
  static const green700 = Color(0xFF388E3C);
  static const green800 = Color(0xFF2E7D32);
  static const green900 = Color(0xFF1B5E20);
  
  static const pink700 = Color(0xFFAD1457);
  static const pink900 = Color(0xFF880E4F);
  
  static const purple700 = Color(0xFF5E35B1);
  static const purple900 = Color(0xFF311B92);
  
  static const white = Colors.white;
  static const w70 = Color(0xB3FFFFFF);
  static const w50 = Color(0x80FFFFFF);
  static const w20 = Color(0x33FFFFFF);
  static const w15 = Color(0x26FFFFFF);
  static const w10 = Color(0x1AFFFFFF);
  static const teal = Color(0xFF64FFDA);
  static const online = Color(0xFF69F0AE);
  static const borderR = BorderRadius.vertical(top: Radius.circular(16));
}







class BubbleAdaptiveHeader extends StatefulWidget {
  final BubbleContext bubbleCtx;
  final String peerName;
  final String peerAvatar;
  final bool isPeerOnline;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback? onFullScreen;

  const BubbleAdaptiveHeader({
    super.key,
    required this.bubbleCtx,
    required this.peerName,
    required this.peerAvatar,
    this.isPeerOnline = false,
    required this.onMinimize,
    required this.onClose,
    this.onFullScreen,
  });

  @override
  State<BubbleAdaptiveHeader> createState() => _BubbleAdaptiveHeaderState();
}

class _BubbleAdaptiveHeaderState extends State<BubbleAdaptiveHeader> with TickerProviderStateMixin {
  late AnimationController _modeAnim;
  late AnimationController _pulseAnim;
  bool _mediaPlaying = false;

  @override
  void initState() {
    super.initState();
    _modeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..forward();

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(BubbleAdaptiveHeader old) {
    super.didUpdateWidget(old);
    if (old.bubbleCtx.mode != widget.bubbleCtx.mode) {
      _modeAnim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _modeAnim.dispose();
    _pulseAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _modeAnim, curve: Curves.easeOut),
      child: _buildForMode(widget.bubbleCtx.mode),
    );
  }

  Widget _buildForMode(BubbleMode mode) {
    switch (mode) {
      case BubbleMode.work:
        return _WorkHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          topic: widget.bubbleCtx.detectedTopic,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
          onFullScreen: widget.onFullScreen,
        );
      case BubbleMode.media:
        return _MediaHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          isPlaying: _mediaPlaying,
          onPlayPause: () => setState(() => _mediaPlaying = !_mediaPlaying),
          position: const Duration(minutes: 1, seconds: 15),
          duration: const Duration(minutes: 3, seconds: 42),
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
        );
      case BubbleMode.location:
        return _LocationHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          distance: widget.bubbleCtx.extraData?['distance'] as double?,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
          pulseAnim: _pulseAnim,
        );
      case BubbleMode.shared:
        return _SharedHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
        );
      case BubbleMode.secure:
        return _SecureHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
          pulseAnim: _pulseAnim,
        );
      case BubbleMode.normal:
      default:
        return _NormalHeader(
          peerName: widget.peerName,
          peerAvatar: widget.peerAvatar,
          isOnline: widget.isPeerOnline,
          onMinimize: widget.onMinimize,
          onClose: widget.onClose,
          onFullScreen: widget.onFullScreen,
        );
    }
  }
}


mixin _WindowActions {
  Widget buildButtons({
    required VoidCallback onMinimize,
    required VoidCallback onClose,
    VoidCallback? onFullScreen,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onFullScreen != null) ...[
          _WBtn(icon: Icons.open_in_full_rounded, onTap: onFullScreen),
          const SizedBox(width: 3),
        ],
        _WBtn(icon: Icons.remove_rounded, onTap: onMinimize),
        const SizedBox(width: 3),
        _WBtn(icon: Icons.close_rounded, onTap: onClose),
      ],
    );
  }
}

class _WBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _WBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _C.w15,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: _C.w70, size: 14),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double radius;
  const _Avatar({required this.url, required this.name, this.radius = 17});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _C.w20, width: 1.5),
        color: _C.w20,
        image: url.isNotEmpty ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
      ),
      child: url.isEmpty
          ? Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: _C.white,
                  fontSize: radius * 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : null,
    );
  }
}


class _NormalHeader extends StatelessWidget with _WindowActions {
  final String peerName;
  final String peerAvatar;
  final bool isOnline;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback? onFullScreen;

  const _NormalHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.isOnline,
    required this.onMinimize,
    required this.onClose,
    this.onFullScreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.blue500, _C.blue900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: _C.borderR,
      ),
      child: Row(
        children: [
          _Avatar(url: peerAvatar, name: peerName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(peerName,
                    style:
                        const TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    if (isOnline) ...[
                      _OnlineDot(),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      isOnline ? 'Đang trực tuyến' : 'Ngoại tuyến',
                      style: TextStyle(color: isOnline ? _C.w70 : _C.w50, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          buildButtons(
            onMinimize: onMinimize,
            onClose: onClose,
            onFullScreen: onFullScreen,
          ),
        ],
      ),
    );
  }
}

class _OnlineDot extends StatefulWidget {
  @override
  State<_OnlineDot> createState() => _OnlineDotState();
}

class _OnlineDotState extends State<_OnlineDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(const Color(0xFF69F0AE), const Color(0xFF00E676), _ctrl.value),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF69F0AE).withValues(alpha: 0.5 * _ctrl.value),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}


class _WorkHeader extends StatelessWidget with _WindowActions {
  final String peerName;
  final String peerAvatar;
  final String? topic;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback? onFullScreen;

  const _WorkHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.topic,
    required this.onMinimize,
    required this.onClose,
    this.onFullScreen,
  });

  static const _actions = [
    (Icons.task_alt_rounded, 'Task', Color(0xFF66BB6A)),
    (Icons.attach_file_rounded, 'Tệp', Color(0xFFFFB74D)),
    (Icons.event_rounded, 'Lịch', Color(0xFFCE93D8)),
    (Icons.checklist_rounded, 'Todo', Color(0xFF4DD0E1)),
    (Icons.timer_rounded, 'Timer', Color(0xFFEF9A9A)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.dark900, _C.dark700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: _C.borderR,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Avatar(url: peerAvatar, name: peerName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(peerName,
                        style: const TextStyle(
                            color: _C.white, fontWeight: FontWeight.w700, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    _TopicBadge(topic: topic),
                  ],
                ),
              ),
              buildButtons(onMinimize: onMinimize, onClose: onClose, onFullScreen: onFullScreen),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: _actions.map((a) {
              return Expanded(
                child: _WorkActionBtn(icon: a.$1, label: a.$2, color: a.$3),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TopicBadge extends StatelessWidget {
  final String? topic;
  const _TopicBadge({this.topic});

  static (String, String) _resolve(String? t) => switch (t) {
        'task' => ('📋', 'Task'),
        'meeting' => ('📅', 'Meeting'),
        'deadline' => ('⏰', 'Deadline'),
        'file' => ('📎', 'File'),
        'engineering' => ('⚙️', 'Kỹ thuật'),
        'bug' => ('🐛', 'Bug'),
        _ => ('💼', 'Work Mode'),
      };

  @override
  Widget build(BuildContext context) {
    final (emoji, label) = _resolve(topic);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF66BB6A).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF66BB6A).withValues(alpha: 0.35), width: 1),
      ),
      child: Text('$emoji $label',
          style:
              const TextStyle(color: Color(0xFF66BB6A), fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _WorkActionBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _WorkActionBtn({required this.icon, required this.label, required this.color});

  @override
  State<_WorkActionBtn> createState() => _WorkActionBtnState();
}

class _WorkActionBtnState extends State<_WorkActionBtn> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.85)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        HapticFeedback.lightImpact();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.color.withValues(alpha: 0.3), width: 1),
          ),
          child: Column(
            children: [
              Icon(widget.icon, size: 15, color: widget.color),
              const SizedBox(height: 2),
              Text(widget.label,
                  style: TextStyle(color: widget.color, fontSize: 9, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}


class _MediaHeader extends StatelessWidget with _WindowActions {
  final String peerName;
  final String peerAvatar;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final Duration position;
  final Duration duration;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _MediaHeader({
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
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [_C.pink900, _C.pink700], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: _C.borderR,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Avatar(url: peerAvatar, name: peerName, radius: 15),
              const SizedBox(width: 10),
              Expanded(
                child: Text(peerName,
                    style:
                        const TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onPlayPause();
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: _C.w20, shape: BoxShape.circle),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(isPlaying),
                      color: _C.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              buildButtons(onMinimize: onMinimize, onClose: onClose),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: _C.w15, borderRadius: BorderRadius.circular(4)),
                child: const Text('🎵 Media',
                    style: TextStyle(color: _C.w70, fontSize: 9, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: _C.w20,
                    color: _C.white,
                    minHeight: 3,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('${_fmt(position)}/${_fmt(duration)}',
                  style: const TextStyle(color: _C.w70, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}


class _LocationHeader extends StatelessWidget with _WindowActions {
  final String peerName;
  final String peerAvatar;
  final double? distance;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final AnimationController pulseAnim;

  const _LocationHeader({
    required this.peerName,
    required this.peerAvatar,
    required this.distance,
    required this.onMinimize,
    required this.onClose,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    final distStr = distance == null
        ? 'Đang xác định...'
        : distance! < 0.1
            ? '${(distance! * 1000).round()} m'
            : '${distance!.toStringAsFixed(1)} km';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [_C.green900, _C.green700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: _C.borderR,
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, __) => Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _C.white.withValues(alpha: 0.08 + pulseAnim.value * 0.12),
                border: Border.all(
                  color: _C.white.withValues(alpha: 0.2 + pulseAnim.value * 0.25),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.location_on_rounded, color: _C.white, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(peerName,
                    style:
                        const TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('📍 Cách bạn $distStr', style: const TextStyle(color: _C.w70, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => HapticFeedback.lightImpact(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _C.w20,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_rounded, color: _C.white, size: 14),
                  SizedBox(width: 4),
                  Text('Bản đồ',
                      style: TextStyle(color: _C.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          buildButtons(onMinimize: onMinimize, onClose: onClose),
        ],
      ),
    );
  }
}


class _SharedHeader extends StatelessWidget with _WindowActions {
  final String peerName;
  final String peerAvatar;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  const _SharedHeader({
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
            colors: [_C.purple900, _C.purple700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: _C.borderR,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: _C.w20, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.palette_rounded, color: _C.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(peerName,
                    style:
                        const TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const Text('🎨 Shared Space đang mở',
                    style: TextStyle(color: _C.w70, fontSize: 11)),
              ],
            ),
          ),
          buildButtons(onMinimize: onMinimize, onClose: onClose),
        ],
      ),
    );
  }
}


class _SecureHeader extends StatelessWidget with _WindowActions {
  final String peerName;
  final String peerAvatar;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final AnimationController pulseAnim;

  const _SecureHeader({
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
        final t = pulseAnim.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(const Color(0xFF0A0E1A), const Color(0xFF0D1F3C), t * 0.4)!,
                const Color(0xFF1A2A50),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(
              bottom: BorderSide(color: _C.teal.withValues(alpha: 0.2 + t * 0.25)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _C.teal.withValues(alpha: 0.1 + t * 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _C.teal.withValues(alpha: 0.3 + t * 0.3)),
                ),
                child: Icon(Icons.shield_rounded,
                    color: _C.teal.withValues(alpha: 0.8 + t * 0.2), size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(peerName,
                        style: const TextStyle(
                            color: _C.white, fontWeight: FontWeight.w700, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text('🔒 Bảo mật đầu cuối',
                        style: TextStyle(color: _C.teal.withValues(alpha: 0.7), fontSize: 10)),
                  ],
                ),
              ),
              buildButtons(onMinimize: onMinimize, onClose: onClose),
            ],
          ),
        );
      },
    );
  }
}
