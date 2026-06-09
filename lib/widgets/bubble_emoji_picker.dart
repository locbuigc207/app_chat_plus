// lib/widgets/bubble_emoji_picker.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// EMOJI DATA
// ═══════════════════════════════════════════════════════════════════════════

class _Cat {
  final String icon;
  final String label;
  final List<String> emojis;
  const _Cat(this.icon, this.label, this.emojis);
}

const _categories = [
  _Cat('🕐', 'Gần đây', []), // populated at runtime
  _Cat('⭐', 'Gợi ý', []), // populated from BubbleMode
  _Cat('😀', 'Mặt', [
    '😀',
    '😃',
    '😄',
    '😁',
    '😆',
    '😅',
    '🤣',
    '😂',
    '🙂',
    '😉',
    '😊',
    '😇',
    '🥰',
    '😍',
    '🤩',
    '😘',
    '😗',
    '😚',
    '😙',
    '🥲',
    '😋',
    '😛',
    '😜',
    '🤪',
    '😝',
    '🤑',
    '🤗',
    '🤭',
    '🤫',
    '🤔',
    '😐',
    '😑',
    '😶',
    '😏',
    '😒',
    '🙄',
    '😬',
    '🤥',
    '😌',
    '😔',
    '😪',
    '🤤',
    '😴',
    '😷',
    '🤒',
    '🤕',
    '🤢',
    '🤧',
    '🥵',
    '🥶',
    '😵',
    '🤯',
    '🤠',
    '🥳',
    '😎',
    '🤓',
    '😕',
    '😟',
    '😮',
    '😲',
    '😳',
    '🥺',
    '😦',
    '😧',
    '😨',
    '😰',
    '😥',
    '😢',
    '😭',
    '😱',
    '😡',
    '🤬',
    '😈',
    '💀',
    '💩',
    '🤡',
    '👻',
    '👽',
    '🤖',
    '👋',
    '🤚',
    '✋',
    '🖐️',
    '👌',
    '🤌',
    '🤏',
    '✌️',
    '🤞',
    '🤟',
    '🤘',
    '👈',
    '👉',
    '👆',
    '👇',
    '☝️',
    '👍',
    '👎',
    '✊',
    '👊',
    '🤛',
    '🤜',
    '👏',
    '🙌',
    '🫶',
    '🤲',
    '🤝',
    '🙏',
  ]),
  _Cat('🐶', 'Động vật', [
    '🐶',
    '🐱',
    '🐭',
    '🐹',
    '🐰',
    '🦊',
    '🐻',
    '🐼',
    '🐨',
    '🐯',
    '🦁',
    '🐮',
    '🐷',
    '🐸',
    '🐵',
    '🙈',
    '🙉',
    '🙊',
    '🐔',
    '🐧',
    '🐦',
    '🦆',
    '🦅',
    '🦉',
    '🦇',
    '🐺',
    '🐗',
    '🦄',
    '🐝',
    '🦋',
    '🐌',
    '🐞',
    '🐜',
    '🦂',
    '🐢',
    '🦎',
    '🐍',
    '🦕',
    '🦀',
    '🦞',
    '🦐',
    '🦑',
    '🐬',
    '🐳',
    '🐋',
    '🦈',
    '🦭',
    '🐅',
    '🐆',
    '🦓',
    '🦍',
    '🦧',
    '🦣',
    '🐘',
    '🦛',
    '🦏',
    '🐪',
    '🐫',
    '🦒',
    '🦘',
    '🦬',
    '🐃',
    '🐂',
    '🐄',
    '🐎',
    '🐖',
    '🐏',
    '🐑',
    '🦙',
    '🐐',
    '🦌',
    '🐕',
    '🐩',
    '🦮',
    '🐕‍🦺',
    '🐈',
    '🐈‍⬛',
    '🪶',
    '🌸',
    '🌹',
    '🌺',
    '🌻',
    '🌼',
  ]),
  _Cat('🍎', 'Đồ ăn', [
    '🍎',
    '🍊',
    '🍋',
    '🍇',
    '🍓',
    '🫐',
    '🍈',
    '🍑',
    '🍒',
    '🥭',
    '🍍',
    '🥥',
    '🥝',
    '🍅',
    '🍆',
    '🥑',
    '🥦',
    '🥬',
    '🥒',
    '🌶️',
    '🧄',
    '🧅',
    '🥔',
    '🍠',
    '🥐',
    '🥯',
    '🍞',
    '🥖',
    '🥨',
    '🧀',
    '🥚',
    '🍳',
    '🧈',
    '🥞',
    '🧇',
    '🥓',
    '🍗',
    '🍖',
    '🌭',
    '🍔',
    '🍟',
    '🍕',
    '🌮',
    '🌯',
    '🥙',
    '🧆',
    '🍱',
    '🍘',
    '🍣',
    '🍤',
    '🍜',
    '🍝',
    '🍛',
    '🍚',
    '🍙',
    '🍲',
    '🥣',
    '🥗',
    '🥫',
    '🧂',
    '🍿',
    '🧈',
    '🍩',
    '🍪',
    '🎂',
    '🍰',
    '🧁',
    '🍫',
    '🍬',
    '🍭',
    '🍮',
    '🍯',
    '☕',
    '🫖',
    '🧃',
    '🥤',
    '🍵',
    '🧋',
    '🍺',
    '🥂',
    '🍷',
    '🍸',
    '🍹',
    '🧉',
  ]),
  _Cat('⚽', 'Hoạt động', [
    '⚽',
    '🏀',
    '🏈',
    '⚾',
    '🎾',
    '🏐',
    '🏉',
    '🎱',
    '🏓',
    '🏸',
    '🥊',
    '🥋',
    '⛷️',
    '🏂',
    '🏋️',
    '🤼',
    '🤸',
    '🤺',
    '🏊',
    '🚵',
    '🏇',
    '🧘',
    '🛹',
    '🛷',
    '⛵',
    '🏄',
    '🚣',
    '🤽',
    '🧗',
    '🚴',
    '🏌️',
    '⛸️',
    '🎿',
    '🛼',
    '🎯',
    '🎱',
    '🔮',
    '🧩',
    '🪀',
    '🪁',
    '🎮',
    '🕹️',
    '🎳',
    '🎰',
    '🎲',
    '♟️',
    '🎭',
    '🎨',
    '🖼️',
    '🎪',
    '🎠',
    '🎡',
    '🎢',
    '🎤',
    '🎧',
    '🎼',
    '🎵',
    '🎶',
    '🎷',
    '🎸',
    '🎹',
    '🎺',
    '🎻',
    '🥁',
    '🪘',
    '🪗',
    '🪕',
    '🎬',
    '🎥',
    '📷',
    '📸',
    '📹',
  ]),
  _Cat('✈️', 'Du lịch', [
    '🚀',
    '🛸',
    '✈️',
    '🛫',
    '🛬',
    '🛩️',
    '🚁',
    '🛻',
    '🚗',
    '🚕',
    '🚙',
    '🚌',
    '🚎',
    '🏎️',
    '🚓',
    '🚑',
    '🚒',
    '🚐',
    '🛻',
    '🚚',
    '🚛',
    '🚜',
    '🏍️',
    '🛵',
    '🚲',
    '🛴',
    '🛺',
    '🚂',
    '🚃',
    '🚄',
    '🚅',
    '🚆',
    '🚇',
    '🚈',
    '🚉',
    '🚊',
    '⛵',
    '🚤',
    '🛥️',
    '🛳️',
    '⛴️',
    '🚢',
    '🪂',
    '🏔️',
    '⛰️',
    '🌋',
    '🗻',
    '🏕️',
    '🏖️',
    '🏜️',
    '🏝️',
    '🏞️',
    '🏟️',
    '🏛️',
    '🏗️',
    '🏘️',
    '🏠',
    '🏡',
    '🏢',
    '🏬',
    '🏭',
    '🏯',
    '🏰',
    '🗼',
    '🗽',
    '⛪',
    '🕌',
    '⛩️',
    '💒',
    '🌁',
    '🌃',
    '🏙️',
    '🌄',
    '🌅',
    '🌆',
    '🌇',
    '🌉',
    '🌌',
    '🌠',
    '🎇',
    '🎆',
    '🌈',
    '🌤️',
    '⛅',
  ]),
  _Cat('💡', 'Đồ vật', [
    '💡',
    '🔦',
    '🕯️',
    '💰',
    '💳',
    '⚖️',
    '🔧',
    '🔨',
    '⛏️',
    '🛠️',
    '🗡️',
    '⚔️',
    '🛡️',
    '🏹',
    '🪚',
    '🔩',
    '🗜️',
    '🔗',
    '🧲',
    '💊',
    '🩹',
    '🩺',
    '🩻',
    '🔬',
    '🔭',
    '🧫',
    '🧪',
    '🌡️',
    '🧹',
    '🧺',
    '🧻',
    '🪣',
    '🧼',
    '🪥',
    '🧽',
    '🛁',
    '🚿',
    '🚽',
    '🚪',
    '🛋️',
    '🪑',
    '🛏️',
    '🧸',
    '🎁',
    '🎀',
    '🎗️',
    '📱',
    '💻',
    '🖥️',
    '🖨️',
    '⌨️',
    '🖱️',
    '💾',
    '💿',
    '📀',
    '🎙️',
    '📞',
    '☎️',
    '📺',
    '📷',
    '🎥',
    '📽️',
    '🎞️',
    '📻',
    '🔋',
    '🔌',
    '💡',
    '🔦',
    '🕯️',
    '🗑️',
    '🔑',
    '🗝️',
    '🔐',
    '🔒',
    '🔓',
    '🔏',
    '📦',
    '📫',
    '📬',
    '📭',
    '📮',
    '🗳️',
    '✏️',
    '✒️',
    '🖊️',
    '🖋️',
    '📝',
    '📁',
    '📂',
    '📊',
    '📈',
    '📉',
    '🗒️',
    '📖',
    '📚',
    '🔖',
  ]),
  _Cat('❤️', 'Ký hiệu', [
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🤍',
    '🤎',
    '💔',
    '❣️',
    '💕',
    '💞',
    '💓',
    '💗',
    '💖',
    '💘',
    '💝',
    '💟',
    '☮️',
    '✝️',
    '☪️',
    '🕉️',
    '☸️',
    '✡️',
    '🔯',
    '☯️',
    '🛐',
    '⛎',
    '♈',
    '♉',
    '♊',
    '♋',
    '♌',
    '♍',
    '♎',
    '♏',
    '♐',
    '♑',
    '♒',
    '♓',
    '🆔',
    '⚕️',
    '♾️',
    '♻️',
    '⚜️',
    '🔱',
    '📛',
    '🔰',
    '⭕',
    '✅',
    '☑️',
    '✔️',
    '❎',
    '🆒',
    '🆓',
    '🆕',
    '🆗',
    '🆙',
    '🆚',
    '🈁',
    '🅰️',
    '🅱️',
    '🆎',
    '🅾️',
    '🆘',
    '❌',
    '⛔',
    '📵',
    '🚫',
    '💯',
    '♨️',
    '🔅',
    '🔆',
    '📶',
    '🔇',
    '🔉',
    '🔊',
    '📢',
    '📣',
    '🔔',
    '🔕',
    '🎵',
    '🎶',
    '💤',
    '🔞',
    '🈷️',
    '🈵',
    '🈹',
    '🈲',
    '🅰️',
    '🅱️',
    '🈶',
    '🈚',
    '🅾️',
    '🈸',
    '🈴',
  ]),
];

