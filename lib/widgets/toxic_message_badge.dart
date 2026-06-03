// lib/widgets/toxic_message_badge.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:provider/provider.dart';

class ToxicMessageBadge extends StatefulWidget {
  final String category;
  final bool showDetails;

  const ToxicMessageBadge({
    super.key,
    required this.category,
    this.showDetails = false,
  });

  @override
  State<ToxicMessageBadge> createState() => _ToxicMessageBadgeState();
}

class _ToxicMessageBadgeState extends State<ToxicMessageBadge>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  String get _label => switch (widget.category) {
        'hate' => '⚠️ Phát ngôn thù ghét',
        'harassment' => '⚠️ Quấy rối',
        'discrimination' => '⚠️ Phân biệt đối xử',
        'offensive' => '⚠️ Nội dung xúc phạm',
        _ => '⚠️ Nội dung không phù hợp',
      };

  String get _description => switch (widget.category) {
        'hate' =>
          'Tin nhắn này có thể chứa ngôn ngữ thù ghét. Hãy báo cáo nếu cần.',
        'harassment' => 'Tin nhắn này được đánh giá là có tính chất quấy rối.',
        'discrimination' => 'Nội dung có thể chứa yếu tố phân biệt đối xử.',
        'offensive' => 'Nội dung có thể xúc phạm hoặc không phù hợp.',
        _ => 'AI phát hiện nội dung không phù hợp trong tin nhắn này.',
      };

  @override
  Widget build(BuildContext context) {
    final p = context.read<ThemeProvider>().palette;
    final dangerColor = p.dangerColor;

    return GestureDetector(
      onTap: widget.showDetails
          ? () {
              setState(() => _expanded = !_expanded);
              if (_expanded) {
                _animCtrl.forward();
              } else {
                _animCtrl.reverse();
              }
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(top: 3, bottom: 2),
        decoration: BoxDecoration(
          color: dangerColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: dangerColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 12, color: dangerColor),
                  const SizedBox(width: 5),
                  Text(
                    _label,
                    style: TextStyle(
                      fontSize: 11,
                      color: dangerColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.showDetails) ...[
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 12,
                        color: dangerColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.showDetails)
              SizeTransition(
                sizeFactor: _expandAnim,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 0, 9, 8),
                  child: Text(
                    _description,
                    style: TextStyle(
                      fontSize: 11,
                      color: dangerColor.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
