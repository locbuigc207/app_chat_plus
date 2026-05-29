// ignore_for_file: use_build_context_synchronously
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:provider/provider.dart';






Color _getThemeBaseColor(ThemeColor color) {
  switch (color) {
    case ThemeColor.blue:
      return const Color(0xFF2196F3);
    case ThemeColor.green:
      return const Color(0xFF4CAF50);
    case ThemeColor.purple:
      return const Color(0xFF9C27B0);
    case ThemeColor.orange:
      return const Color(0xFFFF9800);
    case ThemeColor.pink:
      return const Color(0xFFE91E63);
    case ThemeColor.teal:
      return const Color(0xFF009688);
    case ThemeColor.red:
      return const Color(0xFFE53935);
    case ThemeColor.indigo:
      return const Color(0xFF5A67D8);
    case ThemeColor.violet:
      return const Color(0xFF7C3AED);
    case ThemeColor.rose:
      return const Color(0xFFE11D48);
    case ThemeColor.amber:
      return const Color(0xFFD97706);
    case ThemeColor.emerald:
      return const Color(0xFF059669);
    case ThemeColor.sky:
      return const Color(0xFF0284C7);
    case ThemeColor.coral:
      return const Color(0xFFEA580C);
    case ThemeColor.slate:
      return const Color(0xFF475569);
  }
}

Color _getThemeLightColor(ThemeColor color) {
  switch (color) {
    case ThemeColor.blue:
      return const Color(0xFF64B5F6);
    case ThemeColor.green:
      return const Color(0xFF81C784);
    case ThemeColor.purple:
      return const Color(0xFFCE93D8);
    case ThemeColor.orange:
      return const Color(0xFFFFB74D);
    case ThemeColor.pink:
      return const Color(0xFFF48FB1);
    case ThemeColor.teal:
      return const Color(0xFF80CBC4);
    case ThemeColor.red:
      return const Color(0xFFEF9A9A);
    case ThemeColor.indigo:
      return const Color(0xFF7F8CF7);
    case ThemeColor.violet:
      return const Color(0xFFA78BFA);
    case ThemeColor.rose:
      return const Color(0xFFFB7185);
    case ThemeColor.amber:
      return const Color(0xFFFBBF24);
    case ThemeColor.emerald:
      return const Color(0xFF34D399);
    case ThemeColor.sky:
      return const Color(0xFF38BDF8);
    case ThemeColor.coral:
      return const Color(0xFFFB923C);
    case ThemeColor.slate:
      return const Color(0xFF94A3B8);
  }
}

String _getThemeColorName(ThemeColor color) {
  switch (color) {
    case ThemeColor.blue:
      return 'Xanh dương';
    case ThemeColor.green:
      return 'Xanh lá';
    case ThemeColor.purple:
      return 'Tím';
    case ThemeColor.orange:
      return 'Cam';
    case ThemeColor.pink:
      return 'Hồng';
    case ThemeColor.teal:
      return 'Xanh cổ vịt';
    case ThemeColor.red:
      return 'Đỏ';
    case ThemeColor.indigo:
      return 'Chàm';
    case ThemeColor.violet:
      return 'Tím Violet';
    case ThemeColor.rose:
      return 'Hồng Rose';
    case ThemeColor.amber:
      return 'Hổ phách';
    case ThemeColor.emerald:
      return 'Xanh ngọc';
    case ThemeColor.sky:
      return 'Xanh trời';
    case ThemeColor.coral:
      return 'San hô';
    case ThemeColor.slate:
      return 'Xám xanh';
  }
}





class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> with TickerProviderStateMixin {
  late AnimationController _headerAnim;
  late AnimationController _contentAnim;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _contentAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    _contentAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final p = theme.palette;