// Mode-specific quick suggestions
const _modeSuggestions = <BubbleMode, List<String>>{
  BubbleMode.normal: [
    '❤️',
    '😊',
    '👍',
    '😂',
    '🎉',
    '🙏',
    '🤩',
    '😘',
    '💪',
    '🥳'
  ],
  BubbleMode.work: ['📋', '✅', '⏰', '💼', '📊', '🔔', '💡', '📈', '🎯', '🤝'],
  BubbleMode.secure: [
    '🔒',
    '🛡️',
    '✅',
    '🤫',
    '👁️',
    '🔐',
    '🙈',
    '🙉',
    '🙊',
    '🕵️'
  ],
  BubbleMode.location: [
    '📍',
    '🗺️',
    '🧭',
    '🏙️',
    '✈️',
    '🚗',
    '🏃',
    '👀',
    '🌍',
    '🛣️'
  ],
  BubbleMode.media: ['🎵', '🎬', '📷', '🎧', '🎸', '🎤', '🎼', '🎹', '🔥', '⭐'],
  BubbleMode.shared: [
    '🎨',
    '🖌️',
    '✏️',
    '💡',
    '🌈',
    '🖼️',
    '✨',
    '🪄',
    '🎭',
    '🤝'
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
// RECENTLY USED  (SharedPreferences, max 24)
// ═══════════════════════════════════════════════════════════════════════════

class _RecentEmojis {
  static const _key = 'recent_emojis_v2';
  static const _maxLen = 24;

  static Future<List<String>> load() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_key) ?? [];
  }

  static Future<void> push(String emoji) async {
    final p = await SharedPreferences.getInstance();
    final list = (p.getStringList(_key) ?? []).toList();
    list.remove(emoji);
    list.insert(0, emoji);
    if (list.length > _maxLen) list.removeLast();
    await p.setStringList(_key, list);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BUBBLE EMOJI PICKER  —  main widget
// ═══════════════════════════════════════════════════════════════════════════

/// Full emoji keyboard panel that slides in from the bottom.
///
/// Features
/// ─────────
/// • 8 emoji categories + Recent + Mode suggestions
/// • Search with instant filtering
/// • Recently used row (persisted in SharedPreferences)
/// • BubbleMode-specific suggestion row at the top
/// • Smooth animated appearance (slide + fade)
/// • Haptic feedback on every selection
/// • Category tabs with active indicator
///
/// Usage
/// ──────
/// ```dart
/// BubbleEmojiPicker(
///   isOpen   : _emojiOpen,
///   mode     : context.bubbleCtx.mode,
///   onEmoji  : (e) => _inputBar.insertText(e),
///   onClose  : () => setState(() => _emojiOpen = false),
/// )
/// ```
class BubbleEmojiPicker extends StatefulWidget {
  final bool isOpen;
  final BubbleMode mode;
  final void Function(String emoji) onEmoji;
  final VoidCallback? onClose;
  final double height;

  const BubbleEmojiPicker({
    super.key,
    required this.isOpen,
    required this.mode,
    required this.onEmoji,
    this.onClose,
    this.height = 280,
  });

  @override
  State<BubbleEmojiPicker> createState() => _BubbleEmojiPickerState();
}

class _BubbleEmojiPickerState extends State<BubbleEmojiPicker>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  // Category tabs start at index 2 (skip Recent + Suggestions)
  int _catIndex = 2;
  String _search = '';

  List<String> _recents = [];
  List<String> _suggestions = [];
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.5)));

    _loadRecents();
    _suggestions =
        _modeSuggestions[widget.mode] ?? _modeSuggestions[BubbleMode.normal]!;

    if (widget.isOpen) _ctrl.forward();
  }

  @override
  void didUpdateWidget(BubbleEmojiPicker old) {
    super.didUpdateWidget(old);
    if (widget.isOpen != old.isOpen) {
      if (widget.isOpen)
        _ctrl.forward();
      else
        _ctrl.reverse();
    }
    if (widget.mode != old.mode) {
      setState(() {
        _suggestions = _modeSuggestions[widget.mode] ?? [];
      });
    }
  }

  Future<void> _loadRecents() async {
    final r = await _RecentEmojis.load();
    if (mounted) setState(() => _recents = r);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Emoji tapped ─────────────────────────────────────────────────────────

  void _onEmoji(String e) {
    HapticFeedback.lightImpact();
    widget.onEmoji(e);
    _RecentEmojis.push(e).then((_) => _loadRecents());
  }

  // ── Search filter ────────────────────────────────────────────────────────

  List<String> get _searchResults {
    if (_search.isEmpty) return [];
    final q = _search.toLowerCase();
    return _categories
        .skip(2)
        .expand((c) => c.emojis)
        .where((e) => e.contains(q))
        .take(60)
        .toList();
  }

  // ── Current category emojis ───────────────────────────────────────────────

  List<String> get _currentEmojis {
    if (_search.isNotEmpty) return _searchResults;
    if (_catIndex == 0) return _recents;
    if (_catIndex == 1) return _suggestions;
    return _categories[_catIndex].emojis;
  }

  // ═════════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1A1A2E)
                : Colors.white,
            border: Border(
                top: BorderSide(
                    color: Colors.grey.withOpacity(0.15), width: 0.8)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 16,
                  offset: const Offset(0, -4)),
            ],
          ),
          child: Column(
            children: [
              _SearchBar(
                ctrl: _searchCtrl,
                onChanged: (v) => setState(() {
                  _search = v;
                }),
                onClose: widget.onClose,
              ),
              _CategoryTabs(
                categories: _buildTabCategories(),
                selectedIndex: _search.isEmpty ? _catIndex : -1,
                onTap: (i) => setState(() {
                  _catIndex = i;
                  _search = '';
                  _searchCtrl.clear();
                }),
                accentColor: _modeAccent(),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _search.isNotEmpty && _searchResults.isEmpty
                      ? _EmptySearch(query: _search)
                      : _EmojiGrid(
                          key: ValueKey(_catIndex),
                          emojis: _currentEmojis,
                          onEmoji: _onEmoji,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_Cat> _buildTabCategories() => [
        _Cat('🕐', 'Gần đây', _recents),
        _Cat(_modeSuggestions[widget.mode] != null ? '⭐' : '⭐', 'Gợi ý',
            _suggestions),
        ..._categories.skip(2),
      ];

  Color _modeAccent() => switch (widget.mode) {
        BubbleMode.work => const Color(0xFF66BB6A),
        BubbleMode.secure => const Color(0xFF64FFDA),
        BubbleMode.location => const Color(0xFF69F0AE),
        BubbleMode.media => const Color(0xFFAD1457),
        BubbleMode.shared => const Color(0xFF9C27B0),
        _ => const Color(0xFF2979FF),
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// SEARCH BAR
// ═══════════════════════════════════════════════════════════════════════════

class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClose;
  const _SearchBar({required this.ctrl, required this.onChanged, this.onClose});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF252535) : const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: ctrl,
                onChanged: onChanged,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Tìm emoji…',
                  hintStyle:
                      TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: Colors.grey),
                  suffixIcon: ctrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            ctrl.clear();
                            onChanged('');
                          },
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Colors.grey))
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
              ),
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClose,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.keyboard_rounded,
                    size: 18, color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CATEGORY TABS
