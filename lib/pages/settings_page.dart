import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with TickerProviderStateMixin {
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _aboutMeCtrl;
  final FocusNode _nicknameFocus = FocusNode();
  final FocusNode _aboutMeFocus = FocusNode();

  String _userId = '';
  String _nickname = '';
  String _aboutMe = '';
  String _avatarUrl = '';
  String _phoneNumber = '';
  String _qrCode = '';

  bool _is2FAEnabled = false;
  String _twoFactorSecretStr = '';

  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _hasUnsavedChanges = false;
  File? _avatarFile;

  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  late final SettingProvider _settingProvider = context.read<SettingProvider>();

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _readLocal();
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _nicknameCtrl.dispose();
    _aboutMeCtrl.dispose();
    _nicknameFocus.dispose();
    _aboutMeFocus.dispose();
    super.dispose();
  }

  void _readLocal() {
    setState(() {
      _userId = _settingProvider.getPref(FirestoreConstants.id) ?? '';
      _nickname = _settingProvider.getPref(FirestoreConstants.nickname) ?? '';
      _aboutMe = _settingProvider.getPref(FirestoreConstants.aboutMe) ?? '';
      _avatarUrl = _settingProvider.getPref(FirestoreConstants.photoUrl) ?? '';
      _phoneNumber = _settingProvider.getPref(FirestoreConstants.phoneNumber) ?? '';
      _qrCode = _settingProvider.getPref(FirestoreConstants.qrCode) ?? '';
      _is2FAEnabled = _settingProvider.getBoolPref('is2FAEnabled') ?? false;
      _twoFactorSecretStr = _settingProvider.getPref('twoFactorSecret') ?? '';
    });

    _nicknameCtrl = TextEditingController(text: _nickname);
    _aboutMeCtrl = TextEditingController(text: _aboutMe);

    _nicknameCtrl.addListener(_onFieldChanged);
    _aboutMeCtrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    final changed = _nicknameCtrl.text != _nickname || _aboutMeCtrl.text != _aboutMe;
    if (changed != _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = changed);
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 800,
          maxHeight: 800
      );

      if (picked == null) return;

      setState(() {
        _avatarFile = File(picked.path);
        _isUploadingAvatar = true;
      });

      final snapshot = await _settingProvider.uploadFile(_avatarFile!, _userId);
      final url = await snapshot.ref.getDownloadURL();
      final updateInfo = _buildUserChat(photoUrl: url);

      await _settingProvider.updateDataFirestore(FirestoreConstants.pathUserCollection, _userId, updateInfo.toJson());
      await _settingProvider.setPref(FirestoreConstants.photoUrl, url);

      setState(() {
        _avatarUrl = url;
        _isUploadingAvatar = false;
      });

      _showToast('✅ Ảnh đại diện đã cập nhật', isSuccess: true);
    } on FirebaseException catch (e) {
      setState(() => _isUploadingAvatar = false);
      _showToast(e.message ?? 'Lỗi tải ảnh lên');
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      _showToast('Lỗi: $e');
    }
  }

  Future<void> _saveProfile() async {
    _nicknameFocus.unfocus();
    _aboutMeFocus.unfocus();

    final newNick = _nicknameCtrl.text.trim();
    final newAbout = _aboutMeCtrl.text.trim();

    if (newNick.isEmpty) {
      _showToast('Tên hiển thị không được để trống');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isSaving = true);

    try {
      final info = _buildUserChat(nickname: newNick, aboutMe: newAbout);
      await _settingProvider.updateDataFirestore(FirestoreConstants.pathUserCollection, _userId, info.toJson());

      await Future.wait([
        _settingProvider.setPref(FirestoreConstants.nickname, newNick),
        _settingProvider.setPref(FirestoreConstants.aboutMe, newAbout),
      ]);

      setState(() {
        _nickname = newNick;
        _aboutMe = newAbout;
        _isSaving = false;
        _hasUnsavedChanges = false;
      });

      _showToast('✅ Hồ sơ đã được lưu', isSuccess: true);
    } catch (e) {
      setState(() => _isSaving = false);
      _showToast('Không thể lưu: $e');
    }
  }

  void _on2FAToggle(bool val, ThemeProvider theme) {
    if (val) {
      Navigator.push(context, _slideRoute(const TwoFactorSetupPage())).then((_) => _readLocal());
    } else {
      _showDisable2FADialog(theme);
    }
  }

  void _showDisable2FADialog(ThemeProvider theme) {
    final p = theme.palette;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Tắt xác thực 2 lớp?', style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('Tài khoản sẽ kém bảo mật hơn. Bạn có chắc không?',
            style: TextStyle(color: p.textSecondary, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Hủy', style: TextStyle(color: p.textSecondary))
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _settingProvider.updateDataFirestore(
                  FirestoreConstants.pathUserCollection, _userId, {'is2FAEnabled': false, 'twoFactorSecret': ''});
              await _settingProvider.setPref('is2FAEnabled', false);
              await _settingProvider.setPref('twoFactorSecret', '');

              setState(() {
                _is2FAEnabled = false;
                _twoFactorSecretStr = '';
              });

              _showToast('Đã tắt xác thực 2 lớp');
            },
            child: Text('Tắt 2FA', style: TextStyle(color: p.dangerColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  UserChat _buildUserChat({String? nickname, String? aboutMe, String? photoUrl}) => UserChat(
    id: _userId,
    photoUrl: photoUrl ?? _avatarUrl,
    nickname: nickname ?? _nickname,
    aboutMe: aboutMe ?? _aboutMe,
    phoneNumber: _phoneNumber,
    qrCode: _qrCode,
    is2FAEnabled: _is2FAEnabled,
    twoFactorSecret: _twoFactorSecretStr,
  );

  void _showToast(String msg, {bool isSuccess = false}) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: isSuccess ? Colors.green.shade700 : Colors.red.shade700,
      textColor: Colors.white,
    );
  }

  PageRoute _slideRoute(Widget page) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 300),
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(p, theme),
              Expanded(
                child: SlideTransition(
                  position: _entrySlide,
                  child: FadeTransition(
                    opacity: _entryFade,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                      child: Column(
                        children: [
                          _buildAvatarSection(p, theme),
                          const SizedBox(height: 28),
                          _buildProfileCard(p, theme),
                          const SizedBox(height: 16),
                          _buildSecurityCard(p, theme),
                          const SizedBox(height: 16),
                          _buildAppearanceCard(p, theme),
                          const SizedBox(height: 16),
                          _buildAccountCard(p, theme),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(ThemePalette p, ThemeProvider theme) {
    return Container(
      color: p.appBarBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
          children: [
            _CircleBtn(
              icon: Icons.arrow_back_ios_rounded,
              onTap: () => Navigator.pop(context),
              palette: p,
              primary: theme.primaryColor,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                  'Chỉnh sửa hồ sơ',
                  style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3
                  )
              ),
            ),
            AnimatedScale(
              scale: _hasUnsavedChanges ? 1.0 : 0.8,
              duration: const Duration(milliseconds: 200),
              child: AnimatedOpacity(
                opacity: _hasUnsavedChanges ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: _hasUnsavedChanges ? _saveProfile : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryLightColor]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: theme.primaryColor.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3)
                        )
                      ],
                    ),
                    child: _isSaving
                        ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    )
                        : const Text(
                        'Lưu',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)
                    ),
                  ),
                ),
              ),
            ),
          ]
      ),
    );
  }

  Widget _buildAvatarSection(ThemePalette p, ThemeProvider theme) {
    final initial = _nickname.isNotEmpty ? _nickname[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.divider, width: 0.6),
        boxShadow: [
          BoxShadow(color: p.shadow, blurRadius: 10, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
          children: [
            GestureDetector(
              onTap: _isUploadingAvatar ? null : _pickAvatar,
              child: Stack(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryLightColor]),
                        boxShadow: [
                          BoxShadow(
                              color: theme.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 6)
                          )
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: ClipOval(child: _buildAvatarContent(initial, p)),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryLightColor]),
                          shape: BoxShape.circle,
                          border: Border.all(color: p.background, width: 2.5),
                        ),
                        child: _isUploadingAvatar
                            ? const Padding(
                            padding: EdgeInsets.all(7),
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                            : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15),
                      ),
                    ),
                  ]
              ),
            ),
            const SizedBox(height: 14),
            Text(
                _nickname.isNotEmpty ? _nickname : 'Chưa đặt tên',
                style: TextStyle(
                    color: p.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4
                )
            ),
            if (_phoneNumber.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_phoneNumber, style: TextStyle(color: p.textSecondary, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_rounded, size: 12, color: theme.primaryColor),
                    const SizedBox(width: 5),
                    Text(
                        'Nhấn ảnh để thay đổi',
                        style: TextStyle(color: theme.primaryColor, fontSize: 11.5, fontWeight: FontWeight.w500)
                    ),
                  ]
              ),
            ),
          ]
      ),
    );
  }

  Widget _buildAvatarContent(String initial, ThemePalette p) {
    if (_avatarFile != null) return Image.file(_avatarFile!, fit: BoxFit.cover);
    if (_avatarUrl.isNotEmpty) {
      return Image.network(
          _avatarUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _InitialAvatar(initial: initial, palette: p)
      );
    }
    return _InitialAvatar(initial: initial, palette: p);
  }

  Widget _buildProfileCard(ThemePalette p, ThemeProvider theme) {
    return _SettingSection(
      title: 'Thông tin cá nhân',
      icon: Icons.person_outline_rounded,
      palette: p,
      primary: theme.primaryColor,
      children: [
        _InputField(
          icon: Icons.badge_outlined,
          label: 'Tên hiển thị',
          controller: _nicknameCtrl,
          focusNode: _nicknameFocus,
          palette: p,
          primary: theme.primaryColor,
        ),
        _SectionDivider(palette: p),
        _InputField(
          icon: Icons.info_outline_rounded,
          label: 'Giới thiệu',
          controller: _aboutMeCtrl,
          focusNode: _aboutMeFocus,
          maxLines: 3,
          palette: p,
          primary: theme.primaryColor,
        ),
        if (_phoneNumber.isNotEmpty) ...[
          _SectionDivider(palette: p),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
                children: [
                  Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10)
                      ),
                      child: Icon(Icons.phone_outlined, color: theme.primaryColor, size: 18)
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Số điện thoại',
                                style: TextStyle(
                                    color: theme.primaryColor.withValues(alpha: 0.7),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600
                                )
                            ),
                            const SizedBox(height: 3),
                            Text(
                                _phoneNumber,
                                style: TextStyle(color: p.textPrimary, fontSize: 15)
                            ),
                          ]
                      )
                  ),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                          color: Colors.green.shade500.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade400.withValues(alpha: 0.3))
                      ),
                      child: Text(
                          'Đã xác minh',
                          style: TextStyle(color: Colors.green.shade600, fontSize: 11, fontWeight: FontWeight.w600)
                      )
                  ),
                ]
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSecurityCard(ThemePalette p, ThemeProvider theme) {
    return _SettingSection(
      title: 'Bảo mật & Quyền riêng tư',
      icon: Icons.security_rounded,
      palette: p,
      primary: theme.primaryColor,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (_is2FAEnabled ? Colors.green.shade500 : theme.primaryColor).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      _is2FAEnabled ? Icons.verified_user_rounded : Icons.shield_outlined,
                      color: _is2FAEnabled ? Colors.green.shade500 : theme.primaryColor,
                      size: 20
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Xác thực 2 lớp (2FA)',
                              style: TextStyle(color: p.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600)
                          ),
                          const SizedBox(height: 2),
                          Text(
                              _is2FAEnabled ? 'Tài khoản đang được bảo vệ' : 'Bật để tăng cường bảo mật',
                              style: TextStyle(color: p.textSecondary, fontSize: 12)
                          ),
                        ]
                    )
                ),
                Switch(
                  value: _is2FAEnabled,
                  onChanged: (v) => _on2FAToggle(v, theme),
                  activeColor: Colors.green.shade500,
                  activeTrackColor: Colors.green.shade400.withValues(alpha: 0.25),
                  inactiveThumbColor: p.textSecondary,
                  inactiveTrackColor: p.divider,
                ),
              ]
          ),
        ),
        if (_is2FAEnabled && _twoFactorSecretStr.isNotEmpty) ...[
          _SectionDivider(palette: p),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
                children: [
                  Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: Colors.amber.shade400.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)
                      ),
                      child: Icon(Icons.key_rounded, color: Colors.amber.shade600, size: 20)
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Secret Key',
                                style: TextStyle(color: p.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)
                            ),
                            Text(
                                '${_twoFactorSecretStr.substring(0, 4)}··············',
                                style: TextStyle(color: p.textSecondary, fontSize: 12, fontFamily: 'monospace')
                            ),
                          ]
                      )
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _twoFactorSecretStr));
                      _showToast('Đã sao chép secret key', isSuccess: true);
                    },
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                            color: p.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: p.divider)
                        ),
                        child: Text(
                            'Sao chép',
                            style: TextStyle(color: p.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)
                        )
                    ),
                  ),
                ]
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAppearanceCard(ThemePalette p, ThemeProvider theme) {
    return _SettingSection(
      title: 'Giao diện',
      icon: Icons.palette_outlined,
      palette: p,
      primary: theme.primaryColor,
      children: [
        _ActionTile(
          icon: Icons.color_lens_outlined,
          iconColor: theme.primaryColor,
          label: 'Tuỳ chỉnh giao diện',
          subtitle: 'Màu sắc, bubble, font chữ, hình nền...',
          palette: p,
          onTap: () => Navigator.push(context, _slideRoute(const ThemeSettingsPage())),
        ),
      ],
    );
  }

  Widget _buildAccountCard(ThemePalette p, ThemeProvider theme) {
    return _SettingSection(
      title: 'Tài khoản',
      icon: Icons.manage_accounts_outlined,
      palette: p,
      primary: theme.primaryColor,
      children: [
        _ActionTile(
          icon: Icons.logout_rounded,
          iconColor: Colors.orange.shade600,
          label: 'Đăng xuất',
          palette: p,
          onTap: () => _confirmSignOut(p, theme),
        ),
        _SectionDivider(palette: p),
        _ActionTile(
          icon: Icons.delete_outline_rounded,
          iconColor: p.dangerColor,
          label: 'Xóa tài khoản',
          subtitle: 'Không thể hoàn tác',
          palette: p,
          labelColor: p.dangerColor,
          onTap: () => _confirmDeleteAccount(p, theme),
        ),
      ],
    );
  }

  void _confirmSignOut(ThemePalette p, ThemeProvider theme) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Đăng xuất?', style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700)),
        content: Text('Bạn chắc chắn muốn đăng xuất?', style: TextStyle(color: p.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Hủy', style: TextStyle(color: p.textSecondary))
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<AuthProvider>().handleSignOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
              }
            },
            child: Text('Đăng xuất', style: TextStyle(color: Colors.orange.shade600, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(ThemePalette p, ThemeProvider theme) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Xóa tài khoản?', style: TextStyle(color: p.dangerColor, fontWeight: FontWeight.w700)),
        content: Text('Hành động không thể hoàn tác. Tất cả dữ liệu sẽ bị xóa vĩnh viễn.',
            style: TextStyle(color: p.textSecondary, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Hủy', style: TextStyle(color: p.textSecondary))
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await context.read<AuthProvider>().deleteAccount();
              if (success && mounted) {
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
              }
            },
            child: Text('Xóa vĩnh viễn', style: TextStyle(color: p.dangerColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _InitialAvatar extends StatelessWidget {
  final String initial;
  final ThemePalette palette;

  const _InitialAvatar({required this.initial, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.surfaceVariant,
      child: Center(
          child: Text(
              initial,
              style: TextStyle(color: palette.textPrimary, fontSize: 38, fontWeight: FontWeight.w700)
          )
      ),
    );
  }
}

class _SettingSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final ThemePalette palette;
  final Color primary;
  final List<Widget> children;

  const _SettingSection({
    required this.title,
    required this.icon,
    required this.palette,
    required this.primary,
    required this.children
  });

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
                children: [
                  Icon(icon, size: 13, color: primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                      title.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: palette.textSecondary,
                          letterSpacing: 0.8
                      )
                  ),
                ]
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.divider, width: 0.6),
              boxShadow: [
                BoxShadow(
                    color: palette.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2)
                )
              ],
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(children: children)
            ),
          ),
        ]
    );
  }
}

