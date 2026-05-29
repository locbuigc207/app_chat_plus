import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:sensors_plus/sensors_plus.dart';

class ShakeMessageWidget extends StatefulWidget {
  final String secretText;
  final String? label;
  final Color? accentColor;

  const ShakeMessageWidget({
    super.key,
    required this.secretText,
    this.label,
    this.accentColor,
  });

  @override
  State<ShakeMessageWidget> createState() => _ShakeMessageWidgetState();
}

class _ShakeMessageWidgetState extends State<ShakeMessageWidget> with TickerProviderStateMixin {
  bool _isRevealed = false;
  StreamSubscription<UserAccelerometerEvent>? _accelSubscription;
  double _shakeIntensity = 0.0;

  late AnimationController _shakeAnim;
  late AnimationController _revealAnim;
  late AnimationController _glowAnim;
  late AnimationController _ribbonAnim;

  late Animation<double> _translateX;
  late Animation<double> _scaleReveal;
  late Animation<double> _glowPulse;

  final List<_ConfettiPiece> _confetti = [];
  final Random _rng = Random();

  static const double _shakeThreshold = 15.0;

  @override
  void initState() {
    super.initState();

    _shakeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _revealAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _glowAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _ribbonAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _translateX = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeAnim, curve: Curves.easeInOut));

    _scaleReveal = CurvedAnimation(
      parent: _revealAnim,
      curve: Curves.elasticOut,
    );

    _glowPulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _glowAnim, curve: Curves.easeInOut),
    );

    _startListening();
  }

  void _startListening() {
    _accelSubscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      if (_isRevealed) return;

      double mag = event.x.abs() + event.y.abs() + event.z.abs();
      double intensity = (mag / _shakeThreshold).clamp(0.0, 1.0);

      if (mounted) setState(() => _shakeIntensity = intensity);

      if (mag > _shakeThreshold) {
        _triggerReveal();
      } else if (mag > 8.0 && !_shakeAnim.isAnimating) {
        _shakeAnim.forward(from: 0);
      }
    });
  }

  void _triggerReveal() {
    if (_isRevealed) return;
    _accelSubscription?.cancel();
    _confetti.clear();
    for (int i = 0; i < 28; i++) {
      _confetti.add(_ConfettiPiece(rng: _rng));
    }
    setState(() {
      _isRevealed = true;
      _shakeIntensity = 0;
    });
    _revealAnim.forward();
    _ribbonAnim.forward();
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
    _shakeAnim.dispose();
    _revealAnim.dispose();
    _glowAnim.dispose();
    _ribbonAnim.dispose();
    super.dispose();
  }

  Color get _accent => widget.accentColor ?? const Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_translateX, _scaleReveal, _glowPulse, _ribbonAnim]),
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(_isRevealed ? 0 : _translateX.value, 0),
          child: _isRevealed ? _buildRevealed() : _buildHidden(),
        );
      },
    );
  }

  Widget _buildHidden() {
    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            _accent,
            _accent.withRed((_accent.red - 40).clamp(0, 255)),
            Colors.deepOrange.shade800,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.25 + _shakeIntensity * 0.35),
            blurRadius: 14 + _shakeIntensity * 20,
            spreadRadius: 1 + _shakeIntensity * 4,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _glowPulse,
            builder: (_, __) => Transform.scale(
              scale: 1.0 + _shakeIntensity * 0.12 * _glowPulse.value,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4 + _shakeIntensity * 0.4), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: _glowPulse.value * 0.25),
                      blurRadius: 12,
                    )
                  ],
                ),
                child: const Center(
                  child: Text("🎁", style: TextStyle(fontSize: 28)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.label ?? "Lắc máy để mở quà!",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              double threshold = (i + 1) / 5.0;
              bool active = _shakeIntensity >= threshold;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? Colors.white : Colors.white.withValues(alpha: 0.22),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.6),
                            blurRadius: 6,
                          )
                        ]
                      : [],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildRevealed() {
    return ScaleTransition(
      scale: _scaleReveal,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFF3E0),
                  const Color(0xFFFFE0B2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.22),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: _accent.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text("🎉", style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      "Tin nhắn bí mật",
                      style: TextStyle(
                        color: _accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.secretText,
                  style: TextStyle(
                    color: Colors.brown.shade800,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ribbonAnim,
                builder: (_, __) => CustomPaint(
                  painter: _ConfettiPainter(
                    pieces: _confetti,
                    progress: _ribbonAnim.value,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPiece {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final bool isRect;

  _ConfettiPiece({required Random rng})
      : angle = rng.nextDouble() * 2 * pi,
        speed = 50 + rng.nextDouble() * 90,
        size = 4 + rng.nextDouble() * 7,
        isRect = rng.nextBool(),
        color = [
          const Color(0xFFFF6B35),
          const Color(0xFFFFD700),
          const Color(0xFF4CAF50),
          const Color(0xFF2196F3),
          const Color(0xFFE91E63),
          const Color(0xFF9C27B0),
        ][rng.nextInt(6)];
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double progress;

  _ConfettiPainter({required this.pieces, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final p in pieces) {
      final opacity = (1.0 - progress * 0.85).clamp(0.0, 1.0);
      final dx = cos(p.angle) * p.speed * progress;
      final dy = sin(p.angle) * p.speed * progress - 30 * progress;
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      final pos = center + Offset(dx, dy);
      if (p.isRect) {
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(progress * pi * 3);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(pos, p.size * 0.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
