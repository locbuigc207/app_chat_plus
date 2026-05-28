import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/color_constants.dart';
import 'package:flutter_chat_demo/constants/firestore_constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:otp/otp.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

class TwoFactorSetupPage extends StatefulWidget {
  const TwoFactorSetupPage({super.key});

  @override
  State<TwoFactorSetupPage> createState() => _TwoFactorSetupPageState();
}

class _TwoFactorSetupPageState extends State<TwoFactorSetupPage>
    with TickerProviderStateMixin {
  late String _secret;
  late String _qrUri;
  late String _nickname;

  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isVerifying = false;
  int _currentStep = 0; // 0 = scan QR, 1 = enter code

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // TOTP countdown
  late Timer _timer;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _generateSecret();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _fadeCtrl.forward();
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

    _nickname =
        context.read<SettingProvider>().getPref(FirestoreConstants.nickname) ??
            'User';
    _qrUri =
        'otpauth://totp/AppChatPlus:$_nickname?secret=$_secret&issuer=AppChatPlus';
  }

  String get _enteredCode => _controllers.map((c) => c.text.trim()).join();

  void _onOtpDigit(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  void _nextStep() {
    _fadeCtrl.reset();
    setState(() => _currentStep = 1);
    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 100), () {
      _focusNodes[0].requestFocus();
    });
  }

  void _prevStep() {
    _fadeCtrl.reset();
    setState(() {
      _currentStep = 0;
      for (final c in _controllers) {
        c.clear();
      }
    });
    _fadeCtrl.forward();
  }

  Future<void> _verifyAndEnable() async {
    final code = _enteredCode;
    if (code.length != 6) {
      _showError("Vui lòng nhập đủ 6 chữ số");
      return;
    }

    setState(() => _isVerifying = true);

    await Future.delayed(const Duration(milliseconds: 400));

    final isValid = OTP.generateTOTPCodeString(
            _secret, DateTime.now().millisecondsSinceEpoch) ==
        code;

    if (!mounted) return;

    if (isValid) {
      setState(() => _isLoading = true);
      try {
        final settingProvider = context.read<SettingProvider>();
        final userId = settingProvider.getPref(FirestoreConstants.id);

        await settingProvider.updateDataFirestore(
          FirestoreConstants.pathUserCollection,
          userId!,
          {'is2FAEnabled': true, 'twoFactorSecret': _secret},
        );
        await settingProvider.setPref('is2FAEnabled', true);
        await settingProvider.setPref('twoFactorSecret', _secret);

        if (mounted) {
          _showSuccess("Kích hoạt 2FA thành công!");
          await Future.delayed(const Duration(milliseconds: 800));
          Navigator.pop(context, true);
        }
      } catch (e) {
        _showError("Lỗi kết nối: ${e.toString()}");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      _showError("Mã xác thực không đúng. Vui lòng thử lại.");
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
      msg: "Đã sao chép khóa bí mật",
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );
  }

  void _showError(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: Colors.red.shade700,
      textColor: Colors.white,
    );
  }

  void _showSuccess(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: Colors.green.shade700,
      textColor: Colors.white,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF8F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white : Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Bảo mật 2 lớp',
          style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStepIndicator(),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: _currentStep == 0
                        ? _buildScanStep()
                        : _buildVerifyStep(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      child: Row(
        children: [
          _stepDot(0, "Quét mã"),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: _currentStep >= 1
                    ? ColorConstants.primaryColor
                    : Colors.grey.shade300,
              ),
            ),
          ),
          _stepDot(1, "Xác nhận"),
        ],
      ),
    );
  }

  Widget _stepDot(int step, String label) {
    final active = _currentStep >= step;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? ColorConstants.primaryColor : Colors.grey.shade200,
          ),
          child: Center(
            child: active
                ? (step < _currentStep
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : Text('${step + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)))
                : Text('${step + 1}',
                    style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color:
                    active ? ColorConstants.primaryColor : Colors.grey.shade400,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      ],
    );
  }

  // ── Step 1: Scan QR ──────────────────────────────────────────────────

  Widget _buildScanStep() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.grey.shade100),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 4))
                    ],
            ),
            child: Column(
              children: [
                // QR Container
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: _qrUri,
                    version: QrVersions.auto,
                    size: 180.0,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Khóa bí mật thủ công',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _copySecret,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: ColorConstants.primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: ColorConstants.primaryColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatSecret(_secret),
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.5,
                              color: ColorConstants.primaryColor),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.copy_rounded,
                            size: 16, color: ColorConstants.primaryColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildInstructionCard(),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: ColorConstants.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Đã quét xong',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSecret(String s) {
    return s.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m.group(0)} ').trim();
  }

  Widget _buildInstructionCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final steps = [
      (
        Icons.download_rounded,
        'Tải Google Authenticator hoặc ứng dụng tương tự'
      ),
      (Icons.qr_code_scanner_rounded, 'Nhấn nút "+" rồi quét mã QR phía trên'),
      (Icons.check_circle_rounded, 'Nhập mã 6 số hiển thị vào bước tiếp theo'),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color:
                isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hướng dẫn',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 14),
          ...steps.asMap().entries.map((entry) {
            final i = entry.key;
            final (icon, text) = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 12 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: ColorConstants.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon,
                        size: 17, color: ColorConstants.primaryColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(text,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade700)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Step 2: Verify Code ───────────────────────────────────────────────

  Widget _buildVerifyStep() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _secondsLeft / 30.0;
    final isExpiring = _secondsLeft <= 10;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Icon with countdown ring
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      isExpiring ? Colors.red : ColorConstants.primaryColor),
                ),
              ),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ColorConstants.primaryColor.withOpacity(0.1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$_secondsLeft',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isExpiring
                              ? Colors.red
                              : ColorConstants.primaryColor),
                    ),
                    Text('giây',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Nhập mã từ Authenticator',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 8),
          Text(
            'Mã 6 số đang hiển thị trong ứng dụng của bạn.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 32),
          // OTP boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) => _buildOtpBox(i)),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isVerifying ? null : _verifyAndEnable,
              style: ElevatedButton.styleFrom(
                backgroundColor: ColorConstants.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor:
                    ColorConstants.primaryColor.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _isVerifying
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('Xác nhận & Kích hoạt',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: _prevStep,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Quay lại quét mã'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpBox(int index) {
    final isFilled = _controllers[index].text.isNotEmpty;
    final isFocused = _focusNodes[index].hasFocus;

    return Container(
      width: 46,
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isFilled
            ? ColorConstants.primaryColor.withOpacity(0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: isFocused ? 2.0 : 1.5,
          color: isFocused
              ? ColorConstants.primaryColor
              : isFilled
                  ? ColorConstants.primaryColor.withOpacity(0.4)
                  : Colors.grey.shade300,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                    color: ColorConstants.primaryColor.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]
            : [],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: TextField(
              controller: _controllers[index],
              focusNode: _focusNodes[index],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: ColorConstants.primaryColor),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => _onOtpDigit(index, v),
              onSubmitted: (_) {
                if (index == 5 && _enteredCode.length == 6) {
                  _verifyAndEnable();
                }
              },
            ),
          ),
          if (!isFilled)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    width: 8,
                    height: 2,
                    color: Colors.grey.shade300,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
