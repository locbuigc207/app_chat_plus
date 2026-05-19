
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:provider/provider.dart';

class OnlineFriendsBar extends StatefulWidget {
  final String currentUserId;

  const OnlineFriendsBar({
    super.key,
    required this.currentUserId,
  });

  @override
  State<OnlineFriendsBar> createState() => _OnlineFriendsBarState();
}

class _OnlineFriendsBarState extends State<OnlineFriendsBar>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); 

    final presenceProvider = context.read<UserPresenceProvider>();

    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: presenceProvider.getOnlineFriends(widget.currentUserId),
        builder: (context, snapshot) {
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ColorConstants.themeColor,
                ),
              ),
            );
          }

          
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load online friends',
                style: TextStyle(
                  color: ColorConstants.greyColor,
                  fontSize: 12,
                ),
              ),
            );
          }

          final onlineFriends = snapshot.hasData
              ? snapshot.data!
                  .where((user) => user['id'] != widget.currentUserId)
                  .toList()
              : [];

          if (onlineFriends.isEmpty) {
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.wifi_off,
                    color: ColorConstants.greyColor,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'No friends online',
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
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: onlineFriends.length,
            
            itemExtent: 78, 
            addAutomaticKeepAlives: true,
            addRepaintBoundaries: true,
            cacheExtent: 400, 
            itemBuilder: (context, index) {
              return _OnlineFriendItem(
                key: ValueKey(onlineFriends[index]['id']),
                friend: onlineFriends[index],
              );
            },
          );
        },
      ),
    );
  }
}


class _OnlineFriendItem extends StatelessWidget {
  final Map<String, dynamic> friend;

  const _OnlineFriendItem({
    super.key,
    required this.friend,
  });

  @override
  Widget build(BuildContext context) {
    
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatPage(
                arguments: ChatPageArguments(
                  peerId: friend['id'],
                  peerAvatar: friend['photoUrl'],
                  peerNickname: friend['nickname'],
                ),
              ),
            ),
          );
        },
        child: Container(
          width: 70, 
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  children: [
                    
                    Hero(
                      tag: 'avatar_${friend['id']}',
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ColorConstants.primaryColor,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: _buildAvatar(),
                        ),
                      ),
                    ),

                    
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              
              SizedBox(
                width: 70,
                child: Text(
                  friend['nickname']?.toString() ?? 'User',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ColorConstants.primaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  
  Widget _buildAvatar() {
    final photoUrl = friend['photoUrl']?.toString() ?? '';

    if (photoUrl.isEmpty) {
      return const Icon(
        Icons.account_circle,
        size: 56,
        color: ColorConstants.greyColor,
      );
    }

    return Image.network(
      photoUrl,
      fit: BoxFit.cover,
      
      cacheWidth: 120, 
      cacheHeight: 120,
      
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => const Icon(
        Icons.account_circle,
        size: 56,
        color: ColorConstants.greyColor,
      ),
    );
  }
}
