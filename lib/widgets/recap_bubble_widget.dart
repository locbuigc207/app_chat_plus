// lib/widgets/recap_bubble_widget.dart
// Bong bóng Recap dạng Card + tính năng chia sẻ Story 9:16
// Bao gồm: RecapBubbleWidget, RecapShareSheet, RecapStoryCard (9:16)

// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/weekly_recap_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// STYLE THEME CONFIG
// ══════════════════════════════════════════════════════════════════════════════

class _RecapStyleTheme {
  final Color colorStart;
  final Color colorEnd;
  final Color accentColor;
  final IconData icon;

  const _RecapStyleTheme({
    required this.colorStart,
    required this.colorEnd,
    required this.accentColor,
    required this.icon,
  });
}

const Map<RecapStyle, _RecapStyleTheme> _kStyleThemes = {
  RecapStyle.humorous: _RecapStyleTheme(
    colorStart: Color(0xFFBF360C),
    colorEnd: Color(0xFFFF8F00),
    accentColor: Color(0xFFFFE082),
    icon: Icons.emoji_emotions_rounded,
  ),
  RecapStyle.professional: _RecapStyleTheme(
    colorStart: Color(0xFF0A1628),
    colorEnd: Color(0xFF1565C0),
    accentColor: Color(0xFF82B1FF),
    icon: Icons.analytics_rounded,
  ),
  RecapStyle.romantic: _RecapStyleTheme(
    colorStart: Color(0xFF4A0E2B),
    colorEnd: Color(0xFFAD1457),
    accentColor: Color(0xFFF48FB1),
    icon: Icons.favorite_rounded,
  ),
  RecapStyle.tvHost: _RecapStyleTheme(
    colorStart: Color(0xFF1A0A00),
    colorEnd: Color(0xFFBF360C),
    accentColor: Color(0xFFFFCC80),
    icon: Icons.live_tv_rounded,
  ),
  RecapStyle.minimal: _RecapStyleTheme(
    colorStart: Color(0xFF102027),
    colorEnd: Color(0xFF37474F),
    accentColor: Color(0xFFB0BEC5),
    icon: Icons.format_list_bulleted_rounded,
  ),
};

// ══════════════════════════════════════════════════════════════════════════════
// RECAP BUBBLE WIDGET  (inline card in chat / recap page)
// ══════════════════════════════════════════════════════════════════════════════

/// Widget hiển thị kết quả recap dạng card gọn đẹp.
/// Có nút "Chia sẻ" mở RecapShareSheet với card 9:16.
class RecapBubbleWidget extends StatelessWidget {
  final WeeklyRecapData recap;
  final String conversationName;
  final VoidCallback? onRefresh;

  const RecapBubbleWidget({
    super.key,
    required this.recap,
    required this.conversationName,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final primary = theme.primaryColor;
    final st = _kStyleThemes[recap.style]!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: st.colorEnd.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(color: st.colorEnd.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Gradient header ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [st.colorStart, st.colorEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Icon(st.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(recap.recapTitle,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                    Text(
                      DateFormat('dd/MM/yyyy').format(recap.generatedAt),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5),
                    ),
                  ]),
                ),
                // Sentiment badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${recap.sentimentEmoji} ${recap.sentimentLabel}',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),

            // ── Body ─────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Summary text
                Text(
                  recap.fullText,
                  style: TextStyle(fontSize: 13.5, color: p.textSecondary, height: 1.65),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),

                if (recap.hasHighlights) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: st.colorEnd.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: st.colorEnd.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.auto_awesome_rounded, size: 14, color: st.colorEnd),
                          const SizedBox(width: 6),
                          Text('Điểm nổi bật',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: st.colorEnd)),
                        ]),
                        const SizedBox(height: 8),
                        ...recap.highlights.take(3).map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(color: st.colorEnd, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(h,
                                  style: TextStyle(fontSize: 13, color: p.textSecondary, height: 1.4)),
                            ),
                          ]),
                        )),
                      ],
                    ),
                  ),
                ],

                // Keywords
                if (recap.hasKeywords) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    ...recap.topKeywords.take(5).map((kw) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: p.surfaceVariant,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: p.divider),
                      ),
                      child: Text('#$kw', style: TextStyle(fontSize: 11, color: p.textHint, fontWeight: FontWeight.w500)),
                    )),
                  ]),
                ],

                const SizedBox(height: 14),

                // Stats + action row
                Row(children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 14, color: p.textHint),
                  const SizedBox(width: 4),
                  Text('${recap.messageCount} tin nhắn',
                      style: TextStyle(fontSize: 12, color: p.textHint)),
                  const SizedBox(width: 12),
                  Icon(Icons.schedule_rounded, size: 14, color: p.textHint),
                  const SizedBox(width: 4),
                  Text('${recap.lookbackDays} ngày qua',
                      style: TextStyle(fontSize: 12, color: p.textHint)),
                  const Spacer(),
                  if (onRefresh != null)
                    GestureDetector(
                      onTap: onRefresh,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: p.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.refresh_rounded, size: 16, color: p.textHint),
                      ),
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _openShareSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [st.colorStart, st.colorEnd],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: st.colorEnd.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.share_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Chia sẻ Story', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void _openShareSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => RecapShareSheet(
        recap: recap,
        conversationName: conversationName,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RECAP SHARE SHEET  (bottom sheet hiển thị card 9:16 + actions)
