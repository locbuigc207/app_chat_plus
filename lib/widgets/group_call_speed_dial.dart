// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/group_call_model.dart';

class _K {
  static const bg = Color(0xFF080E1C);
  static const surface = Color(0xFF111827);
  static const s2 = Color(0xFF1C2333);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const purple = Color(0xFF8B5CF6);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallSpeedDial
// Expandable FAB with video + voice options, animated with stagger
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallSpeedDial extends StatefulWidget {
  final ValueChanged<GroupCallType> onCallTypeSelected;
  final bool isLoading;

  const GroupCallSpeedDial({
    super.key,
    required this.onCallTypeSelected,
    this.isLoading = false,
  });

  @override
  State<GroupCallSpeedDial> createState() => _GroupCallSpeedDialState();
}

class _GroupCallSpeedDialState extends State<GroupCallSpeedDial>
    with TickerProviderStateMixin {
  bool _isOpen = false;

  late AnimationController _mainCtrl;
  late AnimationController _staggerCtrl;
  late Animation<double> _mainRotate;
  late Animation<double> _bgFade;
  late List<Animation<double>> _itemAnims;
  late List<Animation<Offset>> _itemSlides;

  static const _items = [
    (
      icon: Icons.videocam_rounded,
      label: 'Gọi video',
      color: _K.accent,
      type: GroupCallType.video
    ),
    (
      icon: Icons.phone_rounded,
      label: 'Gọi thoại',
      color: _K.green,
      type: GroupCallType.voice
    ),
  ];

  @override
  void initState() {
    super.initState();

    _mainCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _staggerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));

    _mainRotate = Tween<double>(begin: 0, end: 0.375)
        .animate(CurvedAnimation(parent: _mainCtrl, curve: Curves.easeOutBack));
    _bgFade = CurvedAnimation(parent: _mainCtrl, curve: Curves.easeOut);

    _itemAnims = List.generate(_items.length, (i) {
      final start = i * 0.25;
      final end = start + 0.75;
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _staggerCtrl,
          curve: Interval(start, end, curve: Curves.elasticOut),
        ),
      );
    });

    _itemSlides = List.generate(_items.length, (i) {
      final start = i * 0.15;
      final end = start + 0.85;
      return Tween<Offset>(
        begin: const Offset(0, 0.5),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _staggerCtrl,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ));
    });
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _staggerCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    if (_isOpen) {
      _mainCtrl.reverse();
      _staggerCtrl.reverse();
    } else {
      _mainCtrl.forward();
      _staggerCtrl.forward();
    }
    setState(() => _isOpen = !_isOpen);
  }

  void _select(GroupCallType type) {
    HapticFeedback.mediumImpact();
    _mainCtrl.reverse();
    _staggerCtrl.reverse();
    setState(() => _isOpen = false);
    widget.onCallTypeSelected(type);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      clipBehavior: Clip.none,
      children: [
        // Background overlay tap-to-close
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle,
              child: FadeTransition(
                opacity: _bgFade,
                child: Container(color: Colors.black.withOpacity(0.35)),
              ),
            ),
          ),

        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Speed dial items (reverse so video is on top)
            ..._items
                .asMap()
                .entries
                .map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  return ScaleTransition(
                    scale: _itemAnims[i],
                    child: SlideTransition(
                      position: _itemSlides[i],
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SpeedDialItem(
                          icon: item.icon,
                          label: item.label,
                          color: item.color,
                          onTap: () => _select(item.type),
                        ),
                      ),
                    ),
                  );
                })
                .toList()
                .reversed,

            const SizedBox(height: 4),

            // Main FAB
            _MainFab(
              isOpen: _isOpen,
              isLoading: widget.isLoading,
              rotateAnim: _mainRotate,
              onTap: widget.isLoading ? null : _toggle,
            ),
          ],
        ),
      ],
    );
  }
}

class _SpeedDialItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SpeedDialItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_SpeedDialItem> createState() => _SpeedDialItemState();
}

class _SpeedDialItemState extends State<_SpeedDialItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _press;
  late Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _pressAnim = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _press, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) {
        _press.reverse();
        widget.onTap();
      },
      onTapCancel: () => _press.reverse(),
      child: ScaleTransition(
        scale: _pressAnim,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _K.s2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.07)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Text(widget.label,
                  style: const TextStyle(
                      color: _K.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            // Icon button
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: widget.color.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainFab extends StatelessWidget {
  final bool isOpen;
  final bool isLoading;
  final Animation<double> rotateAnim;
  final VoidCallback? onTap;

  const _MainFab({
    required this.isOpen,
    required this.isLoading,
    required this.rotateAnim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: isOpen ? const Color(0xFF374151) : _K.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (isOpen ? Colors.black : _K.accent).withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : RotationTransition(
                turns: rotateAnim,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isOpen ? Icons.close_rounded : Icons.call_rounded,
                    key: ValueKey(isOpen),
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CallTypeSelector
// Inline horizontal selector (alternative to speed dial)
// ══════════════════════════════════════════════════════════════════════════════
class CallTypeSelector extends StatelessWidget {
  final GroupCallType selected;
  final ValueChanged<GroupCallType> onChanged;

  const CallTypeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _K.s2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _option(
              GroupCallType.video, Icons.videocam_rounded, 'Video', _K.accent),
          const SizedBox(width: 4),
          _option(GroupCallType.voice, Icons.phone_rounded, 'Thoại', _K.green),
        ],
      ),
    );
  }

  Widget _option(GroupCallType type, IconData icon, String label, Color color) {
    final active = selected == type;
    return GestureDetector(
      onTap: () => onChanged(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? color.withOpacity(0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? color : _K.muted, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  color: active ? color : _K.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}
