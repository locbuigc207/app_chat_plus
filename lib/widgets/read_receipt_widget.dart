// lib/widgets/read_receipt_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class ReadReceiptWidget extends StatelessWidget {
  final bool isRead;
  final bool isSent;
  final double size;

  const ReadReceiptWidget({
    super.key,
    required this.isRead,
    this.isSent = true,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSent) {
      // Message sending
      return Icon(
        Icons.schedule,
        size: size,
        color: ColorConstants.greyColor,
      );
    }

    if (isRead) {
      // Message read - double check with fill
      return Stack(
        children: [
          Icon(
            Icons.done_all,
            size: size,
            color: Colors.blue,
          ),
        ],
      );
    }

    // Message sent but not read - double check without fill
    return Icon(
      Icons.done_all,
      size: size,
      color: ColorConstants.greyColor,
    );
  }
}

// Message status text
class MessageStatusText extends StatelessWidget {
  final bool isRead;
  final bool isSent;
  final DateTime? readAt;

  const MessageStatusText({
    super.key,
    required this.isRead,
    this.isSent = true,
    this.readAt,
  });

  @override
  Widget build(BuildContext context) {
    String statusText;
    Color statusColor;

    if (!isSent) {
      statusText = 'Sending...';
      statusColor = ColorConstants.greyColor;
    } else if (isRead) {
      if (readAt != null) {
        final now = DateTime.now();
        final diff = now.difference(readAt!);

        if (diff.inSeconds < 60) {
          statusText = 'Read just now';
        } else if (diff.inMinutes < 60) {
          statusText = 'Read ${diff.inMinutes}m ago';
        } else {
          statusText = 'Read';
        }
      } else {
        statusText = 'Read';
      }
      statusColor = Colors.blue;
    } else {
      statusText = 'Delivered';
      statusColor = ColorConstants.greyColor;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReadReceiptWidget(
          isRead: isRead,
          isSent: isSent,
          size: 14,
        ),
        const SizedBox(width: 4),
        Text(
          statusText,
          style: TextStyle(
            fontSize: 11,
            color: statusColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
