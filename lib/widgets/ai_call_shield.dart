import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/realtime_ai_service.dart';

// ══════════════════════════════════════════════════════
// AI CALL SHIELD  — Real-time scam / deepfake protection
// ══════════════════════════════════════════════════════
class AICallShield extends StatefulWidget {
  final bool alignRight;
  const AICallShield({super.key, this.alignRight = true});

  @override
  State<AICallShield> createState() => _AICallShieldState();
}

class _AICallShieldState extends State<AICallShield>
    with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────
  late final AnimationController _pulseCtrl;
  late final AnimationController _shakeCtrl;
  late final AnimationController _panelCtrl;
  late final AnimationController _scanCtrl;
  late final AnimationController _expandCtrl;

  late final Animation<double> _pulseAnim;
  late final Animation<double> _shakeAnim;
  late final Animation<double> _panelFade;
  late final Animation<Offset> _panelSlide;
  late final Animation<double> _scanAnim;
  late final Animation<double> _expandAnim;

  // ── State ──────────────────────────────────────────
  SecurityEvent _event = SecurityEvent.safe();
  bool _expanded = false;
  bool _dismissed = false;

  // Recent threat history (max 5)
  final List<SecurityEvent> _history = [];

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.55, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -7.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -7.0, end: 7.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 7.0, end: -5.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5.0, end: 5.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 5.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeOut));

    _panelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _panelFade = CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOut);
    _panelSlide = Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOutCubic));

    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _scanAnim = Tween<double>(begin: 0, end: 1).animate(_scanCtrl);

    _expandCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _expandAnim =
        CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    _panelCtrl.dispose();
    _scanCtrl.dispose();
    _expandCtrl.dispose();
    super.dispose();
  }

  void _onEvent(SecurityEvent event) {
    // =========================================================================
    // 💡 TÍCH HỢP DEEPFAKE: Bỏ qua xử lý UI ở đây nếu là sự kiện Deepfake
    // Vì Widget DeepfakeStatusBadge (chuyên biệt) sẽ chịu trách nhiệm hiển thị.
    // =========================================================================
    if (event.category == ThreatCategory.deepfake) return;

    if (event.status == _event.status && event.message == _event.message) {
      return;
    }

    final prev = _event;
    setState(() {
      _event = event;
      _dismissed = false;
    });

    if (event.isAlert) {
      // Record history
      if (_history.isEmpty || _history.last.message != event.message) {
        _history.add(event);
        if (_history.length > 5) _history.removeAt(0);
      }

      _panelCtrl.forward();
      if (event.status == SecurityStatus.danger) {
        _shakeCtrl.forward(from: 0);
        HapticFeedback.heavyImpact();
      } else if (prev.status != SecurityStatus.warning) {
        HapticFeedback.mediumImpact();
      }
    } else if (event.status == SecurityStatus.scanning) {
      _panelCtrl.reverse();
    } else {
      _panelCtrl.reverse();
      if (_expanded) {
        _expanded = false;
        _expandCtrl.reverse();
      }
    }
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandCtrl.forward();
      HapticFeedback.selectionClick();
    } else {
      _expandCtrl.reverse();
    }
  }

  void _dismiss() {
    setState(() {
      _dismissed = true;
      _expanded = false;
    });
    _panelCtrl.reverse();
    _expandCtrl.reverse();
  }

  _ShieldTheme get _theme => _themeFor(_event.status);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SecurityEvent>(
      stream: RealtimeAIService().securityStream,
      initialData: SecurityEvent.safe(),
      builder: (ctx, snap) {
        if (snap.hasData) _onEvent(snap.data!);

        return AnimatedBuilder(
          animation: _shakeAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(_shakeAnim.value, 0),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: widget.alignRight
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning panel
              if (!_dismissed)
                _WarningPanel(
                  event: _event,
                  theme: _theme,
                  fadeAnim: _panelFade,
                  slideAnim: _panelSlide,
                  onDismiss: _dismiss,
                  onExpand: _toggleExpand,
                  expanded: _expanded,
                ),

              if (!_dismissed && _event.isAlert) const SizedBox(height: 6),

              // Expanded detail card
              SizeTransition(
                sizeFactor: _expandAnim,
                child: _DetailCard(
                  event: _event,
                  theme: _theme,
                  history: List.from(_history),
                  onDismiss: _dismiss,
                ),
              ),

              if (_expanded) const SizedBox(height: 6),

              // Shield badge
              _ShieldBadge(
                theme: _theme,
                event: _event,
                pulseAnim: _pulseAnim,
                scanAnim: _scanAnim,
                onTap: _event.isAlert ? _toggleExpand : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════
// WARNING PANEL
// ══════════════════════════════════════════════════════
class _WarningPanel extends StatelessWidget {
  final SecurityEvent event;
  final _ShieldTheme theme;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideAnim;
  final VoidCallback onDismiss;
  final VoidCallback onExpand;
  final bool expanded;

  const _WarningPanel({
    required this.event,
    required this.theme,
    required this.fadeAnim,
    required this.slideAnim,
    required this.onDismiss,
    required this.onExpand,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    if (!event.isAlert || event.message.isEmpty) return const SizedBox.shrink();

    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(
        position: slideAnim,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                color: theme.surface.withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: theme.primary.withOpacity(0.55), width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: theme.primary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                        event.status == SecurityStatus.danger
                            ? Icons.crisis_alert_rounded
                            : Icons.warning_amber_rounded,
                        color: theme.primary,
                        size: 17),
                  ),
                  const SizedBox(width: 8),

                  // Content
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...event.message.split('\n').map((line) => Text(
                              line,
                              style: TextStyle(
                                color: line.startsWith('⚠️') ||
                                        line.startsWith('🔍')
                                    ? theme.primary
                                    : Colors.white70,
                                fontSize: 12,
                                fontWeight: line.startsWith('⚠️') ||
                                        line.startsWith('🔍')
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                height: 1.45,
                              ),
                            )),
                        if (event.riskScore > 0) ...[
                          const SizedBox(height: 8),
                          _RiskBar(
                              score: event.riskScore, color: theme.primary),
                        ],
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: onExpand,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(
                              expanded ? 'Thu gọn' : 'Xem chi tiết',
                              style: TextStyle(
                                  color: theme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                                expanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: theme.primary,
                                size: 14),
                          ]),
                        ),
                      ],
                    ),
                  ),

                  // Dismiss
                  GestureDetector(
                    onTap: onDismiss,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.close_rounded,
                          color: Colors.white30, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// DETAIL CARD  (expanded)
// ══════════════════════════════════════════════════════
class _DetailCard extends StatelessWidget {
  final SecurityEvent event;
  final _ShieldTheme theme;
  final List<SecurityEvent> history;
  final VoidCallback onDismiss;

  const _DetailCard({
    required this.event,
    required this.theme,
    required this.history,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (!event.isAlert) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.surface.withOpacity(0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.primary.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(children: [
                Icon(Icons.security_rounded, color: theme.primary, size: 14),
                const SizedBox(width: 6),
                Text('Báo cáo bảo mật',
                    style: TextStyle(
                        color: theme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 10),

              // Threat info
              _InfoRow('Loại nguy cơ:', _categoryLabel(event.category),
                  theme.primary),
              const SizedBox(height: 6),
              _InfoRow('Mức độ rủi ro:', '${(event.riskScore * 100).round()}%',
                  theme.primary),
              const SizedBox(height: 6),
              _InfoRow(
                  'Thời điểm:', _timeLabel(event.timestamp), Colors.white54),

              // Recommendations
              if (event.status == SecurityStatus.danger) ...[
                const SizedBox(height: 12),
                _RecommendationBox(theme: theme),
              ],

              // History timeline
              if (history.length > 1) ...[
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 8),
                const Text('Lịch sử phát hiện:',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...history.reversed.take(3).map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _themeFor(e.status).primary.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(
                          _categoryLabel(e.category),
                          style: TextStyle(
                              color:
                                  _themeFor(e.status).primary.withOpacity(0.7),
                              fontSize: 10),
                        )),
                        Text(_timeLabel(e.timestamp),
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 9)),
                      ]),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s trước';
    return '${diff.inMinutes}ph trước';
  }

  static String _categoryLabel(ThreatCategory cat) {
    switch (cat) {
      case ThreatCategory.financialFraud:
        return 'Lừa đảo tài chính';
      case ThreatCategory.otp:
        return 'Đánh cắp OTP/mật khẩu';
      case ThreatCategory.phishing:
        return 'Mạo danh cơ quan';
      case ThreatCategory.urgencyTrick:
        return 'Tạo áp lực khẩn cấp';
      case ThreatCategory.deepfake:
        return 'Giọng giả mạo (Deepfake)'; // Giữ lại dự phòng
      case ThreatCategory.unknown:
      case ThreatCategory.none:
        return 'Nội dung đáng ngờ';
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  const _InfoRow(this.label, this.value, this.valueColor);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Flexible(
              child: Text(value,
                  style: TextStyle(
                      color: valueColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600))),
        ],
      );
}

class _RecommendationBox extends StatelessWidget {
  final _ShieldTheme theme;
  const _RecommendationBox({required this.theme});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.primary.withOpacity(0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.tips_and_updates_rounded,
                color: theme.primary, size: 12),
            const SizedBox(width: 5),
            Text('Khuyến nghị',
                style: TextStyle(
                    color: theme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          ...[
            '🚫 Không cung cấp OTP/mã PIN',
            '🚫 Không chuyển tiền theo yêu cầu lạ',
            '✅ Cúp máy và gọi lại số chính thức',
          ].map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(tip,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 10, height: 1.5)),
              )),
        ]),
      );
}

