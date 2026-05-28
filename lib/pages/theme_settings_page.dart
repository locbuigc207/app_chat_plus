import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:provider/provider.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = themeProvider.primaryColor;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF6F6F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white : Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Giao diện',
          style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _buildSection(
            isDark: isDark,
            title: 'Chế độ màn hình',
            icon: Icons.brightness_6_rounded,
            primary: primary,
            child: Column(
              children: [
                _ThemeModeOption(
                  mode: AppThemeMode.light,
                  label: 'Sáng',
                  subtitle: 'Nền trắng, chữ tối',
                  icon: Icons.light_mode_rounded,
                  provider: themeProvider,
                  isDark: isDark,
                ),
                _Divider(isDark: isDark),
                _ThemeModeOption(
                  mode: AppThemeMode.dark,
                  label: 'Tối',
                  subtitle: 'Nền đen, chữ sáng',
                  icon: Icons.dark_mode_rounded,
                  provider: themeProvider,
                  isDark: isDark,
                ),
                _Divider(isDark: isDark),
                _ThemeModeOption(
                  mode: AppThemeMode.system,
                  label: 'Theo hệ thống',
                  subtitle: 'Tự động theo cài đặt thiết bị',
                  icon: Icons.brightness_auto_rounded,
                  provider: themeProvider,
                  isDark: isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildSection(
            isDark: isDark,
            title: 'Màu chủ đạo',
            icon: Icons.palette_rounded,
            primary: primary,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ColorOption(
                    themeColor: ThemeColor.blue,
                    colorValue: const Color(0xFF2196F3),
                    label: 'Xanh dương',
                    provider: themeProvider,
                    isDark: isDark,
                  ),
                  _ColorOption(
                    themeColor: ThemeColor.green,
                    colorValue: const Color(0xFF4CAF50),
                    label: 'Xanh lá',
                    provider: themeProvider,
                    isDark: isDark,
                  ),
                  _ColorOption(
                    themeColor: ThemeColor.purple,
                    colorValue: const Color(0xFF9C27B0),
                    label: 'Tím',
                    provider: themeProvider,
                    isDark: isDark,
                  ),
                  _ColorOption(
                    themeColor: ThemeColor.orange,
                    colorValue: const Color(0xFFFF9800),
                    label: 'Cam',
                    provider: themeProvider,
                    isDark: isDark,
                  ),
                  _ColorOption(
                    themeColor: ThemeColor.pink,
                    colorValue: const Color(0xFFE91E63),
                    label: 'Hồng',
                    provider: themeProvider,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildSection(
            isDark: isDark,
            title: 'Xem trước',
            icon: Icons.preview_rounded,
            primary: primary,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _PreviewCard(isDark: isDark, primaryColor: primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required bool isDark,
    required String title,
    required IconData icon,
    required Color primary,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primary,
                    letterSpacing: 0.3),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.07)
                    : Colors.grey.shade200),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  final AppThemeMode mode;
  final String label;
  final String subtitle;
  final IconData icon;
  final ThemeProvider provider;
  final bool isDark;

  const _ThemeModeOption({
    required this.mode,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.provider,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = provider.themeMode == mode;
    final primary = provider.primaryColor;

    return InkWell(
      onTap: () => provider.setThemeMode(mode),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? primary.withOpacity(0.12)
                    : (isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: isSelected ? primary : Colors.grey.shade500, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? Colors.white38 : Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isSelected
                  ? Container(
                      key: const ValueKey('check'),
                      width: 24,
                      height: 24,
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, color: primary),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 14),
                    )
                  : Container(
                      key: const ValueKey('empty'),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color:
                                isDark ? Colors.white24 : Colors.grey.shade300),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorOption extends StatelessWidget {
  final ThemeColor themeColor;
  final Color colorValue;
  final String label;
  final ThemeProvider provider;
  final bool isDark;

  const _ColorOption({
    required this.themeColor,
    required this.colorValue,
    required this.label,
    required this.provider,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = provider.themeColor == themeColor;

    return GestureDetector(
      onTap: () => provider.setThemeColor(themeColor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? colorValue : Colors.transparent,
            width: 2,
          ),
          color: isSelected
              ? colorValue.withOpacity(isDark ? 0.15 : 0.08)
              : Colors.transparent,
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorValue,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: colorValue.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ]
                    : [],
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 20)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected
                    ? colorValue
                    : (isDark ? Colors.white54 : Colors.grey.shade600),
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

class _PreviewCard extends StatelessWidget {
  final bool isDark;
  final Color primaryColor;

  const _PreviewCard({required this.isDark, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Sent message
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: const Text(
                'Xin chào! Đây là tin nhắn gửi đi.',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Received message
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF2C2C3E) : const Color(0xFFEEEEF0),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Text(
                'Chào bạn! Đây là tin nhắn nhận.',
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Timestamp
          Text(
            'Hôm nay, 10:45',
            style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white30 : Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        indent: 72,
        endIndent: 16,
        color: isDark ? Colors.white.withOpacity(0.07) : Colors.grey.shade100,
      );
}
