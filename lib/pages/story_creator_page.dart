// lib/pages/story_creator_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/providers/story_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

// ─────────────────────────────────────────────────────────────
// STORY CREATOR PAGE
// ─────────────────────────────────────────────────────────────

class StoryCreatorPage extends StatefulWidget {
  final String userId;
  final String userName;
  final String userPhotoUrl;

  const StoryCreatorPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
  });

  @override
  State<StoryCreatorPage> createState() => _StoryCreatorPageState();
}

class _StoryCreatorPageState extends State<StoryCreatorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_tab.indexIsChanging) setState(() => _tabIndex = _tab.index);
      });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── Top bar ──────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),

                  // Tab selector
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TabBtn(
                          label: '📸  Photo',
                          selected: _tabIndex == 0,
                          onTap: () {
                            _tab.animateTo(0);
                            setState(() => _tabIndex = 0);
                          },
                        ),
                        _TabBtn(
                          label: '✍️  Text',
                          selected: _tabIndex == 1,
                          onTap: () {
                            _tab.animateTo(1);
                            setState(() => _tabIndex = 1);
                          },
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),
                  const SizedBox(width: 48), // balance close button
                ],
              ),
            ),
          ),

          // ── Tab content ──────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _PhotoCreator(
                  userId: widget.userId,
                  userName: widget.userName,
                  userPhotoUrl: widget.userPhotoUrl,
                ),
                _TextCreator(
                  userId: widget.userId,
                  userName: widget.userName,
                  userPhotoUrl: widget.userPhotoUrl,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Small tab button
class _TabBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PHOTO CREATOR
// ─────────────────────────────────────────────────────────────

class _PhotoCreator extends StatefulWidget {
  final String userId;
  final String userName;
  final String userPhotoUrl;

  const _PhotoCreator({
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
  });

  @override
  State<_PhotoCreator> createState() => _PhotoCreatorState();
}

class _PhotoCreatorState extends State<_PhotoCreator> {
  File? _image;
  final _captionCtrl = TextEditingController();
  bool _loading = false;
  StoryPrivacy _privacy = StoryPrivacy.friends;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final picked = await ImagePicker().pickImage(
      source: src,
      imageQuality: 85,
      maxWidth: 1080,
      maxHeight: 1920,
    );
    if (picked != null && mounted) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _publish() async {
    if (_image == null) return;
    setState(() => _loading = true);
    try {
      final id = await context.read<StoryProvider>().createImageStory(
            userId: widget.userId,
            userName: widget.userName,
            userPhotoUrl: widget.userPhotoUrl,
            imageFile: _image!,
            caption: _captionCtrl.text.trim().isEmpty
                ? null
                : _captionCtrl.text.trim(),
            privacy: _privacy,
          );
      if (id != null && mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Status published!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return _PickerPrompt(onPick: _pick);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview
        Image.file(_image!, fit: BoxFit.cover),

        // Side tools
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              _SideBtn(
                  icon: Icons.collections,
                  label: 'Gallery',
                  onTap: () => _pick(ImageSource.gallery)),
              const SizedBox(height: 12),
              _SideBtn(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () => _pick(ImageSource.camera)),
              const SizedBox(height: 12),
              _SideBtn(
                icon: _privacy == StoryPrivacy.friends
                    ? Icons.people
                    : Icons.public,
                label: _privacy == StoryPrivacy.friends ? 'Friends' : 'All',
                onTap: () => setState(() {
                  _privacy = _privacy == StoryPrivacy.friends
                      ? StoryPrivacy.everyone
                      : StoryPrivacy.friends;
                }),
              ),
            ],
          ),
        ),

        // Caption
        Positioned(
          bottom: 96,
          left: 16,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _captionCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Add a caption…',
                hintStyle: TextStyle(color: Colors.white54),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: InputBorder.none,
              ),
              maxLines: 3,
              minLines: 1,
            ),
          ),
        ),

        // Publish
        Positioned(
          bottom: 32,
          left: 16,
          right: 16,
          child: _PublishBtn(loading: _loading, onTap: _publish),
        ),
      ],
    );
  }
}

