import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/providers/theme_provider.dart';
import 'package:provider/provider.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme Settings'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Mode Section
          _buildSectionTitle('Theme Mode'),
          Card(
            child: Column(
              children: [
                _buildThemeModeOption(
                  context,
                  AppThemeMode.light,
                  'Light',
                  Icons.light_mode,
                  themeProvider,
                ),
                const Divider(height: 1),
                _buildThemeModeOption(
                  context,
                  AppThemeMode.dark,
                  'Dark',
                  Icons.dark_mode,
                  themeProvider,
                ),
                const Divider(height: 1),
                _buildThemeModeOption(
                  context,
                  AppThemeMode.system,
                  'System',
                  Icons.brightness_auto,
                  themeProvider,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Theme Color Section
          _buildSectionTitle('Theme Color'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildColorOption(
                    context,
                    ThemeColor.blue,
                    const Color(0xff2196f3),
                    'Blue',
                    themeProvider,
                  ),
                  _buildColorOption(
                    context,
                    ThemeColor.green,
                    const Color(0xff4caf50),
                    'Green',
                    themeProvider,
                  ),
                  _buildColorOption(
                    context,
                    ThemeColor.purple,
                    const Color(0xff9c27b0),
                    'Purple',
                    themeProvider,
                  ),
                  _buildColorOption(
                    context,
                    ThemeColor.orange,
                    const Color(0xffff9800),
                    'Orange',
                    themeProvider,
                  ),
                  _buildColorOption(
                    context,
                    ThemeColor.pink,
                    const Color(0xffe91e63),
                    'Pink',
                    themeProvider,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Preview Section
          _buildSectionTitle('Preview'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: themeProvider.getPrimaryColor(),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.message, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This is how messages will look',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xff2c2c2c)
                          : const Color(0xffe8e8e8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Received messages',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildThemeModeOption(
      BuildContext context,
      AppThemeMode mode,
      String label,
      IconData icon,
      ThemeProvider provider,
      ) {
    final isSelected = provider.themeMode == mode;

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? provider.getPrimaryColor() : null,
      ),
      title: Text(label),
      trailing: isSelected
          ? Icon(Icons.check, color: provider.getPrimaryColor())
          : null,
      onTap: () => provider.setThemeMode(mode),
    );
  }

  Widget _buildColorOption(
      BuildContext context,
      ThemeColor color,
      Color colorValue,
      String label,
      ThemeProvider provider,
      ) {
    final isSelected = provider.themeColor == color;

    return InkWell(
      onTap: () => provider.setThemeColor(color),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? colorValue : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorValue,
                shape: BoxShape.circle,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
