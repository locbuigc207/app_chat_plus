import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';




abstract class _SC {
  static const bg0 = Color(0xFF060A14);
  static const bg1 = Color(0xFF0D1528);
  static const accent = Color(0xFF3D5AFE);
  static const accentL = Color(0xFF82B1FF);
  static const danger = Color(0xFFCF6679);
  static const safe = Color(0xFF69F0AE);
  static const white70 = Color(0xB3FFFFFF);
  static const white40 = Color(0x66FFFFFF);
  static const white20 = Color(0x33FFFFFF);
  static const white10 = Color(0x1AFFFFFF);
}





enum SecureState {
  
  disabled,

  
  monitoring,

  
  warning,

  
  blurred,
}

















class SecureOverlayManager extends StatefulWidget {
  final Widget child;
  final bool isActive;
  final VoidCallback? onSecureStateChanged;

  
  final void Function(SecureState state)? onStateChanged;

  const SecureOverlayManager({
    super.key,
    required this.child,
    required this.isActive,
    this.onSecureStateChanged,
    this.onStateChanged,
  });

  @override
  State<SecureOverlayManager> createState() => SecureOverlayManagerState();
}

class SecureOverlayManagerState extends State<SecureOverlayManager> with TickerProviderStateMixin {
  SecureState _state = SecureState.disabled;
  SecureState get currentState => _state;

  
  int _suspiciousFrames = 0;
  static const _blurThreshold = 4; 
  static const _clearThreshold = 6; 

  bool _revealRequested = false;

  
  late AnimationController _blurCtrl; 
  late AnimationController _shieldCtrl; 
  late AnimationController _warningCtrl; 
  late AnimationController _scanCtrl; 
  late AnimationController _warningShimCtrl; 

  late Animation<double> _blurCurve;
  late Animation<double> _warningSlide;

  
  @override
  void initState() {
    super.initState();

    _blurCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _blurCurve = CurvedAnimation(parent: _blurCtrl, curve: Curves.easeInOut);

    _shieldCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);

    _warningCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _warningSlide = CurvedAnimation(parent: _warningCtrl, curve: Curves.easeOutBack);

    _scanCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat();

