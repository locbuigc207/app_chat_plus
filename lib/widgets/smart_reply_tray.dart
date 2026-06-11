// lib/widgets/smart_reply_tray.dart
// SmartReplyTray — Khay gợi ý trả lời nhanh đa phương tiện (text + sticker)
// Hỗ trợ: tone-aware chips, sticker thumbnails, entry animation

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/smart_reply_item.dart';
import '../providers/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class SmartReplyTray extends StatefulWidget {
  /// Danh sách gợi ý (text + sticker đã merged)
  final List<SmartReplyItem> items;

  /// true khi AI đang xử lý
  final bool isLoading;

  /// Callback khi người dùng chọn: (payload, messageType)
  /// messageType: 0=text, 2=sticker
  final void Function(String payload, int messageType) onSelect;

  /// Đóng khay
  final VoidCallback? onDismiss;

  const SmartReplyTray({
    super.key,
    required this.items,
    required this.onSelect,
    this.isLoading = false,
    this.onDismiss,
  });

  @override
  State<SmartReplyTray> createState() => _SmartReplyTrayState();
}

class _SmartReplyTrayState extends State<SmartReplyTray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _slideAnim =
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.5),
          end: Offset.zero,
        ).animate(_slideAnim),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(
              top: BorderSide(color: p.divider, width: 0.5),
            ),
          ),
          child: widget.isLoading
              ? _LoadingState(p: p, primary: theme.primaryColor)
              : widget.items.isEmpty
                  ? const SizedBox.shrink()
                  : _Content(
                      items: widget.items,
                      onSelect: widget.onSelect,
                      onDismiss: widget.onDismiss,
                      p: p,
                      theme: theme,
                    ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADING STATE
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  final ThemePalette p;
  final Color primary;
  const _LoadingState({required this.p, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 16),
        SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: primary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'AI đang gợi ý…',
          style: TextStyle(
            fontSize: 12.5,
            color: p.textHint,
            fontStyle: FontStyle.italic,
          ),
        ),
        // Loading skeleton chips
        const SizedBox(width: 12),
        ...List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _SkeletonChip(width: 60.0 + i * 16),
          ),
        ),
      ],
    );
  }
}

class _SkeletonChip extends StatefulWidget {
  final double width;
  const _SkeletonChip({required this.width});

  @override
  State<_SkeletonChip> createState() => _SkeletonChipState();
}

