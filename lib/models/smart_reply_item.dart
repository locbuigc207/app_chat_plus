// lib/models/smart_reply_item.dart
// Rich SmartReplyItem model hỗ trợ text, sticker và emoji replies

import 'ai_models.dart' show SmartReply;

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

enum SmartReplyType {
  text,
  sticker,
  emoji;

  static SmartReplyType fromString(String? s) => switch (s?.toLowerCase()) {
        'sticker' => SmartReplyType.sticker,
        'emoji' => SmartReplyType.emoji,
        _ => SmartReplyType.text,
      };
}

enum SmartReplyTone {
  casual,
  formal,
  playful,
  empathetic;

  static SmartReplyTone fromString(String? s) => switch (s?.toLowerCase()) {
        'formal' => SmartReplyTone.formal,
        'playful' => SmartReplyTone.playful,
        'empathetic' => SmartReplyTone.empathetic,
        _ => SmartReplyTone.casual,
      };

  String get label => switch (this) {
        SmartReplyTone.casual => 'Thân thiện',
        SmartReplyTone.formal => 'Trang trọng',
        SmartReplyTone.playful => 'Vui vẻ',
        SmartReplyTone.empathetic => 'Đồng cảm',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// SMART REPLY ITEM
// ─────────────────────────────────────────────────────────────────────────────

class SmartReplyItem {
  final String text;
  final SmartReplyType type;
  final String? stickerId;
  final SmartReplyTone tone;
  final double confidence;
  final bool isAiGenerated;

  const SmartReplyItem({
    required this.text,
    this.type = SmartReplyType.text,
    this.stickerId,
    this.tone = SmartReplyTone.casual,
    this.confidence = 0.8,
    this.isAiGenerated = true,
  });

  // ── Convenience Factories ──────────────────────────────────────────────────

  factory SmartReplyItem.text({
    required String text,
    SmartReplyTone tone = SmartReplyTone.casual,
    double confidence = 0.8,
    bool isAiGenerated = true,
  }) =>
      SmartReplyItem(
        text: text,
        type: SmartReplyType.text,
        tone: tone,
        confidence: confidence,
        isAiGenerated: isAiGenerated,
      );

  factory SmartReplyItem.sticker(String stickerId) => SmartReplyItem(
        text: stickerId,
        type: SmartReplyType.sticker,
        stickerId: stickerId,
        confidence: 0.9,
        isAiGenerated: true,
      );

  /// Convert từ legacy SmartReply model
  factory SmartReplyItem.fromSmartReply(SmartReply reply) => SmartReplyItem(
        text: reply.text,
        type: SmartReplyType.text,
        confidence: reply.confidence ?? 0.8,
        isAiGenerated: reply.isAiGenerated,
      );

  factory SmartReplyItem.fromMap(Map<dynamic, dynamic> m) => SmartReplyItem(
        text: m['text'] as String? ?? '',
        type: SmartReplyType.fromString(m['type'] as String?),
        stickerId: m['stickerId'] as String?,
        tone: SmartReplyTone.fromString(m['tone'] as String?),
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0.8,
        isAiGenerated: m['isAiGenerated'] as bool? ?? true,
      );

  // ── Computed ───────────────────────────────────────────────────────────────

  bool get isSticker => type == SmartReplyType.sticker;
  bool get isText => type == SmartReplyType.text;
  bool get isEmoji => type == SmartReplyType.emoji;

  /// Message type để truyền vào _onSend: 0=text, 2=sticker
  int get messageType => isSticker ? 2 : 0;

  /// Nội dung thực tế để gửi đi
  String get sendPayload => stickerId ?? text;

  @override
  String toString() =>
      'SmartReplyItem(type: ${type.name}, text: $text, tone: ${tone.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartReplyItem &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          type == other.type;

  @override
  int get hashCode => Object.hash(text, type);
}

// ─────────────────────────────────────────────────────────────────────────────
// ENHANCED SMART REPLY RESULT
// ─────────────────────────────────────────────────────────────────────────────

class EnhancedSmartReplyResult {
  final List<SmartReplyItem> suggestions;
  final List<String> suggestStickers;
  final String detectedEmotion;
  final DateTime createdAt;

  EnhancedSmartReplyResult({
    required this.suggestions,
    required this.suggestStickers,
    required this.detectedEmotion,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory EnhancedSmartReplyResult.empty() => EnhancedSmartReplyResult(
        suggestions: const [],
        suggestStickers: const [],
        detectedEmotion: 'neutral',
      );

  factory EnhancedSmartReplyResult.fromLegacy(List<SmartReply> replies) =>
      EnhancedSmartReplyResult(
        suggestions:
            replies.map((r) => SmartReplyItem.fromSmartReply(r)).toList(),
        suggestStickers: const [],
        detectedEmotion: 'neutral',
      );

  factory EnhancedSmartReplyResult.fromMap(Map<dynamic, dynamic> m) {
    final rawSuggestions = m['suggestions'] as List? ?? [];
    final rawStickers = m['suggestStickers'] as List? ?? [];
    return EnhancedSmartReplyResult(
      suggestions: rawSuggestions
          .map((s) => SmartReplyItem.fromMap(s as Map<dynamic, dynamic>))
          .where((s) => s.text.isNotEmpty)
          .toList(),
      suggestStickers: rawStickers
          .map((s) => s.toString())
          .where((s) => s.isNotEmpty)
          .toList(),
      detectedEmotion: m['detectedEmotion'] as String? ?? 'neutral',
    );
  }

  bool get isEmpty => suggestions.isEmpty && suggestStickers.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// Merge text suggestions + sticker items thành unified list
  List<SmartReplyItem> get merged {
    final items = <SmartReplyItem>[];
    items.addAll(suggestions);
    for (final id in suggestStickers) {
      if (!items.any((i) => i.stickerId == id)) {
        items.add(SmartReplyItem.sticker(id));
      }
    }
    return items;
  }

  /// Chỉ lấy text suggestions
  List<SmartReplyItem> get textOnly =>
      suggestions.where((s) => s.isText).toList();

  /// Chỉ lấy sticker suggestions
  List<SmartReplyItem> get stickersOnly => [
        ...suggestions.where((s) => s.isSticker),
        ...suggestStickers.map(SmartReplyItem.sticker)
      ];

  @override
  String toString() =>
      'EnhancedSmartReplyResult(${suggestions.length} texts, ${suggestStickers.length} stickers, emotion: $detectedEmotion)';
}

// ─────────────────────────────────────────────────────────────────────────────
// STICKER CATALOG
// ─────────────────────────────────────────────────────────────────────────────

/// Danh sách sticker khả dụng trong app
class StickerCatalog {
  StickerCatalog._();

  static const List<StickerMeta> all = [
    StickerMeta(id: 'mimi1', label: 'Chào', emotions: ['greeting', 'happy']),
    StickerMeta(id: 'mimi2', label: 'Cười', emotions: ['laugh', 'funny']),
    StickerMeta(id: 'mimi3', label: 'Yêu', emotions: ['love', 'heart']),
    StickerMeta(id: 'mimi4', label: 'Buồn', emotions: ['sad', 'cry']),
    StickerMeta(id: 'mimi5', label: 'Tức', emotions: ['angry', 'frustrated']),
    StickerMeta(id: 'mimi6', label: 'Ngạc', emotions: ['surprised', 'wow']),
    StickerMeta(id: 'mimi7', label: 'OK', emotions: ['agree', 'thumbsup']),
    StickerMeta(id: 'mimi8', label: 'Bye', emotions: ['bye', 'farewell']),
    StickerMeta(id: 'mimi9', label: 'Nghĩ', emotions: ['thinking', 'hmm']),
  ];

  static String assetPath(String id) => 'images/$id.gif';
}

class StickerMeta {
  final String id;
  final String label;
  final List<String> emotions;

  const StickerMeta({
    required this.id,
    required this.label,
    required this.emotions,
  });
}
