import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/color_constants.dart';
import 'package:flutter_chat_demo/pages/home_page.dart';
import 'package:flutter_chat_demo/pages/login_page.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:otp/otp.dart';
import 'package:provider/provider.dart';

class TwoFactorVerifyPage extends StatefulWidget {
  const TwoFactorVerifyPage({super.key});

  @override
  State<TwoFactorVerifyPage> createState() => _TwoFactorVerifyPageState();
}

class _TwoFactorVerifyPageState extends State<TwoFactorVerifyPage>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  int _failCount = 0;
  bool _isLocked = false;
  int _lockSeconds = 0;
  Timer? _lockTimer;

  // TOTP countdown
  late Timer _totpTimer;
  int _secondsLeft = 30;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    _startTotpTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
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
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  String get _enteredCode => _controllers.map((c) => c.text.trim()).join();

  void _onOtpDigit(int index, String value) {
    if (value.length == 1) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        // Auto-submit on last digit
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
      _showToast("Vui lòng nhập đủ 6 chữ số", isError: true);
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final secret = authProvider.tempUserChat?.twoFactorSecret;

    if (secret == null || secret.isEmpty) {
      _showToast("Lỗi dữ liệu 2FA. Vui lòng đăng nhập lại.", isError: true);
      await authProvider.handleSignOut();
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const LoginPage()));
      }
      return;
    }

    setState(() => _isVerifying = true);
    await Future.delayed(const Duration(milliseconds: 300));

    final isValid = OTP.generateTOTPCodeString(
            secret, DateTime.now().millisecondsSinceEpoch) ==
        code;

    if (!mounted) return;

    if (isValid) {
      _showToast("Đăng nhập thành công!", isError: false);
      await authProvider.complete2FALogin();
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomePage()));
      }
    } else {
      _failCount++;
      _shakeCtrl.forward(from: 0);
      for (final c in _controllers) c.clear();
      _focusNodes[0].requestFocus();

      if (_failCount >= 3) {
        _showToast("Sai ${_failCount} lần. Khóa ${30 * _failCount}s.",
            isError: true);
        _startLockout();
      } else {
        _showToast("Mã không đúng. Còn ${3 - _failCount} lần thử.",
            isError: true);
      }
    }

    if (mounted) setState(() => _isVerifying = false);
  }

  void _showToast(String msg, {required bool isError}) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_LONG,
    );
  }

  void _signOutAndBack() async {
    await context.read<AuthProvider>().handleSignOut();
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF8F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white : Colors.black87, size: 20),
          onPressed: _signOutAndBack,
          tooltip: 'Quay lại đăng nhập',
        ),
        title: Text(
          'Xác minh 2 lớp',
          style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeader(isDark),
                const SizedBox(height: 40),
                _buildOtpSection(isDark),
                const SizedBox(height: 36),
                _buildActions(isDark),
                const SizedBox(height: 24),
                _buildFooter(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final progress = _secondsLeft / 30.0;
    final isExpiring = _secondsLeft <= 10;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 5,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                    isExpiring ? Colors.red : ColorConstants.primaryColor),
              ),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ColorConstants.primaryColor.withOpacity(0.1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_rounded,
                      color:
                          isExpiring ? Colors.red : ColorConstants.primaryColor,
                      size: 28),
                  Text(
                    '$_secondsLeft',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isExpiring
                            ? Colors.red
                            : ColorConstants.primaryColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Xác minh danh tính',
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87),
        ),
        const SizedBox(height: 10),
        Text(
          'Tài khoản của bạn được bảo vệ bằng xác thực 2 lớp.\nNhập mã từ ứng dụng Authenticator để tiếp tục.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: isDark ? Colors.white54 : Colors.grey.shade600),
        ),
        if (isExpiring) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.red, size: 16),
                const SizedBox(width: 6),
                Text('Mã sắp hết hạn, hãy nhập nhanh!',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOtpSection(bool isDark) {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (context, child) {
        final dx =
            _shakeCtrl.isAnimating ? 8 * (0.5 - _shakeAnim.value).abs() : 0.0;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) => _buildOtpBox(i, isDark)),
          ),
          if (_isLocked) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_clock_rounded,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Tạm khóa: còn ${_lockSeconds}s',
                    style: const TextStyle(
                        color: Colors.orange, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
          if (_failCount > 0 && !_isLocked) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _failCount ? Colors.red : Colors.grey.shade300,
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOtpBox(int index, bool isDark) {
    final isFilled = _controllers[index].text.isNotEmpty;
    final isFocused = _focusNodes[index].hasFocus;

    return Container(
      width: 46,
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _isLocked
            ? Colors.grey.shade100
            : isFilled
                ? ColorConstants.primaryColor.withOpacity(0.08)
                : isDark
                    ? const Color(0xFF1C1C2E)
                    : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: isFocused ? 2.0 : 1.5,
          color: _isLocked
              ? Colors.grey.shade300
              : isFocused
                  ? ColorConstants.primaryColor
                  : isFilled
                      ? ColorConstants.primaryColor.withOpacity(0.4)
                      : isDark
                          ? Colors.white12
                          : Colors.grey.shade300,
        ),
        boxShadow: isFocused && !_isLocked
            ? [
                BoxShadow(
                    color: ColorConstants.primaryColor.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ]
            : [],
      ),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        enabled: !_isLocked,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: _isLocked ? Colors.grey : ColorConstants.primaryColor),
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (v) => _onOtpDigit(index, v),
      ),
    );
  }

  Widget _buildActions(bool isDark) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_isVerifying || _isLocked) ? null : _verifyLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: ColorConstants.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              disabledBackgroundColor:
                  ColorConstants.primaryColor.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: _isVerifying
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('Xác minh & Đăng nhập',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(bool isDark) {
    return Column(
      children: [
        Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _signOutAndBack,
          icon:
              Icon(Icons.logout_rounded, size: 16, color: Colors.grey.shade500),
          label: Text(
            'Đăng xuất & Quay lại',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Không thể truy cập mã? Liên hệ hỗ trợ.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
        ),
      ],
    );
  }
}
