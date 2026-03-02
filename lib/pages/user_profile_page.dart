import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/providers/friend_provider.dart';
import 'package:flutter_chat_demo/providers/home_provider.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

class UserProfilePage extends StatefulWidget {
  final UserChat userChat;

  const UserProfilePage({super.key, required this.userChat});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _isLoading = false;
  bool _areFriends = false;
  String? _friendRequestStatus;

  late final String _currentUserId;
  late final FriendProvider _friendProvider;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
    _friendProvider = FriendProvider(
      firebaseFirestore: context.read<HomeProvider>().firebaseFirestore,
    );
    _checkFriendshipStatus();
  }

  Future<void> _checkFriendshipStatus() async {
    setState(() => _isLoading = true);

    final areFriends = await _friendProvider.areFriends(
      _currentUserId,
      widget.userChat.id,
    );

    String? requestStatus;
    if (!areFriends) {
      requestStatus = await _friendProvider.checkFriendRequest(
        _currentUserId,
        widget.userChat.id,
      );
    }

    setState(() {
      _areFriends = areFriends;
      _friendRequestStatus = requestStatus;
      _isLoading = false;
    });
  }

  Future<void> _handleFriendAction() async {
    if (_areFriends) {
      // Navigate to chat
      final conversationId = await _friendProvider.getOrCreateConversation(
        _currentUserId,
        widget.userChat.id,
        false,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            arguments: ChatPageArguments(
              peerId: widget.userChat.id,
              peerAvatar: widget.userChat.photoUrl,
              peerNickname: widget.userChat.nickname,
            ),
          ),
        ),
      );
    } else if (_friendRequestStatus == 'sent') {
      Fluttertoast.showToast(msg: "Friend request already sent");
    } else if (_friendRequestStatus != null && _friendRequestStatus != 'sent') {
      // Accept friend request
      setState(() => _isLoading = true);

      final success = await _friendProvider.acceptFriendRequest(
        _friendRequestStatus!,
        _currentUserId,
        widget.userChat.id,
      );

      if (success) {
        Fluttertoast.showToast(msg: "Friend request accepted!");
        _checkFriendshipStatus();
      } else {
        setState(() => _isLoading = false);
        Fluttertoast.showToast(msg: "Failed to accept request");
      }
    } else {
      // Send friend request
      setState(() => _isLoading = true);

      final success = await _friendProvider.sendFriendRequest(
        _currentUserId,
        widget.userChat.id,
      );

      if (success) {
        Fluttertoast.showToast(msg: "Friend request sent!");
        _checkFriendshipStatus();
      } else {
        setState(() => _isLoading = false);
        Fluttertoast.showToast(msg: "Failed to send request");
      }
    }
  }

  String _getButtonText() {
    if (_areFriends) return "Message";
    if (_friendRequestStatus == 'sent') return "Request Sent";
    if (_friendRequestStatus != null && _friendRequestStatus != 'sent') {
      return "Accept Request";
    }
    return "Add Friend";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'User Profile',
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
                const SizedBox(height: 40),

                // Avatar
                Container(
                  margin: const EdgeInsets.all(20),
                  child: widget.userChat.photoUrl.isNotEmpty
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(45),
                    child: Image.network(
                      widget.userChat.photoUrl,
                      fit: BoxFit.cover,
                      width: 90,
                      height: 90,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.account_circle,
                        size: 90,
                        color: ColorConstants.greyColor,
                      ),
                      loadingBuilder: (_, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                          width: 90,
                          height: 90,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: ColorConstants.themeColor,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                      : const Icon(
                    Icons.account_circle,
                    size: 90,
                    color: ColorConstants.greyColor,
                  ),
                ),

                // User Info
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nickname
                    Container(
                      margin: const EdgeInsets.only(left: 10, bottom: 5, top: 10),
                      child: const Text(
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ColorConstants.greyColor2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      width: double.infinity,
                      child: Text(
                        widget.userChat.nickname,
                        style: const TextStyle(
                          color: ColorConstants.primaryColor,
                          fontSize: 16,
                        ),
                      ),
                    ),

                    // About Me
                    Container(
                      margin: const EdgeInsets.only(left: 10, top: 30, bottom: 5),
                      child: const Text(
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ColorConstants.greyColor2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      width: double.infinity,
                      child: Text(
                        widget.userChat.aboutMe.isEmpty
                            ? 'No information'
                            : widget.userChat.aboutMe,
                        style: const TextStyle(
                          color: ColorConstants.primaryColor,
                          fontSize: 16,
                        ),
                      ),
                    ),

                    // Phone Number
                    if (widget.userChat.phoneNumber.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(
                              left: 10,
                              top: 30,
                              bottom: 5,
                            ),
                            child: const Text(
                              'Phone Number',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.bold,
                                color: ColorConstants.primaryColor,
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 30),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: ColorConstants.greyColor2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.phone,
                                    color: ColorConstants.greyColor),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    widget.userChat.phoneNumber,
                                    style: const TextStyle(
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

                // Action Button
                Container(
                  margin: const EdgeInsets.only(top: 50, bottom: 50),
                  child: TextButton(
                    onPressed: _isLoading ? null : _handleFriendAction,
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all<Color>(
                        _friendRequestStatus == 'sent'
                            ? ColorConstants.greyColor
                            : ColorConstants.primaryColor,
                      ),
                      padding: WidgetStateProperty.all<EdgeInsets>(
                        const EdgeInsets.fromLTRB(30, 10, 30, 10),
                      ),
                    ),
                    child: Text(
                      _getButtonText(),
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Loading Overlay
          Positioned(
            child: _isLoading ? LoadingView() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}