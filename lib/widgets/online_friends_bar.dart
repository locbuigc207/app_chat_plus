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
      height: 98,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: presenceProvider.getOnlineFriendsStream(widget.currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: ColorConstants.themeColor,
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 18,
                    color: ColorConstants.greyColor.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Không thể tải danh sách',
                    style: TextStyle(
                      fontSize: 12,
                      color: ColorConstants.greyColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            );
          }

          final onlineFriends = (snapshot.data ?? [])
              .where((u) => u['id'] != widget.currentUserId)
              .toList();

          if (onlineFriends.isEmpty) {
            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD1D5DB),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Không có bạn bè trực tuyến',
                    style: TextStyle(
                      fontSize: 13,
                      color: ColorConstants.greyColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            cacheExtent: 400.0, // <--- FIXED
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            itemCount: onlineFriends.length,
            itemExtent: 76,
            addAutomaticKeepAlives: true,
            addRepaintBoundaries: true,
            itemBuilder: (context, index) {
              final friend = onlineFriends[index];
              return _OnlineFriendItem(
                key: ValueKey(friend['id']),
                friend: friend,
                isFirst: index == 0,
              );
            },
          );
        },
      ),
    );
  }
}

class _OnlineFriendItem extends StatefulWidget {
  final Map<String, dynamic> friend;
  final bool isFirst;

  const _OnlineFriendItem({
    super.key,
    required this.friend,
    this.isFirst = false,
  });

  @override
  State<_OnlineFriendItem> createState() => _OnlineFriendItemState();
}

class _OnlineFriendItemState extends State<_OnlineFriendItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nickname = widget.friend['nickname']?.toString() ?? 'User';
    final photoUrl = widget.friend['photoUrl']?.toString() ?? '';

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _navigate(context),
        child: Container(
          width: 70,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              ColorConstants.primaryColor,
                              ColorConstants.primaryColor
                                  .withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Hero(
                        tag: 'avatar_${widget.friend['id']}',
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: ClipOval(child: _buildAvatarImage(photoUrl)),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, __) => Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.green
                                    .withValues(alpha: 0.3 * _pulseAnim.value),
                              ),
                            ),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF34C759),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                nickname,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarImage(String photoUrl) {
    if (photoUrl.isEmpty) return _placeholder();

    return Image.network(
      photoUrl,
      fit: BoxFit.cover,
      cacheWidth: 108,
      cacheHeight: 108,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          color: ColorConstants.greyColor2,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                color: ColorConstants.primaryColor,
              ),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
        color: ColorConstants.greyColor2,
        child: Icon(
          Icons.account_circle_rounded,
          size: 54,
          color: ColorConstants.greyColor.withValues(alpha: 0.5),
        ),
      );

  void _navigate(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          arguments: ChatPageArguments(
            peerId: widget.friend['id'],
            peerAvatar: widget.friend['photoUrl'] ?? '',
            peerNickname: widget.friend['nickname'] ?? 'User',
          ),
        ),
      ),
    );
  }
}