// ═══════════════════════════════════════════════════════════════════════════

class _CategoryTabs extends StatelessWidget {
  final List<_Cat> categories;
  final int selectedIndex;
  final void Function(int) onTap;
  final Color accentColor;
  const _CategoryTabs(
      {required this.categories,
      required this.selectedIndex,
      required this.onTap,
      required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: categories.length,
        itemBuilder: (_, i) {
          final sel = i == selectedIndex;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap(i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: sel ? accentColor.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: sel
                    ? Border.all(color: accentColor.withOpacity(0.4))
                    : null,
              ),
              child: Center(
                child: Text(
                  categories[i].icon,
                  style: TextStyle(
                      fontSize: sel ? 18 : 16,
                      shadows: sel
                          ? [
                              Shadow(
                                  color: accentColor.withOpacity(0.5),
                                  blurRadius: 8)
                            ]
                          : null),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMOJI GRID
// ═══════════════════════════════════════════════════════════════════════════

class _EmojiGrid extends StatelessWidget {
  final List<String> emojis;
  final void Function(String) onEmoji;
  const _EmojiGrid({super.key, required this.emojis, required this.onEmoji});

  @override
  Widget build(BuildContext context) {
    if (emojis.isEmpty) {
      return const Center(
        child: Text('Trống', style: TextStyle(color: Colors.grey)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 44,
        mainAxisExtent: 42,
      ),
      itemCount: emojis.length,
      itemBuilder: (_, i) =>
          _EmojiCell(emoji: emojis[i], onTap: () => onEmoji(emojis[i])),
    );
  }
}

class _EmojiCell extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;
  const _EmojiCell({required this.emoji, required this.onTap});

  @override
  State<_EmojiCell> createState() => _EmojiCellState();
}

class _EmojiCellState extends State<_EmojiCell>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1, end: 0.72)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Center(
          child: Text(widget.emoji,
              style: const TextStyle(fontSize: 24, height: 1)),
        ),
      ),
    );
  }
}

// ─── Empty search ────────────────────────────────────────────────────────────

class _EmptySearch extends StatelessWidget {
  final String query;
  const _EmptySearch({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔍', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text('Không tìm thấy "$query"',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}