// ══════════════════════════════════════════════════════
// RISK BAR
// ══════════════════════════════════════════════════════
class _RiskBar extends StatefulWidget {
  final double score;
  final Color color;
  const _RiskBar({required this.score, required this.color});

  @override
  State<_RiskBar> createState() => _RiskBarState();
}

class _RiskBarState extends State<_RiskBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _anim = Tween<double>(begin: 0, end: widget.score)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_RiskBar old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) {
      _anim = Tween<double>(begin: _anim.value, end: widget.score)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Text('Rủi ro: ${(_anim.value * 100).round()}%',
                style: TextStyle(
                    color: widget.color.withOpacity(0.75),
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => LinearProgressIndicator(
                value: _anim.value.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
              ),
            ),
          ),
        ],
      );
}

// ══════════════════════════════════════════════════════
// SHIELD BADGE
// ══════════════════════════════════════════════════════
class _ShieldBadge extends StatelessWidget {
  final _ShieldTheme theme;
  final SecurityEvent event;
  final Animation<double> pulseAnim;
  final Animation<double> scanAnim;
  final VoidCallback? onTap;

  const _ShieldBadge({
    required this.theme,
    required this.event,
    required this.pulseAnim,
    required this.scanAnim,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, __) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: theme.primary
                        .withOpacity(0.25 + pulseAnim.value * 0.45),
                    width: 1.5,
                  ),
                  boxShadow: event.isAlert
                      ? [
                          BoxShadow(
                            color: theme.primary
                                .withOpacity(pulseAnim.value * 0.2),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _buildIcon(),
                  const SizedBox(width: 7),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      color: theme.primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                    child: Text(theme.label),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded,
                        color: theme.primary.withOpacity(0.7), size: 13),
                  ],
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIcon() {
    if (event.status == SecurityStatus.scanning) {
      return AnimatedBuilder(
        animation: scanAnim,
        builder: (_, child) => Transform.rotate(
          angle: scanAnim.value * 2 * math.pi,
          child: child,
        ),
        child: Icon(Icons.radar_rounded, color: theme.primary, size: 14),
      );
    }

    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) => Icon(theme.icon,
          color: theme.primary.withOpacity(0.65 + pulseAnim.value * 0.35),
          size: 14),
    );
  }
}

