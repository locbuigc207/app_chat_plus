// lib/widgets/autopilot_status_indicator.dart
// TÍNH NĂNG 1: AUTOPILOT — Status indicators cho AppBar và Input
// Gồm: AutoPilotAppBarButton, AutoPilotInputStatusBar, AutoPilotToggleRow

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/autopilot_provider.dart';
import '../providers/theme_provider.dart';
import 'autopilot_config_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AutoPilotAppBarButton — hiển thị trong AppBar chat_page.dart
// Usage: actions: [AutoPilotAppBarButton(conversationId: ..., currentUserId: ...)]
// ─────────────────────────────────────────────────────────────────────────────

class AutoPilotAppBarButton extends StatelessWidget {
  final String conversationId;
  final String currentUserId;
  final bool isGroup;

  const AutoPilotAppBarButton({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final pilot = context.watch<AutoPilotProvider>();
    final config = pilot.getConfig(conversationId);

    final isOn = config.isEnabled;
    final isNow = config.isActiveNow;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        AutoPilotConfigSheet.show(
          context,
          conversationId: conversationId,
          currentUserId: currentUserId,
          isGroup: isGroup,
        );
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        pilot.toggleAutoPlayForConversation(
          conversationId,
          enabled: !isOn,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              Icon(
                !isOn ? Icons.smart_toy_rounded : Icons.smart_toy_outlined,
                color: Colors.white,
                size: 17,
              ),
              const SizedBox(width: 8),
              Text(!isOn ? 'AutoPilot đã bật' : 'AutoPilot đã tắt'),
            ]),
            backgroundColor: !isOn ? Colors.green : Colors.grey[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Tooltip(
        message: isOn
            ? (isNow
                ? 'AutoPilot đang hoạt động (nhấn giữ để tắt)'
                : 'AutoPilot bật nhưng ngoài giờ hoạt động')
            : 'AutoPilot tắt (nhấn để cài đặt)',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isOn && isNow
                ? theme.primaryColor.withValues(alpha: 0.12)
                : isOn
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: isOn
                ? Border.all(
                    color: isNow
                        ? theme.primaryColor.withValues(alpha: 0.3)
                        : Colors.orange.withValues(alpha: 0.3),
                    width: 1,
                  )
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnimatedBotIcon(
                isActive: isOn && isNow,
                isEnabled: isOn,
                primary: theme.primaryColor,
              ),
              if (isOn) ...[
                const SizedBox(width: 5),
                Text(
                  'Auto',
                  style: TextStyle(
                    color: isNow ? theme.primaryColor : Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AutoPilotInputStatusBar — banner trượt lên trên input field
// Usage: đặt ở đầu Column của _buildInput() trong chat_page.dart
// ─────────────────────────────────────────────────────────────────────────────

class AutoPilotInputStatusBar extends StatefulWidget {
  final String conversationId;
  final String currentUserId;
  final bool isGroup;

  const AutoPilotInputStatusBar({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    this.isGroup = false,
  });

  @override
  State<AutoPilotInputStatusBar> createState() =>
      _AutoPilotInputStatusBarState();
}

class _AutoPilotInputStatusBarState extends State<AutoPilotInputStatusBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pilot = context.watch<AutoPilotProvider>();
    final theme = context.watch<ThemeProvider>();
    final config = pilot.getConfig(widget.conversationId);

    // Chỉ hiển thị banner nếu AutoPilot được BẬT
    final isEnabled = config.isEnabled;
    final isActiveNow = config.isActiveNow;

    if (isEnabled && !_wasActive) {
      _wasActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animCtrl.forward();
      });
    } else if (!isEnabled && _wasActive) {
      _wasActive = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animCtrl.reverse();
      });
    }

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: isEnabled || _animCtrl.isAnimating
            ? GestureDetector(
                onTap: () => AutoPilotConfigSheet.show(
                  context,
                  conversationId: widget.conversationId,
                  currentUserId: widget.currentUserId,
                  isGroup: widget.isGroup,
                ),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isActiveNow
                          ? [
                              theme.primaryColor.withValues(alpha: 0.12),
                              theme.primaryColor.withValues(alpha: 0.04),
                            ]
                          : [
                              Colors.orange.withValues(alpha: 0.08),
                              Colors.orange.withValues(alpha: 0.03),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActiveNow
                          ? theme.primaryColor.withValues(alpha: 0.2)
                          : Colors.orange.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (isActiveNow) ...[
                        _PulsingDot(color: theme.primaryColor),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        Icons.smart_toy_rounded,
                        size: 14,
                        color: isActiveNow ? theme.primaryColor : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isActiveNow
                              ? 'AutoPilot đang hoạt động · ${config.tone.label}'
                              : 'AutoPilot bật · Ngoài giờ hoạt động',
                          style: TextStyle(
                            color: isActiveNow
                                ? theme.primaryColor
                                : Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.tune_rounded,
                        size: 14,
                        color: isActiveNow
                            ? theme.primaryColor.withValues(alpha: 0.6)
                            : Colors.orange.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AutoPilotToggleRow — dùng trong Settings page hoặc Chat Info
// ─────────────────────────────────────────────────────────────────────────────

class AutoPilotToggleRow extends StatelessWidget {
  final String conversationId;
  final String currentUserId;

  const AutoPilotToggleRow({
    super.key,
    required this.conversationId,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final pilot = context.watch<AutoPilotProvider>();
    final config = pilot.getConfig(conversationId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.divider, width: 0.7),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: config.isEnabled
                  ? theme.primaryColor.withValues(alpha: 0.1)
                  : p.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              config.isEnabled
                  ? Icons.smart_toy_rounded
                  : Icons.smart_toy_outlined,
              color: config.isEnabled ? theme.primaryColor : p.textHint,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: () => AutoPilotConfigSheet.show(
                context,
                conversationId: conversationId,
                currentUserId: currentUserId,
              ),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AutoPilot',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    config.isEnabled
                        ? '${config.tone.emoji} ${config.tone.label} · ${_scheduleLabel(config)}'
                        : 'Tự động trả lời khi vắng mặt',
                    style: TextStyle(
                      color: p.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => AutoPilotConfigSheet.show(
              context,
              conversationId: conversationId,
              currentUserId: currentUserId,
            ),
            child: Icon(
              Icons.chevron_right_rounded,
              color: p.textHint,
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: config.isEnabled,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              pilot.toggleAutoPlayForConversation(
                conversationId,
                enabled: val,
              );
            },
            activeColor: theme.primaryColor,
          ),
        ],
      ),
    );
  }

  String _scheduleLabel(AutoPilotConfig config) {
    switch (config.scheduleMode) {
      case ScheduleMode.always:
        return 'Luôn bật';
      case ScheduleMode.sleepHours:
        return 'Giờ ngủ';
      case ScheduleMode.workHours:
        return 'Giờ làm';
      case ScheduleMode.custom:
        return '${config.startHour.toString().padLeft(2, '0')}h–${config.endHour.toString().padLeft(2, '0')}h';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets & Animations
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedBotIcon extends StatefulWidget {
  final bool isActive;
  final bool isEnabled;
  final Color primary;

  const _AnimatedBotIcon({
    required this.isActive,
    required this.isEnabled,
    required this.primary,
  });

  @override
  State<_AnimatedBotIcon> createState() => _AnimatedBotIconState();
}

class _AnimatedBotIconState extends State<_AnimatedBotIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.isActive) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AnimatedBotIcon old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isActive && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeProvider>();

    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (_, child) => Transform.scale(
        scale: widget.isActive ? _scaleAnim.value : 1.0,
        child: child,
      ),
      child: Icon(
        widget.isEnabled ? Icons.smart_toy_rounded : Icons.smart_toy_outlined,
        size: 20,
        color: widget.isActive
            ? widget.primary
            : widget.isEnabled
                ? Colors.orange
                : theme.isDark
                    ? Colors.white54
                    : Colors.grey[600],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
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
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: _anim.value),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _anim.value * 0.4),
              blurRadius: 5,
              spreadRadius: 1.5,
            ),
          ],
        ),
      ),
    );
  }
}
