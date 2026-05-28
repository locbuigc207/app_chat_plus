import 'package:flutter/material.dart';

/// Model dữ liệu cho một mention
class MentionUser {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  const MentionUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  String get label => displayName ?? username;
}

/// TextEditingController nâng cao với hỗ trợ @mention đầy đủ:
/// - Highlight @mention với màu sắc và background
/// - Xóa cả block mention khi backspace
/// - Detect đang gõ @query để trigger gợi ý
/// - Insert mention với caret đúng vị trí
/// - Hỗ trợ unicode (tiếng Việt, emoji, v.v.)
class MentionTextEditingController extends TextEditingController {
  // Callback khi người dùng đang gõ @query (null khi kết thúc)
  final void Function(String? query)? onMentionQuery;

  // Danh sách mention đã được insert (để track)
  final Map<String, MentionUser> _insertedMentions = {};

  // Regex nhận diện @mention trong text
  static final _mentionRegex = RegExp(r'@([\p{L}0-9_.]+)', unicode: true);

  // Regex phát hiện đang gõ @ (chưa chọn từ gợi ý)
  static final _queryRegex = RegExp(r'@([\p{L}0-9_.]*)$', unicode: true);

  MentionTextEditingController({
    super.text,
    this.onMentionQuery,
  });

  // ─── Render ─────────────────────────────────────────────────────────────────

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <InlineSpan>[];
    final fullText = value.text;
    int lastEnd = 0;

    for (final match in _mentionRegex.allMatches(fullText)) {
      // Text bình thường trước mention
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: fullText.substring(lastEnd, match.start),
          style: style,
        ));
      }

      // Block mention
      final mentionText = match.group(0)!;
      final isSaved = _insertedMentions.containsKey(mentionText);

      spans.add(TextSpan(
        text: mentionText,
        style: style?.copyWith(
          color: const Color(0xFF007AFF),
          fontWeight: isSaved ? FontWeight.w600 : FontWeight.normal,
          backgroundColor: isSaved
              ? const Color(0xFF007AFF).withOpacity(0.12)
              : Colors.transparent,
        ),
      ));

      lastEnd = match.end;
    }

    // Phần text còn lại
    if (lastEnd < fullText.length) {
      spans.add(TextSpan(
        text: fullText.substring(lastEnd),
        style: style,
      ));
    }

    return TextSpan(children: spans, style: style);
  }

  // ─── Value Setter ────────────────────────────────────────────────────────────

  @override
  set value(TextEditingValue newValue) {
    final oldText = value.text;
    final newText = newValue.text;

    // Phát hiện backspace trong block mention → xóa cả block
    if (newText.length < oldText.length) {
      final cursorPos = newValue.selection.baseOffset;
      if (cursorPos >= 0 && cursorPos <= oldText.length) {
        // Text trước con trỏ (theo old text)
        final textBefore = oldText.substring(0, cursorPos + 1);
        final match =
            RegExp(r'@[\p{L}0-9_.]+$', unicode: true).firstMatch(textBefore);

        if (match != null) {
          final newT = oldText.replaceRange(match.start, match.end, '');
          _insertedMentions.remove(match.group(0));
          super.value = TextEditingValue(
            text: newT,
            selection: TextSelection.collapsed(offset: match.start),
          );
          _checkMentionQuery(newT, match.start);
          return;
        }
      }
    }

    super.value = newValue;

    // Kiểm tra đang gõ @query
    _checkMentionQuery(newText, newValue.selection.baseOffset);
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Insert một mention đã chọn từ gợi ý
  void insertMention(MentionUser user) {
    final cursorPos = selection.baseOffset;
    if (cursorPos < 0) return;

    final currentText = text;
    // Tìm @query trước cursor để thay thế
    final textBefore = currentText.substring(0, cursorPos);
    final match = _queryRegex.firstMatch(textBefore);

    if (match != null) {
      final mentionText = '@${user.username}';
      final newText = currentText.replaceRange(
        match.start,
        cursorPos,
        '$mentionText ', // Thêm space sau mention
      );

      _insertedMentions[mentionText] = user;

      value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: match.start + mentionText.length + 1,
        ),
      );

      // Kết thúc query
      onMentionQuery?.call(null);
    }
  }

  /// Xóa tất cả mention đã insert
  void clearMentions() {
    _insertedMentions.clear();
  }

  /// Lấy danh sách MentionUser hiện có trong text
  List<MentionUser> get currentMentions {
    final mentions = <MentionUser>[];
    for (final match in _mentionRegex.allMatches(text)) {
      final key = match.group(0)!;
      if (_insertedMentions.containsKey(key)) {
        mentions.add(_insertedMentions[key]!);
      }
    }
    return mentions;
  }

  /// Lấy danh sách userId được mention
  List<String> get mentionedUserIds =>
      currentMentions.map((u) => u.id).toList();

  /// Text thuần không có @prefix (dùng khi gửi lên server)
  String get plainText {
    return text.replaceAllMapped(
      _mentionRegex,
      (m) => _insertedMentions['@${m.group(1)}']?.label ?? m.group(0)!,
    );
  }

  // ─── Private ─────────────────────────────────────────────────────────────────

  void _checkMentionQuery(String fullText, int cursorPos) {
    if (cursorPos < 0 || cursorPos > fullText.length) {
      onMentionQuery?.call(null);
      return;
    }

    final textBeforeCursor = fullText.substring(0, cursorPos);
    final match = _queryRegex.firstMatch(textBeforeCursor);

    if (match != null) {
      onMentionQuery?.call(match.group(1) ?? '');
    } else {
      onMentionQuery?.call(null);
    }
  }

  @override
  void dispose() {
    _insertedMentions.clear();
    super.dispose();
  }
}

/// Widget dropdown gợi ý mention (dùng kèm với MentionTextEditingController)
class MentionSuggestionOverlay extends StatelessWidget {
  final List<MentionUser> suggestions;
  final void Function(MentionUser) onSelect;
  final bool isLoading;

  const MentionSuggestionOverlay({
    super.key,
    required this.suggestions,
    required this.onSelect,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty && !isLoading) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.5),
        ),
      ),
      child: isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: Theme.of(context).dividerColor.withOpacity(0.3),
              ),
              itemBuilder: (context, index) {
                final user = suggestions[index];
                return InkWell(
                  onTap: () => onSelect(user),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              const Color(0xFF007AFF).withOpacity(0.15),
                          backgroundImage: user.avatarUrl != null
                              ? NetworkImage(user.avatarUrl!)
                              : null,
                          child: user.avatarUrl == null
                              ? Text(
                                  user.username[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF007AFF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.displayName ?? user.username,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (user.displayName != null)
                                Text(
                                  '@${user.username}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.5),
                                      ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