// ══════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════
_ShieldTheme _themeFor(SecurityStatus status) {
  switch (status) {
    case SecurityStatus.safe:
      return const _ShieldTheme(
        primary: Color(0xFF34D399),
        surface: Color(0xFF052E1E),
        icon: Icons.verified_user_rounded,
        label: 'AI Bảo vệ',
      );
    case SecurityStatus.scanning:
      return const _ShieldTheme(
        primary: Color(0xFF60A5FA),
        surface: Color(0xFF0C1E3D),
        icon: Icons.radar_rounded,
        label: 'Đang quét...',
      );
    case SecurityStatus.warning:
      return const _ShieldTheme(
        primary: Color(0xFFFBBF24),
        surface: Color(0xFF2D1F00),
        icon: Icons.warning_amber_rounded,
        label: 'Cảnh báo',
      );
    case SecurityStatus.danger:
      return const _ShieldTheme(
        primary: Color(0xFFF87171),
        surface: Color(0xFF3B0A0A),
        icon: Icons.gpp_bad_rounded,
        label: 'NGUY HIỂM!',
      );
  }
}

class _ShieldTheme {
  final Color primary;
  final Color surface;
  final IconData icon;
  final String label;
  const _ShieldTheme({
    required this.primary,
    required this.surface,
    required this.icon,
    required this.label,
  });
}
