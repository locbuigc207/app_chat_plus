import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/phone_auth_provider.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

class PhoneLoginPage extends StatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  State<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _selectedCountryCode = '+84'; // Vietnam default

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _sendOTP() {
    if (_formKey.currentState!.validate()) {
      final phoneNumber = _selectedCountryCode + _phoneController.text.trim();
      context.read<PhoneAuthProvider>().sendOTP(phoneNumber);
    }
  }

  void _verifyOTP() async {
    final phoneNumber = _selectedCountryCode + _phoneController.text.trim();
    final phoneAuthProvider = context.read<PhoneAuthProvider>();

    final isSuccess = await phoneAuthProvider.verifyOTP(
      _otpController.text.trim(),
      phoneNumber,
    );

    if (isSuccess) {
      Fluttertoast.showToast(msg: "Login successful");
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage()),
      );
    } else {
      Fluttertoast.showToast(msg: "Invalid OTP");
    }
  }

  @override
  Widget build(BuildContext context) {
    final phoneAuthProvider = context.watch<PhoneAuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Phone Login',
          style: TextStyle(color: ColorConstants.primaryColor),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 40),

                  // Logo or Icon
                  Icon(
                    Icons.phone_android,
                    size: 100,
                    color: ColorConstants.primaryColor,
                  ),
                  SizedBox(height: 40),

                  // Phone Number Input
                  Text(
                    'Enter your phone number',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: ColorConstants.primaryColor,
                    ),
                  ),
                  SizedBox(height: 16),

                  Row(
                    children: [
                      // Country Code Dropdown
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: ColorConstants.greyColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedCountryCode,
                          underline: SizedBox(),
                          items: [
                            DropdownMenuItem(value: '+84', child: Text('+84 🇻🇳')),
                            DropdownMenuItem(value: '+1', child: Text('+1 🇺🇸')),
                            DropdownMenuItem(value: '+44', child: Text('+44 🇬🇧')),
                            DropdownMenuItem(value: '+91', child: Text('+91 🇮🇳')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedCountryCode = value!;
                            });
                          },
                        ),
                      ),
                      SizedBox(width: 12),

                      // Phone Number Field
                      Expanded(
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: 'Phone number',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter phone number';
                            }
                            if (value.length < 9) {
                              return 'Invalid phone number';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24),

                  // Send OTP Button
                  if (phoneAuthProvider.status != PhoneAuthStatus.codeSent)
                    ElevatedButton(
                      onPressed: phoneAuthProvider.status == PhoneAuthStatus.authenticating
                          ? null
                          : _sendOTP,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ColorConstants.primaryColor,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Send OTP',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),

                  // OTP Input Section
                  if (phoneAuthProvider.status == PhoneAuthStatus.codeSent) ...[
                    SizedBox(height: 24),
                    Text(
                      'Enter OTP',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: ColorConstants.primaryColor,
                      ),
                    ),
                    SizedBox(height: 16),

                    TextFormField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        hintText: '6-digit OTP',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    SizedBox(height: 16),

                    // Verify OTP Button
                    ElevatedButton(
                      onPressed: phoneAuthProvider.status == PhoneAuthStatus.authenticating
                          ? null
                          : _verifyOTP,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ColorConstants.primaryColor,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Verify OTP',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    // Resend OTP
                    SizedBox(height: 16),
                    TextButton(
                      onPressed: _sendOTP,
                      child: Text(
                        'Resend OTP',
                        style: TextStyle(
                          color: ColorConstants.primaryColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Loading Overlay
          if (phoneAuthProvider.status == PhoneAuthStatus.authenticating)
            Positioned.fill(
              child: LoadingView(),
            ),
        ],
      ),
    );
  }
}