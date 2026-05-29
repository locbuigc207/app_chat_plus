import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _contentController;
  late AnimationController _floatController;

  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<Offset> _logoSlide;
  late Animation<double> _cardFade;
  late Animation<Offset> _cardSlide;
  late Animation<double> _btnFade;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _logoFade = CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    ));

    _cardFade = CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.3, 0.75, curve: Curves.easeOut),
    );
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.3, 0.85, curve: Curves.easeOutCubic),
    ));

    _btnFade = CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );

    _floatAnim = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _contentController.forward();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _contentController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final size = MediaQuery.of(context).size;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (authProvider.status) {
        case Status.authenticateError:
          Fluttertoast.showToast(
            msg: 'Đăng nhập thất bại. Vui lòng thử lại.',
            backgroundColor: const Color(0xFFFF4B4B),
            textColor: Colors.white,
          );
          break;
        case Status.authenticateCanceled:
          Fluttertoast.showToast(
            msg: 'Đã hủy đăng nhập',
            backgroundColor: const Color(0xFF666666),
            textColor: Colors.white,
          );
          break;
        case Status.authenticated:
          Fluttertoast.showToast(
            msg: 'Chào mừng trở lại! 👋',
            backgroundColor: const Color(0xFF00C896),
            textColor: Colors.white,
          );
          break;
        default:
          break;
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bgController,
            builder: (_, __) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: const [
                      Color(0xFF0A0E1A),
                      Color(0xFF0D1B3E),
                      Color(0xFF0A1628),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: -size.height * 0.1,
            left: -size.width * 0.2,
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (_, __) {
                return _GlowOrb(
                  color: const Color(0xFF4F8DFF).withValues(alpha: 0.15),
                  size: size.width * 0.8,
                  animValue: _bgController.value,
                );
              },
            ),
          ),
          Positioned(
            bottom: -size.height * 0.05,
            right: -size.width * 0.15,
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (_, __) {
                return _GlowOrb(
                  color: const Color(0xFF7B4FFF).withValues(alpha: 0.12),
                  size: size.width * 0.7,
                  animValue: 1.0 - _bgController.value,
                );
              },
            ),
          ),
          ...List.generate(6, (i) => _FloatingDot(index: i, size: size)),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    children: [
                      SlideTransition(
                        position: _logoSlide,
                        child: FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: AnimatedBuilder(
                              animation: _floatAnim,
                              builder: (_, child) {
                                return Transform.translate(
                                  offset: Offset(0, _floatAnim.value),
                                  child: child,
                                );
                              },
                              child: _LogoSection(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      SlideTransition(
                        position: _cardSlide,
                        child: FadeTransition(
                          opacity: _cardFade,
                          child: _AuthCard(
                            btnFade: _btnFade,
                            authProvider: authProvider,
                            onSignInSuccess: (result) {
                              if (result == 'success') {
                                Navigator.pushReplacement(
                                  context,
                                  _FadeRoute(page: HomePage()),
                                );
                              } else if (result == 'requires_2fa') {
                                Navigator.pushReplacement(
                                  context,
                                  _FadeRoute(page: TwoFactorVerifyPage()),
                                );
                              }
                            },
                            onPhoneTap: () {
                              Navigator.push(
                                context,
                                _SlideRoute(page: PhoneLoginPage()),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (authProvider.status == Status.authenticating) const _LoadingOverlay(),
        ],
      ),
    );
  }
}

class _LogoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xFF4F8DFF), Color(0xFF7B4FFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F8DFF).withValues(alpha: 0.4),
                blurRadius: 32,
                offset: const Offset(0, 12),
                spreadRadius: -4,
              ),
              BoxShadow(
                color: const Color(0xFF7B4FFF).withValues(alpha: 0.25),
                blurRadius: 48,
                offset: const Offset(0, 20),
                spreadRadius: -8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 45,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.2),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'FlutterChat',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Kết nối · Chia sẻ · Trải nghiệm',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _AuthCard extends StatelessWidget {
  final Animation<double> btnFade;
  final AuthProvider authProvider;
  final void Function(String) onSignInSuccess;
  final VoidCallback onPhoneTap;

  const _AuthCard({
    required this.btnFade,
    required this.authProvider,
    required this.onSignInSuccess,
    required this.onPhoneTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(28),
          child: FadeTransition(
            opacity: btnFade,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đăng nhập',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Chọn phương thức đăng nhập của bạn',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                _SignInButton(
                  onPressed: () {
                    authProvider.handleSignIn().then(onSignInSuccess).catchError(
                      (e) {
                        Fluttertoast.showToast(msg: e.toString());
                        authProvider.handleException();
                      },
                    );
                  },
                  icon: const _GoogleColorIcon(),
                  label: 'Tiếp tục với Google',
                  isPrimary: true,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'hoặc',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SignInButton(
                  onPressed: onPhoneTap,
                  icon: const Icon(
                    Icons.phone_rounded,
                    size: 20,
                    color: Color(0xFF4F8DFF),
                  ),
                  label: 'Tiếp tục với Số điện thoại',
                  isPrimary: false,
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Khi tiếp tục, bạn đồng ý với\nĐiều khoản dịch vụ và Chính sách bảo mật',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 11.5,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final String label;
  final bool isPrimary;

  const _SignInButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.isPrimary,
  });

  @override
  State<_SignInButton> createState() => _SignInButtonState();
}

class _SignInButtonState extends State<_SignInButton> with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        widget.onPressed();
      },
      onTapCancel: () => _pressController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: widget.isPrimary ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
            border: Border.all(
              color: widget.isPrimary
                  ? Colors.white.withValues(alpha: 0.15)
                  : const Color(0xFF4F8DFF).withValues(alpha: 0.3),
              width: 1,
            ),
            gradient: widget.isPrimary
                ? null
                : LinearGradient(
                    colors: [
                      const Color(0xFF4F8DFF).withValues(alpha: 0.08),
                      const Color(0xFF7B4FFF).withValues(alpha: 0.08),
                    ],
                  ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.icon,
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isPrimary
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFF4F8DFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleColorIcon extends StatelessWidget {
  const _GoogleColorIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..style = PaintingStyle.fill;
    const rect = Rect.fromLTWH(0, 0, 22, 22);

    p.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -math.pi / 2, 2.0, true, p);
    p.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, 0.43, 1.65, true, p);
    p.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.08, 0.93, true, p);
    p.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 3.01, 0.71, true, p);
    p.color = const Color(0xFF0D1B3E);
    canvas.drawCircle(Offset(s.width / 2, s.height / 2), s.width * 0.35, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          color: Colors.black.withValues(alpha: 0.4),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          color: const Color(0xFF4F8DFF),
                          strokeWidth: 2.5,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Đang đăng nhập...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double animValue;

  const _GlowOrb({
    required this.color,
    required this.size,
    required this.animValue,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.95 + animValue * 0.1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _FloatingDot extends StatefulWidget {
  final int index;
  final Size size;

  const _FloatingDot({required this.index, required this.size});

  @override
  State<_FloatingDot> createState() => _FloatingDotState();
}

class _FloatingDotState extends State<_FloatingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _y;
  late double _x, _dotSize, _opacity;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(widget.index * 13);
    _x = rng.nextDouble() * widget.size.width;
    _dotSize = 2.0 + rng.nextDouble() * 4.0;
    _opacity = 0.1 + rng.nextDouble() * 0.3;

    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: 4 + widget.index * 2),
    )..repeat(reverse: true);

    _y = Tween<double>(
      begin: widget.size.height * 0.2 + rng.nextDouble() * widget.size.height * 0.4,
      end: widget.size.height * 0.2 + rng.nextDouble() * widget.size.height * 0.4,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _y,
      builder: (_, __) => Positioned(
        left: _x,
        top: _y.value,
        child: Container(
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4F8DFF).withValues(alpha: _opacity),
          ),
        ),
      ),
    );
  }
}

class _FadeRoute extends PageRouteBuilder {
  final Widget page;
  _FadeRoute({required this.page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        );
}

class _SlideRoute extends PageRouteBuilder {
  final Widget page;
  _SlideRoute({required this.page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, anim, __, child) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 350),
        );
}
