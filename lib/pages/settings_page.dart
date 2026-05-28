import 'dart:io';
import 'dart:ui';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  // ── Controllers & Focus ───────────────────────────────────────────────────
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _aboutMeCtrl;
  final FocusNode _nicknameFocus = FocusNode();
  final FocusNode _aboutMeFocus = FocusNode();

  // ── User State ────────────────────────────────────────────────────────────
  String _userId = '';
  String _nickname = '';
  String _aboutMe = '';
  String _avatarUrl = '';
  String _phoneNumber = '';
  String _qrCode = '';
  bool _is2FAEnabled = false;
  String _twoFactorSecret = '';

  // ── UI State ──────────────────────────────────────────────────────────────
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  File? _avatarFile;
  bool _hasUnsavedChanges = false;

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  late final SettingProvider _settingProvider = context.read<SettingProvider>();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

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

  // ── Data ──────────────────────────────────────────────────────────────────

  void _readLocal() {
    setState(() {
      _userId = _settingProvider.getPref(FirestoreConstants.id) ?? '';
      _nickname = _settingProvider.getPref(FirestoreConstants.nickname) ?? '';
      _aboutMe = _settingProvider.getPref(FirestoreConstants.aboutMe) ?? '';
      _avatarUrl = _settingProvider.getPref(FirestoreConstants.photoUrl) ?? '';
      _phoneNumber =
          _settingProvider.getPref(FirestoreConstants.phoneNumber) ?? '';
      _qrCode = _settingProvider.getPref(FirestoreConstants.qrCode) ?? '';
      _is2FAEnabled = _settingProvider.getPref('is2FAEnabled') == true;
      _twoFactorSecret = _settingProvider.getPref('twoFactorSecret') ?? '';
    });
    _nicknameCtrl = TextEditingController(text: _nickname);
    _aboutMeCtrl = TextEditingController(text: _aboutMe);

    _nicknameCtrl.addListener(_onFieldChanged);
    _aboutMeCtrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    final changed =
        _nicknameCtrl.text != _nickname || _aboutMeCtrl.text != _aboutMe;
    if (changed != _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = changed);
    }
  }

  // ── Avatar ────────────────────────────────────────────────────────────────

  Future<void> _pickAndUploadAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked == null) return;

      setState(() {
        _avatarFile = File(picked.path);
        _isUploadingAvatar = true;
      });

      await _uploadAvatarFile();
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      _showError('Không thể chọn ảnh: ${e.toString()}');
    }
  }

  Future<void> _uploadAvatarFile() async {
    try {
      final snapshot = await _settingProvider.uploadFile(_avatarFile!, _userId);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      final updateInfo = _buildUserChat(photoUrl: downloadUrl);
      await _settingProvider.updateDataFirestore(
        FirestoreConstants.pathUserCollection,
        _userId,
        updateInfo.toJson(),
      );
      await _settingProvider.setPref(FirestoreConstants.photoUrl, downloadUrl);

      setState(() {
        _avatarUrl = downloadUrl;
        _isUploadingAvatar = false;
      });

      _showSuccess('Ảnh đại diện đã được cập nhật');
    } on FirebaseException catch (e) {
      setState(() => _isUploadingAvatar = false);
      _showError(e.message ?? 'Lỗi tải ảnh lên');
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      _showError('Lỗi: ${e.toString()}');
    }
  }

  // ── Save Profile ──────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    _nicknameFocus.unfocus();
    _aboutMeFocus.unfocus();

    final newNickname = _nicknameCtrl.text.trim();
    final newAboutMe = _aboutMeCtrl.text.trim();

    if (newNickname.isEmpty) {
      _showError('Tên hiển thị không được để trống');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isSaving = true);

    try {
      final updateInfo = _buildUserChat(
        nickname: newNickname,
        aboutMe: newAboutMe,
      );

      await _settingProvider.updateDataFirestore(
        FirestoreConstants.pathUserCollection,
        _userId,
        updateInfo.toJson(),
      );

      await Future.wait([
        _settingProvider.setPref(FirestoreConstants.nickname, newNickname),
        _settingProvider.setPref(FirestoreConstants.aboutMe, newAboutMe),
      ]);

      setState(() {
        _nickname = newNickname;
        _aboutMe = newAboutMe;
        _isSaving = false;
        _hasUnsavedChanges = false;
      });

      _showSuccess('Hồ sơ đã được lưu');
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Không thể lưu: ${e.toString()}');
    }
  }

  // ── 2FA Toggle ────────────────────────────────────────────────────────────

  void _on2FAToggle(bool val) {
    if (val) {
      Navigator.push(
        context,
        _slideRoute(const TwoFactorSetupPage()),
      ).then((_) => _readLocal());
    } else {
      _showDisable2FADialog();
    }
  }

  void _showDisable2FADialog() {
    showDialog(
      context: context,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          backgroundColor: const Color(0xFF0D1B3E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Tắt xác thực 2 lớp?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Tài khoản của bạn sẽ kém bảo mật hơn. Bạn có chắc chắn muốn tắt 2FA không?',
            style: TextStyle(color: Colors.white.withOpacity(0.6), height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Hủy',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _settingProvider.updateDataFirestore(
                  FirestoreConstants.pathUserCollection,
                  _userId,
                  {'is2FAEnabled': false, 'twoFactorSecret': ''},
                );
                await _settingProvider.setPref('is2FAEnabled', false);
                await _settingProvider.setPref('twoFactorSecret', '');
                setState(() {
                  _is2FAEnabled = false;
                  _twoFactorSecret = '';
                });
                _showSuccess('Đã tắt xác thực 2 lớp');
              },
              child: const Text(
                'Tắt 2FA',
                style: TextStyle(
                    color: Color(0xFFFF4B4B), fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  UserChat _buildUserChat({
    String? nickname,
    String? aboutMe,
    String? photoUrl,
  }) {
    return UserChat(
      id: _userId,
      photoUrl: photoUrl ?? _avatarUrl,
      nickname: nickname ?? _nickname,
      aboutMe: aboutMe ?? _aboutMe,
      phoneNumber: _phoneNumber,
      qrCode: _qrCode,
      is2FAEnabled: _is2FAEnabled,
      twoFactorSecret: _twoFactorSecret,
    );
  }

  void _showSuccess(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: const Color(0xFF00C896),
      textColor: Colors.white,
    );
  }

  void _showError(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: const Color(0xFFFF4B4B),
      textColor: Colors.white,
    );
  }

  PageRoute _slideRoute(Widget page) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
        children: [
          // Background gradient
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
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF4F8DFF).withOpacity(0.08),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: SlideTransition(
                    position: _entrySlide,
                    child: FadeTransition(
                      opacity: _entryFade,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        child: Column(
                          children: [
                            _buildAvatarSection(),
                            const SizedBox(height: 28),
                            _buildProfileCard(),
                            const SizedBox(height: 16),
                            _buildSecurityCard(),
                            const SizedBox(height: 16),
                            _buildAccountCard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Global loading overlay
          if (_isSaving)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Center(
                    child: _GlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              color: Color(0xFF4F8DFF),
                              strokeWidth: 2.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Đang lưu...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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

  // ── App Bar ───────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _GlassIconBtn(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Chỉnh sửa hồ sơ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _hasUnsavedChanges ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: _GradientButton(
              label: 'Lưu',
              onTap: _hasUnsavedChanges ? _saveProfile : null,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  // ── Avatar Section ────────────────────────────────────────────────────────

  Widget _buildAvatarSection() {
    final initial = _nickname.isNotEmpty ? _nickname[0].toUpperCase() : '?';

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
            child: Stack(
              children: [
                // Avatar circle
                Container(
                  width: 106,
                  height: 106,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F8DFF), Color(0xFF7B4FFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F8DFF).withOpacity(0.3),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: ClipOval(
                      child: _buildAvatarContent(initial),
                    ),
                  ),
                ),

                // Camera badge
                Positioned(
                  right: 0,
                  bottom: 2,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F8DFF), Color(0xFF7B4FFF)],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0A0E1A),
                        width: 2.5,
                      ),
                    ),
                    child: _isUploadingAvatar
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _nickname.isNotEmpty ? _nickname : 'Chưa đặt tên',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          if (_phoneNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _phoneNumber,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatarContent(String initial) {
    if (_avatarFile != null) {
      return Image.file(_avatarFile!, fit: BoxFit.cover);
    }
    if (_avatarUrl.isNotEmpty) {
      return Image.network(
        _avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initials(initial),
      );
    }
    return _initials(initial);
  }

  Widget _initials(String initial) {
    return Container(
      color: const Color(0xFF0D1B3E),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Profile Card ──────────────────────────────────────────────────────────

  Widget _buildProfileCard() {
    return _SectionCard(
      title: 'Thông tin cá nhân',
      icon: Icons.person_outline_rounded,
      children: [
        _FieldRow(
          icon: Icons.badge_outlined,
          label: 'Tên hiển thị',
          child: TextField(
            controller: _nicknameCtrl,
            focusNode: _nicknameFocus,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Nhập tên của bạn',
              hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.25), fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        _divider(),
        _FieldRow(
          icon: Icons.info_outline_rounded,
          label: 'Giới thiệu',
          child: TextField(
            controller: _aboutMeCtrl,
            focusNode: _aboutMeFocus,
            maxLines: 3,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: 'Viết gì đó về bản thân...',
              hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.25), fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (_phoneNumber.isNotEmpty) ...[
          _divider(),
          _FieldRow(
            icon: Icons.phone_outlined,
            label: 'Số điện thoại',
            child: Row(
              children: [
                Text(
                  _phoneNumber,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                _Badge(
                  label: 'Đã xác minh',
                  color: const Color(0xFF00C896),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Security Card ─────────────────────────────────────────────────────────

  Widget _buildSecurityCard() {
    return _SectionCard(
      title: 'Bảo mật',
      icon: Icons.security_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (_is2FAEnabled
                          ? const Color(0xFF00C896)
                          : const Color(0xFF4F8DFF))
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _is2FAEnabled
                      ? Icons.verified_user_rounded
                      : Icons.shield_outlined,
                  color: _is2FAEnabled
                      ? const Color(0xFF00C896)
                      : const Color(0xFF4F8DFF),
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Xác thực 2 lớp (2FA)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _is2FAEnabled
                          ? 'Tài khoản được bảo vệ'
                          : 'Bật để tăng cường bảo mật',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _is2FAEnabled,
                onChanged: _on2FAToggle,
                activeColor: const Color(0xFF00C896),
                activeTrackColor: const Color(0xFF00C896).withOpacity(0.25),
                inactiveThumbColor: Colors.white.withOpacity(0.4),
                inactiveTrackColor: Colors.white.withOpacity(0.1),
              ),
            ],
          ),
        ),
        if (_is2FAEnabled) ...[
          _divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.qr_code_rounded,
                    color: Color(0xFFFFB300),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Secret Key',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _twoFactorSecret.isNotEmpty
                            ? '${_twoFactorSecret.substring(0, 4)}··············'
                            : '—',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _twoFactorSecret));
                    _showSuccess('Đã sao chép secret key');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Text(
                      'Sao chép',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Account Card ──────────────────────────────────────────────────────────

  Widget _buildAccountCard() {
    return _SectionCard(
      title: 'Tài khoản',
      icon: Icons.manage_accounts_outlined,
      children: [
        _ActionRow(
          icon: Icons.logout_rounded,
          iconColor: const Color(0xFFFF6B6B),
          label: 'Đăng xuất',
          onTap: _confirmSignOut,
        ),
        _divider(),
        _ActionRow(
          icon: Icons.delete_outline_rounded,
          iconColor: const Color(0xFFFF4B4B),
          label: 'Xóa tài khoản',
          labelColor: const Color(0xFFFF4B4B),
          onTap: _confirmDeleteAccount,
        ),
      ],
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          backgroundColor: const Color(0xFF0D1B3E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Đăng xuất?',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          content: Text('Bạn chắc chắn muốn đăng xuất?',
              style: TextStyle(color: Colors.white.withOpacity(0.6))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Hủy',
                  style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await context.read<AuthProvider>().handleSignOut();
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const LoginPage(),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                      transitionDuration: const Duration(milliseconds: 400),
                    ),
                    (_) => false,
                  );
                }
              },
              child: const Text('Đăng xuất',
                  style: TextStyle(
                      color: Color(0xFFFF6B6B), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          backgroundColor: const Color(0xFF0D1B3E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Xóa tài khoản?',
              style: TextStyle(
                  color: Color(0xFFFF4B4B), fontWeight: FontWeight.w700)),
          content: Text(
            'Hành động này không thể hoàn tác. Tất cả dữ liệu của bạn sẽ bị xóa vĩnh viễn.',
            style: TextStyle(color: Colors.white.withOpacity(0.6), height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Hủy',
                  style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final success =
                    await context.read<AuthProvider>().deleteAccount();
                if (success && mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => const LoginPage(),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                    ),
                    (_) => false,
                  );
                }
              },
              child: const Text('Xóa vĩnh viễn',
                  style: TextStyle(
                      color: Color(0xFFFF4B4B), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        indent: 68,
        endIndent: 0,
        color: Colors.white.withOpacity(0.06),
      );
}

// ─── Reusable Widgets ─────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withOpacity(0.05),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: Row(
                  children: [
                    Icon(icon,
                        size: 14,
                        color: const Color(0xFF4F8DFF).withOpacity(0.8)),
                    const SizedBox(width: 6),
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _FieldRow({
    required this.icon,
    required this.label,
    required this.child,
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
              color: const Color(0xFF4F8DFF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF4F8DFF), size: 18),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: const Color(0xFF4F8DFF).withOpacity(0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: labelColor ?? Colors.white.withOpacity(0.85),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.2),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withOpacity(0.07),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconBtn({required this.icon, required this.onTap});

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
              color: Colors.white.withOpacity(0.07),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool compact;

  const _GradientButton({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 24,
          vertical: compact ? 9 : 13,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: onTap != null
                ? const [Color(0xFF4F8DFF), Color(0xFF7B4FFF)]
                : [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.1)
                  ],
          ),
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                    color: const Color(0xFF4F8DFF).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onTap != null ? Colors.white : Colors.white.withOpacity(0.3),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
