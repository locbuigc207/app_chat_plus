// lib/widgets/message_reactions_display.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class MessageReactionsDisplay extends StatelessWidget {
  final Map<String, int> reactions; // emoji -> count
  final String currentUserId;
  final Map<String, bool> userReactions; // emoji -> hasReacted
  final Function(String emoji) onReactionTap;

  const MessageReactionsDisplay({
    super.key,
    required this.reactions,
    required this.currentUserId,
    required this.userReactions,
    required this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: reactions.entries.map((entry) {
        final hasReacted = userReactions[entry.key] ?? false;

        return GestureDetector(
          onTap: () => onReactionTap(entry.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hasReacted
                  ? ColorConstants.primaryColor.withOpacity(0.2)
                  : ColorConstants.greyColor2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasReacted
                    ? ColorConstants.primaryColor
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.key,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 4),
                Text(
                  '${entry.value}',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasReacted
                        ? ColorConstants.primaryColor
                        : ColorConstants.greyColor,
                    fontWeight: hasReacted ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
