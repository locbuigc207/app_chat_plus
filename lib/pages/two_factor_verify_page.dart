// lib/pages/two_factor_verify_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/color_constants.dart';
import 'package:flutter_chat_demo/pages/home_page.dart';
import 'package:flutter_chat_demo/pages/login_page.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:otp/otp.dart';
import 'package:provider/provider.dart';

class TwoFactorVerifyPage extends StatefulWidget {
  const TwoFactorVerifyPage({Key? key}) : super(key: key);

  @override
  State<TwoFactorVerifyPage> createState() => _TwoFactorVerifyPageState();
}

class _TwoFactorVerifyPageState extends State<TwoFactorVerifyPage> {
  final TextEditingController _codeController = TextEditingController();

  void _verifyLogin() async {
    final authProvider = context.read<AuthProvider>();
    final code = _codeController.text.trim();

    if (code.length != 6) {
      Fluttertoast.showToast(msg: "Vui lòng nhập mã 6 số");
      return;
    }

    final secret = authProvider.tempUserChat?.twoFactorSecret;
    if (secret == null || secret.isEmpty) {
      Fluttertoast.showToast(msg: "Lỗi dữ liệu 2FA. Vui lòng đăng nhập lại.");
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => LoginPage()));
      return;
    }

    final isValid = OTP.generateTOTPCodeString(
            secret, DateTime.now().millisecondsSinceEpoch) ==
        code;

    if (isValid) {
      await authProvider.complete2FALogin(); // Lưu SharedPrefs
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => HomePage()));
    } else {
      Fluttertoast.showToast(msg: "Mã xác minh không chính xác!");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác minh 2 lớp'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.read<AuthProvider>().handleSignOut();
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => LoginPage()));
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_clock,
                size: 80, color: ColorConstants.primaryColor),
            const SizedBox(height: 24),
            const Text(
              "Tài khoản của bạn được bảo vệ bằng 2FA.\nVui lòng nhập mã từ ứng dụng Authenticator.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, letterSpacing: 12),
              decoration: InputDecoration(
                hintText: "------",
                counterText: "",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _verifyLogin,
                style: ElevatedButton.styleFrom(
                    backgroundColor: ColorConstants.primaryColor),
                child: const Text('Xác minh & Đăng nhập',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
