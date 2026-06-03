// lib/widgets/tone_rewriter_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';
import 'package:provider/provider.dart';

class ToneRewriterSheet extends StatefulWidget {
  final String originalMessage;
  final void Function(String rewritten) onApply;

  const ToneRewriterSheet({
    super.key,
    required this.originalMessage,
    required this.onApply,
  });

  @override
  State<ToneRewriterSheet> createState() => _ToneRewriterSheetState();
}

class _ToneRewriterSheetState extends State<ToneRewriterSheet>
    with SingleTickerProviderStateMixin {
  static const _tones = <String, (String, IconData)>{
    'formal': ('📋 Trang trọng', Icons.business_center_rounded),
    'casual': ('😊 Bình thường', Icons.chat_rounded),
    'professional': ('💼 Chuyên nghiệp', Icons.work_rounded),
    'friendly': ('🤝 Thân thiện', Icons.favorite_rounded),
    'assertive': ('💪 Quyết đoán', Icons.bolt_rounded),
    'soft': ('🌸 Nhẹ nhàng', Icons.spa_rounded),
    'empathetic': ('❤️ Đồng cảm', Icons.volunteer_activism_rounded),
    'enthusiastic': ('🔥 Nhiệt tình', Icons.star_rounded),
  };

  String? _selectedTone;
  String? _rewrittenText;
  bool _isLoading = false;
  String? _error;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _rewrite(String tone) async {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedTone = tone;
      _isLoading = true;
      _error = null;
      _rewrittenText = null;
    });
    _animCtrl.reset();
    try {
      final result = await AIBackendService().generateMessageTone(
        message: widget.originalMessage,
        toTone: tone,
      );
      if (!mounted) return;
      setState(() {
        _rewrittenText = result?.rewritten;
        _isLoading = false;
        if (result == null) _error = 'Không thể viết lại lúc này. Thử lại nhé!';
      });
      if (result != null) _animCtrl.forward();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Có lỗi xảy ra. Vui lòng thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeProvider>();
    final p = theme.palette;
    final primary = theme.primaryColor;

    return Container(
      padding: EdgeInsets.only(
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
              color: p.shadowStrong,
              blurRadius: 24,
              offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: p.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),

          // Title row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(Icons.edit_note_rounded, color: primary, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'Viết lại theo tông giọng',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Original preview
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.divider),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded, color: p.textHint, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.originalMessage.length > 100
                          ? '${widget.originalMessage.substring(0, 100)}...'
                          : widget.originalMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: p.textSecondary,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tone selector chips
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _tones.entries.map((entry) {
                final isSelected = _selectedTone == entry.key;
                final label = entry.value.$1;
                final icon = entry.value.$2;
                return GestureDetector(
                  onTap: () => _rewrite(entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? primary : p.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected ? primary : p.divider,
                        width: 1.2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                  color: primary.withValues(alpha: 0.3),
                                  blurRadius: 8)
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 15,
                          color: isSelected ? Colors.white : p.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // Result area
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: primary, strokeWidth: 2.5),
                    const SizedBox(height: 12),
                    Text(
                      'AI đang viết lại...',
                      style: TextStyle(color: p.textHint, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.red, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _rewrite(_selectedTone!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Thử lại',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_rewrittenText != null)
            FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Result label
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 14, color: primary),
                          const SizedBox(width: 5),
                          Text(
                            'Kết quả AI',
                            style: TextStyle(
                              fontSize: 12,
                              color: primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Result box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              primary.withValues(alpha: 0.04),
                              primary.withValues(alpha: 0.08),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: primary.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          _rewrittenText!,
                          style: TextStyle(
                            fontSize: 15,
                            color: p.textPrimary,
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: _rewrittenText!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('📋 Đã sao chép vào clipboard'),
                                    duration: Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Sao chép'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primary,
                                side: BorderSide(
                                    color: primary.withValues(alpha: 0.4)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                widget.onApply(_rewrittenText!);
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.send_rounded, size: 16),
                              label: const Text('Gửi ngay'),
                              style: FilledButton.styleFrom(
                                backgroundColor: primary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_rounded,
                        size: 32, color: p.textHint.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Text(
                      'Chọn tông giọng ở trên để viết lại tin nhắn',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: p.textHint,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
