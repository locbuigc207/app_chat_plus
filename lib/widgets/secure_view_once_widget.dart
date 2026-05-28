import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS  (dark-on-dark palette for the secure overlay)
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
// SECURE STATE
// ─────────────────────────────────────────────────────────────────────────────

enum SecureState {
  /// Secure mode is off — content shown normally.
  disabled,

  /// Front-camera active, no threat detected.
  monitoring,

  /// Threat frame count is rising — showing a subtle warning shimmer.
  warning,

  /// Content fully blurred — secondary viewer confirmed.
  blurred,
}

// ─────────────────────────────────────────────────────────────────────────────
// SECURE OVERLAY MANAGER
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps any widget with an anti-shoulder-surf overlay.
///
/// ### Production usage
/// Call [SecureOverlayManager.reportDetection] from your ML / camera pipeline:
/// ```dart
/// SecureOverlayManager.reportDetection(isSuspicious: faces.length > 1);
/// ```
///
/// ### Simulation / demo
/// When [isActive] becomes true the widget runs a safe internal simulation
/// loop that never triggers blur automatically — useful for demos.
/// Toggle blur manually via [debugTriggerBlur] / [debugClearBlur].
class SecureOverlayManager extends StatefulWidget {
  final Widget child;
  final bool isActive;
  final VoidCallback? onSecureStateChanged;

  /// Called with the new [SecureState] whenever it changes.
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

class SecureOverlayManagerState extends State<SecureOverlayManager>
    with TickerProviderStateMixin {
  SecureState _state = SecureState.disabled;
  SecureState get currentState => _state;

  // ── Detection counters ────────────────────────────────────────────────────
  int _suspiciousFrames = 0;
  static const _blurThreshold = 4; // consecutive suspicious frames → blur
  static const _clearThreshold = 6; // consecutive safe frames → clear

  bool _revealRequested = false;

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _blurCtrl; // 0→1 : none→full blur
  late AnimationController _shieldCtrl; // repeating pulse on shield icon
  late AnimationController _warningCtrl; // 0→1 : slide-in warning card
  late AnimationController _scanCtrl; // repeating scanline sweep
  late AnimationController _warningShimCtrl; // border shimmer in warning state

  late Animation<double> _blurCurve;
  late Animation<double> _warningSlide;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _blurCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _blurCurve = CurvedAnimation(parent: _blurCtrl, curve: Curves.easeInOut);

    _shieldCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);

    _warningCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _warningSlide =
        CurvedAnimation(parent: _warningCtrl, curve: Curves.easeOutBack);

    _scanCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat();

    _warningShimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
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

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIVATION
  // ─────────────────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: DETECTION FEED-IN
  // ─────────────────────────────────────────────────────────────────────────

  /// Feed a detection result from your ML pipeline.
  /// Safe to call from any isolate / callback.
  void reportDetection({required bool isSuspicious}) {
    if (!mounted || !widget.isActive) return;
    if (isSuspicious) {
      _suspiciousFrames++;
      if (_suspiciousFrames >= _blurThreshold &&
          _state != SecureState.blurred) {
        _triggerBlur();
      } else if (_suspiciousFrames >= 2 && _state == SecureState.monitoring) {
        _transitionTo(SecureState.warning);
      }
    } else {
      if (_suspiciousFrames > 0) _suspiciousFrames--;
      if (_state == SecureState.warning && _suspiciousFrames < 2) {
        _transitionTo(SecureState.monitoring);
      }
      if (_state == SecureState.blurred &&
          _suspiciousFrames == 0 &&
          _revealRequested) {
        _clearBlur();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEBUG / TEST
  // ─────────────────────────────────────────────────────────────────────────

  /// Force blur (useful in tests / demo buttons).
  void debugTriggerBlur() => _triggerBlur();

  /// Force clear (useful in tests / demo buttons).
  void debugClearBlur() => _clearBlur();

  // ─────────────────────────────────────────────────────────────────────────
  // BLUR TRANSITIONS
  // ─────────────────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

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
            // 1. Blur + dim
            if (bp > 0.01)
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: bp * 24,
                      sigmaY: bp * 24,
                    ),
                    child: Container(
                      color: _SC.bg0.withOpacity(bp * 0.6),
                    ),
                  ),
                ),
              ),

            // 2. Scanline sweep (monitoring + warning)
            if (_state == SecureState.monitoring ||
                _state == SecureState.warning)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ScanlinePainter(
                      progress: _scanCtrl.value,
                      opacity: _state == SecureState.warning ? 0.07 : 0.03,
                      color: _state == SecureState.warning
                          ? _SC.danger
                          : _SC.accentL,
                    ),
                  ),
                ),
              ),

            // 3. Warning border shimmer
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

            // 4. Warning card (slides in when blurred)
            if (bp > 0.35)
              Positioned.fill(
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.86, end: 1.0)
                      .animate(_warningSlide),
                  child: FadeTransition(
                    opacity: _warningSlide,
                    child: _WarningCard(
                      shieldAnim: _shieldCtrl,
                      onReveal: _onRevealTapped,
                    ),
                  ),
                ),
              ),

            // 5. Status badge (always when active)
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

