// lib/pages/story_creator_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/providers/story_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

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
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.white70,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      padding: const EdgeInsets.all(3),
                      tabs: const [
                        Tab(text: '  📸 Photo  '),
                        Tab(text: '  ✍️ Text  '),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ImageStoryCreator(
                  userId: widget.userId,
                  userName: widget.userName,
                  userPhotoUrl: widget.userPhotoUrl,
                ),
                _TextStoryCreator(
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

// ──────────────────────────────────────────────────────────
// IMAGE STORY CREATOR
// ──────────────────────────────────────────────────────────
class _ImageStoryCreator extends StatefulWidget {
  final String userId;
  final String userName;
  final String userPhotoUrl;

  const _ImageStoryCreator({
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
  });

  @override
  State<_ImageStoryCreator> createState() => _ImageStoryCreatorState();
}

class _ImageStoryCreatorState extends State<_ImageStoryCreator> {
  File? _selectedImage;
  final _captionController = TextEditingController();
  bool _isLoading = false;
  StoryPrivacy _privacy = StoryPrivacy.friends;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1080,
      maxHeight: 1920,
    );
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _publishStory() async {
    if (_selectedImage == null) return;
    setState(() => _isLoading = true);

    try {
      final id = await context.read<StoryProvider>().createImageStory(
            userId: widget.userId,
            userName: widget.userName,
            userPhotoUrl: widget.userPhotoUrl,
            imageFile: _selectedImage!,
            caption: _captionController.text.trim().isEmpty
                ? null
                : _captionController.text.trim(),
            privacy: _privacy,
          );

      if (id != null && mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Story published!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Preview ──
        if (_selectedImage != null)
          Image.file(_selectedImage!, fit: BoxFit.cover)
        else
          _EmptyImagePicker(onPick: _pickImage),

        // ── Controls ──
        if (_selectedImage != null) ...[
          // Top buttons
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                _CircleIconBtn(
                  icon: Icons.collections,
                  label: 'Gallery',
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                const SizedBox(height: 12),
                _CircleIconBtn(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                const SizedBox(height: 12),
                _CircleIconBtn(
                  icon: _privacy == StoryPrivacy.friends
                      ? Icons.people
                      : Icons.public,
                  label:
                      _privacy == StoryPrivacy.friends ? 'Friends' : 'Everyone',
                  onTap: () => setState(() {
                    _privacy = _privacy == StoryPrivacy.friends
                        ? StoryPrivacy.everyone
                        : StoryPrivacy.friends;
                  }),
                ),
              ],
            ),
          ),

          // Caption input
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _captionController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
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

          // Publish button
          Positioned(
            bottom: 32,
            left: 16,
            right: 16,
            child: _PublishButton(
              isLoading: _isLoading,
              onPublish: _publishStory,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyImagePicker extends StatelessWidget {
  final void Function(ImageSource) onPick;
  const _EmptyImagePicker({required this.onPick});

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
              color: Colors.white12,
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Icon(Icons.add_photo_alternate,
                color: Colors.white54, size: 48),
          ),
          const SizedBox(height: 24),
          const Text(
            'Share a photo or video',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose from your gallery or take a new one',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PickerButton(
                icon: Icons.collections,
                label: 'Gallery',
                onTap: () => onPick(ImageSource.gallery),
              ),
              const SizedBox(width: 24),
              _PickerButton(
                icon: Icons.camera_alt,
                label: 'Camera',
                onTap: () => onPick(ImageSource.camera),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerButton(
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
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// TEXT STORY CREATOR
// ──────────────────────────────────────────────────────────

class _TextStoryCreator extends StatefulWidget {
  final String userId;
  final String userName;
  final String userPhotoUrl;

  const _TextStoryCreator({
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
  });

  @override
  State<_TextStoryCreator> createState() => _TextStoryCreatorState();
}

class _TextStoryCreatorState extends State<_TextStoryCreator> {
  final _textController = TextEditingController();
  bool _isLoading = false;
  StoryPrivacy _privacy = StoryPrivacy.friends;

  int _bgIndex = 0;
  int _fontIndex = 0;
  double _fontSize = 28.0;

  static const List<List<Color>> _backgrounds = [
    [Color(0xFF1A1A2E), Color(0xFF16213E)],
    [Color(0xFF833AB4), Color(0xFFFD1D1D)],
    [Color(0xFF0F2027), Color(0xFF203A43)],
    [Color(0xFFf7971e), Color(0xFFffd200)],
    [Color(0xFF11998e), Color(0xFF38ef7d)],
    [Color(0xFF6a3093), Color(0xFFa044ff)],
    [Color(0xFF1D976C), Color(0xFF93F9B9)],
    [Color(0xFFFC5C7D), Color(0xFF6A82FB)],
  ];

  static const List<String?> _fonts = [
    null,
    'Georgia',
    'Courier New',
  ];

  static const List<Color> _textColors = [
    Colors.white,
    Colors.yellow,
    Color(0xFFFFB347),
    Color(0xFF87CEEB),
    Colors.lightGreenAccent,
  ];

  int _textColorIndex = 0;

  Color get _bgColor1 => _backgrounds[_bgIndex][0];
  Color get _bgColor2 => _backgrounds[_bgIndex][1];
  Color get _textColor => _textColors[_textColorIndex];

  Future<void> _publishStory() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final id = await context.read<StoryProvider>().createTextStory(
            userId: widget.userId,
            userName: widget.userName,
            userPhotoUrl: widget.userPhotoUrl,
            textContent: text,
            backgroundColor: _bgColor1,
            textColor: _textColor,
            fontFamily: _fonts[_fontIndex],
            fontSize: _fontSize,
            privacy: _privacy,
          );

      if (id != null && mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Story published!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background preview ──
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_bgColor1, _bgColor2],
            ),
          ),
        ),

        // ── Text input overlay ──
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: IntrinsicHeight(
              child: TextField(
                controller: _textController,
                style: TextStyle(
                  color: _textColor,
                  fontSize: _fontSize,
                  fontFamily: _fonts[_fontIndex],
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                decoration: InputDecoration(
                  hintText: 'Type something…',
                  hintStyle: TextStyle(
                    color: _textColor.withOpacity(0.5),
                    fontSize: _fontSize,
                    fontWeight: FontWeight.w700,
                  ),
                  border: InputBorder.none,
                ),
                textAlign: TextAlign.center,
                maxLines: null,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ),

        // ── Controls ──
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              // Font toggle
              _CircleIconBtn(
                icon: Icons.text_fields,
                label: 'Font',
                onTap: () => setState(() {
                  _fontIndex = (_fontIndex + 1) % _fonts.length;
                }),
              ),
              const SizedBox(height: 12),
              // Text color
              _CircleIconBtn(
                icon: Icons.format_color_text,
                label: 'Color',
                onTap: () => setState(() {
                  _textColorIndex = (_textColorIndex + 1) % _textColors.length;
                }),
                color: _textColor,
              ),
              const SizedBox(height: 12),
              // Privacy
              _CircleIconBtn(
                icon: _privacy == StoryPrivacy.friends
                    ? Icons.people
                    : Icons.public,
                label:
                    _privacy == StoryPrivacy.friends ? 'Friends' : 'Everyone',
                onTap: () => setState(() {
                  _privacy = _privacy == StoryPrivacy.friends
                      ? StoryPrivacy.everyone
                      : StoryPrivacy.friends;
                }),
              ),
            ],
          ),
        ),

        // ── Background selector ──
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Font size slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  children: [
                    const Icon(Icons.text_decrease,
                        color: Colors.white54, size: 16),
                    Expanded(
                      child: Slider(
                        value: _fontSize,
                        min: 16,
                        max: 52,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                        onChanged: (v) => setState(() => _fontSize = v),
                      ),
                    ),
                    const Icon(Icons.text_increase,
                        color: Colors.white54, size: 16),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Background swatches
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _backgrounds.length,
                  itemBuilder: (_, i) {
                    final selected = i == _bgIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _bgIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 10),
                        width: selected ? 40 : 32,
                        height: selected ? 40 : 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _backgrounds[i],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(color: Colors.white, width: 2.5)
                              : null,
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.4),
                                    blurRadius: 8,
                                  )
                                ]
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

        // ── Publish button ──
        Positioned(
          bottom: 32,
          left: 16,
          right: 16,
          child: _PublishButton(
            isLoading: _isLoading,
            onPublish: _publishStory,
            enabled: _textController.text.trim().isNotEmpty,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────
// SHARED WIDGETS
// ──────────────────────────────────────────────────────────

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _CircleIconBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

class _PublishButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPublish;
  final bool enabled;

  const _PublishButton({
    required this.isLoading,
    required this.onPublish,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (isLoading || !enabled) ? null : onPublish,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: enabled && !isLoading
                ? [const Color(0xFF2196F3), const Color(0xFF1976D2)]
                : [Colors.grey.shade600, Colors.grey.shade700],
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: enabled && !isLoading
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
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
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
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
