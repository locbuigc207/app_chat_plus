import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/widgets/loading_view.dart';
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
  String _phoneNumber = ''; // NEW
  String _qrCode = ''; // NEW

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
      _userId = _settingProvider.getPref(FirestoreConstants.id) ?? "";
      _nickname = _settingProvider.getPref(FirestoreConstants.nickname) ?? "";
      _aboutMe = _settingProvider.getPref(FirestoreConstants.aboutMe) ?? "";
      _avatarUrl = _settingProvider.getPref(FirestoreConstants.photoUrl) ?? "";
      _phoneNumber =
          _settingProvider.getPref(FirestoreConstants.phoneNumber) ?? ""; // NEW
      _qrCode = _settingProvider.getPref(FirestoreConstants.qrCode) ?? ""; // NEW
    });

    _controllerNickname = TextEditingController(text: _nickname);
    _controllerAboutMe = TextEditingController(text: _aboutMe);
  }

  Future<bool> _pickAvatar() async {
    final imagePicker = ImagePicker();

    final pickedXFile = await imagePicker.pickImage(source: ImageSource.gallery)
        .catchError((err) {
      Fluttertoast.showToast(msg: err.toString());
      return null;
    });

    if (pickedXFile != null) {
      final imageFile = File(pickedXFile.path);
      setState(() {
        _avatarFile = imageFile;
        _isLoading = true;
      });
      return true;
    } else {
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
        phoneNumber: _phoneNumber, // NEW
        qrCode: _qrCode, // NEW
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
        Fluttertoast.showToast(msg: "Upload success");
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
      phoneNumber: _phoneNumber, // NEW
      qrCode: _qrCode, // NEW
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
      Fluttertoast.showToast(msg: "Update success");
    }).catchError((err) {
      setState(() => _isLoading = false);
      Fluttertoast.showToast(msg: err.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppConstants.settingsTitle,
          style: TextStyle(color: ColorConstants.primaryColor),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                /// Avatar
                CupertinoButton(
                  onPressed: () {
                    _pickAvatar().then((isSuccess) {
                      if (isSuccess) _uploadFile();
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    child: _avatarFile == null
                        ? _avatarUrl.isNotEmpty
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(45),
                      child: Image.network(
                        _avatarUrl,
                        fit: BoxFit.cover,
                        width: 90,
                        height: 90,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.account_circle,
                          size: 90,
                          color: ColorConstants.greyColor,
                        ),
                        loadingBuilder:
                            (_, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return SizedBox(
                            width: 90,
                            height: 90,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: ColorConstants.themeColor,
                                value: loadingProgress
                                    .expectedTotalBytes !=
                                    null
                                    ? loadingProgress
                                    .cumulativeBytesLoaded /
                                    loadingProgress
                                        .expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                        : Icon(
                      Icons.account_circle,
                      size: 90,
                      color: ColorConstants.greyColor,
                    )
                        : ClipOval(
                      child: Image.file(
                        _avatarFile!,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

                /// Input Fields
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Nickname
                    Container(
                      margin:
                      const EdgeInsets.only(left: 10, bottom: 5, top: 10),
                      child: Text(
                        'Nickname',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.bold,
                          color: ColorConstants.primaryColor,
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 30),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          primaryColor: ColorConstants.primaryColor,
                        ),
                        child: TextField(
                          controller: _controllerNickname,
                          focusNode: _focusNodeNickname,
                          decoration: InputDecoration(
                            hintText: 'Sweetie',
                            contentPadding: const EdgeInsets.all(5),
                            hintStyle:
                            TextStyle(color: ColorConstants.greyColor),
                          ),
                          onChanged: (value) => _nickname = value,
                        ),
                      ),
                    ),

                    /// About Me
                    Container(
                      margin:
                      const EdgeInsets.only(left: 10, top: 30, bottom: 5),
                      child: Text(
                        'About me',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.bold,
                          color: ColorConstants.primaryColor,
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 30),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          primaryColor: ColorConstants.primaryColor,
                        ),
                        child: TextField(
                          controller: _controllerAboutMe,
                          focusNode: _focusNodeAboutMe,
                          decoration: InputDecoration(
                            hintText: 'Fun, like travel and play PES...',
                            contentPadding: const EdgeInsets.all(5),
                            hintStyle:
                            TextStyle(color: ColorConstants.greyColor),
                          ),
                          onChanged: (value) => _aboutMe = value,
                        ),
                      ),
                    ),

                    /// Phone Number (Read-only) - NEW
                    if (_phoneNumber.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(
                              left: 10,
                              top: 30,
                              bottom: 5,
                            ),
                            child: Text(
                              'Phone Number',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.bold,
                                color: ColorConstants.primaryColor,
                              ),
                            ),
                          ),
                          Container(
                            margin:
                            const EdgeInsets.symmetric(horizontal: 30),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: ColorConstants.greyColor2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.phone,
                                    color: ColorConstants.greyColor),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _phoneNumber,
                                    style: TextStyle(
                                      color: ColorConstants.primaryColor,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                /// Update Button
                Container(
                  margin: const EdgeInsets.only(top: 50, bottom: 50),
                  child: TextButton(
                    onPressed: _handleUpdateData,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all<Color>(
                        ColorConstants.primaryColor,
                      ),
                      padding: WidgetStateProperty.all<EdgeInsets>(
                        const EdgeInsets.fromLTRB(30, 10, 30, 10),
                      ),
                    ),
                    child: const Text(
                      'Update',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),

          /// Loading Overlay
          Positioned(
            child: _isLoading ? LoadingView() : const SizedBox.shrink(),
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