// Empty state prompt
class _PickerPrompt extends StatelessWidget {
  final void Function(ImageSource) onPick;
  const _PickerPrompt({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Icon(Icons.add_photo_alternate,
                color: Colors.white54, size: 48),
          ),
          const SizedBox(height: 24),
          const Text('Share a photo',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Choose or take a photo to share as status',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BigPickBtn(
                  icon: Icons.collections,
                  label: 'Gallery',
                  onTap: () => onPick(ImageSource.gallery)),
              const SizedBox(width: 24),
              _BigPickBtn(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () => onPick(ImageSource.camera)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigPickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BigPickBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TEXT CREATOR
// ─────────────────────────────────────────────────────────────

class _TextCreator extends StatefulWidget {
  final String userId;
  final String userName;
  final String userPhotoUrl;

  const _TextCreator({
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
  });

  @override
  State<_TextCreator> createState() => _TextCreatorState();
}

class _TextCreatorState extends State<_TextCreator> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  StoryPrivacy _privacy = StoryPrivacy.friends;

  int _bgIdx = 0;
  int _fontIdx = 0;
  int _colorIdx = 0;
  double _fontSize = 28.0;

  static const _bgs = <List<int>>[
    [0xFF1A1A2E, 0xFF16213E],
    [0xFF833AB4, 0xFFFD1D1D],
    [0xFF0F2027, 0xFF203A43],
    [0xFFf7971e, 0xFFffd200],
    [0xFF11998e, 0xFF38ef7d],
    [0xFF6a3093, 0xFFa044ff],
    [0xFF1D976C, 0xFF93F9B9],
    [0xFFFC5C7D, 0xFF6A82FB],
  ];

  static const _fontFamilies = <String?>[null, 'Georgia', 'Courier New'];

  static const _textColors = <int>[
    0xFFFFFFFF,
    0xFFFFFF00,
    0xFFFFB347,
    0xFF87CEEB,
    0xFF90EE90,
  ];

  Color get _bg1 => Color(_bgs[_bgIdx][0]);
  Color get _bg2 => Color(_bgs[_bgIdx][1]);
  Color get _tc => Color(_textColors[_colorIdx]);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final id = await context.read<StoryProvider>().createTextStory(
            userId: widget.userId,
            userName: widget.userName,
            userPhotoUrl: widget.userPhotoUrl,
            textContent: text,
            backgroundColor: _bg1,
            textColor: _tc,
            fontFamily: _fontFamilies[_fontIdx],
            fontSize: _fontSize,
            privacy: _privacy,
          );
      if (id != null && mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Status published!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background gradient
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_bg1, _bg2],
            ),
          ),
        ),

        // Text input (centered)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: null,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _tc,
                fontSize: _fontSize,
                fontFamily: _fontFamilies[_fontIdx],
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
              decoration: InputDecoration(
                hintText: 'Type something…',
                hintStyle: TextStyle(
                  color: _tc.withOpacity(0.4),
                  fontSize: _fontSize,
                  fontWeight: FontWeight.w700,
                ),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),

        // Side tools
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              _SideBtn(
                icon: Icons.text_fields,
                label: 'Font',
                onTap: () => setState(
                    () => _fontIdx = (_fontIdx + 1) % _fontFamilies.length),
              ),
              const SizedBox(height: 12),
              _SideBtn(
                icon: Icons.format_color_text,
                label: 'Color',
                iconColor: _tc,
                onTap: () => setState(
                    () => _colorIdx = (_colorIdx + 1) % _textColors.length),
              ),
              const SizedBox(height: 12),
              _SideBtn(
                icon: _privacy == StoryPrivacy.friends
                    ? Icons.people
                    : Icons.public,
                label: _privacy == StoryPrivacy.friends ? 'Friends' : 'All',
                onTap: () => setState(() {
                  _privacy = _privacy == StoryPrivacy.friends
                      ? StoryPrivacy.everyone
                      : StoryPrivacy.friends;
                }),
              ),
            ],
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: 96,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Font size slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    const Icon(Icons.text_decrease,
                        color: Colors.white54, size: 16),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                          trackHeight: 2,
                        ),
                        child: Slider(
                          value: _fontSize,
                          min: 14,
                          max: 54,
                          onChanged: (v) => setState(() => _fontSize = v),
                        ),
                      ),
                    ),
                    const Icon(Icons.text_increase,
                        color: Colors.white54, size: 16),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Background swatches
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _bgs.length,
                  itemBuilder: (_, i) {
                    final sel = i == _bgIdx;
                    return GestureDetector(
                      onTap: () => setState(() => _bgIdx = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 10),
                        width: sel ? 42 : 32,
                        height: sel ? 42 : 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(_bgs[i][0]), Color(_bgs[i][1])],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: sel
                              ? Border.all(color: Colors.white, width: 2.5)
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Publish button
        Positioned(
          bottom: 32,
          left: 16,
          right: 16,
          child: _PublishBtn(
            loading: _loading,
            enabled: _ctrl.text.trim().isNotEmpty,
            onTap: _publish,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────

class _SideBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SideBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: iconColor ?? Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

class _PublishBtn extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  final bool enabled;

  const _PublishBtn({
    required this.loading,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;

    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [const Color(0xFF2196F3), const Color(0xFF1565C0)]
                : [Colors.grey.shade700, Colors.grey.shade800],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF2196F3).withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Share to Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
