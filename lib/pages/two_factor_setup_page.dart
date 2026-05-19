
import 'dart:math';

import 'package:flutter/material.dart';
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

class _TwoFactorSetupPageState extends State<TwoFactorSetupPage> {
  late String _secret;
  late String _qrUri;
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _generateSecret();
  }

  void _generateSecret() {
    
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final rnd = Random.secure();
    _secret =
        List.generate(16, (index) => chars[rnd.nextInt(chars.length)]).join();

    final nickname =
        context.read<SettingProvider>().getPref(FirestoreConstants.nickname) ??
            'User';
    
    _qrUri =
        'otpauth://totp/AppChatPlus:$nickname?secret=$_secret&issuer=AppChatPlus';
  }

  void _verifyAndEnable() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      Fluttertoast.showToast(msg: "Vui lòng nhập đủ 6 số");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final isValid = OTP.generateTOTPCodeString(
              _secret, DateTime.now().millisecondsSinceEpoch) ==
          code;

      if (isValid) {
        final settingProvider = context.read<SettingProvider>();
        final userId = settingProvider.getPref(FirestoreConstants.id);

        await settingProvider.updateDataFirestore(
            FirestoreConstants.pathUserCollection,
            userId!,
            {'is2FAEnabled': true, 'twoFactorSecret': _secret});

        await settingProvider.setPref('is2FAEnabled', true);
        await settingProvider.setPref('twoFactorSecret', _secret);

        Fluttertoast.showToast(msg: "Kích hoạt 2FA thành công!");
        Navigator.pop(context);
      } else {
        Fluttertoast.showToast(msg: "Mã xác thực không hợp lệ");
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Lỗi: ${e.toString()}");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thiết lập 2FA')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    "Sử dụng Google Authenticator hoặc ứng dụng quét mã tương tự để quét mã QR dưới đây:",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: QrImageView(
                      data: _qrUri,
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text("Khóa dự phòng (Secret Key):\n$_secret",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 32),
                  const Text("Nhập mã 6 số từ ứng dụng để xác nhận:"),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: "000000",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _verifyAndEnable,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: ColorConstants.primaryColor),
                      child: const Text('Kích hoạt',
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
