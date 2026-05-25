import 'dart:convert';

import 'package:flutter/material.dart';

class PollMessageWidget extends StatelessWidget {
  final String content; // Chuỗi JSON chứa question, options, votes
  final String messageId;
  final String currentUserId;
  final Function(String messageId, String optionId) onVote;

  const PollMessageWidget({
    super.key,
    required this.content,
    required this.messageId,
    required this.currentUserId,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> pollData = jsonDecode(content);
    String question = pollData['question'];
    List<dynamic> options = pollData['options'];

    int totalVotes =
        options.fold(0, (sum, opt) => sum + (opt['votes'] as List).length);

    return Container(
      width: MediaQuery.of(context).size.width * 0.75,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll, color: Color(0xFF007AFF)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(question,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          const SizedBox(height: 12),
          ...options.map((opt) {
            List<dynamic> votes = opt['votes'];
            bool hasVoted = votes.contains(currentUserId);
            double percentage = totalVotes == 0 ? 0 : votes.length / totalVotes;

            return GestureDetector(
              onTap: () => onVote(messageId, opt['id']),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  children: [
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: percentage,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: hasVoted
                              ? const Color(0xFF007AFF).withOpacity(0.2)
                              : Colors.blueGrey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(opt['text'],
                                style: TextStyle(
                                    color: hasVoted
                                        ? const Color(0xFF007AFF)
                                        : Colors.black87,
                                    fontWeight: hasVoted
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                            Text('${votes.length}',
                                style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          Text('$totalVotes lượt bình chọn',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
