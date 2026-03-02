import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/providers/auth_provider.dart';
import 'package:flutter_chat_demo/providers/friend_provider.dart';
import 'package:flutter_chat_demo/providers/home_provider.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final String _currentUserId;
  late final FriendProvider _friendProvider;
  late final FirebaseFirestore _firebaseFirestore;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().userFirebaseId ?? '';
    _friendProvider = FriendProvider(
      firebaseFirestore: context.read<HomeProvider>().firebaseFirestore,
    );
    _firebaseFirestore = context.read<HomeProvider>().firebaseFirestore;
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 7) {
        return DateFormat('MMM dd, yyyy').format(dateTime);
      } else if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    } catch (_) {
      return '';
    }
  }

  Future<void> _handleAcceptRequest(String requestId, String requesterId) async {
    setState(() => _isLoading = true);

    final success = await _friendProvider.acceptFriendRequest(
      requestId,
      _currentUserId,
      requesterId,
    );

    setState(() => _isLoading = false);

    if (success) {
      Fluttertoast.showToast(msg: "Friend request accepted!");
    } else {
      Fluttertoast.showToast(msg: "Failed to accept request");
    }
  }

  Future<void> _handleRejectRequest(String requestId) async {
    setState(() => _isLoading = true);

    try {
      await _firebaseFirestore
          .collection(FirestoreConstants.pathFriendRequestCollection)
          .doc(requestId)
          .update({FirestoreConstants.status: 'rejected'});

      Fluttertoast.showToast(msg: "Friend request rejected");
    } catch (e) {
      Fluttertoast.showToast(msg: "Failed to reject request");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildRequestItem(DocumentSnapshot requestDoc) {
    final request = FriendRequest.fromDocument(requestDoc);

    return FutureBuilder<DocumentSnapshot>(
      future: _firebaseFirestore
          .collection(FirestoreConstants.pathUserCollection)
          .doc(request.requesterId)
          .get(),
      builder: (_, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          // Hiển thị khi đang tải dữ liệu người gửi
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              children: [
                CircularProgressIndicator(
                  color: ColorConstants.themeColor,
                ),
                SizedBox(width: 12),
                Text(
                  'Loading...',
                  style: TextStyle(
                    color: ColorConstants.greyColor,
                  ),
                ),
              ],
            ),
          );
        }

        if (!userSnapshot.hasData || userSnapshot.data == null) {
          return const SizedBox.shrink();
        }

        final requester = UserChat.fromDocument(userSnapshot.data!);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar
              ClipOval(
                child: requester.photoUrl.isNotEmpty
                    ? Image.network(
                  requester.photoUrl,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.account_circle,
                    size: 50,
                    color: ColorConstants.greyColor,
                  ),
                )
                    : const Icon(
                  Icons.account_circle,
                  size: 50,
                  color: ColorConstants.greyColor,
                ),
              ),
              const SizedBox(width: 12),

              // User info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      requester.nickname.isEmpty ? 'User' : requester.nickname,
                      style: const TextStyle(
                        color: ColorConstants.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(request.createdAt),
                      style: const TextStyle(
                        color: ColorConstants.greyColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Action buttons
              if (request.status == 'pending') ...[
                IconButton(
                  icon: const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 28,
                  ),
                  onPressed: () => _handleAcceptRequest(
                    request.id,
                    request.requesterId,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.cancel,
                    color: Colors.red,
                    size: 28,
                  ),
                  onPressed: () => _handleRejectRequest(request.id),
                ),
              ] else if (request.status == 'accepted')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Accepted',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Rejected',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Friend Requests',
          style: TextStyle(color: ColorConstants.primaryColor),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _firebaseFirestore
                .collection(FirestoreConstants.pathFriendRequestCollection)
                .where(FirestoreConstants.receiverId, isEqualTo: _currentUserId)
                .orderBy(FirestoreConstants.createdAt, descending: true)
                .snapshots(),
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: ColorConstants.themeColor,
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 60,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 80,
                        color: ColorConstants.greyColor.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No friend requests',
                        style: TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'When someone sends you a friend request,\nit will appear here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ColorConstants.greyColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (_, index) {
                  return _buildRequestItem(snapshot.data!.docs[index]);
                },
              );
            },
          ),

          // Loading overlay
          if (_isLoading)
            Positioned.fill(
              child: LoadingView(),
            ),
        ],
      ),
    );
  }
}
