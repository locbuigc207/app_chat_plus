import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';





class MyQRCodePage extends StatefulWidget {
  const MyQRCodePage({super.key});

  @override
  State<MyQRCodePage> createState() => _MyQRCodePageState();
}

class _MyQRCodePageState extends State<MyQRCodePage> with SingleTickerProviderStateMixin {
  String _qrCode = '';
  String _nickname = '';
  String _phoneNumber = '';
  bool _isLoading = true;

  late final AnimationController _entryCtrl;
  late final Animation<double> _scaleFade;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack);
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
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  void _copyQrCode() {
    if (_qrCode.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _qrCode));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Đã sao chép mã QR'),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? ColorConstants.backgroundDark : const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white70 : ColorConstants.primaryColor,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Mã QR của tôi',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1A1D2E),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.share_rounded,
                color: isDark ? Colors.white70 : ColorConstants.primaryColor),
            onPressed: () {
              
              HapticFeedback.lightImpact();
            },
            tooltip: 'Chia sẻ',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: ColorConstants.primaryColor, strokeWidth: 2))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
              child: Column(
                children: [
                  
                  Text(
                    'Quét để kết bạn',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cho bạn bè quét mã này để thêm bạn',
                    style: TextStyle(color: ColorConstants.greyColor, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  
                  ScaleTransition(
                    scale: _scaleFade,
                    child: FadeTransition(
                      opacity: CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: isDark ? ColorConstants.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: ColorConstants.primaryColor
                                  .withValues(alpha: isDark ? 0.15 : 0.1),
                              blurRadius: 40,
                              spreadRadius: 4,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : ColorConstants.primaryColor.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Column(
                          children: [
                            
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: ColorConstants.primaryColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor:
                                        ColorConstants.primaryColor.withValues(alpha: 0.12),
                                    child: Text(
                                      _nickname.isNotEmpty ? _nickname[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        color: ColorConstants.primaryColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _nickname.isEmpty ? 'Người dùng' : _nickname,
                                    style: TextStyle(
                                      color: ColorConstants.primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            
                            _qrCode.isNotEmpty
                                ? Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: ColorConstants.primaryColor.withValues(alpha: 0.15),
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: QrImageView(
                                        data: _qrCode,
                                        version: QrVersions.auto,
                                        size: 220,
                                        backgroundColor: Colors.white,
                                        eyeStyle: QrEyeStyle(
                                          eyeShape: QrEyeShape.square,
                                          color: ColorConstants.primaryColor,
                                        ),
                                        dataModuleStyle: QrDataModuleStyle(
                                          dataModuleShape: QrDataModuleShape.square,
                                          color: const Color(0xFF1A1D2E),
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 220,
                                    height: 220,
                                    decoration: BoxDecoration(
                                      color: ColorConstants.greyColor2,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.qr_code_2_rounded,
                                            size: 64,
                                            color: ColorConstants.greyColor.withValues(alpha: 0.5)),
                                        const SizedBox(height: 8),
                                        const Text('Mã QR chưa sẵn sàng',
                                            style: TextStyle(
                                                color: ColorConstants.greyColor, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? ColorConstants.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Biệt danh',
                          value: _nickname.isNotEmpty ? _nickname : '—',
                          isDark: isDark,
                        ),
                        if (_phoneNumber.isNotEmpty) ...[
                          Divider(
                              height: 20,
                              color:
                                  isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.07)),
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Số điện thoại',
                            value: _phoneNumber,
                            isDark: isDark,
                          ),
                        ],
                        if (_qrCode.isNotEmpty) ...[
                          Divider(
                              height: 20,
                              color:
                                  isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.07)),
                          _InfoRow(
                            icon: Icons.tag_rounded,
                            label: 'Mã QR ID',
                            value: _qrCode.length > 22 ? '${_qrCode.substring(0, 22)}…' : _qrCode,
                            isDark: isDark,
                            trailing: GestureDetector(
                              onTap: _copyQrCode,
                              child: Icon(Icons.copy_rounded,
                                  size: 16, color: ColorConstants.primaryColor),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _qrCode.isNotEmpty ? _copyQrCode : null,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Sao chép mã QR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ColorConstants.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}





class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: ColorConstants.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: ColorConstants.primaryColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                    color: ColorConstants.greyColor, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