class _InputField extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxLines;
  final ThemePalette palette;
  final Color primary;

  const _InputField({
    required this.icon,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.palette,
    required this.primary,
    this.maxLines = 1
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 14, top: 2),
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)
              ),
              child: Icon(icon, color: primary, size: 18),
            ),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          label,
                          style: TextStyle(
                              color: primary.withValues(alpha: 0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2
                          )
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: controller,
                        focusNode: focusNode,
                        maxLines: maxLines,
                        style: TextStyle(color: palette.textPrimary, fontSize: 15),
                        decoration: InputDecoration(
                          hintStyle: TextStyle(color: palette.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ]
                )
            ),
          ]
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final Color? labelColor;
  final ThemePalette palette;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.palette,
    required this.onTap,
    this.subtitle,
    this.labelColor
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11)
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            label,
                            style: TextStyle(
                                color: labelColor ?? palette.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500
                            )
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 1),
                          Text(
                              subtitle!,
                              style: TextStyle(color: palette.textSecondary, fontSize: 12)
                          ),
                        ],
                      ]
                  )
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textSecondary, size: 20),
            ]
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final ThemePalette palette;

  const _SectionDivider({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: 68, endIndent: 0, color: palette.divider);
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ThemePalette palette;
  final Color primary;

  const _CircleBtn({
    required this.icon,
    required this.onTap,
    required this.palette,
    required this.primary
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.divider)
        ),
        child: Icon(icon, color: palette.textPrimary, size: 19),
      ),
    );
  }
}