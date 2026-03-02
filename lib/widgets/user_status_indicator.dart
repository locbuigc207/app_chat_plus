// lib/widgets/user_status_indicator.dart - FIXED OVERFLOW & ADDED textColor
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class UserStatusIndicator extends StatelessWidget {
  final String userId;
  final double size;
  final bool showText;
  final Color? textColor; // ✅ Bổ sung tham số textColor

  const UserStatusIndicator({
    super.key,
    required this.userId,
    this.size = 12,
    this.showText = false,
    this.textColor, // ✅ Khai báo trong constructor
  });

  @override
  Widget build(BuildContext context) {
    final presenceProvider = context.read<UserPresenceProvider>();

    return StreamBuilder<Map<String, dynamic>>(
      stream: presenceProvider.getUserOnlineStatus(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Trường hợp không có dữ liệu (default to Offline/Grey)
          return _buildIndicator(false, null, showText, textColor);
        }

        final data = snapshot.data!;
        final isOnline = data['isOnline'] as bool;
        final lastSeen = data['lastSeen'] as DateTime?;

        return _buildIndicator(isOnline, lastSeen, showText, textColor);
      },
    );
  }

  Widget _buildIndicator(
      bool isOnline, DateTime? lastSeen, bool showText, Color? textColor) {
    if (showText) {
      // Logic cho chế độ hiển thị text (sử dụng Flexible để tránh tràn)
      final defaultTextColor =
          isOnline ? Colors.green : ColorConstants.greyColor;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : ColorConstants.greyColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              _getStatusText(isOnline, lastSeen),
              style: TextStyle(
                fontSize: 11,
                // ✅ SỬ DỤNG textColor nếu được cung cấp, nếu không dùng default
                color: textColor ?? defaultTextColor,
                fontWeight: isOnline ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      );
    }

    // Logic cho chế độ chỉ hiển thị chấm tròn
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isOnline ? Colors.green : ColorConstants.greyColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 2,
        ),
      ),
    );
  }

  String _getStatusText(bool isOnline, DateTime? lastSeen) {
    if (isOnline) {
      return 'Online';
    }

    if (lastSeen == null) {
      return 'Offline';
    }

    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return DateFormat('MMM dd').format(lastSeen);
    }
  }
}

// Avatar with online status
class AvatarWithStatus extends StatelessWidget {
  final String userId;
  final String photoUrl;
  final double size;
  final double indicatorSize;

  const AvatarWithStatus({
    super.key,
    required this.userId,
    required this.photoUrl,
    this.size = 50,
    this.indicatorSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Avatar
        ClipOval(
          child: photoUrl.isNotEmpty
              ? Image.network(
                  photoUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: size,
                      height: size,
                      color: ColorConstants.greyColor2,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.account_circle,
                    size: size,
                    color: ColorConstants.greyColor,
                  ),
                )
              : Icon(
                  Icons.account_circle,
                  size: size,
                  color: ColorConstants.greyColor,
                ),
        ),

        // Online indicator
        Positioned(
          right: 0,
          bottom: 0,
          child: UserStatusIndicator(
            userId: userId,
            size: indicatorSize,
          ),
        ),
      ],
    );
  }
}
