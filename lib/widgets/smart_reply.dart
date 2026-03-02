// Smart Reply Widget
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';

class SmartReplyWidget extends StatelessWidget {
  final List<SmartReply> replies;
  final Function(String) onReplySelected;

  const SmartReplyWidget({
    super.key,
    required this.replies,
    required this.onReplySelected,
  });

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 16,
                color: ColorConstants.primaryColor,
              ),
              const SizedBox(width: 8),
              const Text(
                'Smart Replies',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: ColorConstants.greyColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: replies.map((reply) {
              return ActionChip(
                label: Text(
                  reply.text,
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: () => onReplySelected(reply.text),
                backgroundColor: ColorConstants.greyColor2,
                side: BorderSide(
                  color: ColorConstants.primaryColor.withOpacity(0.3),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}