// ══════════════════════════════════════════════════════════════════════════════

class RecapShareSheet extends StatefulWidget {
  final WeeklyRecapData recap;
  final String conversationName;

  const RecapShareSheet({
    super.key,
    required this.recap,
    required this.conversationName,
  });

  @override
  State<RecapShareSheet> createState() => _RecapShareSheetState();
}

class _RecapShareSheetState extends State<RecapShareSheet> with SingleTickerProviderStateMixin {
  final GlobalKey _repaintKey = GlobalKey();
  late final AnimationController _enterAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  bool _isCapturing = false;
  bool _screenshotMode = false;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _enterAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _enterAnim, curve: Curves.easeOutBack),
    );
    _fadeAnim = CurvedAnimation(parent: _enterAnim, curve: Curves.easeOut);
    _enterAnim.forward();
  }

  @override
  void dispose() {
    _enterAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;
    final size = MediaQuery.sizeOf(context);

    // Card 9:16 — chọn kích thước vừa màn hình
    final cardWidth = (size.width * 0.82).clamp(240.0, 360.0);
    final cardHeight = cardWidth * (16 / 9);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: _screenshotMode ? Colors.black : p.surface,
        borderRadius: _screenshotMode ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_screenshotMode) ...[
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: p.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Text('Chia sẻ Tổng Kết',
                      style: TextStyle(color: p.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close_rounded, color: p.textHint, size: 22),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── 9:16 Card ────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _screenshotMode ? 0 : (size.width - cardWidth) / 2,
                vertical: _screenshotMode ? 0 : 0,
              ),
              child: ScaleTransition(
                scale: _scaleAnim,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: SizedBox(
                      width: _screenshotMode ? size.width : cardWidth,
                      height: _screenshotMode ? size.width * (16 / 9) : cardHeight,
                      child: RecapStoryCard(
                        recap: widget.recap,
                        conversationName: widget.conversationName,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (_screenshotMode) ...[
              // Screenshot mode hint
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                color: Colors.black,
                child: Column(
                  children: [
                    const Text(
                      '📸 Chụp màn hình để lưu',
                      style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => setState(() => _screenshotMode = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('Thoát chế độ chụp',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              // ── Action buttons ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Expanded(child: _ActionButton(
                    icon: Icons.photo_camera_rounded,
                    label: 'Chế độ\nChụp',
                    color: const Color(0xFF37474F),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _screenshotMode = true);
                    },
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _ActionButton(
                    icon: Icons.save_alt_rounded,
                    label: 'Lưu\nẢnh',
                    color: const Color(0xFF1565C0),
                    isLoading: _isCapturing,
                    onTap: _captureAndSave,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _ActionButton(
                    icon: Icons.content_copy_rounded,
                    label: 'Sao chép\nNội dung',
                    color: const Color(0xFF2E7D32),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.recap.fullText));
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Đã sao chép nội dung recap'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  )),
                ]),
              ),

              if (_savedPath != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Ảnh đã lưu thành công!',
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(_savedPath!.split('/').last,
                              style: const TextStyle(color: Colors.green, fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ]),
                  ),
                ),

              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _captureAndSave() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final bytes = await _captureWidget();
      if (bytes == null) {
        _showError('Không thể chụp ảnh. Vui lòng thử lại.');
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'recap_${widget.recap.style.key}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _savedPath = file.path);
    } catch (e) {
      _showError('Lỗi lưu ảnh: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<Uint8List?> _captureWidget() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[RecapShare] Capture error: $e');
      return null;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ACTION BUTTON
// ══════════════════════════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isLoading ? color.withValues(alpha: 0.5) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          isLoading
              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: color))
              : Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RECAP STORY CARD  (9:16 shareable card — nội dung được render để chụp)
// ══════════════════════════════════════════════════════════════════════════════

class RecapStoryCard extends StatelessWidget {
  final WeeklyRecapData recap;
  final String conversationName;

  const RecapStoryCard({
    super.key,
    required this.recap,
    required this.conversationName,
  });

  @override
  Widget build(BuildContext context) {
    final st = _kStyleThemes[recap.style]!;

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;

      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [st.colorStart, st.colorEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            // ── Decorative background circles ─────────────────────────────────
            Positioned(
              right: -w * 0.15,
              top: -h * 0.05,
              child: _DecorCircle(size: w * 0.75, color: st.accentColor, opacity: 0.08),
            ),
            Positioned(
              left: -w * 0.2,
              bottom: h * 0.15,
              child: _DecorCircle(size: w * 0.65, color: Colors.white, opacity: 0.05),
            ),
            Positioned(
              right: w * 0.05,
              bottom: h * 0.28,
              child: _DecorCircle(size: w * 0.3, color: st.accentColor, opacity: 0.12),
            ),
            Positioned(
              left: w * 0.1,
              top: h * 0.28,
              child: _DecorCircle(size: w * 0.18, color: Colors.white, opacity: 0.08),
            ),

            // ── Content ───────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.07, vertical: h * 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar: App branding + date
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.chat_rounded, color: Colors.white, size: 16),
                        ),
                        const SizedBox(width: 7),
                        const Text('ChatApp',
                            style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                      ]),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          DateFormat('dd/MM/yyyy').format(recap.generatedAt),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: h * 0.04),

                  // Style emoji + label badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: st.accentColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(st.icon, color: st.accentColor, size: 14),
                      const SizedBox(width: 5),
                      Text(recap.styleLabel,
                          style: TextStyle(color: st.accentColor, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ]),
                  ),

                  SizedBox(height: h * 0.025),

                  // Conversation name
                  Text(conversationName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: w * 0.065,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),

                  SizedBox(height: h * 0.01),

                  Text(
                    '${recap.lookbackDays} ngày qua  ·  ${recap.messageCount} tin nhắn',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: w * 0.03),
                  ),

                  SizedBox(height: h * 0.03),

                  // Divider line
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),

                  SizedBox(height: h * 0.03),

                  // Main recap text
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recap.fullText,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: w * 0.038,
                              height: 1.6,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                          ),

                          if (recap.hasHighlights) ...[
                            SizedBox(height: h * 0.025),
                            Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                            SizedBox(height: h * 0.02),
                            Row(children: [
                              Icon(Icons.auto_awesome_rounded, color: st.accentColor, size: 13),
                              const SizedBox(width: 5),
                              Text('Điểm nổi bật',
                                  style: TextStyle(color: st.accentColor, fontSize: 12, fontWeight: FontWeight.w700)),
                            ]),
                            SizedBox(height: h * 0.012),
                            ...recap.highlights.take(3).map((h_) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 5, right: 7),
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(color: st.accentColor, shape: BoxShape.circle),
                                ),
                                Expanded(child: Text(h_,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
                                        fontSize: w * 0.032, height: 1.4))),
                              ]),
                            )),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── Footer ────────────────────────────────────────────────────
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
                  SizedBox(height: h * 0.02),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Text(recap.sentimentEmoji, style: TextStyle(fontSize: w * 0.04)),
                        const SizedBox(width: 5),
                        Text(recap.sentimentLabel,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: w * 0.03)),
                      ]),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: w * 0.03, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#TổngKếtTuần',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: w * 0.028, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DECORATIVE CIRCLE
