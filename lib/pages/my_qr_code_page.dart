import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyQRCodePage extends StatefulWidget {
  const MyQRCodePage({super.key});

  @override
  State<MyQRCodePage> createState() => _MyQRCodePageState();
}

class _MyQRCodePageState extends State<MyQRCodePage> {
  String _qrCode = '';
  String _nickname = '';
  String _phoneNumber = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _qrCode = prefs.getString(FirestoreConstants.qrCode) ?? '';
      _nickname = prefs.getString(FirestoreConstants.nickname) ?? '';
      _phoneNumber = prefs.getString(FirestoreConstants.phoneNumber) ?? '';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My QR Code',
          style: TextStyle(color: ColorConstants.primaryColor),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // Title
            Text(
              'Share your QR code',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: ColorConstants.primaryColor,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'Let others scan this code to add you as a friend',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ColorConstants.greyColor,
              ),
            ),

            const SizedBox(height: 40),

            // QR Code
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: _qrCode.isNotEmpty
                  ? QrImageView(
                data: _qrCode,
                version: QrVersions.auto,
                size: 250.0,
                backgroundColor: Colors.white,
              )
                  : Container(
                width: 250,
                height: 250,
                alignment: Alignment.center,
                child: Text(
                  'QR Code not available',
                  style: TextStyle(
                    color: ColorConstants.greyColor,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // User Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ColorConstants.greyColor2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person,
                        color: ColorConstants.primaryColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nickname',
                              style: TextStyle(
                                color: ColorConstants.greyColor,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _nickname,
                              style: TextStyle(
                                color: ColorConstants.primaryColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_phoneNumber.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.phone,
                          color: ColorConstants.primaryColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Phone Number',
                                style: TextStyle(
                                  color: ColorConstants.greyColor,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _phoneNumber,
                                style: TextStyle(
                                  color: ColorConstants.primaryColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // QR Code ID
            Text(
              'QR Code ID: ${_qrCode.substring(0, _qrCode.length > 20 ? 20 : _qrCode.length)}...',
              style: TextStyle(
                color: ColorConstants.greyColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
