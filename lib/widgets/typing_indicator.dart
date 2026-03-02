// lib/widgets/typing_indicator.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';

class TypingIndicator extends StatefulWidget {
  final String userName;

  const TypingIndicator({
    super.key,
    required this.userName,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Animated dots
          SizedBox(
            width: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final offset = (index * 0.2);
                    final value = (_controller.value - offset) % 1.0;
                    final opacity = value < 0.5 ? value * 2 : 2 - (value * 2);

                    return Opacity(
                      opacity: opacity.clamp(0.3, 1.0),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: ColorConstants.primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),

          const SizedBox(width: 8),

          // Text
          Text(
            '${widget.userName} is typing...',
            style: const TextStyle(
              color: ColorConstants.greyColor,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// Compact typing indicator for chat input area
class CompactTypingIndicator extends StatefulWidget {
  const CompactTypingIndicator({super.key});

  @override
  State<CompactTypingIndicator> createState() => _CompactTypingIndicatorState();
}

class _CompactTypingIndicatorState extends State<CompactTypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final offset = (index * 0.2);
            final value = (_controller.value - offset) % 1.0;
            final scale = value < 0.5 ? 0.5 + (value) : 1.5 - value;

            return Transform.scale(
              scale: scale.clamp(0.5, 1.0),
              child: Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                  color: ColorConstants.primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