    return Theme(
      data: theme.isDark ? theme.darkTheme : theme.lightTheme,
      child: Scaffold(
        backgroundColor: p.background,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildSliverAppBar(theme, p),
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _contentAnim,
                  curve: Curves.easeOut,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel(text: 'Chế độ hiển thị', palette: p),
                      _ThemeModeCard(theme: theme, palette: p),
                      const SizedBox(height: 24),
                      _SectionLabel(text: 'Màu chủ đạo', palette: p),
                      _ColorPaletteCard(theme: theme, palette: p),
                      const SizedBox(height: 24),
                      _SectionLabel(text: 'Kiểu bong bóng tin nhắn', palette: p),
                      _BubbleStyleCard(theme: theme, palette: p),
                      const SizedBox(height: 24),
                      _SectionLabel(text: 'Cỡ chữ', palette: p),
                      _FontSizeCard(theme: theme, palette: p),
                      const SizedBox(height: 24),
                      _SectionLabel(text: 'Hình nền chat', palette: p),
                      _WallpaperCard(theme: theme, palette: p),
                      const SizedBox(height: 24),
                      _SectionLabel(text: 'Tùy chọn nâng cao', palette: p),
                      _AdvancedOptionsCard(theme: theme, palette: p),
                      const SizedBox(height: 24),
                      _SectionLabel(text: 'Xem trước', palette: p),
                      _LivePreviewCard(theme: theme, palette: p),
                      const SizedBox(height: 32),
                      _ResetButton(theme: theme, palette: p),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(ThemeProvider theme, ThemePalette p) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      stretch: true,
      backgroundColor: p.appBarBackground,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: p.textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: _AnimatedColorDot(color: theme.primaryColor),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: FadeTransition(
          opacity: _headerAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Giao diện',
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Tùy chỉnh trải nghiệm của bạn',
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        background: _HeaderBackground(palette: p, primaryColor: theme.primaryColor),
        stretchModes: const [StretchMode.blurBackground, StretchMode.fadeTitle],
      ),
    );
  }
}





class _HeaderBackground extends StatelessWidget {
  const _HeaderBackground({required this.palette, required this.primaryColor});
  final ThemePalette palette;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: palette.appBarBackground),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -20,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withValues(alpha: palette.isDark ? 0.08 : 0.06),
              ),
            ),
          ),
          Positioned(
            right: 40,
            top: 20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withValues(alpha: palette.isDark ? 0.05 : 0.04),
              ),
            ),
          ),
        ],
      ),
    );
  }
}





class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.palette});
  final String text;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: palette.textHint,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}





class _Card extends StatelessWidget {
  const _Card({required this.palette, required this.child, this.padding});
  final ThemePalette palette;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.divider, width: 0.6),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}





class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({required this.theme, required this.palette});
  final ThemeProvider theme;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      child: Column(
        children: [
          _ThemeModeRow(
            mode: AppThemeMode.light,
            label: 'Sáng',
            subtitle: 'Nền trắng, nhìn rõ ngoài trời',
            icon: Icons.wb_sunny_rounded,
            theme: theme,
            palette: palette,
            showDivider: true,
          ),
          _ThemeModeRow(
            mode: AppThemeMode.dark,
            label: 'Tối',
            subtitle: 'Bảo vệ mắt khi trời tối',
            icon: Icons.nightlight_round,
            theme: theme,
            palette: palette,
            showDivider: true,
          ),
          _ThemeModeRow(
            mode: AppThemeMode.system,
            label: 'Tự động',
            subtitle: 'Theo cài đặt hệ thống',
            icon: Icons.brightness_auto_rounded,
            theme: theme,
            palette: palette,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({
    required this.mode,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.theme,
    required this.palette,
    required this.showDivider,
  });

  final AppThemeMode mode;
  final String label;
  final String subtitle;
  final IconData icon;
  final ThemeProvider theme;
  final ThemePalette palette;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isSelected = theme.themeMode == mode;
    final primary = theme.primaryColor;

    return Column(
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            theme.setThemeMode(mode);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isSelected ? primary.withValues(alpha: 0.12) : palette.surfaceVariant,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? primary : palette.textSecondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: isSelected
                      ? Container(
                          key: const ValueKey('on'),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: primary.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                        )
                      : Container(
                          key: const ValueKey('off'),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: palette.textHint, width: 1.5),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 78,
            endIndent: 18,
            color: palette.divider,
          ),
      ],
    );
  }
}





class _ColorPaletteCard extends StatelessWidget {
  const _ColorPaletteCard({required this.theme, required this.palette});
  final ThemeProvider theme;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 12,
        runSpacing: 14,
        children: ThemeColor.values
            .map((c) => _ColorChip(
                  themeColor: c,
                  theme: theme,
                  palette: palette,
                ))
            .toList(),
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.themeColor,
    required this.theme,
    required this.palette,
  });
  final ThemeColor themeColor;
  final ThemeProvider theme;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final isSelected = theme.themeColor == themeColor;

    
    final color = _getThemeBaseColor(themeColor);
    final lightColor = _getThemeLightColor(themeColor);
    final name = _getThemeColorName(themeColor);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        theme.setThemeColor(themeColor);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.transparent,
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.elasticOut,
              width: isSelected ? 44 : 38,
              height: isSelected ? 44 : 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [lightColor, color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                  : null,
            ),
            const SizedBox(height: 7),
            Text(
              name,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected ? color : palette.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}





