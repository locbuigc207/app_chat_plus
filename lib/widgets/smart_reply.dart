import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';

class SmartReplyWidget extends StatefulWidget {
  final List<SmartReply> replies;
  final Function(String) onReplySelected;
  final bool isLoading;

  const SmartReplyWidget({
    super.key,
    required this.replies,
    required this.onReplySelected,
    this.isLoading = false,
  });

  @override
  State<SmartReplyWidget> createState() => _SmartReplyWidgetState();
}

class _SmartReplyWidgetState extends State<SmartReplyWidget> with SingleTickerProviderStateMixin {
  late AnimationController _entranceCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
    );
    if (widget.replies.isNotEmpty || widget.isLoading) {
      _entranceCtrl.forward();
    }
  }

  @override
  void didUpdateWidget(SmartReplyWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replies != oldWidget.replies && widget.replies.isNotEmpty) {
      _entranceCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading && widget.replies.isEmpty) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: AnimatedBuilder(
        animation: _slideAnim,
        builder: (_, child) =>
            Transform.translate(offset: Offset(0, _slideAnim.value), child: child),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AIIconBadge(),
              const SizedBox(width: 10),
              Expanded(
                child: widget.isLoading
                    ? const _ShimmerChips()
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: List.generate(widget.replies.length, (i) {
                            return _ReplyChip(
                              key: ValueKey(widget.replies[i].text),
                              text: widget.replies[i].text,
                              index: i,
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                widget.onReplySelected(widget.replies[i].text);
                              },
                            );
                          }),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AIIconBadge extends StatefulWidget {
  @override
  State<_AIIconBadge> createState() => _AIIconBadgeState();
}

class _AIIconBadgeState extends State<_AIIconBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
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
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          gradient: SweepGradient(
            startAngle: _ctrl.value * 6.28,
            endAngle: _ctrl.value * 6.28 + 6.28,
            colors: const [
              Color(0xFF8A2387),
              Color(0xFFE94057),
              Color(0xFFF27121),
              Color(0xFF8A2387),
            ],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE94057).withValues(alpha: 0.35),
              blurRadius: 10,
              spreadRadius: 0,
            ),
          ],
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          size: 15,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ReplyChip extends StatefulWidget {
  final String text;
  final int index;
  final VoidCallback onTap;

  const _ReplyChip({
    super.key,
    required this.text,
    required this.index,
    required this.onTap,
  });

  @override
  State<_ReplyChip> createState() => _ReplyChipState();
}

class _ReplyChipState extends State<_ReplyChip> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _slideAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _slideAnim = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );

    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _ctrl.forward();
    });
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
      builder: (_, child) => Transform.translate(
        offset: Offset(_slideAnim.value, 0),
        child: Transform.scale(scale: _scaleAnim.value, child: child),
      ),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          transform: Matrix4.identity()..scale(_pressed ? 0.95 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: _pressed ? ColorConstants.primaryColor.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: ColorConstants.primaryColor.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: _pressed
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Text(
            widget.text,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: _pressed ? ColorConstants.primaryColor : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerChips extends StatefulWidget {
  const _ShimmerChips();

  @override
  State<_ShimmerChips> createState() => _ShimmerChipsState();
}

class _ShimmerChipsState extends State<_ShimmerChips> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
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
        final shimmerColor =
            Color.lerp(const Color(0xFFE8EBF0), const Color(0xFFF5F5F5), _anim.value)!;
        return Row(
          children: List.generate(
            3,
            (i) => Container(
              margin: const EdgeInsets.only(right: 8),
              width: [80.0, 110.0, 70.0][i],
              height: 36,
              decoration: BoxDecoration(
                color: shimmerColor,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        );
      },
    );
  }
}