// ─────────────────────────────────────────────────────────────────────────────
// WARNING CARD
// ─────────────────────────────────────────────────────────────────────────────

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
                  color: _SC.accent.withOpacity(0.22 + t * 0.28),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _SC.accent.withOpacity(0.15 + t * 0.12),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.65),
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
                      color: Colors.white.withOpacity(0.58),
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
                      color: Colors.white.withOpacity(0.28),
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

// ─────────────────────────────────────────────────────────────────────────────
// PULSING EYE ICON
// ─────────────────────────────────────────────────────────────────────────────

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
            // Outer ripple
            Container(
              width: 90 + t * 10,
              height: 90 + t * 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _SC.accent.withOpacity(0.08 + t * 0.10),
                  width: 1,
                ),
              ),
            ),
            // Middle ring
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _SC.accent.withOpacity(0.07 + t * 0.09),
                border: Border.all(
                  color: _SC.accent.withOpacity(0.18 + t * 0.26),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.remove_red_eye_outlined,
                color: Color.lerp(_SC.accentL.withOpacity(0.7), _SC.accentL, t),
                size: 32,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REVEAL BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _RevealButton extends StatefulWidget {
  final VoidCallback onTap;
  const _RevealButton({required this.onTap});

  @override
  State<_RevealButton> createState() => _RevealButtonState();
}

class _RevealButtonState extends State<_RevealButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
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
                color: _SC.accent.withOpacity(0.45),
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

// ─────────────────────────────────────────────────────────────────────────────
// SECURE STATUS BADGE
// ─────────────────────────────────────────────────────────────────────────────

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
            color: _SC.bg0.withOpacity(0.88),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withOpacity(0.2 + t * 0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.12 + t * 0.08),
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

// ─────────────────────────────────────────────────────────────────────────────
// SCANLINE PAINTER
// ─────────────────────────────────────────────────────────────────────────────

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
        color.withOpacity(opacity),
        color.withOpacity(opacity * 1.6),
        color.withOpacity(opacity),
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
  bool shouldRepaint(_ScanlinePainter o) =>
      o.progress != progress || o.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────────────────────
// BORDER GLOW PAINTER  (warning state)
// ─────────────────────────────────────────────────────────────────────────────

class _BorderGlowPainter extends CustomPainter {
  final double opacity;
  final Color color;

  const _BorderGlowPainter({required this.opacity, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_BorderGlowPainter o) =>
      o.opacity != opacity || o.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECURE MODE TOGGLE  (used by ContextualMiniChatOverlay)
// ─────────────────────────────────────────────────────────────────────────────

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

class _SecureModeToggleState extends State<SecureModeToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 140));
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
                ? const LinearGradient(
                    colors: [Color(0xFF0D1B3E), Color(0xFF162B5A)])
                : null,
            color: widget.isActive ? null : const Color(0xFFEEF1F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isActive
                  ? _SC.accent.withOpacity(0.5)
                  : const Color(0xFFDDE3EE),
              width: 1,
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: _SC.accent.withOpacity(0.28),
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
                  widget.isActive
                      ? Icons.shield_rounded
                      : Icons.shield_outlined,
                  key: ValueKey(widget.isActive),
                  size: 14,
                  color:
                      widget.isActive ? _SC.accentL : const Color(0xFF9AA5B8),
                ),
              ),
              const SizedBox(width: 5),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      widget.isActive ? _SC.accentL : const Color(0xFF9AA5B8),
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
