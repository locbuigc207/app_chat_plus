import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:noise_meter/noise_meter.dart';

class BlowMessageWidget extends StatefulWidget {
  final String secretText;
  final String? senderName;
  final Color? accentColor;

  const BlowMessageWidget({
    super.key,
    required this.secretText,
    this.senderName,
    this.accentColor,
  });

  @override
  State<BlowMessageWidget> createState() => _BlowMessageWidgetState();
}

class _BlowMessageWidgetState extends State<BlowMessageWidget> with TickerProviderStateMixin {
  bool _isRevealed = false;
  double _blowProgress = 0.0;
  NoiseMeter? _noiseMeter;
  StreamSubscription<NoiseReading>? _noiseSubscription;

  late AnimationController _pulseController;
  late AnimationController _revealController;
  late AnimationController _particleController;
  late Animation<double> _pulseAnim;
  late Animation<double> _revealAnim;
  late Animation<double> _blurAnim;

  final List<_Particle> _particles = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _revealAnim = CurvedAnimation(
      parent: _revealController,
      curve: Curves.elasticOut,
    );

    _blurAnim = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeOut),
    );

    _noiseMeter = NoiseMeter();
    _startListening();
  }

  void _startListening() {
    try {
      _noiseSubscription = _noiseMeter?.noise.listen((NoiseReading reading) {
        if (_isRevealed) return;

        double progress = ((reading.maxDecibel - 60.0) / 25.0).clamp(0.0, 1.0);

        setState(() => _blowProgress = progress);

        if (reading.maxDecibel > 85.0) {
          _triggerReveal();
        }
      });
    } catch (e) {
      debugPrint("Lỗi Mic: $e");
    }
  }

  void _triggerReveal() {
    if (_isRevealed) return;
    setState(() {
      _isRevealed = true;
      _blowProgress = 1.0;
      _particles.clear();
      for (int i = 0; i < 22; i++) {
        _particles.add(_Particle(rng: _rng));
      }
    });
    _noiseSubscription?.cancel();
    _revealController.forward();
    _particleController.forward();
  }

  @override
  void dispose() {
    _noiseSubscription?.cancel();
    _pulseController.dispose();
    _revealController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  Color get _accent => widget.accentColor ?? const Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _revealAnim, _blurAnim, _particleController]),
      builder: (context, child) {
        return Transform.scale(
          scale: _isRevealed ? _revealAnim.value.clamp(0.85, 1.08) : 1.0,
          child: Container(
            constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: [
                  _accent.withValues(alpha: 0.92),
                  _accent.withAlpha(200),
                  Colors.deepPurple.shade900.withValues(alpha: 0.88),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.38 + _blowProgress * 0.2),
                  blurRadius: 22 + _blowProgress * 16,
                  spreadRadius: 2 + _blowProgress * 4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ShimmerPainter(
                        progress: _blowProgress,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.senderName != null) ...[
                          Text(
                            widget.senderName!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          widget.secretText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isRevealed || _blurAnim.value > 0.5)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: _blurAnim.value,
                            sigmaY: _blurAnim.value,
                          ),
                          child: AnimatedOpacity(
                            opacity: _isRevealed ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 400),
                            child: Container(
                              color: _accent.withValues(alpha: 0.55),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ScaleTransition(
                                    scale: _pulseAnim,
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(alpha: 0.18),
                                        border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.5), width: 2),
                                      ),
                                      child: const Center(
                                        child: Text("🌬️", style: TextStyle(fontSize: 26)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    "Thổi vào mic để mở",
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: 120,
                                    child: Stack(
                                      children: [
                                        Container(
                                          height: 5,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.22),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 120),
                                          height: 5,
                                          width: 120 * _blowProgress,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.white.withValues(alpha: 0.6),
                                                blurRadius: 8,
                                              )
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_isRevealed)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ParticlePainter(
                            particles: _particles,
                            progress: _particleController.value,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;

  _Particle({required Random rng})
      : angle = rng.nextDouble() * 2 * pi,
        speed = 40 + rng.nextDouble() * 80,
        size = 3 + rng.nextDouble() * 6,
        color = [
          Colors.white,
          Colors.amber.shade200,
          Colors.pinkAccent.shade100,
          Colors.cyan.shade200,
        ][rng.nextInt(4)];
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final p in particles) {
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final dx = cos(p.angle) * p.speed * progress;
      final dy = sin(p.angle) * p.speed * progress;
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(center + Offset(dx, dy), p.size * (1 - progress * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}

class _ShimmerPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ShimmerPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.08 * progress),
          color.withValues(alpha: 0.0),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.progress != progress;
}
