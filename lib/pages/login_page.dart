import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    ));

    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    switch (authProvider.status) {
      case Status.authenticateError:
        WidgetsBinding.instance.addPostFrameCallback(
              (_) => Fluttertoast.showToast(msg: 'Sign in failed. Please try again.'),
        );
        break;
      case Status.authenticateCanceled:
        WidgetsBinding.instance.addPostFrameCallback(
              (_) => Fluttertoast.showToast(msg: 'Sign in cancelled'),
        );
        break;
      case Status.authenticated:
        WidgetsBinding.instance.addPostFrameCallback(
              (_) => Fluttertoast.showToast(msg: 'Welcome back!'),
        );
        break;
      default:
        break;
    }

    return Scaffold(
      backgroundColor: isDark ? ColorConstants.backgroundDark : Colors.white,
      body: Stack(
        children: [
          // Background gradient decoration
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ColorConstants.primaryColor.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ColorConstants.primaryColor.withOpacity(0.04),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: size.height * 0.1),

                  // Logo & Brand
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Center(
                        child: Column(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: ColorConstants.primaryGradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: ColorConstants.primaryColor
                                        .withOpacity(0.35),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.chat_bubble_rounded,
                                color: Colors.white,
                                size: 38,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Flutter Chat',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1D2E),
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Connect with friends instantly',
                              style: TextStyle(
                                color: ColorConstants.greyColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: size.height * 0.1),

                  // Sign in options
                  SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Column(
                        children: [
                          // Google Sign In
                          _buildGoogleSignInBtn(authProvider, isDark),
                          const SizedBox(height: 14),

                          // Divider
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: isDark
                                      ? Colors.white.withOpacity(0.08)
                                      : ColorConstants.greyColor2,
                                ),
                              ),
                              Padding(
                                padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'or',
                                  style: TextStyle(
                                    color: ColorConstants.greyColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: isDark
                                      ? Colors.white.withOpacity(0.08)
                                      : ColorConstants.greyColor2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Phone Sign In
                          _buildPhoneSignInBtn(isDark),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Footer
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Center(
                        child: Text(
                          'By continuing, you agree to our Terms of Service\nand Privacy Policy',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ColorConstants.greyColor.withOpacity(0.7),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (authProvider.status == Status.authenticating)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.35),
                child: const Center(
                  child: _LoadingCard(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGoogleSignInBtn(AuthProvider authProvider, bool isDark) {
    return _AuthButton(
      onPressed: () {
        authProvider.handleSignIn().then((isSuccess) {
          if (isSuccess) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => HomePage()),
            );
          }
        }).catchError((error, stackTrace) {
          Fluttertoast.showToast(msg: error.toString());
          authProvider.handleException();
        });
      },
      isDark: isDark,
      icon: _GoogleIcon(),
      label: 'Continue with Google',
      isPrimary: true,
    );
  }

  Widget _buildPhoneSignInBtn(bool isDark) {
    return _AuthButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PhoneLoginPage()),
        );
      },
      isDark: isDark,
      icon: const Icon(Icons.phone_outlined,
          size: 20, color: ColorConstants.primaryColor),
      label: 'Continue with Phone',
      isPrimary: false,
    );
  }
}

class _AuthButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isDark;
  final Widget icon;
  final String label;
  final bool isPrimary;

  const _AuthButton({
    required this.onPressed,
    required this.isDark,
    required this.icon,
    required this.label,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFF1E2130) : Colors.white,
            foregroundColor: isDark ? Colors.white : const Color(0xFF1A1D2E),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: isDark
                    ? ColorConstants.borderDark
                    : ColorConstants.greyColor2,
                width: 1.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ColorConstants.primaryColor.withOpacity(0.08),
          foregroundColor: ColorConstants.primaryColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: ColorConstants.primaryColor,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Red
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
        Rect.fromLTWH(0, 0, size.width, size.height), -1.57, 2.0, true, paint);

    // Blue
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
        Rect.fromLTWH(0, 0, size.width, size.height), 0.43, 1.65, true, paint);

    // Yellow
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
        Rect.fromLTWH(0, 0, size.width, size.height), 2.08, 0.93, true, paint);

    // Green
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
        Rect.fromLTWH(0, 0, size.width, size.height), 3.01, 0.71, true, paint);

    // White center
    paint.color = Colors.white;
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width * 0.35, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: ColorConstants.primaryColor,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Signing in...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: ColorConstants.greyColor,
            ),
          ),
        ],
      ),
    );
  }
}