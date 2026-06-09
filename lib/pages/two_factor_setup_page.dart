import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:otp/otp.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';

class TwoFactorSetupPage extends StatefulWidget {
  const TwoFactorSetupPage({super.key});

  @override
  State<TwoFactorSetupPage> createState() => _TwoFactorSetupPageState();
}

class _TwoFactorSetupPageState extends State<TwoFactorSetupPage> with TickerProviderStateMixin {
  late String _secret;
  late String _qrUri;
  late String _nickname;

  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isVerifying = false;
  int _currentStep = 0;
  int _secondsLeft = 30;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _generateSecret();

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);

    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _fadeCtrl.forward();
    _slideCtrl.forward();
    _startTimer();
  }

  void _startTimer() {
    _updateTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _updateTimer());
    });
  }

  void _updateTimer() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _secondsLeft = 30 - (now % 30);
  }

  @override
  void dispose() {
    _timer.cancel();
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _generateSecret() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final rnd = Random.secure();
    _secret = List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
    _nickname = context.read<SettingProvider>().getPref(FirestoreConstants.nickname) ?? 'User';
    _qrUri = 'otpauth://totp/AppChatPlus:$_nickname?secret=$_secret&issuer=AppChatPlus';
  }

  String get _enteredCode => _controllers.map((c) => c.text.trim()).join();

  void _onOtpDigit(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});

    // Auto verify if 6 digits entered
    if (index == 5 && _enteredCode.length == 6) {
      _verifyAndEnable();
    }
  }

  void _nextStep() {
    _fadeCtrl.reset();
    _slideCtrl.reset();
    setState(() {
      _currentStep = 1;
      for (final c in _controllers) {
        c.clear();
      }
    });
    _fadeCtrl.forward();
    _slideCtrl.forward();
    Future.delayed(const Duration(milliseconds: 120), () => _focusNodes[0].requestFocus());
  }

  void _prevStep() {
    _fadeCtrl.reset();
    _slideCtrl.reset();
    setState(() {
      _currentStep = 0;
      for (final c in _controllers) {
        c.clear();
      }
    });
    _fadeCtrl.forward();
    _slideCtrl.forward();
  }

  Future<void> _verifyAndEnable() async {
    final code = _enteredCode;
    if (code.length != 6) {
      _showToast('Vui lòng nhập đủ 6 chữ số', isError: true);
      return;
    }

    setState(() => _isVerifying = true);
    await Future.delayed(const Duration(milliseconds: 400));

    final isValid = OTP.generateTOTPCodeString(_secret, DateTime.now().millisecondsSinceEpoch) == code;

    if (!mounted) return;

    if (isValid) {
      setState(() => _isLoading = true);
      try {
        final sp = context.read<SettingProvider>();
        final userId = sp.getPref(FirestoreConstants.id);

        await sp.updateDataFirestore(
            FirestoreConstants.pathUserCollection,
            userId!,
            {'is2FAEnabled': true, 'twoFactorSecret': _secret}
        );
        await sp.setPref('is2FAEnabled', true);
        await sp.setPref('twoFactorSecret', _secret);

        if (mounted) {
          _showToast('Kích hoạt 2FA thành công! 🔒', isError: false);
          await Future.delayed(const Duration(milliseconds: 800));
          Navigator.pop(context, true);
        }
      } catch (e) {
        _showToast('Lỗi kết nối: $e', isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      _showToast('Mã xác thực không đúng. Vui lòng thử lại.', isError: true);
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    }
    if (mounted) setState(() => _isVerifying = false);
  }

  void _copySecret() {
    Clipboard.setData(ClipboardData(text: _secret));
    Fluttertoast.showToast(
        msg: '📋 Đã sao chép khóa bí mật',
        backgroundColor: Colors.black87,
        textColor: Colors.white
    );
  }

  void _showToast(String msg, {required bool isError}) {
    Fluttertoast.showToast(
        msg: msg,
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

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
              onPressed: () => Navigator.pop(context)
          ),
          title: Text(
              'Bảo mật 2 lớp',
              style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)
          ),
          centerTitle: true,
        ),
        body: _isLoading
            ? Center(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: theme.primaryColor, strokeWidth: 2.5),
                  const SizedBox(height: 14),
                  Text('Đang kích hoạt 2FA…', style: TextStyle(color: p.textSecondary, fontSize: 14)),
                ]
            )
        )
            : Column(
            children: [
              _buildStepIndicator(p, theme),
              Expanded(
                  child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                          position: _slideAnim,
                          child: _currentStep == 0
                              ? _buildScanStep(p, theme)
                              : _buildVerifyStep(p, theme)
                      )
                  )
              ),
            ]
        ),
      ),
    );
  }

  Widget _buildStepIndicator(ThemePalette p, ThemeProvider theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      color: p.appBarBackground,
      child: Row(
          children: [
            _StepCircle(
                number: 1,
                active: true,
                done: _currentStep > 0,
                label: 'Quét mã',
                primary: theme.primaryColor,
                palette: p
            ),
            Expanded(
                child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: _currentStep >= 1 ? theme.primaryColor : p.divider
                    )
                )
            ),
            _StepCircle(
                number: 2,
                active: _currentStep >= 1,
                done: false,
                label: 'Xác nhận',
                primary: theme.primaryColor,
                palette: p
            ),
          ]
      ),
    );
  }

  Widget _buildScanStep(ThemePalette p, ThemeProvider theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
          children: [
            // QR card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.divider, width: 0.6),
                  boxShadow: [
                    BoxShadow(
                        color: theme.primaryColor.withValues(alpha: 0.08),
                        blurRadius: 24
                    )
                  ]
              ),
              child: Column(
                  children: [
                    Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16)
                        ),
                        child: QrImageView(
                            data: _qrUri,
                            version: QrVersions.auto,
                            size: 180,
                            backgroundColor: Colors.white,
                            eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: theme.primaryColor),
                            dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Color(0xFF1A1D2E)
                            )
                        )
                    ),
                    const SizedBox(height: 20),
                    Text(
                        'Khóa bí mật thủ công',
                        style: TextStyle(fontSize: 12, color: p.textSecondary, letterSpacing: 0.4)
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _copySecret,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  _secret.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m.group(0)} ').trim(),
                                  style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                      color: theme.primaryColor
                                  )
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.copy_rounded, size: 16, color: theme.primaryColor),
                            ]
                        ),
                      ),
                    ),
                  ]
              ),
            ),
            const SizedBox(height: 24),
            // Instructions
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.divider, width: 0.6)
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Hướng dẫn',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: p.textPrimary)
                    ),
                    const SizedBox(height: 14),
                    ...[
                      (Icons.download_rounded, 'Tải Google Authenticator hoặc ứng dụng tương tự'),
                      (Icons.qr_code_scanner_rounded, 'Nhấn "+" rồi quét mã QR phía trên'),
                      (Icons.check_circle_rounded, 'Nhập mã 6 số hiển thị vào bước tiếp theo'),
                    ].asMap().entries.map((e) => Padding(
                      padding: EdgeInsets.only(bottom: e.key < 2 ? 12 : 0),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                    color: theme.primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8)
                                ),
                                child: Icon(e.value.$1, size: 17, color: theme.primaryColor)
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                        e.value.$2,
                                        style: TextStyle(fontSize: 13.5, height: 1.4, color: p.textSecondary)
                                    )
                                )
                            ),
                          ]
                      ),
                    )),
                  ]
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _nextStep,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                  label: const Text('Đã quét xong', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                  ),
                )
            ),
          ]
      ),
    );
  }

  Widget _buildVerifyStep(ThemePalette p, ThemeProvider theme) {
    final progress = _secondsLeft / 30.0;
    final isExpiring = _secondsLeft <= 10;
    final timerColor = isExpiring ? Colors.red.shade500 : theme.primaryColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
          children: [
            // Timer
            Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                      width: 96,
                      height: 96,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 5,
                        backgroundColor: p.divider,
                        valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                      )
                  ),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: timerColor.withValues(alpha: 0.1)
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_rounded, color: timerColor, size: 26),
                          Text(
                              '$_secondsLeft',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: timerColor)
                          ),
                        ]
                    ),
                  ),
                ]
            ),
            const SizedBox(height: 20),
            Text(
                'Nhập mã từ Authenticator',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: p.textPrimary,
                    letterSpacing: -0.4
                )
            ),
            const SizedBox(height: 6),
            Text(
                'Mã 6 số đang hiển thị trong ứng dụng của bạn.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.textSecondary)
            ),
            if (isExpiring) ...[
              const SizedBox(height: 12),
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
                          'Mã sắp hết hạn!',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w600)
                      ),
                    ]
                ),
              ),
            ],
            const SizedBox(height: 32),
            // OTP boxes
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) => _OtpBox(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  primary: theme.primaryColor,
                  palette: p,
                  onChanged: (v) => _onOtpDigit(i, v),
                ))
            ),
            const SizedBox(height: 32),
            SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _verifyAndEnable,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor: p.surfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                  )
                      : const Text('Xác nhận & Kích hoạt', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                )
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _prevStep,
              icon: Icon(Icons.arrow_back_rounded, size: 15, color: p.textSecondary),
              label: Text('Quay lại quét mã', style: TextStyle(color: p.textSecondary)),
            ),
          ]
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  final int number;
  final bool active;
  final bool done;
  final String label;
  final Color primary;
  final ThemePalette palette;

  const _StepCircle({
    required this.number,
    required this.active,
    required this.done,
    required this.label,
    required this.primary,
    required this.palette
  });

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? primary : palette.surfaceVariant
            ),
            child: Center(
                child: done
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
                    : Text(
                    '$number',
                    style: TextStyle(
                        color: active ? Colors.white : palette.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13
                    )
                )
            ),
          ),
          const SizedBox(height: 4),
          Text(
              label,
              style: TextStyle(
                  fontSize: 10.5,
                  color: active ? primary : palette.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400
              )
          ),
        ]
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color primary;
  final ThemePalette palette;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.primary,
    required this.palette,
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
        color: isFilled ? primary.withValues(alpha: 0.08) : palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            width: isFocused ? 2.0 : 1.5,
            color: isFocused
                ? primary
                : isFilled
                ? primary.withValues(alpha: 0.4)
                : palette.divider
        ),
        boxShadow: isFocused
            ? [BoxShadow(color: primary.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3))]
            : [],
      ),
      child: Stack(
          children: [
            Positioned.fill(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primary),
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