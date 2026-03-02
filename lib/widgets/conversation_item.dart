// lib/widgets/conversation_item.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/models/models.dart';

class ConversationItem extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final Function(BuildContext) onLongPress;

  const ConversationItem({
    super.key,
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: conversation.isPinned
            ? ColorConstants.primaryColor.withOpacity(0.05)
            : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => onLongPress(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar
                Stack(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: ColorConstants.greyColor2,
                      child: Icon(
                        Icons.person,
                        color: ColorConstants.greyColor,
                      ),
                    ),
                    if (conversation.isMuted)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.volume_off,
                            size: 14,
                            color: ColorConstants.greyColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (conversation.isPinned)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.push_pin,
                                size: 14,
                                color: ColorConstants.primaryColor,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              'Conversation',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        conversation.lastMessage,
                        style: TextStyle(
                          color: conversation.isMuted
                              ? ColorConstants.greyColor
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
