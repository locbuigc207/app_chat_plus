import 'package:flutter/material.dart';

import '../services/realtime_ai_service.dart';

class LiveCaptionOverlay extends StatelessWidget {
  const LiveCaptionOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
        stream: RealtimeAIService().captionStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const SizedBox.shrink();
          }

          return Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              snapshot.data!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, height: 1.4),
            ),
          );
        });
  }
}