class _BubbleStyleCard extends StatelessWidget {
  const _BubbleStyleCard({required this.theme, required this.palette});
  final ThemeProvider theme;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: BubbleStyle.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final style = BubbleStyle.values[i];
                final isSelected = theme.bubbleStyle == style;
                final primary = theme.primaryColor;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    theme.setBubbleStyle(style);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 90,
                    decoration: BoxDecoration(
                      color: isSelected ? primary.withValues(alpha: 0.1) : palette.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? primary : Colors.transparent,
                        width: 1.8,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _BubbleMiniPreview(style: style, primary: primary, palette: palette),
                        const SizedBox(height: 8),
                        Text(
                          ThemeProvider.bubbleStyleName(style),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                            color: isSelected ? primary : palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 4, right: 4),
            child: Row(
              children: [
                Icon(Icons.gradient_rounded, size: 16, color: palette.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hiệu ứng gradient',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _ThemedSwitch(
                  value: theme.useGradientBubble,
                  onChanged: (v) => theme.setUseGradientBubble(v),
                  primary: theme.primaryColor,
                  palette: palette,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleMiniPreview extends StatelessWidget {
  const _BubbleMiniPreview({required this.style, required this.primary, required this.palette});
  final BubbleStyle style;
  final Color primary;
  final ThemePalette palette;

  BorderRadius _radius() {
    switch (style) {
      case BubbleStyle.modern:
        return const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(3),
        );
      case BubbleStyle.classic:
        return const BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(2),
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(10),
        );
      case BubbleStyle.minimal:
        return BorderRadius.circular(6);
      case BubbleStyle.rounded:
        return const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(3),
        );
      case BubbleStyle.sharp:
        return const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(2),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 26,
      decoration: BoxDecoration(
        color: primary,
        borderRadius: _radius(),
      ),
    );
  }
}





class _FontSizeCard extends StatelessWidget {
  const _FontSizeCard({required this.theme, required this.palette});
  final ThemeProvider theme;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: FontSize.values.map((size) {
              final isSelected = theme.fontSize == size;
              final primary = theme.primaryColor;
              final fontSize = _getFontSize(size);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  theme.setFontSize(size);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: isSelected ? primary.withValues(alpha: 0.1) : palette.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? primary : Colors.transparent,
                      width: 1.8,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Aa',
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? primary : palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ThemeProvider.fontSizeName(size),
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? primary : palette.textHint,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.access_time_filled_rounded, size: 16, color: palette.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Luôn hiện thời gian',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _ThemedSwitch(
                value: theme.showTimestampAlways,
                onChanged: (v) => theme.setShowTimestampAlways(v),
                primary: theme.primaryColor,
                palette: palette,
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _getFontSize(FontSize s) {
    switch (s) {
      case FontSize.small:
        return 14;
      case FontSize.medium:
        return 17;
      case FontSize.large:
        return 20;
      case FontSize.extraLarge:
        return 24;
    }
  }
}





class _WallpaperCard extends StatelessWidget {
  const _WallpaperCard({required this.theme, required this.palette});
  final ThemeProvider theme;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ChatWallpaper.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final wp = ChatWallpaper.values[i];
                final isSelected = theme.chatWallpaper == wp;
                final primary = theme.primaryColor;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    theme.setChatWallpaper(wp);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: palette.surfaceVariant,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? primary : palette.divider,
                        width: isSelected ? 2 : 0.8,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Stack(
                        children: [
                          _WallpaperPreview(
                            wallpaper: wp,
                            color: primary,
                            opacity: 0.3,
                          ),
                          if (isSelected)
                            Center(
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: primary,
                                  shape: BoxShape.circle,
                                ),
                                child:
                                    const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                              ),
                            ),
                          Positioned(
                            bottom: 4,
                            left: 0,
                            right: 0,
                            child: Text(
                              ThemeProvider.wallpaperName(wp),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: isSelected ? primary : palette.textHint,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                              ),
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
          if (theme.chatWallpaper != ChatWallpaper.none) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.opacity_rounded, size: 16, color: palette.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Độ trong suốt',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(theme.chatWallpaperOpacity * 100).round()}%',
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: theme.primaryColor,
                thumbColor: theme.primaryColor,
                inactiveTrackColor: theme.primaryColor.withValues(alpha: 0.2),
                overlayColor: theme.primaryColor.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                trackHeight: 4,
              ),
              child: Slider(
                value: theme.chatWallpaperOpacity,
                min: 0.02,
                max: 0.3,
                onChanged: (v) => theme.setChatWallpaperOpacity(v),
              ),
            ),
          ],
        ],
      ),
    );
  }
}





