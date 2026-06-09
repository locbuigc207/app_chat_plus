import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyQRCodePage extends StatefulWidget {
  const MyQRCodePage({super.key});

  @override
  State<MyQRCodePage> createState() => _MyQRCodePageState();
}

class _MyQRCodePageState extends State<MyQRCodePage>
    with SingleTickerProviderStateMixin {
  String _qrCode = '';
  String _nickname = '';
  String _phoneNumber = '';
  bool _isLoading = true;

  late final AnimationController _entryCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack);
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _loadUserData();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
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

  void _copyQrCode() {
    if (_qrCode.isEmpty) return;

    Clipboard.setData(ClipboardData(text: _qrCode));
    HapticFeedback.lightImpact();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        SizedBox(width: 8),
        Text('Đã sao chép mã QR')
      ]),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
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
          systemOverlayStyle: theme.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: theme.primaryColor, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Mã QR của tôi',
              style: TextStyle(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(Icons.share_rounded, color: theme.primaryColor),
              onPressed: () => HapticFeedback.lightImpact(),
              tooltip: 'Chia sẻ',
            ),
          ],
        ),
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                    color: theme.primaryColor, strokeWidth: 2))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                child: Column(children: [
                  // Hero text
                  Text('Quét để kết bạn',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: p.textPrimary,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text('Cho bạn bè quét mã này để thêm bạn',
                      style: TextStyle(color: p.textSecondary, fontSize: 14),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 32),

                  // QR Card
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                              color: theme.primaryColor.withValues(alpha: 0.12),
                              width: 1.5),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    theme.primaryColor.withValues(alpha: 0.1),
                                blurRadius: 40,
                                spreadRadius: 4,
                                offset: const Offset(0, 8))
                          ],
                        ),
                        child: Column(children: [
                          // User badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: theme.primaryColor
                                      .withValues(alpha: 0.15)),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: [
                                    theme.primaryColor,
                                    theme.primaryLightColor
                                  ]),
                                ),
                                child: Center(
                                    child: Text(
                                  _nickname.isNotEmpty
                                      ? _nickname[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14),
                                )),
                              ),
                              const SizedBox(width: 10),
                              Text(_nickname.isEmpty ? 'Người dùng' : _nickname,
                                  style: TextStyle(
                                      color: theme.primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                            ]),
                          ),
                          const SizedBox(height: 24),

                          // QR Code
                          _qrCode.isNotEmpty
                              ? Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.08),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4))
                                    ],
                                  ),
                                  child: QrImageView(
                                    data: _qrCode,
                                    version: QrVersions.auto,
                                    size: 200,
                                    backgroundColor: Colors.white,
                                    eyeStyle: QrEyeStyle(
                                        eyeShape: QrEyeShape.square,
                                        color: theme.primaryColor),
                                    dataModuleStyle: const QrDataModuleStyle(
                                        dataModuleShape:
                                            QrDataModuleShape.square,
                                        color: Color(0xFF1A1D2E)),
                                  ),
                                )
                              : Container(
                                  width: 232,
                                  height: 232,
                                  decoration: BoxDecoration(
                                      color: p.surfaceVariant,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.qr_code_2_rounded,
                                            size: 64, color: p.textSecondary),
                                        const SizedBox(height: 8),
                                        Text('Mã QR chưa sẵn sàng',
                                            style: TextStyle(
                                                color: p.textSecondary,
                                                fontSize: 13)),
                                      ]),
                                ),
                          const SizedBox(height: 20),

                          // Scan hint
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                                color: p.surfaceVariant,
                                borderRadius: BorderRadius.circular(12)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.qr_code_scanner_rounded,
                                  size: 14, color: p.textSecondary),
                              const SizedBox(width: 6),
                              Text('Dùng camera để quét',
                                  style: TextStyle(
                                      color: p.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: p.divider, width: 0.6),
                    ),
                    child: Column(children: [
                      _InfoRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Biệt danh',
                          value: _nickname.isNotEmpty ? _nickname : '—',
                          palette: p,
                          primary: theme.primaryColor),
                      if (_phoneNumber.isNotEmpty) ...[
                        Divider(height: 18, color: p.divider),
                        _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Số điện thoại',
                            value: _phoneNumber,
                            palette: p,
                            primary: theme.primaryColor),
                      ],
                      if (_qrCode.isNotEmpty) ...[
                        Divider(height: 18, color: p.divider),
                        _InfoRow(
                          icon: Icons.tag_rounded,
                          label: 'Mã QR ID',
                          value: _qrCode.length > 22
                              ? '${_qrCode.substring(0, 22)}…'
                              : _qrCode,
                          palette: p,
                          primary: theme.primaryColor,
                          trailing: GestureDetector(
                              onTap: _copyQrCode,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                    color: theme.primaryColor
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.copy_rounded,
                                          size: 13, color: theme.primaryColor),
                                      const SizedBox(width: 4),
                                      Text('Copy',
                                          style: TextStyle(
                                              color: theme.primaryColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600)),
                                    ]),
                              )),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Copy button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _qrCode.isNotEmpty ? _copyQrCode : null,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Sao chép mã QR',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        disabledBackgroundColor: p.surfaceVariant,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ]),
              ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final ThemePalette palette;
  final Color primary;
  final Widget? trailing;

  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.palette,
      required this.primary,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: primary, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                color: palette.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: palette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ])),
      if (trailing != null) trailing!,
    ]);
  }
}