// ══════════════════════════════════════════════════════════════════════════════

class _DecorCircle extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _DecorCircle({required this.size, required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: opacity),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// RECAP LOADING SHIMMER PLACEHOLDER
// ══════════════════════════════════════════════════════════════════════════════

class RecapLoadingPlaceholder extends StatefulWidget {
  const RecapLoadingPlaceholder({super.key});

  @override
  State<RecapLoadingPlaceholder> createState() => _RecapLoadingPlaceholderState();
}

class _RecapLoadingPlaceholderState extends State<RecapLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>().palette;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final opacity = 0.4 + 0.3 * _anim.value;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: p.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header shimmer
              Row(children: [
                _Shimmer(width: 40, height: 40, radius: 12, color: p.surfaceVariant, opacity: opacity),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Shimmer(width: 140, height: 14, radius: 7, color: p.surfaceVariant, opacity: opacity),
                  const SizedBox(height: 6),
                  _Shimmer(width: 80, height: 10, radius: 5, color: p.surfaceVariant, opacity: opacity),
                ]),
              ]),
              const SizedBox(height: 20),
              // Lines shimmer
              ...List.generate(4, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Shimmer(
                  width: double.infinity,
                  height: 12,
                  radius: 6,
                  color: p.surfaceVariant,
                  opacity: opacity * (1 - i * 0.08),
                ),
              )),
              const SizedBox(height: 16),
              // Generating text
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.watch<ThemeProvider>().primaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('AI đang tạo tóm tắt...',
                      style: TextStyle(color: p.textHint, fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final Color color;
  final double opacity;

  const _Shimmer({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}