class _AdvancedOptionsCard extends StatelessWidget {
  const _AdvancedOptionsCard({required this.theme, required this.palette});
  final ThemeProvider theme;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      child: Column(
        children: [
          _ToggleRow(
            icon: Icons.person_outline_rounded,
            label: 'Hiện avatar trong chat',
            subtitle: 'Ảnh đại diện cạnh tin nhắn',
            value: theme.showAvatarsInChat,
            onChanged: (v) => theme.setShowAvatarsInChat(v),
            theme: theme,
            palette: palette,
            showDivider: true,
          ),
          _ToggleRow(
            icon: Icons.compress_rounded,
            label: 'Chế độ compact',
            subtitle: 'Giảm khoảng cách để thấy nhiều hơn',
            value: theme.compactMode,
            onChanged: (v) => theme.setCompactMode(v),
            theme: theme,
            palette: palette,
            showDivider: true,
          ),
          _ToggleRow(
            icon: Icons.blur_on_rounded,
            label: 'Hiệu ứng blur',
            subtitle: 'Kính mờ cho các panel phủ',
            value: theme.enableBlurEffects,
            onChanged: (v) => theme.setEnableBlurEffects(v),
            theme: theme,
            palette: palette,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.theme,
    required this.palette,
    required this.showDivider,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ThemeProvider theme;
  final ThemePalette palette;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final primary = theme.primaryColor;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.surfaceVariant,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: palette.textSecondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _ThemedSwitch(
                value: value,
                onChanged: onChanged,
                primary: primary,
                palette: palette,
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, indent: 70, endIndent: 18, color: palette.divider),
      ],
    );
  }
}





