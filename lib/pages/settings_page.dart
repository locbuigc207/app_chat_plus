import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/widgets/common_widgets.dart'; // Đã đổi import
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _controllerNickname;
  late final TextEditingController _controllerAboutMe;

  String _userId = '';
  String _nickname = '';
  String _aboutMe = '';
  String _avatarUrl = '';
  String _phoneNumber = '';
  String _qrCode = '';

  bool _isLoading = false;
  File? _avatarFile;

  late final _settingProvider = context.read<SettingProvider>();

  final _focusNodeNickname = FocusNode();
  final _focusNodeAboutMe = FocusNode();

  @override
  void initState() {
    super.initState();
    _readLocal();
  }

  void _readLocal() {
    setState(() {
      _userId = _settingProvider.getPref(FirestoreConstants.id) ?? '';
      _nickname = _settingProvider.getPref(FirestoreConstants.nickname) ?? '';
      _aboutMe = _settingProvider.getPref(FirestoreConstants.aboutMe) ?? '';
      _avatarUrl = _settingProvider.getPref(FirestoreConstants.photoUrl) ?? '';
      _phoneNumber =
          _settingProvider.getPref(FirestoreConstants.phoneNumber) ?? '';
      _qrCode = _settingProvider.getPref(FirestoreConstants.qrCode) ?? '';
    });
    _controllerNickname = TextEditingController(text: _nickname);
    _controllerAboutMe = TextEditingController(text: _aboutMe);
  }

  Future<bool> _pickAvatar() async {
    try {
      final imagePicker = ImagePicker();
      final pickedXFile = await imagePicker.pickImage(
          source: ImageSource.gallery, imageQuality: 80);
      if (pickedXFile != null) {
        setState(() {
          _avatarFile = File(pickedXFile.path);
          _isLoading = true;
        });
        return true;
      }
      return false;
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString());
      return false;
    }
  }

  Future<void> _uploadFile() async {
    final fileName = _userId;
    final uploadTask = _settingProvider.uploadFile(_avatarFile!, fileName);
    try {
      final snapshot = await uploadTask;
      _avatarUrl = await snapshot.ref.getDownloadURL();
      final updateInfo = UserChat(
        id: _userId,
        photoUrl: _avatarUrl,
        nickname: _nickname,
        aboutMe: _aboutMe,
        phoneNumber: _phoneNumber,
        qrCode: _qrCode,
      );
      _settingProvider
          .updateDataFirestore(
        FirestoreConstants.pathUserCollection,
        _userId,
        updateInfo.toJson(),
      )
          .then((_) async {
        await _settingProvider.setPref(FirestoreConstants.photoUrl, _avatarUrl);
        setState(() => _isLoading = false);
        Fluttertoast.showToast(msg: '✅ Photo updated');
      }).catchError((err) {
        setState(() => _isLoading = false);
        Fluttertoast.showToast(msg: err.toString());
      });
    } on FirebaseException catch (e) {
      setState(() => _isLoading = false);
      Fluttertoast.showToast(msg: e.message ?? e.toString());
    }
  }

  void _handleUpdateData() {
    _focusNodeNickname.unfocus();
    _focusNodeAboutMe.unfocus();
    setState(() => _isLoading = true);

    final updateInfo = UserChat(
      id: _userId,
      photoUrl: _avatarUrl,
      nickname: _nickname,
      aboutMe: _aboutMe,
      phoneNumber: _phoneNumber,
      qrCode: _qrCode,
    );

    _settingProvider
        .updateDataFirestore(
      FirestoreConstants.pathUserCollection,
      _userId,
      updateInfo.toJson(),
    )
        .then((_) async {
      await _settingProvider.setPref(FirestoreConstants.nickname, _nickname);
      await _settingProvider.setPref(FirestoreConstants.aboutMe, _aboutMe);
      await _settingProvider.setPref(FirestoreConstants.photoUrl, _avatarUrl);
      setState(() => _isLoading = false);
      Fluttertoast.showToast(msg: '✅ Profile updated');
    }).catchError((err) {
      setState(() => _isLoading = false);
      Fluttertoast.showToast(msg: err.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? ColorConstants.backgroundDark
          : ColorConstants.backgroundLight,
      appBar: AppBar(
        backgroundColor: isDark ? ColorConstants.surfaceDark : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Edit Profile'),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF1A1D2E),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: isDark ? Colors.white70 : ColorConstants.primaryColor,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _handleUpdateData,
              child: Text(
                'Save',
                style: TextStyle(
                  color: ColorConstants.primaryColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildAvatarSection(isDark),
                const SizedBox(height: 24),
                _buildInfoSection(isDark),
              ],
            ),
          ),
          if (_isLoading) const LoadingView(message: 'Saving...'),
        ],
      ),
    );
  }

  Widget _buildAvatarSection(bool isDark) {
    final colorIndex = _nickname.isEmpty
        ? 0
        : _nickname.codeUnitAt(0) % ColorConstants.avatarColors.length;
    final avatarColor = ColorConstants.avatarColors[colorIndex];

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _pickAvatar().then((ok) {
              if (ok) _uploadFile();
            }),
            child: Stack(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: avatarColor.withOpacity(0.12),
                    border: Border.all(
                      color: avatarColor.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: _avatarFile != null
                        ? Image.file(_avatarFile!, fit: BoxFit.cover)
                        : (_avatarUrl.isNotEmpty
                            ? Image.network(
                                _avatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _avatarPlaceholder(avatarColor),
                              )
                            : _avatarPlaceholder(avatarColor)),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: ColorConstants.primaryGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? ColorConstants.backgroundDark
                            : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap to change photo',
            style: TextStyle(
              fontSize: 13,
              color: ColorConstants.primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder(Color color) {
    return Container(
      color: color.withOpacity(0.12),
      child: Center(
        child: Text(
          _nickname.isNotEmpty ? _nickname[0].toUpperCase() : '?',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 36,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? ColorConstants.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.15 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildField(
            icon: Icons.person_outline_rounded,
            label: 'Nickname',
            hint: 'Enter your name',
            controller: _controllerNickname,
            focusNode: _focusNodeNickname,
            isDark: isDark,
            onChanged: (v) => _nickname = v,
          ),
          Divider(
            height: 1,
            indent: 56,
            endIndent: 16,
            color:
                isDark ? ColorConstants.borderDark : ColorConstants.greyColor2,
          ),
          _buildField(
            icon: Icons.info_outline_rounded,
            label: 'About Me',
            hint: 'Write something about yourself',
            controller: _controllerAboutMe,
            focusNode: _focusNodeAboutMe,
            isDark: isDark,
            maxLines: 3,
            onChanged: (v) => _aboutMe = v,
          ),
          if (_phoneNumber.isNotEmpty) ...[
            Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              color: isDark
                  ? ColorConstants.borderDark
                  : ColorConstants.greyColor2,
            ),
            _buildReadOnlyField(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: _phoneNumber,
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isDark,
    required Function(String) onChanged,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: BoxDecoration(
              color: ColorConstants.primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: ColorConstants.primaryColor, size: 18),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ColorConstants.primaryColor.withOpacity(0.8),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: maxLines,
                  onChanged: onChanged,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1A1D2E),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                        color: ColorConstants.greyColor, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: ColorConstants.greyColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: ColorConstants.greyColor, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ColorConstants.greyColor,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF1A1D2E),
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ColorConstants.greyColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Verified',
              style: TextStyle(
                fontSize: 10,
                color: ColorConstants.greyColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controllerNickname.dispose();
    _controllerAboutMe.dispose();
    _focusNodeNickname.dispose();
    _focusNodeAboutMe.dispose();
    super.dispose();
  }
}