    _warningShimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    if (widget.isActive) _activate();
  }

  @override
  void didUpdateWidget(SecureOverlayManager old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _activate();
    } else if (!widget.isActive && old.isActive) {
      _deactivate();
    }
  }

  @override
  void dispose() {
    _blurCtrl.dispose();
    _shieldCtrl.dispose();
    _warningCtrl.dispose();
    _scanCtrl.dispose();
    _warningShimCtrl.dispose();
    super.dispose();
  }

  
  
  

  void _activate() {
    if (!mounted) return;
    _transitionTo(SecureState.monitoring);
    widget.onSecureStateChanged?.call();
  }

  void _deactivate() {
    _suspiciousFrames = 0;
    _revealRequested = false;
    if (!mounted) return;
    _transitionTo(SecureState.disabled);
    _blurCtrl.reverse();
    _warningCtrl.reverse();
    widget.onSecureStateChanged?.call();
  }

  void _transitionTo(SecureState next) {
    if (_state == next) return;
    setState(() => _state = next);
    widget.onStateChanged?.call(next);
  }

  
  
  

  
  
  void reportDetection({required bool isSuspicious}) {
    if (!mounted || !widget.isActive) return;
    if (isSuspicious) {
      _suspiciousFrames++;
      if (_suspiciousFrames >= _blurThreshold && _state != SecureState.blurred) {
        _triggerBlur();
      } else if (_suspiciousFrames >= 2 && _state == SecureState.monitoring) {
        _transitionTo(SecureState.warning);
      }
    } else {
      if (_suspiciousFrames > 0) _suspiciousFrames--;
      if (_state == SecureState.warning && _suspiciousFrames < 2) {
        _transitionTo(SecureState.monitoring);
      }
      if (_state == SecureState.blurred && _suspiciousFrames == 0 && _revealRequested) {
        _clearBlur();
      }
    }
  }

  
  
  

  
  void debugTriggerBlur() => _triggerBlur();

  
  void debugClearBlur() => _clearBlur();

  
  
  

  void _triggerBlur() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _transitionTo(SecureState.blurred);
    _blurCtrl.forward();
    _warningCtrl.forward();
    _revealRequested = false;
    widget.onSecureStateChanged?.call();
  }

  void _clearBlur() {
    if (!mounted) return;
    _transitionTo(SecureState.monitoring);
    _blurCtrl.reverse();
    _warningCtrl.reverse();
    _suspiciousFrames = 0;
    _revealRequested = false;
    widget.onSecureStateChanged?.call();
  }

  void _onRevealTapped() {
    _revealRequested = true;
    _clearBlur();
    HapticFeedback.mediumImpact();
  }

  
  
  

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.isActive) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _blurCurve,
        _shieldCtrl,
        _scanCtrl,
        _warningShimCtrl,
      ]),
      builder: (_, __) {
        final bp = _blurCurve.value;
        return Stack(
          children: [
            
            if (bp > 0.01)
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: bp * 24,
                      sigmaY: bp * 24,
                    ),
                    child: Container(
                      color: _SC.bg0.withValues(alpha: bp * 0.6),
                    ),
                  ),
                ),
              ),

            
            if (_state == SecureState.monitoring || _state == SecureState.warning)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ScanlinePainter(
                      progress: _scanCtrl.value,
                      opacity: _state == SecureState.warning ? 0.07 : 0.03,
                      color: _state == SecureState.warning ? _SC.danger : _SC.accentL,
                    ),
                  ),
                ),
              ),

            
            if (_state == SecureState.warning)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BorderGlowPainter(
                      opacity: 0.3 + _warningShimCtrl.value * 0.35,
                      color: _SC.danger,
                    ),
                  ),
                ),
              ),

            
            if (bp > 0.35)
              Positioned.fill(
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.86, end: 1.0).animate(_warningSlide),
                  child: FadeTransition(
                    opacity: _warningSlide,
                    child: _WarningCard(
                      shieldAnim: _shieldCtrl,
                      onReveal: _onRevealTapped,
                    ),
                  ),
                ),
              ),

            
            if (_state != SecureState.disabled)
              Positioned(
                top: 10,
                right: 10,
                child: _SecureStatusBadge(
                  state: _state,
                  shieldAnim: _shieldCtrl,
                ),
              ),
          ],
        );
      },
    );
  }
}





class _WarningCard extends StatelessWidget {
  final AnimationController shieldAnim;
  final VoidCallback onReveal;

  const _WarningCard({
    required this.shieldAnim,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: AnimatedBuilder(
          animation: shieldAnim,
          builder: (_, __) {
            final t = shieldAnim.value;
            return Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(_SC.bg0, _SC.bg1, t)!,
                    _SC.bg1,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _SC.accent.withValues(alpha: 0.22 + t * 0.28),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _SC.accent.withValues(alpha: 0.15 + t * 0.12),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PulsingEyeIcon(shieldAnim: shieldAnim),
                  const SizedBox(height: 22),
                  const Text(
                    'Phát hiện người nhìn!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Nội dung đã được ẩn để\nbảo vệ quyền riêng tư của bạn.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 13,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  _RevealButton(onTap: onReveal),
                  const SizedBox(height: 12),
                  Text(
                    'Hoặc di chuyển ra xa · màn hình tự mở khi an toàn',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.28),
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}





class _PulsingEyeIcon extends StatelessWidget {
  final AnimationController shieldAnim;
  const _PulsingEyeIcon({required this.shieldAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shieldAnim,
      builder: (_, __) {
        final t = shieldAnim.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            
            Container(
              width: 90 + t * 10,
              height: 90 + t * 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _SC.accent.withValues(alpha: 0.08 + t * 0.10),
                  width: 1,
                ),
              ),
            ),
            
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _SC.accent.withValues(alpha: 0.07 + t * 0.09),
                border: Border.all(
                  color: _SC.accent.withValues(alpha: 0.18 + t * 0.26),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.remove_red_eye_outlined,
                color: Color.lerp(_SC.accentL.withValues(alpha: 0.7), _SC.accentL, t),
                size: 32,
              ),
            ),
          ],
        );
      },
    );
  }
}





