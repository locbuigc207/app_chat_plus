import 'package:flutter/material.dart';

class MentionTextEditingController extends TextEditingController {
  MentionTextEditingController({String? text}) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    List<TextSpan> children = [];
    final text = value.text;

    // Regex tìm kiếm các từ bắt đầu bằng @ (hỗ trợ cả tiếng Việt nhờ unicode)
    final mentionRegex = RegExp(r'@[\p{L}0-9_]+', unicode: true);
    int lastMatchEnd = 0;

    for (final match in mentionRegex.allMatches(text)) {
      final mention = match.group(0)!;

      // Thêm text bình thường trước mention
      if (match.start > lastMatchEnd) {
        children.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: style,
        ));
      }

      // Thêm block Mention (Nền xanh, chữ đậm)
      children.add(TextSpan(
        text: mention,
        style: style?.copyWith(
          color: const Color(0xFF007AFF),
          fontWeight: FontWeight.bold,
          backgroundColor: const Color(0xFF007AFF).withOpacity(0.15),
        ),
      ));

      lastMatchEnd = match.end;
    }

    // Thêm phần text còn lại
    if (lastMatchEnd < text.length) {
      children.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: style,
      ));
    }

    return TextSpan(children: children, style: style);
  }

  // Tối ưu hóa việc xóa cả block mention
  @override
  set value(TextEditingValue newValue) {
    if (newValue.text.length < value.text.length) {
      // Nhận diện thao tác Backspace
      final deletedCharIndex = newValue.selection.baseOffset;
      if (deletedCharIndex >= 0) {
        final textBeforeCursor = value.text.substring(0, deletedCharIndex + 1);
        final mentionMatch =
            RegExp(r'@[\p{L}0-9_]+$').firstMatch(textBeforeCursor);

        if (mentionMatch != null) {
          // Xóa toàn bộ block
          final startMention =
              deletedCharIndex + 1 - mentionMatch.group(0)!.length;
          final newText =
              value.text.replaceRange(startMention, deletedCharIndex + 1, '');
          super.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: startMention),
          );
          return;
        }
      }
    }
    super.value = newValue;
  }
}
