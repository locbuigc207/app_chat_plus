// lib/widgets/translation_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/providers/providers.dart';

class TranslationDialog extends StatefulWidget {
  final String originalText;
  final TranslationProvider translationProvider;

  const TranslationDialog({
    super.key,
    required this.originalText,
    required this.translationProvider,
  });

  @override
  State<TranslationDialog> createState() => _TranslationDialogState();
}

class _TranslationDialogState extends State<TranslationDialog> {
  String _selectedLanguage = 'en';
  String? _translatedText;
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    _translateText();
  }

  Future<void> _translateText() async {
    setState(() {
      _isTranslating = true;
      _translatedText = null;
    });

    final result = await widget.translationProvider.translateText(
      text: widget.originalText,
      targetLanguage: _selectedLanguage,
    );

    setState(() {
      _translatedText = result;
      _isTranslating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                Icon(Icons.translate, color: ColorConstants.primaryColor),
                SizedBox(width: 8),
                Text(
                  'Translation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: ColorConstants.primaryColor,
                  ),
                ),
              ],
            ),

            SizedBox(height: 16),

            // Language selector
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: ColorConstants.greyColor2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: _selectedLanguage,
                isExpanded: true,
                underline: SizedBox(),
                items: TranslationProvider.languages.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedLanguage = value);
                    _translateText();
                  }
                },
              ),
            ),

            SizedBox(height: 16),

            // Original text
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ColorConstants.greyColor2.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Original:',
                    style: TextStyle(
                      fontSize: 12,
                      color: ColorConstants.greyColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    widget.originalText,
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),

            SizedBox(height: 12),

            // Translated text
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ColorConstants.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ColorConstants.primaryColor.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Translation:',
                    style: TextStyle(
                      fontSize: 12,
                      color: ColorConstants.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  if (_isTranslating)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_translatedText != null)
                    Text(
                      _translatedText!,
                      style: TextStyle(
                        fontSize: 14,
                        color: ColorConstants.primaryColor,
                      ),
                    )
                  else
                    Text(
                      'Translation failed',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.red,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Close button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