class _SkeletonChipState extends State<_SkeletonChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: widget.width,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.08 + _ctrl.value * 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT ROW
// ─────────────────────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  final List<SmartReplyItem> items;
  final void Function(String, int) onSelect;
  final VoidCallback? onDismiss;
  final ThemePalette p;
  final ThemeProvider theme;

  const _Content({
    required this.items,
    required this.onSelect,
    required this.onDismiss,
    required this.p,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final textItems = items.where((i) => i.isText).toList();
    final stickerItems = items.where((i) => i.isSticker).toList();

    return Row(
      children: [
        // ── AI Badge ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: _AiBadge(primaryColor: theme.primaryColor),
        ),

        // ── Scrollable chips + stickers ─────────────────────────────────────
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            children: [
              // Text chips
              for (int i = 0; i < textItems.length; i++) ...[
                _TextChip(
                  item: textItems[i],
                  index: i,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSelect(
                        textItems[i].sendPayload, textItems[i].messageType);
                  },
                  p: p,
                  theme: theme,
                ),
                const SizedBox(width: 8),
              ],

              // Separator khi có cả text và sticker
              if (textItems.isNotEmpty && stickerItems.isNotEmpty) ...[
                _SeparatorLine(p: p),
                const SizedBox(width: 10),
              ],

              // Sticker thumbnails
              for (int i = 0; i < stickerItems.length; i++) ...[
                _StickerThumbnail(
                  item: stickerItems[i],
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onSelect(stickerItems[i].sendPayload,
                        stickerItems[i].messageType);
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),

        // ── Dismiss ──────────────────────────────────────────────────────────
        if (onDismiss != null)
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Icon(Icons.close_rounded, size: 16, color: p.textHint),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _AiBadge extends StatelessWidget {
  final Color primaryColor;
  const _AiBadge({required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, const Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'AI',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEXT CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _TextChip extends StatefulWidget {
  final SmartReplyItem item;
  final int index;
  final VoidCallback onTap;
  final ThemePalette p;
  final ThemeProvider theme;

  const _TextChip({
    required this.item,
    required this.index,
    required this.onTap,
    required this.p,
    required this.theme,
  });

  @override
  State<_TextChip> createState() => _TextChipState();
}

class _TextChipState extends State<_TextChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    lowerBound: 0.94,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  // ── Tone → visual styling ──────────────────────────────────────────────────

  List<Color> _getGradient() {
    final isDark = widget.p.isDark;
    if (isDark) {
      return switch (widget.item.tone) {
        SmartReplyTone.formal => [
            const Color(0xFF1C2336),
            const Color(0xFF243049)
          ],
        SmartReplyTone.playful => [
            const Color(0xFF2A1A4A),
            const Color(0xFF341F5E)
          ],
        SmartReplyTone.empathetic => [
            const Color(0xFF18281A),
            const Color(0xFF1E3321)
          ],
        _ => [const Color(0xFF1E2130), const Color(0xFF242840)],
      };
    }
    return switch (widget.item.tone) {
      SmartReplyTone.formal => [
          const Color(0xFFEDF2FF),
          const Color(0xFFE4ECFF)
        ],
      SmartReplyTone.playful => [
          const Color(0xFFFCEFFF),
          const Color(0xFFF8E5FF)
        ],
      SmartReplyTone.empathetic => [
          const Color(0xFFEDFFF5),
          const Color(0xFFE4FFEF)
        ],
      _ => [const Color(0xFFF4F7FF), const Color(0xFFECF0FF)],
    };
  }

  Color _getBorderColor() {
    final base = widget.theme.primaryColor;
    return switch (widget.item.tone) {
      SmartReplyTone.formal => base.withOpacity(0.4),
      SmartReplyTone.playful => const Color(0xFFD946EF).withOpacity(0.35),
      SmartReplyTone.empathetic => const Color(0xFF10B981).withOpacity(0.35),
      _ => base.withOpacity(0.22),
    };
  }

  Color _getTextColor() {
    return switch (widget.item.tone) {
      SmartReplyTone.formal => widget.theme.primaryColor,
      SmartReplyTone.playful =>
        widget.p.isDark ? const Color(0xFFE879F9) : const Color(0xFFA21CAF),
      SmartReplyTone.empathetic =>
        widget.p.isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
      _ =>
        widget.p.isDark ? const Color(0xFFC4D0FF) : widget.theme.primaryColor,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.animateTo(0.94, curve: Curves.easeOut),
      onTapUp: (_) {
        _pressCtrl.animateTo(1.0, curve: Curves.elasticOut);
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.animateTo(1.0, curve: Curves.easeOut),
      child: AnimatedBuilder(
        animation: _pressCtrl,
        builder: (_, child) => Transform.scale(
          scale: _pressCtrl.value,
          child: child,
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 168),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _getGradient(),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _getBorderColor(), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: _getBorderColor().withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.item.text,
                  style: TextStyle(
                    color: _getTextColor(),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STICKER THUMBNAIL
// ─────────────────────────────────────────────────────────────────────────────

class _StickerThumbnail extends StatefulWidget {
  final SmartReplyItem item;
  final VoidCallback onTap;

  const _StickerThumbnail({required this.item, required this.onTap});

  @override
  State<_StickerThumbnail> createState() => _StickerThumbnailState();
}

class _StickerThumbnailState extends State<_StickerThumbnail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    lowerBound: 0.88,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stickerId = widget.item.stickerId ?? widget.item.text;
    return GestureDetector(
      onTapDown: (_) => _ctrl.animateTo(0.88, curve: Curves.easeOut),
      onTapUp: (_) {
        _ctrl.animateTo(1.0, curve: Curves.elasticOut);
        widget.onTap();
      },
      onTapCancel: () => _ctrl.animateTo(1.0, curve: Curves.easeOut),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) =>
            Transform.scale(scale: _ctrl.value, child: child),
        child: Tooltip(
          message: 'Gửi sticker',
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF).withOpacity(0.7),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF6366F1).withOpacity(0.22),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // GIF image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    StickerCatalog.assetPath(stickerId),
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.emoji_emotions_outlined,
                        size: 20,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ),
                // Send indicator dot
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      size: 7,
                      color: Colors.white,
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// SEPARATOR LINE
// ─────────────────────────────────────────────────────────────────────────────

class _SeparatorLine extends StatelessWidget {
  final ThemePalette p;
  const _SeparatorLine({required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: p.divider,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STICKER PICKER SHEET — cho người dùng chủ động chọn sticker để trả lời
// ─────────────────────────────────────────────────────────────────────────────

class StickerPickerSheet extends StatelessWidget {
  final void Function(String stickerId) onSelect;

  const StickerPickerSheet({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).padding.bottom + 20),
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
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: p.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          // Header
          Row(
            children: [
              _AiBadge(primaryColor: theme.primaryColor),
              const SizedBox(width: 8),
              Text(
                'Sticker gợi ý',
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: StickerCatalog.all.length,
            itemBuilder: (_, i) {
              final meta = StickerCatalog.all[i];
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  onSelect(meta.id);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: p.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.divider, width: 0.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.asset(
                      StickerCatalog.assetPath(meta.id),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(meta.label,
                            style: TextStyle(
                                fontSize: 11, color: p.textSecondary)),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
