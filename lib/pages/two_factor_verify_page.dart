import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:otp/otp.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/pages/home_page.dart';
import 'package:flutter_chat_demo/pages/login_page.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';

class TwoFactorVerifyPage extends StatefulWidget {
  const TwoFactorVerifyPage({super.key});

  @override
  State<TwoFactorVerifyPage> createState() => _TwoFactorVerifyPageState();
}

class _TwoFactorVerifyPageState extends State<TwoFactorVerifyPage> with SingleTickerProviderStateMixin {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  bool _isLocked = false;
  int _failCount = 0;
  int _lockSeconds = 0;
  int _secondsLeft = 30;

  Timer? _lockTimer;
  late Timer _totpTimer;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));

    _startTotpTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNodes[0].requestFocus());
  }

  void _startTotpTimer() {
    _updateTimer();
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _updateTimer());
    });
  }

  void _updateTimer() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _secondsLeft = 30 - (now % 30);
  }

  @override
  void dispose() {
    _totpTimer.cancel();
    _lockTimer?.cancel();
    _shakeCtrl.dispose();

    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredCode => _controllers.map((c) => c.text.trim()).join();

  void _onOtpDigit(int index, String value) {
    if (value.length == 1) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _verifyLogin();
      }
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  void _startLockout() {
    setState(() {
      _isLocked = true;
      _lockSeconds = 30 * _failCount;
    });

    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      setState(() => _lockSeconds--);

      if (_lockSeconds <= 0) {
        t.cancel();
        setState(() => _isLocked = false);
      }
    });
  }

  Future<void> _verifyLogin() async {
    if (_isLocked) return;

    final code = _enteredCode;
    if (code.length != 6) {
      _showToast('Vui lòng nhập đủ 6 chữ số', isError: true);
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final secret = authProvider.tempUserChat?.twoFactorSecret;

    if (secret == null || secret.isEmpty) {
      _showToast('Lỗi dữ liệu 2FA. Vui lòng đăng nhập lại.', isError: true);
      await authProvider.handleSignOut();
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      }
      return;
    }

    setState(() => _isVerifying = true);
    await Future.delayed(const Duration(milliseconds: 300));

    final isValid = OTP.generateTOTPCodeString(secret, DateTime.now().millisecondsSinceEpoch) == code;

    if (!mounted) return;

    if (isValid) {
      _showToast('Đăng nhập thành công! 🎉', isError: false);
      await authProvider.complete2FALogin();
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
      }
    } else {
      _failCount++;
      _shakeCtrl.forward(from: 0);

      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();

      if (_failCount >= 3) {
        _showToast('Sai $_failCount lần. Khóa ${30 * _failCount}s.', isError: true);
        _startLockout();
      } else {
        _showToast('Mã không đúng. Còn ${3 - _failCount} lần thử.', isError: true);
      }
    }

    if (mounted) setState(() => _isVerifying = false);
  }

  void _showToast(String msg, {required bool isError}) {
    Fluttertoast.showToast(
        msg: msg,
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG
    );
  }

  Future<void> _signOut() async {
    await context.read<AuthProvider>().handleSignOut();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    final progress = _secondsLeft / 30.0;
    final isExpiring = _secondsLeft <= 10;
    final timerColor = isExpiring ? Colors.red.shade500 : theme.primaryColor;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          backgroundColor: p.appBarBackground,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: theme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.primaryColor, size: 20),
            onPressed: _signOut,
            tooltip: 'Quay lại đăng nhập',
          ),
          title: Text(
              'Xác minh 2 lớp',
              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
                children: [
                  // Timer ring
                  Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                            width: 100,
                            height: 100,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 5,
                              backgroundColor: p.divider,
                              valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                            )
                        ),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: timerColor.withValues(alpha: 0.1)
                          ),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shield_rounded, color: timerColor, size: 30),
                                Text(
                                    '$_secondsLeft',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: timerColor)
                                ),
                              ]
                          ),
                        ),
                      ]
                  ),
                  const SizedBox(height: 28),
                  Text(
                      'Xác minh danh tính',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: p.textPrimary,
                          letterSpacing: -0.5
                      )
                  ),
                  const SizedBox(height: 10),
                  Text(
                      'Nhập mã từ ứng dụng Authenticator\nđể tiếp tục đăng nhập.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, height: 1.6, color: p.textSecondary)
                  ),
                  if (isExpiring) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.25))
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 15),
                            const SizedBox(width: 6),
                            Text(
                                'Mã sắp hết hạn, hãy nhập nhanh!',
                                style: TextStyle(color: Colors.red.shade700, fontSize: 13)
                            ),
                          ]
                      ),
                    ),
                  ],
                  const SizedBox(height: 36),

                  // OTP input with shake animation
                  AnimatedBuilder(
                    animation: _shakeAnim,
                    builder: (context, child) {
                      final dx = _shakeCtrl.isAnimating ? 8 * (0.5 - _shakeAnim.value).abs() : 0.0;
                      return Transform.translate(offset: Offset(dx, 0), child: child);
                    },
                    child: Column(
                        children: [
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(6, (i) => _OtpBox(
                                controller: _controllers[i],
                                focusNode: _focusNodes[i],
                                primary: theme.primaryColor,
                                palette: p,
                                isLocked: _isLocked,
                                onChanged: (v) => _onOtpDigit(i, v),
                              ))
                          ),
                          if (_isLocked) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3))
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.lock_clock_rounded, color: Colors.orange, size: 17),
                                    const SizedBox(width: 8),
                                    Text(
                                        'Tạm khóa: còn ${_lockSeconds}s',
                                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)
                                    ),
                                  ]
                              ),
                            ),
                          ],
                          if (_failCount > 0 && !_isLocked) ...[
                            const SizedBox(height: 14),
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(3, (i) => Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i < _failCount ? Colors.red : p.divider
                                  ),
                                ))
                            ),
                          ],
                        ]
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: (_isVerifying || _isLocked) ? null : _verifyLogin,
                        icon: const Icon(Icons.verified_user_rounded, size: 20),
                        label: _isVerifying
                            ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                        )
                            : const Text(
                            'Xác minh & Đăng nhập',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          disabledBackgroundColor: p.surfaceVariant,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      )
                  ),
                  const SizedBox(height: 24),
                  Divider(color: p.divider),
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: _signOut,
                    icon: Icon(Icons.logout_rounded, size: 15, color: p.textSecondary),
                    label: Text(
                        'Đăng xuất & Quay lại',
                        style: TextStyle(color: p.textSecondary, fontSize: 14)
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'Không thể truy cập mã? Liên hệ hỗ trợ.',
                      style: TextStyle(fontSize: 12.5, color: p.textSecondary)
                  ),
                ]
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color primary;
  final ThemePalette palette;
  final bool isLocked;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.primary,
    required this.palette,
    required this.isLocked,
    required this.onChanged
  });

  @override
  Widget build(BuildContext context) {
    final isFilled = controller.text.isNotEmpty;
    final isFocused = focusNode.hasFocus;

    return Container(
      width: 46,
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isLocked
            ? palette.surfaceVariant
            : isFilled
            ? primary.withValues(alpha: 0.08)
            : palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            width: isFocused ? 2.0 : 1.5,
            color: isLocked
                ? palette.divider
                : isFocused
                ? primary
                : isFilled
                ? primary.withValues(alpha: 0.4)
                : palette.divider
        ),
        boxShadow: isFocused && !isLocked
            ? [BoxShadow(color: primary.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3))]
            : [],
      ),
      child: Stack(
          children: [
            Positioned.fill(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !isLocked,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isLocked ? palette.textSecondary : primary
                  ),
                  decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: onChanged,
                )
            ),
            if (!isFilled)
              Positioned.fill(
                  child: IgnorePointer(
                      child: Center(
                          child: Container(
                              width: 8,
                              height: 2,
                              color: palette.divider
                          )
                      )
                  )
              ),
          ]
      ),
    );
  }
}