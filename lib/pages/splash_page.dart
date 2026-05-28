import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:provider/provider.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _pulseController;
  late AnimationController _particleController;
  late AnimationController _exitController;

  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _ringScale1;
  late Animation<double> _ringScale2;
  late Animation<double> _ringOpacity1;
  late Animation<double> _ringOpacity2;
  late Animation<double> _pulseScale;
  late Animation<double> _appNameFade;
  late Animation<Offset> _appNameSlide;
  late Animation<double> _loaderFade;
  late Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Logo animations
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    _logoFade = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );

    // Ring ripple
    _ringScale1 = Tween<double>(begin: 0.8, end: 2.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );
    _ringOpacity1 = Tween<double>(begin: 0.5, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    _ringScale2 = Tween<double>(begin: 0.8, end: 2.5).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );
    _ringOpacity2 = Tween<double>(begin: 0.3, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    // Pulse for idle
    _pulseScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // App name
    _appNameFade = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    );

    _appNameSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
    ));

    _loaderFade = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    );

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );

    _logoController.forward().then((_) => _checkSignedIn());
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  void _checkSignedIn() async {
    // Minimum splash display time for visual polish
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    bool isLoggedIn = await authProvider.isLoggedIn();

    if (!mounted) return;

    // Fade out before navigating
    await _exitController.forward();

    if (!mounted) return;

    final page = isLoggedIn ? HomePage() : const LoginPage();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _exitFade,
        child: Stack(
          children: [
            // Background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0A0E1A),
                    Color(0xFF0D1B3E),
                    Color(0xFF0A1628),
                  ],
                ),
              ),
            ),

            // Decorative orbs
            Positioned(
              top: -120,
              left: -80,
              child: _Orb(
                color: const Color(0xFF4F8DFF).withOpacity(0.12),
                size: 350,
              ),
            ),
            Positioned(
              bottom: -100,
              right: -60,
              child: _Orb(
                color: const Color(0xFF7B4FFF).withOpacity(0.1),
                size: 300,
              ),
            ),

            // Floating particles
            AnimatedBuilder(
              animation: _particleController,
              builder: (_, __) => CustomPaint(
                painter: _ParticlePainter(progress: _particleController.value),
                size: MediaQuery.of(context).size,
              ),
            ),

            // Grid lines (subtle)
            CustomPaint(
              painter: _GridPainter(),
              size: MediaQuery.of(context).size,
            ),

            // Center content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo with rings
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (_, __) {
                      return SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer ring 2
                            Transform.scale(
                              scale: _ringScale2.value,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF4F8DFF)
                                        .withOpacity(_ringOpacity2.value),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                            // Outer ring 1
                            Transform.scale(
                              scale: _ringScale1.value,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF4F8DFF)
                                        .withOpacity(_ringOpacity1.value),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            // Logo icon
                            FadeTransition(
                              opacity: _logoFade,
                              child: ScaleTransition(
                                scale: _logoScale,
                                child: AnimatedBuilder(
                                  animation: _pulseScale,
                                  builder: (_, child) => Transform.scale(
                                    scale: _pulseScale.value,
                                    child: child,
                                  ),
                                  child: _LogoIcon(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  // App name
                  SlideTransition(
                    position: _appNameSlide,
                    child: FadeTransition(
                      opacity: _appNameFade,
                      child: Column(
                        children: [
                          const Text(
                            'FlutterChat',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Kết nối không giới hạn',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 64),

                  // Loader
                  FadeTransition(
                    opacity: _loaderFade,
                    child: _AnimatedDotLoader(),
                  ),
                ],
              ),
            ),

            // Version tag at bottom
            FadeTransition(
              opacity: _appNameFade,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Text(
                    'v2.0.0',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.2),
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Logo Icon ────────────────────────────────────────────────────────────────

class _LogoIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF4F8DFF), Color(0xFF7B4FFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F8DFF).withOpacity(0.45),
            blurRadius: 40,
            offset: const Offset(0, 14),
            spreadRadius: -4,
          ),
          BoxShadow(
            color: const Color(0xFF7B4FFF).withOpacity(0.25),
            blurRadius: 60,
            offset: const Offset(0, 24),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Shine overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.22),
                    Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          const Icon(
            Icons.chat_bubble_rounded,
            color: Colors.white,
            size: 46,
          ),
        ],
      ),
    );
  }
}

// ─── Animated Dot Loader ──────────────────────────────────────────────────────

class _AnimatedDotLoader extends StatefulWidget {
  @override
  State<_AnimatedDotLoader> createState() => _AnimatedDotLoaderState();
}

class _AnimatedDotLoaderState extends State<_AnimatedDotLoader>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      ),
    );

    _anims = _controllers
        .map(
          (c) => Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut),
          ),
        )
        .toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: 6 + _anims[i].value * 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Color.lerp(
                  const Color(0xFF4F8DFF).withOpacity(0.4),
                  const Color(0xFF4F8DFF),
                  _anims[i].value,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ─── Orb ──────────────────────────────────────────────────────────────────────

class _Orb extends StatelessWidget {
  final Color color;
  final double size;

  const _Orb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}

// ─── Particle Painter ─────────────────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final double progress;
  static final List<_Particle> _particles = List.generate(
    20,
    (i) {
      final rng = math.Random(i * 7 + 3);
      return _Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        speed: 0.04 + rng.nextDouble() * 0.08,
        size: 1.0 + rng.nextDouble() * 2.5,
        opacity: 0.06 + rng.nextDouble() * 0.2,
        phase: rng.nextDouble(),
      );
    },
  );

  _ParticlePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final t = (progress + p.phase) % 1.0;
      final y = (p.y - t * p.speed) % 1.0;
      final paint = Paint()
        ..color = const Color(0xFF4F8DFF)
            .withOpacity(p.opacity * (1.0 - (t * p.speed * 5).clamp(0.0, 1.0)))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(p.x * size.width, y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.progress != progress;
}

class _Particle {
  final double x, y, speed, size, opacity, phase;
  const _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.phase,
  });
}

// ─── Grid Painter ─────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4F8DFF).withOpacity(0.03)
      ..strokeWidth = 0.5;

    const spacing = 60.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
