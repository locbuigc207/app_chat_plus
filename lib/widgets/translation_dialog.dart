import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/constants/constants.dart';
import 'package:flutter_chat_demo/services/ai_backend_service.dart';

class TranslationDialog extends StatefulWidget {
  final String originalMessage;

  const TranslationDialog({
    super.key,
    required this.originalMessage,
  });

  @override
  _TranslationDialogState createState() => _TranslationDialogState();
}

class _TranslationDialogState extends State<TranslationDialog> {
  final AIBackendService _aiService = AIBackendService();

  String _selectedMode = 'elder';
  String? _translatedText;
  bool _isLoading = false;

  final Map<String, String> _modes = {
    'elder': 'Người lớn tuổi (Dễ hiểu, lễ phép)',
    'work': 'Công việc (Chuyên nghiệp, súc tích)',
    'student': 'Gen Z (Trẻ trung, năng động)',
  };

  Future<void> _translate() async {
    setState(() {
      _isLoading = true;
      _translatedText = null;
    });

    final result = await _aiService.translateCommunication(
      widget.originalMessage,
      _selectedMode,
    );

    if (mounted) {
      setState(() {
        _translatedText = result ?? 'Có lỗi xảy ra khi dịch.';
        _isLoading = false;
      });
    }
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
            
            Row(
              children: [
                Icon(Icons.auto_awesome, color: ColorConstants.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Dịch khoảng cách thế hệ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: ColorConstants.primaryColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: ColorConstants.greyColor2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: _selectedMode,
                isExpanded: true,
                underline: const SizedBox(),
                items: _modes.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedMode = value);
                },
              ),
            ),

            const SizedBox(height: 16),

            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ColorConstants.greyColor2.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tin gốc:',
                    style: TextStyle(
                      fontSize: 12,
                      color: ColorConstants.greyColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.originalMessage,
                    style: const TextStyle(
                        fontSize: 14, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
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
                    'Kết quả AI:',
                    style: TextStyle(
                      fontSize: 12,
                      color: ColorConstants.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
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
                    const Text(
                      'Nhấn nút để chuyển đổi phong cách.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Đóng'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _translate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ColorConstants.primaryColor,
                  ),
                  child: const Text('Dịch AI',
                      style: TextStyle(color: Colors.white)),
                ),
                if (_translatedText != null && !_isLoading) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, _translatedText),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ColorConstants.primaryColor,
                    ),
                    child: const Text('Dùng câu này',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
