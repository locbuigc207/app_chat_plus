import 'dart:convert';
import 'dart:io';

import 'package:deepar_flutter_plus/deepar_flutter_plus.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/constants/color_constants.dart';
import 'package:flutter_chat_demo/providers/story_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StoryCreatorPage
// ─────────────────────────────────────────────────────────────────────────────

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
    _tab = TabController(length: 3, vsync: this)
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
                  _TabSelector(
                    index: _tabIndex,
                    onSelect: (i) {
                      _tab.animateTo(i);
                      setState(() => _tabIndex = i);
                    },
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              physics: const NeverScrollableScrollPhysics(),
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
                _VideoCreator(
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

// ─────────────────────────────────────────────────────────────────────────────
// Tab Selector
// ─────────────────────────────────────────────────────────────────────────────

class _TabSelector extends StatelessWidget {
  final int index;
  final void Function(int) onSelect;

  static const _tabs = [
    (icon: '📸', label: 'Photo'),
    (icon: '✍️', label: 'Text'),
    (icon: '🎥', label: 'Video'),
  ];

  const _TabSelector({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_tabs.length, (i) {
          final t = _tabs[i];
          final sel = i == index;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${t.icon}  ${t.label}',
                style: TextStyle(
                  color: sel ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo Creator
// ─────────────────────────────────────────────────────────────────────────────

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
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _publish() async {
    if (_image == null) return;
    setState(() => _loading = true);
    HapticFeedback.mediumImpact();

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

      if (!mounted) return;
      if (id != null) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Status published!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _togglePrivacy() {
    setState(() {
      _privacy = _privacy == StoryPrivacy.friends
          ? StoryPrivacy.everyone
          : StoryPrivacy.friends;
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) return _PickerPrompt(onPick: _pick);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.file(_image!, fit: BoxFit.cover),

          // Dark gradient bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 260,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
            ),
          ),

          // Side buttons
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                _SideBtn(
                  icon: Icons.collections,
                  label: 'Gallery',
                  onTap: () => _pick(ImageSource.gallery),
                ),
                const SizedBox(height: 12),
                _SideBtn(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () => _pick(ImageSource.camera),
                ),
                const SizedBox(height: 12),
                _SideBtn(
                  icon: _privacy == StoryPrivacy.friends
                      ? Icons.people
                      : Icons.public,
                  label: _privacy == StoryPrivacy.friends ? 'Friends' : 'All',
                  onTap: _togglePrivacy,
                  iconColor: _privacy == StoryPrivacy.friends
                      ? Colors.amber
                      : Colors.greenAccent,
                ),
              ],
            ),
          ),

          // Caption input
          Positioned(
            bottom: bottomInset > 0 ? bottomInset + 16 : 96,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white24),
              ),
              child: TextField(
                controller: _captionCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Add a caption…',
                  hintStyle: TextStyle(color: Colors.white38),
                  contentPadding:
                  EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  border: InputBorder.none,
                  prefixIcon:
                  Icon(Icons.edit_note, color: Colors.white38, size: 22),
                ),
                maxLines: 3,
                minLines: 1,
              ),
            ),
          ),

          // Publish button
          if (bottomInset == 0)
            Positioned(
              bottom: 32,
              left: 16,
              right: 16,
              child: _PublishBtn(loading: _loading, onTap: _publish),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Picker prompt (empty state)
// ─────────────────────────────────────────────────────────────────────────────

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
              gradient: const LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF7C4DFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(Icons.add_photo_alternate,
                color: Colors.white, size: 50),
          ),
          const SizedBox(height: 28),
          const Text(
            'Share a Photo',
            style: TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose or take a photo to share as status',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 44),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BigPickBtn(
                icon: Icons.collections,
                label: 'Gallery',
                gradient: const [Color(0xFF7C4DFF), Color(0xFF2196F3)],
                onTap: () => onPick(ImageSource.gallery),
              ),
              const SizedBox(width: 24),
              _BigPickBtn(
                icon: Icons.camera_alt,
                label: 'Camera',
                gradient: const [Color(0xFFFF6B35), Color(0xFFFF2D55)],
                onTap: () => onPick(ImageSource.camera),
              ),
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
  final List<Color> gradient;
  final VoidCallback onTap;

  const _BigPickBtn({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient:
              LinearGradient(colors: gradient, begin: Alignment.topLeft),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                    color: gradient.last.withOpacity(0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text Creator
// ─────────────────────────────────────────────────────────────────────────────

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
  double _fontSize = 30.0;
  TextAlign _align = TextAlign.center;

  static const _bgs = <List<int>>[
    [0xFF1A1A2E, 0xFF16213E],
    [0xFF833AB4, 0xFFFD1D1D],
    [0xFF0F2027, 0xFF2C5364],
    [0xFFf7971e, 0xFFffd200],
    [0xFF11998e, 0xFF38ef7d],
    [0xFF6a3093, 0xFFa044ff],
    [0xFF1D976C, 0xFF93F9B9],
    [0xFFFC5C7D, 0xFF6A82FB],
    [0xFF373B44, 0xFF4286f4],
    [0xFFcb2d3e, 0xFFef473a],
  ];

  static const _fontFamilies = <String?>[null, 'Georgia', 'Courier New'];
  static const _fontLabels = ['Default', 'Serif', 'Mono'];

  static const _textColors = <int>[
    0xFFFFFFFF,
    0xFFFFFF00,
    0xFFFFB347,
    0xFF87CEEB,
    0xFF90EE90,
    0xFFFF69B4,
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
    HapticFeedback.mediumImpact();

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

      if (!mounted) return;
      if (id != null) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Status published!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_bg1, _bg2],
            ),
          ),
        ),

        // Text input centred
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: TextField(
              controller: _ctrl,
              autofocus: false,
              maxLines: null,
              textAlign: _align,
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

        // Right-side controls
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              _SideBtn(
                icon: Icons.text_fields,
                label: _fontLabels[_fontIdx],
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
                icon: _align == TextAlign.center
                    ? Icons.format_align_center
                    : _align == TextAlign.left
                    ? Icons.format_align_left
                    : Icons.format_align_right,
                label: 'Align',
                onTap: () => setState(() {
                  if (_align == TextAlign.center) {
                    _align = TextAlign.left;
                  } else if (_align == TextAlign.left) {
                    _align = TextAlign.right;
                  } else {
                    _align = TextAlign.center;
                  }
                }),
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
                iconColor: _privacy == StoryPrivacy.friends
                    ? Colors.amber
                    : Colors.greenAccent,
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
                    const Icon(Icons.text_decrease, color: Colors.white54, size: 16),
                    Expanded(
                      child: SliderTheme(
                        data: const SliderThemeData(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                          trackHeight: 2,
                        ),
                        child: Slider(
                          value: _fontSize,
                          min: 14,
                          max: 60,
                          onChanged: (v) => setState(() => _fontSize = v),
                        ),
                      ),
                    ),
                    const Icon(Icons.text_increase, color: Colors.white54, size: 16),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Background gradient swatches
              SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _bgs.length,
                  itemBuilder: (_, i) {
                    final sel = i == _bgIdx;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _bgIdx = i);
                        HapticFeedback.selectionClick();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 10),
                        width: sel ? 44 : 34,
                        height: sel ? 44 : 34,
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
                          boxShadow: sel
                              ? [
                            BoxShadow(
                              color: Color(_bgs[i][1]).withOpacity(0.5),
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

// ─────────────────────────────────────────────────────────────────────────────
// AR Filter model
// ─────────────────────────────────────────────────────────────────────────────

class _ArFilter {
  final String displayName;
  final String? assetPath;

  const _ArFilter({required this.displayName, this.assetPath});

  static const _ArFilter none = _ArFilter(displayName: 'None');

  static String _toDisplayName(String assetPath) {
    final withoutExt =
    assetPath.split('/').last.replaceAll('.deepar', '');
    return withoutExt
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static Future<List<_ArFilter>> loadAll() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final manifest = json.decode(manifestJson) as Map<String, dynamic>;
      final effectPaths = manifest.keys
          .where((k) =>
      k.startsWith('assets/effects/') && k.endsWith('.deepar'))
          .toList()
        ..sort();

      return [
        _ArFilter.none,
        ...effectPaths.map(
              (p) => _ArFilter(displayName: _toDisplayName(p), assetPath: p),
        ),
      ];
    } catch (e) {
      debugPrint('Error loading filters: $e');
      return [_ArFilter.none];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Creator
// ─────────────────────────────────────────────────────────────────────────────

class _VideoCreator extends StatefulWidget {
  final String userId;
  final String userName;
  final String userPhotoUrl;

  const _VideoCreator({
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
  });

  @override
  State<_VideoCreator> createState() => _VideoCreatorState();
}

class _VideoCreatorState extends State<_VideoCreator>
    with SingleTickerProviderStateMixin {
  static const _androidKey =
      '694aafc68314126d55d03f1cb2b23ce05f57467994107fb3895aab7f7060c2a5863a6c28f29a341b';
  static const _iosKey = 'YOUR_IOS_DEEPAR_KEY_HERE';

  late DeepArControllerPlus _deepArController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  late AnimationController _pulseCtrl;

  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isProcessing = false;
  String? _selectedAudioPath;
  String? _selectedAudioName;
  int _recordSeconds = 0;
  static const int _maxSeconds = 15;

  List<_ArFilter> _filters = [];
  int _currentFilterIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _initAll();
  }

  Future<void> _initAll() async {
    final filters = await _ArFilter.loadAll();
    if (mounted) setState(() => _filters = filters);
    await _initDeepAr();
  }

  Future<void> _initDeepAr() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      _deepArController = DeepArControllerPlus();
      await _deepArController.initialize(
        androidLicenseKey: _androidKey,
        iosLicenseKey: _iosKey,
        resolution: Resolution.high,
      );
      if (mounted) setState(() => _isInitialized = true);
    } else {
      Fluttertoast.showToast(msg: 'Camera & Mic permissions required!');
      if (mounted) Navigator.pop(context);
    }
  }

  void _switchFilter(int i) {
    setState(() => _currentFilterIndex = i);
    _deepArController.switchEffect(_filters[i].assetPath ?? '');
    HapticFeedback.selectionClick();
  }

  Future<void> _pickMusic() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        final name = result.files.first.name;
        if (path != null) {
          setState(() {
            _selectedAudioPath = path;
            _selectedAudioName =
            name.length > 20 ? '${name.substring(0, 20)}…' : name;
          });
          await _audioPlayer.setFilePath(path);
          Fluttertoast.showToast(msg: '✅ Music added!');
        }
      }
    } catch (e) {
      debugPrint('FilePicker Error: $e');
      Fluttertoast.showToast(msg: '❌ Could not pick audio!');
    }
  }

  Future<void> _startRecording() async {
    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
    });
    HapticFeedback.heavyImpact();

    if (_selectedAudioPath != null) {
      await _audioPlayer.seek(Duration.zero);
      _audioPlayer.play();
    }

    await _deepArController.startVideoRecording();

    // Count seconds up to max
    _countUp();
  }

  void _countUp() async {
    while (_isRecording && _recordSeconds < _maxSeconds) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _recordSeconds++);
    }
    if (_isRecording && _recordSeconds >= _maxSeconds) {
      await _stopRecording();
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    if (_selectedAudioPath != null) await _audioPlayer.stop();

    try {
      final File videoFile = await _deepArController.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });
      HapticFeedback.mediumImpact();

      if (_selectedAudioPath != null) {
        await _mergeAudioAndVideo(videoFile.path, _selectedAudioPath!);
      } else {
        await _uploadStory(videoFile.path,
            Duration(seconds: _recordSeconds.clamp(1, _maxSeconds)));
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
      Fluttertoast.showToast(msg: 'Error stopping recording!');
    }
  }

  Future<void> _mergeAudioAndVideo(
      String videoPath, String audioPath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final output =
          '${dir.path}/story_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final cmd =
          "-i '$videoPath' -i '$audioPath' -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest '$output'";

      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();

      if (ReturnCode.isSuccess(rc)) {
        await _uploadStory(output,
            Duration(seconds: _recordSeconds.clamp(1, _maxSeconds)));
      } else {
        final logs = await session.getAllLogsAsString();
        debugPrint('FFmpeg logs: $logs');
        if (mounted) setState(() => _isProcessing = false);
        Fluttertoast.showToast(msg: 'Error merging audio!');
      }
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
      Fluttertoast.showToast(msg: 'Error: $e');
    }
  }

  Future<void> _uploadStory(String finalPath, Duration duration) async {
    try {
      await context.read<StoryProvider>().createVideoStory(
        userId: widget.userId,
        userName: widget.userName,
        userPhotoUrl: widget.userPhotoUrl,
        videoFile: File(finalPath),
        videoDuration: duration,
        privacy: StoryPrivacy.friends,
      );
      Fluttertoast.showToast(msg: '✅ Story published!');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Upload error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    if (_isInitialized) _deepArController.destroy();
    _audioPlayer.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: ColorConstants.primaryColor),
            const SizedBox(height: 16),
            const Text('Initializing camera…',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        Positioned.fill(child: DeepArPreviewPlus(_deepArController)),

        // Music button top-right
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              _SideBtn(
                icon: _selectedAudioPath != null
                    ? Icons.music_note
                    : Icons.music_off,
                label: _selectedAudioName ?? 'Music',
                iconColor: _selectedAudioPath != null
                    ? Colors.greenAccent
                    : Colors.white,
                onTap: _pickMusic,
              ),
            ],
          ),
        ),

        // Recording timer
        if (_isRecording)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, __) => Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(
                              Colors.red, Colors.red.withOpacity(0.2),
                              _pulseCtrl.value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_recordSeconds}s / ${_maxSeconds}s',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Processing overlay
        if (_isProcessing)
          Container(
            color: Colors.black87,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Processing video…',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),
          ),

        // Bottom controls
        if (!_isProcessing)
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Filter carousel
                if (_filters.isNotEmpty)
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _filters.length,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemBuilder: (_, i) {
                        final filter = _filters[i];
                        final sel = i == _currentFilterIndex;
                        return GestureDetector(
                          onTap: () => _switchFilter(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 64,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: sel
                                  ? const LinearGradient(
                                colors: [
                                  Color(0xFF2196F3),
                                  Color(0xFF7C4DFF)
                                ],
                              )
                                  : null,
                              color: sel ? null : Colors.white24,
                              border: Border.all(
                                color: sel ? Colors.white : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                filter.displayName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 16),

                // Record button
                GestureDetector(
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopRecording(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _isRecording ? Colors.red : Colors.white,
                          width: 4),
                      gradient: _isRecording
                          ? const LinearGradient(
                        colors: [Color(0xFFFF2D55), Color(0xFFFF6B35)],
                      )
                          : null,
                      color: _isRecording ? null : Colors.white30,
                      boxShadow: _isRecording
                          ? [
                        const BoxShadow(
                          color: Colors.red,
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ]
                          : null,
                    ),
                    child: _isRecording
                        ? const Icon(Icons.stop, color: Colors.white, size: 40)
                        : const Icon(Icons.videocam,
                        color: Colors.white, size: 36),
                  ),
                ),

                const SizedBox(height: 10),
                Text(
                  _isRecording ? 'Release to stop' : 'Hold to record',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: iconColor ?? Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
        height: 54,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [const Color(0xFF2196F3), const Color(0xFF1565C0)]
                : [Colors.grey.shade700, Colors.grey.shade800],
          ),
          borderRadius: BorderRadius.circular(27),
          boxShadow: active
              ? [
            BoxShadow(
              color: const Color(0xFF2196F3).withOpacity(0.45),
              blurRadius: 18,
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