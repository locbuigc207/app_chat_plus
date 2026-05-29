import 'package:flutter/material.dart';

import '../services/realtime_ai_service.dart';











class AICallShield extends StatefulWidget {
  
  final bool alignRight;

  const AICallShield({super.key, this.alignRight = true});

  @override
  State<AICallShield> createState() => _AICallShieldState();
}

class _AICallShieldState extends State<AICallShield> with TickerProviderStateMixin {
  
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  late AnimationController _panelCtrl;
  late Animation<double> _panelFade;
  late Animation<Offset> _panelSlide;

  late AnimationController _scanCtrl;
  late Animation<double> _scanAnim;

  SecurityEvent _currentEvent = SecurityEvent.safe();
  SecurityEvent? _previousEvent;

  @override
  void initState() {
    super.initState();

    
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeOut));

    
    _panelCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _panelFade = CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOut);
    _panelSlide = Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOutCubic));

    
    _scanCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _scanAnim = Tween<double>(begin: 0, end: 1).animate(_scanCtrl);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    _panelCtrl.dispose();
    _scanCtrl.dispose();
    super.dispose();
  }

  void _handleEvent(SecurityEvent event) {
    if (event.status == _currentEvent.status && event.message == _currentEvent.message) {
      return;
    }

    _previousEvent = _currentEvent;
    setState(() => _currentEvent = event);

    if (event.isAlert) {
      _panelCtrl.forward();
      if (event.status == SecurityStatus.danger) {
        _shakeCtrl.forward(from: 0);
      }
    } else {
      _panelCtrl.reverse();
    }
  }

  

  _ShieldTheme get _theme => _shieldThemeFor(_currentEvent.status);

  static _ShieldTheme _shieldThemeFor(SecurityStatus status) {
    switch (status) {
      case SecurityStatus.safe:
        return _ShieldTheme(
          primary: const Color(0xFF34D399),
          surface: const Color(0xFF052E1E),
          icon: Icons.verified_user_rounded,
          label: 'AI Đang bảo vệ',
        );
      case SecurityStatus.scanning:
        return _ShieldTheme(
          primary: const Color(0xFF60A5FA),
          surface: const Color(0xFF0C1E3D),
          icon: Icons.radar_rounded,
          label: 'AI Đang quét...',
        );
      case SecurityStatus.warning:
        return _ShieldTheme(
          primary: const Color(0xFFFBBF24),
          surface: const Color(0xFF2D1F00),
          icon: Icons.warning_amber_rounded,
          label: 'Phát hiện nhạy cảm',
        );
      case SecurityStatus.danger:
        return _ShieldTheme(
          primary: const Color(0xFFF87171),
          surface: const Color(0xFF3B0A0A),
          icon: Icons.gpp_bad_rounded,
          label: 'NGUY HIỂM!',
        );
    }
  }

  

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SecurityEvent>(
      stream: RealtimeAIService().securityStream,
      initialData: SecurityEvent.safe(),
      builder: (context, snapshot) {
        if (snapshot.hasData) _handleEvent(snapshot.data!);

        return AnimatedBuilder(
          animation: _shakeAnim,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnim.value, 0),
            child: child,
          ),
          child: Column(
            crossAxisAlignment:
                widget.alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              
              _WarningPanel(
                event: _currentEvent,
                theme: _theme,
                fadeAnim: _panelFade,
                slideAnim: _panelSlide,
              ),
              const SizedBox(height: 6),
              
              _ShieldBadge(
                theme: _theme,
                event: _currentEvent,
                pulseAnim: _pulseAnim,
                scanAnim: _scanAnim,
              ),
            ],
          ),
        );
      },
    );
  }
}





class _WarningPanel extends StatelessWidget {
  final SecurityEvent event;
  final _ShieldTheme theme;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideAnim;

  const _WarningPanel({
    required this.event,
    required this.theme,
    required this.fadeAnim,
    required this.slideAnim,
  });

  @override
  Widget build(BuildContext context) {
    if (!event.isAlert || event.message.isEmpty) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(
        position: slideAnim,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.primary.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.primary.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                event.status == SecurityStatus.danger
                    ? Icons.crisis_alert_rounded
                    : Icons.info_outline_rounded,
                color: theme.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...event.message.split('\n').map((line) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            line,
                            style: TextStyle(
                              color: line.startsWith('⚠️') || line.startsWith('🔍')
                                  ? theme.primary
                                  : Colors.white70,
                              fontSize: 12,
                              fontWeight: line.startsWith('⚠️') || line.startsWith('🔍')
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              height: 1.4,
                            ),
                          ),
                        )),
                    if (event.riskScore > 0) ...[
                      const SizedBox(height: 6),
                      _RiskBar(score: event.riskScore, color: theme.primary),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}





class _RiskBar extends StatelessWidget {
  final double score;
  final Color color;

  const _RiskBar({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mức độ rủi ro: ${(score * 100).round()}%',
          style: TextStyle(
              color: color.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}





class _ShieldBadge extends StatelessWidget {
  final _ShieldTheme theme;
  final SecurityEvent event;
  final Animation<double> pulseAnim;
  final Animation<double> scanAnim;

  const _ShieldBadge({
    required this.theme,
    required this.event,
    required this.pulseAnim,
    required this.scanAnim,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.primary.withValues(alpha: 0.3 + pulseAnim.value * 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.primary.withValues(alpha: pulseAnim.value * 0.15),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(),
              const SizedBox(width: 7),
              Text(
                theme.label,
                style: TextStyle(
                  color: theme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIcon() {
    if (event.status == SecurityStatus.scanning) {
      return AnimatedBuilder(
        animation: scanAnim,
        builder: (_, child) => Transform.rotate(
          angle: scanAnim.value * 2 * 3.14159,
          child: child,
        ),
        child: Icon(Icons.radar_rounded, color: theme.primary, size: 15),
      );
    }

    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) => Icon(
        theme.icon,
        color: theme.primary.withValues(alpha: 0.7 + pulseAnim.value * 0.3),
        size: 15,
      ),
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
