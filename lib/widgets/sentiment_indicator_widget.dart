// lib/widgets/sentiment_indicator_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';
import 'package:flutter_chat_demo/services/local_db_service.dart';

class SentimentIndicatorWidget extends StatefulWidget {
  final String groupChatId;

  const SentimentIndicatorWidget({super.key, required this.groupChatId});

  @override
  State<SentimentIndicatorWidget> createState() =>
      _SentimentIndicatorWidgetState();
}

class _SentimentIndicatorWidgetState extends State<SentimentIndicatorWidget>
    with SingleTickerProviderStateMixin {
  String _emoji = '';
  String _tooltip = 'Cảm xúc cuộc trò chuyện';
  String _mood = '';
  double _score = 0.5;
  bool _loaded = false;
  bool _isAnalyzing = false;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _analyze();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    if (_isAnalyzing) return;
    _isAnalyzing = true;

    final rawMsgs = LocalDbService().getMessages(widget.groupChatId);

    final msgs = rawMsgs
        .take(30)
        .map((m) => m['content']?.toString() ?? '')
        .where((c) =>
            c.isNotEmpty &&
            !c.startsWith('{"iv":') &&
            !c.startsWith('{') &&
            c.length > 3)
        .take(20)
        .toList()
        .reversed
        .toList();

    if (msgs.length < 3) {
      _isAnalyzing = false;
      return;
    }

    try {
      final result = await AIBackendService().analyzeSentiment(msgs);
      if (!mounted || result == null) {
        _isAnalyzing = false;
        return;
      }
      final emoji = result['emoji'] as String? ?? '';
      final mood = result['mood'] as String? ?? 'Trung tính';
      final score = (result['score'] as num?)?.toDouble() ?? 0.5;

      if (emoji.isNotEmpty) {
        setState(() {
          _emoji = emoji;
          _mood = mood;
          _score = score;
          _tooltip = 'Cảm xúc: $mood (${(score * 100).round()}% tích cực)';
          _loaded = true;
        });
        // Animate for positive conversations
        if (score > 0.6) {
          _pulseCtrl.repeat(reverse: true);
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) _pulseCtrl.stop();
          });
        }
      }
    } catch (_) {
      // Silent fail - indicator is optional
    } finally {
      _isAnalyzing = false;
    }
  }

  Color get _indicatorColor {
    if (_score > 0.65) return const Color(0xFF22C55E);
    if (_score > 0.4) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _emoji.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: _tooltip,
      preferBelow: false,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ScaleTransition(
        scale: _pulseAnim,
        child: GestureDetector(
          onTap: _analyze,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _indicatorColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _indicatorColor.withValues(alpha: 0.25),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 3),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _indicatorColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _indicatorColor.withValues(alpha: 0.4),
                        blurRadius: 4,
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
