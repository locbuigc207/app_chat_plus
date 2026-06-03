// lib/widgets/icebreaker_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';
import 'package:provider/provider.dart';

class IcebreakerPanel extends StatefulWidget {
  final String peerId;
  final String peerName;
  final void Function(String text) onSelect;

  const IcebreakerPanel({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.onSelect,
  });

  @override
  State<IcebreakerPanel> createState() => _IcebreakerPanelState();
}

class _IcebreakerPanelState extends State<IcebreakerPanel>
    with SingleTickerProviderStateMixin {
  List<String> _icebreakers = [];
  bool _isLoading = false;
  bool _hasError = false;
  String _style = 'casual';

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;

  static const _styles = <String, (String, Color)>{
    'casual': ('😊 Nhẹ nhàng', Color(0xFF10B981)),
    'playful': ('🎉 Vui vẻ', Color(0xFFF59E0B)),
    'deep': ('🧠 Sâu sắc', Color(0xFF8B5CF6)),
    'work': ('💼 Công việc', Color(0xFF0EA5E9)),
  };

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _icebreakers = [];
    });
    _animCtrl.reset();
    try {
      final results = await AIBackendService().generateIcebreakers(
        count: 5,
        style: _style,
        relationshipType: 'friend',
      );
      if (!mounted) return;
      setState(() {
        _icebreakers = results;
        _isLoading = false;
      });
      _animCtrl.forward();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _changeStyle(String style) {
    if (_style == style || _isLoading) return;
    HapticFeedback.selectionClick();
    setState(() => _style = style);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeProvider>();
    final p = theme.palette;
    final primary = theme.primaryColor;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.58,
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 24),
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
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: p.divider,
              borderRadius: BorderRadius.circular(999),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(Icons.waving_hand_rounded, color: primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mở đầu với ${widget.peerName}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'AI gợi ý câu mở đầu phù hợp',
                        style: TextStyle(fontSize: 11.5, color: p.textHint),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _isLoading ? 1 : 0,
                  duration: const Duration(seconds: 1),
                  child: TextButton.icon(
                    onPressed: _isLoading ? null : _load,
                    icon: Icon(Icons.refresh_rounded,
                        size: 16, color: _isLoading ? p.textHint : primary),
                    label: Text(
                      'Tạo lại',
                      style:
                          TextStyle(color: _isLoading ? p.textHint : primary),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Style selector
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _styles.entries.map((e) {
                final isSelected = _style == e.key;
                final label = e.value.$1;
                final color = e.value.$2;
                return GestureDetector(
                  onTap: () => _changeStyle(e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? color : p.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? color
                            : p.divider.withValues(alpha: 0.6),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                  color: color.withValues(alpha: 0.25),
                                  blurRadius: 6)
                            ]
                          : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : p.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Content
          Flexible(
            child: _isLoading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                              color: primary, strokeWidth: 2.5),
                          const SizedBox(height: 14),
                          Text(
                            'AI đang sáng tạo câu mở đầu...',
                            style: TextStyle(color: p.textHint, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : _hasError
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: p.surfaceVariant,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.wifi_off_rounded,
                                    size: 32, color: p.textHint),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Không thể tải gợi ý',
                                style: TextStyle(
                                  color: p.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _load,
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Thử lại'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: primary),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _icebreakers.isEmpty
                        ? Center(
                            child: Text(
                              'Không có gợi ý nào',
                              style: TextStyle(color: p.textHint),
                            ),
                          )
                        : FadeTransition(
                            opacity: _fadeAnim,
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              itemCount: _icebreakers.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: p.divider,
                              ),
                              itemBuilder: (_, i) {
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      HapticFeedback.mediumImpact();
                                      widget.onSelect(_icebreakers[i]);
                                      Navigator.pop(context);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: primary.withValues(
                                                  alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${i + 1}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              _icebreakers[i],
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                color: p.textPrimary,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: primary.withValues(
                                                  alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              Icons.send_rounded,
                                              size: 16,
                                              color: primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