class _LivePreviewCard extends StatelessWidget {
  const _LivePreviewCard({required this.theme, required this.palette});
  final ThemeProvider theme;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      child: Column(
        children: [
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: palette.appBarBackground,
              border: Border(bottom: BorderSide(color: palette.divider)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.primaryLightColor, theme.primaryColor],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('A',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('An Nguyen',
                          style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14 * theme.fontSizeMultiplier)),
                      Text('Đang hoạt động',
                          style: TextStyle(
                              color: palette.onlineIndicator,
                              fontSize: 11 * theme.fontSizeMultiplier)),
                    ],
                  ),
                ),
                Icon(Icons.more_vert_rounded, color: palette.textSecondary, size: 20),
              ],
            ),
          ),
          
          Container(
            color: palette.background,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 220),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: palette.incomingBubble,
                      borderRadius: theme.incomingRadius(true),
                      border: Border.all(color: palette.divider, width: 0.5),
                      boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 6)],
                    ),
                    child: Text(
                      'Chào bạn! 👋',
                      style: TextStyle(
                        color: palette.incomingText,
                        fontSize: 14 * theme.fontSizeMultiplier,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 220),
                    padding: theme.bubblePadding,
                    decoration: BoxDecoration(
                      gradient: theme.useGradientBubble
                          ? theme.outgoingBubbleGradient(palette.isDark)
                          : null,
                      color: theme.useGradientBubble ? null : theme.primaryColor,
                      borderRadius: theme.outgoingRadius(true),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      'Xin chào! Trông đẹp đấy ✨',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14 * theme.fontSizeMultiplier,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '10:45',
                        style: TextStyle(fontSize: 10, color: palette.textHint),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.done_all_rounded, size: 13, color: theme.primaryColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}





class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.theme, required this.palette});
  final ThemeProvider theme;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: palette.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Đặt lại giao diện', style: TextStyle(color: palette.textPrimary)),
            content:
                Text('Đặt tất cả về mặc định?', style: TextStyle(color: palette.textSecondary)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Huỷ', style: TextStyle(color: palette.textSecondary))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: palette.dangerColor),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Đặt lại'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await theme.resetToDefaults();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: palette.dangerColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.dangerColor.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.refresh_rounded, color: palette.dangerColor, size: 18),
            const SizedBox(width: 8),
            Text(
              'Đặt lại về mặc định',
              style: TextStyle(
                color: palette.dangerColor,
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}





class _WallpaperPreview extends StatelessWidget {
  const _WallpaperPreview({
    required this.wallpaper,
    required this.color,
    required this.opacity,
  });
  final ChatWallpaper wallpaper;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (wallpaper == ChatWallpaper.none) {
      return const SizedBox.expand();
    }
    return CustomPaint(
      painter: _WallpaperPainter(wallpaper: wallpaper, color: color, opacity: opacity),
      size: Size.infinite,
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  const _WallpaperPainter({
    required this.wallpaper,
    required this.color,
    required this.opacity,
  });
  final ChatWallpaper wallpaper;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;

    switch (wallpaper) {
      case ChatWallpaper.dots:
        _drawDots(canvas, size, paint);
        break;
      case ChatWallpaper.grid:
        _drawGrid(canvas, size, paint);
        break;
      case ChatWallpaper.waves:
        _drawWaves(canvas, size, paint);
        break;
      case ChatWallpaper.diagonal:
        _drawDiagonal(canvas, size, paint);
        break;
      case ChatWallpaper.circuit:
        _drawCircuit(canvas, size, paint);
        break;
      case ChatWallpaper.none:
        break;
    }
  }

  void _drawDots(Canvas canvas, Size size, Paint paint) {
    const spacing = 14.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    const spacing = 16.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawWaves(Canvas canvas, Size size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    const waveHeight = 8.0;
    const waveWidth = 24.0;
    const spacing = 16.0;
    for (double y = 0; y < size.height; y += spacing) {
      final path = Path()..moveTo(0, y);
      for (double x = 0; x < size.width; x += waveWidth) {
        path.relativeCubicTo(
            waveWidth / 4, -waveHeight, 3 * waveWidth / 4, -waveHeight, waveWidth, 0);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawDiagonal(Canvas canvas, Size size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    const spacing = 16.0;
    final total = size.width + size.height;
    for (double i = 0; i < total; i += spacing) {
      final startX = i < size.width ? i : size.width;
      final startY = i < size.width ? 0.0 : i - size.width;
      final endX = i < size.height ? 0.0 : i - size.height;
      final endY = i < size.height ? i : size.height;
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }
  }

  void _drawCircuit(Canvas canvas, Size size, Paint paint) {
    paint.style = PaintingStyle.stroke;
    final rng = math.Random(42);
    for (int i = 0; i < 20; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final len = 10 + rng.nextDouble() * 20;
      final horiz = rng.nextBool();
      if (horiz) {
        canvas.drawLine(Offset(x, y), Offset(x + len, y), paint);
        canvas.drawCircle(Offset(x + len, y), 2, paint);
      } else {
        canvas.drawLine(Offset(x, y), Offset(x, y + len), paint);
        canvas.drawCircle(Offset(x, y + len), 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) =>
      old.wallpaper != wallpaper || old.color != color || old.opacity != opacity;
}





class _ThemedSwitch extends StatelessWidget {
  const _ThemedSwitch({
    required this.value,
    required this.onChanged,
    required this.primary,
    required this.palette,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color primary;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: (v) {
        HapticFeedback.selectionClick();
        onChanged(v);
      },
      activeThumbColor: primary,
      activeTrackColor: primary.withValues(alpha: 0.3),
      inactiveThumbColor: palette.textHint,
      inactiveTrackColor: palette.divider,
    );
  }
}





class _AnimatedColorDot extends StatefulWidget {
  const _AnimatedColorDot({required this.color});
  final Color color;

  @override
  State<_AnimatedColorDot> createState() => _AnimatedColorDotState();
}

class _AnimatedColorDotState extends State<_AnimatedColorDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [widget.color.withValues(alpha: 0.6), widget.color],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.5),
              blurRadius: 10,
            ),
          ],
        ),
      ),
    );
  }
}


class ChatWallpaperWidget extends StatelessWidget {
  const ChatWallpaperWidget({
    super.key,
    required this.wallpaper,
    required this.color,
    required this.opacity,
    required this.child,
  });
  final ChatWallpaper wallpaper;
  final Color color;
  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _WallpaperPreview(
            wallpaper: wallpaper,
            color: color,
            opacity: opacity,
          ),
        ),
        child,
      ],
    );
  }
}