class _RevealButton extends StatefulWidget {
  final VoidCallback onTap;
  const _RevealButton({required this.onTap});

  @override
  State<_RevealButton> createState() => _RevealButtonState();
}

class _RevealButtonState extends State<_RevealButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.93)
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
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_SC.accent, Color(0xFF1A237E)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _SC.accent.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.visibility_rounded, color: Colors.white, size: 17),
              SizedBox(width: 9),
              Text(
                'Hiển thị lại nội dung',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}





class _SecureStatusBadge extends StatelessWidget {
  final SecureState state;
  final AnimationController shieldAnim;

  const _SecureStatusBadge({
    required this.state,
    required this.shieldAnim,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _data(state);
    return AnimatedBuilder(
      animation: shieldAnim,
      builder: (_, __) {
        final t = shieldAnim.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _SC.bg0.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: 0.2 + t * 0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12 + t * 0.08),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 11),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static (IconData, Color, String) _data(SecureState s) {
    switch (s) {
      case SecureState.blurred:
        return (Icons.visibility_off_rounded, _SC.danger, 'PROTECTED');
      case SecureState.warning:
        return (Icons.warning_amber_rounded, _SC.danger, 'WARNING');
      default:
        return (Icons.shield_rounded, _SC.accentL, 'SECURE');
    }
  }
}





class _ScanlinePainter extends CustomPainter {
  final double progress;
  final double opacity;
  final Color color;

  const _ScanlinePainter({
    required this.progress,
    required this.opacity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = progress * (size.height + 48) - 24;
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        color.withValues(alpha: opacity),
        color.withValues(alpha: opacity * 1.6),
        color.withValues(alpha: opacity),
        Colors.transparent,
      ],
      stops: const [0, 0.25, 0.5, 0.75, 1],
    ).createShader(Rect.fromLTWH(0, y - 24, size.width, 48));
    canvas.drawRect(
      Rect.fromLTWH(0, y - 24, size.width, 48),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_ScanlinePainter o) => o.progress != progress || o.opacity != opacity;
}





class _BorderGlowPainter extends CustomPainter {
  final double opacity;
  final Color color;

  const _BorderGlowPainter({required this.opacity, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_BorderGlowPainter o) => o.opacity != opacity || o.color != color;
}





class SecureModeToggle extends StatefulWidget {
  final bool isActive;
  final ValueChanged<bool> onChanged;

  const SecureModeToggle({
    super.key,
    required this.isActive,
    required this.onChanged,
  });

  @override
  State<SecureModeToggle> createState() => _SecureModeToggleState();
}

class _SecureModeToggleState extends State<SecureModeToggle> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
    _scale = Tween<double>(begin: 1.0, end: 0.90)
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
        widget.onChanged(!widget.isActive);
        HapticFeedback.mediumImpact();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 270),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: widget.isActive
                ? const LinearGradient(colors: [Color(0xFF0D1B3E), Color(0xFF162B5A)])
                : null,
            color: widget.isActive ? null : const Color(0xFFEEF1F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isActive ? _SC.accent.withValues(alpha: 0.5) : const Color(0xFFDDE3EE),
              width: 1,
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: _SC.accent.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  widget.isActive ? Icons.shield_rounded : Icons.shield_outlined,
                  key: ValueKey(widget.isActive),
                  size: 14,
                  color: widget.isActive ? _SC.accentL : const Color(0xFF9AA5B8),
                ),
              ),
              const SizedBox(width: 5),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: widget.isActive ? _SC.accentL : const Color(0xFF9AA5B8),
                ),
                child: Text(widget.isActive ? 'Bảo mật ON' : 'Bảo mật'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
