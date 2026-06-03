// lib/widgets/relationship_memory_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';
import 'package:provider/provider.dart';

class RelationshipMemoryWidget extends StatefulWidget {
  final String conversationId;
  final String peerName;

  const RelationshipMemoryWidget({
    super.key,
    required this.conversationId,
    required this.peerName,
  });

  @override
  State<RelationshipMemoryWidget> createState() =>
      _RelationshipMemoryWidgetState();
}

class _RelationshipMemoryWidgetState extends State<RelationshipMemoryWidget>
    with SingleTickerProviderStateMixin {
  RelationshipMemory? _memory;
  bool _loading = false;
  bool _loaded = false;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result =
          await AIBackendService().extractRelationshipMemoryFromLocal(
        conversationId: widget.conversationId,
      );
      if (!mounted) return;
      setState(() {
        _memory = result;
        _loading = false;
        _loaded = true;
      });
      _animCtrl.forward();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loaded = true;
      });
    }
  }

  void _refresh() {
    _animCtrl.reset();
    setState(() {
      _loaded = false;
      _memory = null;
    });
    _load();
  }

  String _getRelationshipIcon(String? type) => switch (type) {
        'friend' => '🤝',
        'family' => '👨‍👩‍👧',
        'colleague' => '💼',
        'romantic' => '💕',
        _ => '👤',
      };

  String _getRelationshipLabel(String? type) => switch (type) {
        'friend' => 'Bạn bè',
        'family' => 'Gia đình',
        'colleague' => 'Đồng nghiệp',
        'romantic' => 'Tình cảm',
        _ => 'Không xác định',
      };

  Color _getClosenessColor(ThemePalette p, int level) {
    if (level >= 4) return p.successColor;
    if (level >= 3) return p.infoColor;
    if (level >= 2) return p.warningColor;
    return p.textHint;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeProvider>();
    final p = theme.palette;
    final primary = theme.primaryColor;

    // Pre-load state: tap to trigger
    if (!_loaded) {
      return GestureDetector(
        onTap: _load,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFEC4899).withValues(alpha: 0.15),
                      primary.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.psychology_rounded,
                    color: Color(0xFFEC4899), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phân tích mối quan hệ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      'Với ${widget.peerName}',
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              if (_loading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: primary),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFFEC4899), primary],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Phân tích',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // No data
    if (_memory == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: p.textHint, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Chưa đủ dữ liệu để phân tích mối quan hệ với ${widget.peerName}',
                style: TextStyle(fontSize: 13, color: p.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final mem = _memory!;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: const Color(0xFFEC4899).withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                  color: p.shadow, blurRadius: 10, offset: const Offset(0, 3))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEC4899), Color(0xFFFF6B9D)],
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Center(
                      child: Text('❤️', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phân tích mối quan hệ',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                        Text(
                          'Với ${widget.peerName}',
                          style:
                              TextStyle(fontSize: 12, color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _refresh,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: p.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.refresh_rounded,
                          size: 16, color: p.textHint),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Relationship type
              if (mem.relationshipType != null) ...[
                Row(
                  children: [
                    Text(
                      _getRelationshipIcon(mem.relationshipType),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Loại quan hệ: ',
                      style: TextStyle(fontSize: 12.5, color: p.textHint),
                    ),
                    _RelChip(
                      _getRelationshipLabel(mem.relationshipType),
                      const Color(0xFFEC4899),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // Closeness level
              if (mem.closenessLevel != null && mem.closenessLevel! > 0) ...[
                Row(
                  children: [
                    Text(
                      'Độ thân thiết: ',
                      style: TextStyle(fontSize: 12.5, color: p.textHint),
                    ),
                    ...List.generate(5, (i) {
                      final filled = i < (mem.closenessLevel ?? 0);
                      final color =
                          _getClosenessColor(p, mem.closenessLevel ?? 0);
                      return Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Icon(
                          filled
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 16,
                          color: filled ? color : p.divider,
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // Communication style
              if (mem.communicationStyle != null) ...[
                Row(
                  children: [
                    Text(
                      'Phong cách: ',
                      style: TextStyle(fontSize: 12.5, color: p.textHint),
                    ),
                    _RelChip(
                      switch (mem.communicationStyle) {
                        'formal' => '📋 Trang trọng',
                        'casual' => '😊 Thoải mái',
                        _ => '🔄 Linh hoạt',
                      },
                      primary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Shared topics
              if (mem.sharedTopics.isNotEmpty) ...[
                Text(
                  'Chủ đề chung:',
                  style: TextStyle(fontSize: 12.5, color: p.textHint),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: mem.sharedTopics
                      .take(8)
                      .map((t) => _RelChip(t, primary))
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],

              // Important dates
              if (mem.importantDates.isNotEmpty) ...[
                Text(
                  'Ngày đáng nhớ:',
                  style: TextStyle(fontSize: 12.5, color: p.textHint),
                ),
                const SizedBox(height: 6),
                ...mem.importantDates.take(4).map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('📅', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                d,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: p.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
              ],

              // Summary
              if (mem.summary != null && mem.summary!.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    mem.summary!,
                    style: TextStyle(
                      fontSize: 13,
                      color: p.textSecondary,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RelChip extends StatelessWidget {
  final String label;
  final Color color;

  const _RelChip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}
