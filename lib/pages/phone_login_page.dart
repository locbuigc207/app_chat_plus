import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/phone_auth_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  State<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage>
    with TickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _otpControllers =
  List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
  List.generate(6, (_) => FocusNode());

  String _selectedCountryCode = '+84';
  String _selectedFlag = '🇻🇳';
  bool _phoneFieldFocused = false;
  int _resendSeconds = 0;

  late AnimationController _entryController;
  late AnimationController _shakeController;
  late AnimationController _successController;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;
  late Animation<double> _shakeAnim;
  late Animation<double> _successScale;

  static const _countryCodes = [
    (code: '+84', flag: '🇻🇳', name: 'Việt Nam'),
    (code: '+1', flag: '🇺🇸', name: 'Hoa Kỳ'),
    (code: '+44', flag: '🇬🇧', name: 'Anh'),
    (code: '+91', flag: '🇮🇳', name: 'Ấn Độ'),
    (code: '+81', flag: '🇯🇵', name: 'Nhật Bản'),
    (code: '+82', flag: '🇰🇷', name: 'Hàn Quốc'),
    (code: '+65', flag: '🇸🇬', name: 'Singapore'),
    (code: '+66', flag: '🇹🇭', name: 'Thái Lan'),
    (code: '+60', flag: '🇲🇾', name: 'Malaysia'),
    (code: '+86', flag: '🇨🇳', name: 'Trung Quốc'),
  ];

  @override
  void initState() {
    super.initState();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _entryFade = CurvedAnimation(
        parent: _entryController, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _entryController, curve: Curves.easeOutCubic));

    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _successScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _shakeController.dispose();
    _successController.dispose();
    _phoneController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _sendOTP() {
    if (_formKey.currentState!.validate()) {
      HapticFeedback.lightImpact();
      final phoneNumber =
          _selectedCountryCode + _phoneController.text.trim();
      context.read<PhoneAuthProvider>().sendOTP(phoneNumber);
      _startResendCountdown();
    }
  }

  void _startResendCountdown() {
    setState(() => _resendSeconds = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendSeconds--);
      return _resendSeconds > 0;
    });
  }

  String get _fullOtp =>
      _otpControllers.map((c) => c.text).join();

  void _verifyOTP() async {
    if (_fullOtp.length < 6) {
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      return;
    }

    HapticFeedback.lightImpact();
    final phoneNumber =
        _selectedCountryCode + _phoneController.text.trim();
    final phoneAuthProvider = context.read<PhoneAuthProvider>();

    final isSuccess =
    await phoneAuthProvider.verifyOTP(_fullOtp, phoneNumber);

    if (!mounted) return;

    if (isSuccess) {
      _successController.forward();
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Fluttertoast.showToast(
        msg: '✅ Đăng nhập thành công!',
        backgroundColor: const Color(0xFF00C896),
        textColor: Colors.white,
      );
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => HomePage(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else {
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      Fluttertoast.showToast(
        msg: '❌ Mã OTP không đúng',
        backgroundColor: const Color(0xFFFF4B4B),
        textColor: Colors.white,
      );
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
    if (_fullOtp.length == 6) {
      Future.delayed(const Duration(milliseconds: 100), _verifyOTP);
    }
    setState(() {});
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountryPickerSheet(
        countries: _countryCodes,
        selected: _selectedCountryCode,
        onSelect: ({required code, required flag}) {
          setState(() {
            _selectedCountryCode = code;
            _selectedFlag = flag;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phoneAuthProvider = context.watch<PhoneAuthProvider>();
    final isCodeSent =
        phoneAuthProvider.status == PhoneAuthStatus.codeSent;
    final isLoading =
        phoneAuthProvider.status == PhoneAuthStatus.authenticating;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
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

          // Subtle orb
          Positioned(
            top: -100,
            right: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF4F8DFF).withOpacity(0.12),
                    const Color(0xFF4F8DFF).withOpacity(0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _GlassIconButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      Text(
                        'Đăng nhập',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),

                Expanded(
                  child: SlideTransition(
                    position: _entrySlide,
                    child: FadeTransition(
                      opacity: _entryFade,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Phone icon & title
                              Center(
                                child: AnimatedSwitcher(
                                  duration:
                                  const Duration(milliseconds: 400),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(
                                          scale: anim, child: child),
                                  child: isCodeSent
                                      ? ScaleTransition(
                                    key: const ValueKey('otp'),
                                    scale: _successScale,
                                    child: _PhoneIllustration(
                                        isOtp: true),
                                  )
                                      : const _PhoneIllustration(
                                    key: ValueKey('phone'),
                                    isOtp: false,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Animated title
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Column(
                                  key: ValueKey(isCodeSent),
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isCodeSent
                                          ? 'Nhập mã xác minh'
                                          : 'Nhập số điện thoại',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isCodeSent
                                          ? 'Chúng tôi đã gửi mã 6 chữ số đến\n$_selectedCountryCode ${_phoneController.text}'
                                          : 'Chúng tôi sẽ gửi mã xác minh\nqua SMS đến số của bạn',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.45),
                                        fontSize: 14,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Phone input or OTP
                              if (!isCodeSent) ...[
                                _PhoneInputField(
                                  controller: _phoneController,
                                  countryCode: _selectedCountryCode,
                                  flag: _selectedFlag,
                                  isFocused: _phoneFieldFocused,
                                  onCountryTap: _showCountryPicker,
                                  onFocusChange: (v) => setState(
                                          () => _phoneFieldFocused = v),
                                ),
                                const SizedBox(height: 28),
                                _PrimaryButton(
                                  label: 'Gửi mã OTP',
                                  onTap: isLoading ? null : _sendOTP,
                                  isLoading: isLoading,
                                ),
                              ] else ...[
                                // OTP boxes
                                AnimatedBuilder(
                                  animation: _shakeAnim,
                                  builder: (_, child) {
                                    final shake = (_shakeAnim.value * 8 *
                                        (1 - _shakeAnim.value))
                                        .clamp(-8.0, 8.0);
                                    return Transform.translate(
                                      offset: Offset(shake, 0),
                                      child: child,
                                    );
                                  },
                                  child: _OtpInputRow(
                                    controllers: _otpControllers,
                                    focusNodes: _otpFocusNodes,
                                    onChanged: _onOtpChanged,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                _PrimaryButton(
                                  label: 'Xác minh',
                                  onTap: isLoading ? null : _verifyOTP,
                                  isLoading: isLoading,
                                ),
                                const SizedBox(height: 20),
                                Center(
                                  child: _resendSeconds > 0
                                      ? Text(
                                    'Gửi lại sau $_resendSeconds giây',
                                    style: TextStyle(
                                      color: Colors.white
                                          .withOpacity(0.4),
                                      fontSize: 13,
                                    ),
                                  )
                                      : GestureDetector(
                                    onTap: _sendOTP,
                                    child: const Text(
                                      'Gửi lại mã OTP',
                                      style: TextStyle(
                                        color: Color(0xFF4F8DFF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        decoration:
                                        TextDecoration.underline,
                                        decorationColor:
                                        Color(0xFF4F8DFF),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: GestureDetector(
                                    onTap: () {
                                      context
                                          .read<PhoneAuthProvider>()
                                          .resetStatus();
                                      for (var c in _otpControllers) {
                                        c.clear();
                                      }
                                    },
                                    child: Text(
                                      'Thay đổi số điện thoại',
                                      style: TextStyle(
                                        color:
                                        Colors.white.withOpacity(0.35),
                                        fontSize: 13,
                                        decoration:
                                        TextDecoration.underline,
                                        decorationColor:
                                        Colors.white.withOpacity(0.35),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (isLoading)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: const Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: Color(0xFF4F8DFF),
                        strokeWidth: 2.5,
                      ),
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

// ─── Phone Illustration ───────────────────────────────────────────────────────

class _PhoneIllustration extends StatelessWidget {
  final bool isOtp;
  const _PhoneIllustration({super.key, required this.isOtp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: isOtp
              ? [const Color(0xFF00C896), const Color(0xFF00A67E)]
              : [const Color(0xFF4F8DFF), const Color(0xFF7B4FFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOtp ? const Color(0xFF00C896) : const Color(0xFF4F8DFF))
                .withOpacity(0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        isOtp ? Icons.shield_rounded : Icons.phone_rounded,
        color: Colors.white,
        size: 42,
      ),
    );
  }
}

// ─── Phone Input Field ────────────────────────────────────────────────────────

class _PhoneInputField extends StatelessWidget {
  final TextEditingController controller;
  final String countryCode;
  final String flag;
  final bool isFocused;
  final VoidCallback onCountryTap;
  final ValueChanged<bool> onFocusChange;

  const _PhoneInputField({
    required this.controller,
    required this.countryCode,
    required this.flag,
    required this.isFocused,
    required this.onCountryTap,
    required this.onFocusChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Số điện thoại',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFocused
                  ? const Color(0xFF4F8DFF).withOpacity(0.6)
                  : Colors.white.withOpacity(0.1),
              width: isFocused ? 1.5 : 1.0,
            ),
            color: Colors.white.withOpacity(0.05),
          ),
          child: Row(
            children: [
              // Country picker
              GestureDetector(
                onTap: onCountryTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(flag, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(
                        countryCode,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withOpacity(0.4),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),

              // Phone number field
              Expanded(
                child: Focus(
                  onFocusChange: onFocusChange,
                  child: TextFormField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: '0XX XXX XXXX',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.25),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Vui lòng nhập số điện thoại';
                      }
                      if (v.length < 9) {
                        return 'Số điện thoại không hợp lệ';
                      }
                      return null;
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── OTP Input Row ────────────────────────────────────────────────────────────

class _OtpInputRow extends StatelessWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final void Function(int, String) onChanged;

  const _OtpInputRow({
    required this.controllers,
    required this.focusNodes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(
        6,
            (i) => _OtpBox(
          controller: controllers[i],
          focusNode: focusNodes[i],
          onChanged: (v) => onChanged(i, v),
        ),
      ),
    );
  }
}

class _OtpBox extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(() {
      setState(() => _focused = widget.focusNode.hasFocus);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 46,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused
              ? const Color(0xFF4F8DFF)
              : hasValue
              ? const Color(0xFF4F8DFF).withOpacity(0.4)
              : Colors.white.withOpacity(0.1),
          width: _focused ? 2.0 : 1.0,
        ),
        color: hasValue
            ? const Color(0xFF4F8DFF).withOpacity(0.08)
            : Colors.white.withOpacity(0.04),
        boxShadow: _focused
            ? [
          BoxShadow(
            color: const Color(0xFF4F8DFF).withOpacity(0.2),
            blurRadius: 12,
            spreadRadius: -2,
          )
        ]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          counterText: '',
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: widget.onChanged,
      ),
    );
  }
}

// ─── Primary Button ───────────────────────────────────────────────────────────

class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null
          ? (_) => _pressCtrl.forward()
          : null,
      onTapUp: widget.onTap != null
          ? (_) {
        _pressCtrl.reverse();
        widget.onTap?.call();
      }
          : null,
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF4F8DFF), Color(0xFF7B4FFF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F8DFF).withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
                : Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Glass Icon Button ────────────────────────────────────────────────────────

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withOpacity(0.08),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
          ),
        ),
      ),
    );
  }
}

// ─── Country Picker Sheet ─────────────────────────────────────────────────────

typedef _Country = ({String code, String flag, String name});

class _CountryPickerSheet extends StatefulWidget {
  final List<_Country> countries;
  final String selected;
  final void Function({required String code, required String flag}) onSelect;

  const _CountryPickerSheet({
    required this.countries,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.countries
        .where((c) =>
    c.name.toLowerCase().contains(_search.toLowerCase()) ||
        c.code.contains(_search))
        .toList();

    return ClipRRect(
      borderRadius:
      const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: const Color(0xFF0D1B3E).withOpacity(0.95),
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withOpacity(0.07),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.1)),
                  ),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm quốc gia...',
                      hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 14),
                      prefixIcon: Icon(Icons.search,
                          color: Colors.white.withOpacity(0.4),
                          size: 20),
                      border: InputBorder.none,
                      contentPadding:
                      const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final isSelected = c.code == widget.selected;
                    return ListTile(
                      leading: Text(c.flag,
                          style: const TextStyle(fontSize: 22)),
                      title: Text(
                        c.name,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      trailing: Text(
                        c.code,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF4F8DFF)
                              : Colors.white.withOpacity(0.45),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () {
                        widget.onSelect(
                            code: c.code, flag: c.flag);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}