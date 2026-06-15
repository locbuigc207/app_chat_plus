import 'dart:async';
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

// ─── Page ─────────────────────────────────────────────────────────────────────

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
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
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
          _buildTopBar(),
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

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(
          children: [
            _CircleIconBtn(
              icon: Icons.close_rounded,
              onTap: () => Navigator.pop(context),
            ),
            const Spacer(),
            _TabPill(
              index: _tabIndex,
              onSelect: (i) {
                _tab.animateTo(i);
                setState(() => _tabIndex = i);
              },
            ),
            const Spacer(),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

// ─── Tab Pill ──────────────────────────────────────────────────────────────────

class _TabPill extends StatelessWidget {
  final int index;
  final void Function(int) onSelect;

  static const _tabs = [
    (icon: Icons.photo_camera_rounded, label: 'Photo'),
    (icon: Icons.text_fields_rounded, label: 'Text'),
    (icon: Icons.videocam_rounded, label: 'Video'),
  ];

  const _TabPill({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    t.icon,
                    size: 15,
                    color: sel ? Colors.black : Colors.white70,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    t.label,
                    style: TextStyle(
                      color: sel ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Photo Creator ────────────────────────────────────────────────────────────

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
  StoryFilter _filter = StoryFilter.none;
  bool _showCaption = false;
  bool _showFilters = false;

  final _filterNames = [
    'None',
    'Clarendon',
    'Gingham',
    'Moon',
    'Lark',
    'Reyes',
    'Juno',
    'Slumber',
    'Crema',
    'Ludwig',
    'Aden',
    'Perpetua',
  ];

  ColorFilter _getColorFilter(StoryFilter f) {
    return switch (f) {
      StoryFilter.clarendon => const ColorFilter.matrix([
        1.1,
        0,
        0,
        0,
        0,
        0,
        1.1,
        0,
        0,
        0,
        0,
        0,
        1.2,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      StoryFilter.moon => const ColorFilter.matrix([
        0.33,
        0.33,
        0.33,
        0,
        0,
        0.33,
        0.33,
        0.33,
        0,
        0,
        0.33,
        0.33,
        0.33,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      StoryFilter.lark => const ColorFilter.matrix([
        1.0,
        0,
        0,
        0,
        15,
        0,
        1.05,
        0,
        0,
        5,
        0,
        0,
        0.9,
        0,
        -5,
        0,
        0,
        0,
        1,
        0,
      ]),
      StoryFilter.juno => const ColorFilter.matrix([
        1.15,
        0,
        0,
        0,
        0,
        0,
        1.0,
        0,
        0,
        0,
        0,
        0,
        0.9,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      StoryFilter.slumber => const ColorFilter.matrix([
        0.85,
        0.1,
        0.05,
        0,
        10,
        0.05,
        0.85,
        0.1,
        0,
        5,
        0.1,
        0.05,
        0.85,
        0,
        5,
        0,
        0,
        0,
        0.9,
        0,
      ]),
      _ => const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
    };
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final picked = await ImagePicker().pickImage(
      source: src,
      imageQuality: 90,
      maxWidth: 1440,
      maxHeight: 2560,
    );
    if (picked != null && mounted) {
      setState(() {
        _image = File(picked.path);
        _showFilters = false;
      });
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
        filter: _filter,
      );

      if (!mounted) return;
      if (id != null) {
        Navigator.of(context).pop(true);
        Fluttertoast.showToast(
          msg: '✨ Story shared!',
          backgroundColor: Colors.green.shade700,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Fluttertoast.showToast(msg: '❌ Error: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return _MediaPickerPrompt(
        icon: Icons.add_photo_alternate_rounded,
        title: 'Share a Photo',
        subtitle: 'Choose from gallery or take a new photo',
        primaryColor: const Color(0xFF7B61FF),
        secondaryColor: const Color(0xFF2196F3),
        onGallery: () => _pick(ImageSource.gallery),
        onCamera: () => _pick(ImageSource.camera),
      );
    }

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() {
          _showCaption = false;
          _showFilters = false;
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _filter == StoryFilter.none
              ? Image.file(_image!, fit: BoxFit.cover)
              : ColorFiltered(
                  colorFilter: _getColorFilter(_filter),
                  child: Image.file(_image!, fit: BoxFit.cover),
                ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 280,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 14,
            child: Column(
              children: [
                _SideAction(
                  icon: Icons.collections_rounded,
                  label: 'Gallery',
                  onTap: () => _pick(ImageSource.gallery),
                ),
                const SizedBox(height: 12),
                _SideAction(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  onTap: () => _pick(ImageSource.camera),
                ),
                const SizedBox(height: 12),
                _SideAction(
                  icon: Icons.auto_fix_high_rounded,
                  label: 'Filter',
                  onTap: () => setState(() {
                    _showFilters = !_showFilters;
                    _showCaption = false;
                  }),
                  active: _showFilters,
                ),
                const SizedBox(height: 12),
                _SideAction(
                  icon: Icons.edit_rounded,
                  label: 'Caption',
                  onTap: () => setState(() {
                    _showCaption = !_showCaption;
                    _showFilters = false;
                    if (_showCaption) {
                      Future.delayed(
                        const Duration(milliseconds: 100),
                        () => FocusScope.of(context).requestFocus(FocusNode()),
                      );
                    }
                  }),
                  active: _showCaption,
                ),
                const SizedBox(height: 12),
                _PrivacyButton(
                  privacy: _privacy,
                  onTap: () => setState(() {
                    final idx = StoryPrivacy.values.indexOf(_privacy);
                    _privacy = StoryPrivacy
                        .values[(idx + 1) % StoryPrivacy.values.length];
                  }),
                ),
              ],
            ),
          ),
          if (_showFilters)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: _FilterStrip(
                selected: _filter,
                image: _image,
                onSelect: (f) => setState(() => _filter = f),
              ),
            ),
          if (_showCaption && bottomInset == 0)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: _CaptionInput(controller: _captionCtrl),
            ),
          if (bottomInset == 0 && !_showFilters)
            Positioned(
              bottom: 28,
              left: 16,
              right: 16,
              child: _PublishButton(
                loading: _loading,
                onTap: _publish,
                label: 'Share Story',
              ),
            ),
          if (bottomInset > 0)
            Positioned(
              bottom: bottomInset + 12,
              left: 16,
              right: 16,
              child: _CaptionInput(controller: _captionCtrl),
            ),
        ],
      ),
    );
  }
}

// ─── Text Creator ─────────────────────────────────────────────────────────────

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
  double _fontSize = 32.0;
  TextAlign _align = TextAlign.center;
  bool _hasTextBg = false;

  static const _backgrounds = <List<int>>[
    [0xFF0F0C29, 0xFF302B63, 0xFF24243e],
    [0xFFFF416C, 0xFFFF4B2B],
    [0xFF1D976C, 0xFF93F9B9],
    [0xFF2980B9, 0xFF6DD5FA, 0xFFFFFFFF],
    [0xFFf7971e, 0xFFffd200],
    [0xFF8360c3, 0xFF2ebf91],
    [0xFFFC5C7D, 0xFF6A82FB],
    [0xFF11998e, 0xFF38ef7d],
    [0xFF373B44, 0xFF4286f4],
    [0xFFDA4453, 0xFF89216B],
    [0xFF0099F7, 0xFFF11712],
    [0xFFEDE574, 0xFFE1F5C4],
  ];

  static const _fontFamilies = <String?>[
    null,
    'Georgia',
    'Courier New',
    'serif',
  ];
  static const _fontLabels = ['Classic', 'Serif', 'Mono', 'Slab'];

  static const _textColors = <int>[
    0xFFFFFFFF,
    0xFF000000,
    0xFFFFFF00,
    0xFFFF6B6B,
    0xFF4ECDC4,
    0xFF45B7D1,
    0xFF96CEB4,
    0xFFFF9FF3,
  ];

  Color get _bg1 => Color(_backgrounds[_bgIdx][0]);
  Color get _bg2 => Color(
    _backgrounds[_bgIdx].length > 1
        ? _backgrounds[_bgIdx][1]
        : _backgrounds[_bgIdx][0],
  );
  Color get _tc => Color(_textColors[_colorIdx]);
  List<Color> get _gradColors =>
      _backgrounds[_bgIdx].map((c) => Color(c)).toList();

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
        gradientColors: _gradColors,
      );

      if (!mounted) return;
      if (id != null) {
        Navigator.of(context).pop(true);
        Fluttertoast.showToast(
          msg: '✨ Story shared!',
          backgroundColor: Colors.green.shade700,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Fluttertoast.showToast(msg: '❌ Error: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _gradColors.length >= 2 ? _gradColors : [_bg1, _bg2],
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: _hasTextBg
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                  : EdgeInsets.zero,
              decoration: _hasTextBg
                  ? BoxDecoration(
                      color: _tc.computeLuminance() > 0.5
                          ? Colors.black87
                          : Colors.white.withValues(alpha: 0.87),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                maxLines: null,
                textAlign: _align,
                style: TextStyle(
                  color: _tc,
                  fontSize: _fontSize,
                  fontFamily: _fontFamilies[_fontIdx],
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  shadows: _hasTextBg
                      ? null
                      : [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                decoration: InputDecoration(
                  hintText: 'Type something…',
                  hintStyle: TextStyle(
                    color: _tc.withValues(alpha: 0.4),
                    fontSize: _fontSize,
                    fontWeight: FontWeight.w800,
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 14,
          child: Column(
            children: [
              _SideAction(
                icon: _fontIdx == 0
                    ? Icons.font_download_rounded
                    : Icons.font_download_outlined,
                label: _fontLabels[_fontIdx],
                onTap: () => setState(
                  () => _fontIdx = (_fontIdx + 1) % _fontFamilies.length,
                ),
              ),
              const SizedBox(height: 12),
              _ColorDot(
                color: _tc,
                onTap: () => setState(
                  () => _colorIdx = (_colorIdx + 1) % _textColors.length,
                ),
              ),
              const SizedBox(height: 12),
              _SideAction(
                icon: _align == TextAlign.center
                    ? Icons.format_align_center_rounded
                    : _align == TextAlign.left
                    ? Icons.format_align_left_rounded
                    : Icons.format_align_right_rounded,
                label: 'Align',
                onTap: () => setState(() {
                  _align = _align == TextAlign.center
                      ? TextAlign.left
                      : _align == TextAlign.left
                      ? TextAlign.right
                      : TextAlign.center;
                }),
              ),
              const SizedBox(height: 12),
              _SideAction(
                icon: _hasTextBg
                    ? Icons.format_color_fill_rounded
                    : Icons.text_fields_rounded,
                label: 'Style',
                onTap: () => setState(() => _hasTextBg = !_hasTextBg),
                active: _hasTextBg,
              ),
              const SizedBox(height: 12),
              _PrivacyButton(
                privacy: _privacy,
                onTap: () => setState(() {
                  final idx = StoryPrivacy.values.indexOf(_privacy);
                  _privacy = StoryPrivacy
                      .values[(idx + 1) % StoryPrivacy.values.length];
                }),
              ),
            ],
          ),
        ),
        if (bottomInset == 0)
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.text_decrease_rounded,
                        color: Colors.white54,
                        size: 18,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2,
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                            overlayColor: Colors.white.withValues(alpha: 0.2),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                          ),
                          child: Slider(
                            value: _fontSize,
                            min: 16,
                            max: 64,
                            onChanged: (v) => setState(() => _fontSize = v),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.text_increase_rounded,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _backgrounds.length,
                    itemBuilder: (_, i) {
                      final sel = i == _bgIdx;
                      final colors = _backgrounds[i]
                          .map((c) => Color(c))
                          .toList();
                      return GestureDetector(
                        onTap: () {
                          setState(() => _bgIdx = i);
                          HapticFeedback.selectionClick();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          width: sel ? 40 : 32,
                          height: sel ? 40 : 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: colors.length >= 2
                                  ? colors
                                  : [colors[0], colors[0]],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: sel ? Colors.white : Colors.white24,
                              width: sel ? 2.5 : 1,
                            ),
                            boxShadow: sel
                                ? [
                                    BoxShadow(
                                      color: colors.last.withValues(alpha: 0.6),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _PublishButton(
                    loading: _loading,
                    enabled: _ctrl.text.trim().isNotEmpty,
                    onTap: _publish,
                    label: 'Share Story',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── AR Filter Helper ─────────────────────────────────────────────────────────

class _ArFilter {
  final String displayName;
  final String? assetPath;

  const _ArFilter({required this.displayName, this.assetPath});

  static const _ArFilter none = _ArFilter(displayName: 'None');

  static String _toDisplayName(String assetPath) {
    final withoutExt = assetPath.split('/').last.replaceAll('.deepar', '');
    return withoutExt
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static Future<List<_ArFilter>> loadAll() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final manifest = json.decode(manifestJson) as Map<String, dynamic>;
      final effectPaths =
          manifest.keys
              .where(
                (k) => k.startsWith('assets/effects/') && k.endsWith('.deepar'),
              )
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

// ─── Video Creator ────────────────────────────────────────────────────────────

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
  bool _loading = false;
  File? _videoFile;
  String? _selectedAudioPath;
  String? _selectedAudioName;
  int _recordSeconds = 0;
  static const int _maxSeconds = 15;
  StoryPrivacy _privacy = StoryPrivacy.friends;

  List<_ArFilter> _filters = [];
  int _currentFilterIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _initAll();
  }

  Future<void> _initAll() async {
    final filters = await _ArFilter.loadAll();
    if (mounted) setState(() => _filters = filters);
    await _initDeepAr();
  }

  Future<void> _initDeepAr() async {
    final statuses = await [Permission.camera, Permission.microphone].request();

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
            _selectedAudioName = name.length > 15
                ? '${name.substring(0, 15)}…'
                : name;
          });
          await _audioPlayer.setFilePath(path);
          Fluttertoast.showToast(msg: '✅ Music added!');
        }
      }
    } catch (e) {
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
        _videoFile = videoFile;
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      setState(() => _isRecording = false);
      Fluttertoast.showToast(msg: 'Error stopping recording!');
    }
  }

  Future<void> _pickGalleryVideo() async {
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 30),
    );
    if (picked != null && mounted) {
      setState(() {
        _videoFile = File(picked.path);
        _selectedAudioPath = null;
        _selectedAudioName = null;
      });
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _publish() async {
    if (_videoFile == null) return;
    setState(() => _loading = true);
    HapticFeedback.mediumImpact();

    try {
      File finalVideo = _videoFile!;

      if (_selectedAudioPath != null) {
        final dir = await getApplicationDocumentsDirectory();
        final output =
            '${dir.path}/story_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final cmd =
            "-i '${_videoFile!.path}' -i '$_selectedAudioPath' -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest '$output'";

        final session = await FFmpegKit.execute(cmd);
        final rc = await session.getReturnCode();
        if (ReturnCode.isSuccess(rc)) {
          finalVideo = File(output);
        } else {
          Fluttertoast.showToast(msg: 'Error merging audio!');
        }
      }

      final id = await context.read<StoryProvider>().createVideoStory(
        userId: widget.userId,
        userName: widget.userName,
        userPhotoUrl: widget.userPhotoUrl,
        videoFile: finalVideo,
        privacy: _privacy,
        videoDuration: Duration(
          seconds: _recordSeconds > 0
              ? _recordSeconds.clamp(1, _maxSeconds)
              : 15,
        ),
      );

      if (!mounted) return;
      if (id != null) {
        Navigator.of(context).pop(true);
        Fluttertoast.showToast(
          msg: '✨ Story shared!',
          backgroundColor: Colors.green.shade700,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Fluttertoast.showToast(msg: '❌ Error: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
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
    if (_videoFile != null) {
      // PREVIEW STATE
      return Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Container(
                    width: 100 + _pulseCtrl.value * 8,
                    height: 100 + _pulseCtrl.value * 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(
                            0xFFFF2D55,
                          ).withValues(alpha: 0.8 + _pulseCtrl.value * 0.2),
                          const Color(0xFFFF2D55).withValues(alpha: 0.2),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.videocam_rounded,
                      color: Colors.white,
                      size: 50,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Video ready',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _videoFile!.path.split('/').last,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Positioned(
            top: 16,
            right: 14,
            child: Column(
              children: [
                _SideAction(
                  icon: Icons.close_rounded,
                  label: 'Retake',
                  onTap: () => setState(() {
                    _videoFile = null;
                    _recordSeconds = 0;
                  }),
                ),
                const SizedBox(height: 12),
                _PrivacyButton(
                  privacy: _privacy,
                  onTap: () => setState(() {
                    final idx = StoryPrivacy.values.indexOf(_privacy);
                    _privacy = StoryPrivacy
                        .values[(idx + 1) % StoryPrivacy.values.length];
                  }),
                ),
              ],
            ),
          ),
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFFF2D55)),
                    SizedBox(height: 16),
                    Text(
                      'Uploading…',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          if (!_loading)
            Positioned(
              bottom: 28,
              left: 16,
              right: 16,
              child: _PublishButton(
                loading: false,
                onTap: _publish,
                label: 'Share Video',
              ),
            ),
        ],
      );
    }

    // CAMERA STATE
    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: ColorConstants.primaryColor),
            SizedBox(height: 16),
            Text(
              'Initializing camera…',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: DeepArPreviewPlus(_deepArController)),
        Positioned(
          top: 16,
          right: 14,
          child: Column(
            children: [
              _SideAction(
                icon: _selectedAudioPath != null
                    ? Icons.music_note_rounded
                    : Icons.music_off_rounded,
                label: _selectedAudioName ?? 'Music',
                iconColor: _selectedAudioPath != null
                    ? Colors.greenAccent
                    : Colors.white,
                onTap: _pickMusic,
              ),
              const SizedBox(height: 12),
              _SideAction(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                onTap: _pickGalleryVideo,
              ),
            ],
          ),
        ),
        if (_isRecording)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
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
                            Colors.red,
                            Colors.red.withValues(alpha: 0.2),
                            _pulseCtrl.value,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_recordSeconds}s / ${_maxSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!_isRecording)
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                                        Color(0xFF7C4DFF),
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
                GestureDetector(
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopRecording(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.white30,
                    ),
                    child: const Icon(
                      Icons.videocam,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Hold to record',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _MediaPickerPrompt extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color primaryColor;
  final Color secondaryColor;
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final String galleryLabel;
  final String cameraLabel;

  const _MediaPickerPrompt({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryColor,
    required this.secondaryColor,
    required this.onGallery,
    required this.onCamera,
    this.galleryLabel = 'Gallery',
    this.cameraLabel = 'Camera',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.withValues(alpha: 0.15),
            secondaryColor.withValues(alpha: 0.08),
            Colors.black,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor, secondaryColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 52),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Row(
                children: [
                  Expanded(
                    child: _BigPickBtn(
                      icon: Icons.photo_library_rounded,
                      label: galleryLabel,
                      gradient: [secondaryColor, primaryColor],
                      onTap: onGallery,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _BigPickBtn(
                      icon: cameraLabel == 'Record'
                          ? Icons.videocam_rounded
                          : Icons.camera_alt_rounded,
                      label: cameraLabel,
                      gradient: [primaryColor, secondaryColor],
                      onTap: onCamera,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool active;

  const _SideAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? Colors.white : Colors.white24,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Icon(icon, color: iconColor ?? Colors.white, size: 21),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _ColorDot({required this.color, required this.onTap});

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
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Color',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyButton extends StatelessWidget {
  final StoryPrivacy privacy;
  final VoidCallback onTap;

  const _PrivacyButton({required this.privacy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (privacy) {
      StoryPrivacy.everyone => (Icons.public_rounded, Colors.greenAccent),
      StoryPrivacy.friends => (Icons.people_rounded, Colors.amberAccent),
      StoryPrivacy.closeFriends => (Icons.star_rounded, Colors.greenAccent),
      StoryPrivacy.onlyMe => (Icons.lock_rounded, Colors.redAccent),
    };

    final label = switch (privacy) {
      StoryPrivacy.everyone => 'All',
      StoryPrivacy.friends => 'Friends',
      StoryPrivacy.closeFriends => 'Close',
      StoryPrivacy.onlyMe => 'Only Me',
    };

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _CaptionInput extends StatelessWidget {
  final TextEditingController controller;

  const _CaptionInput({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20),
        ],
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: const InputDecoration(
          hintText: 'Add a caption…',
          hintStyle: TextStyle(color: Colors.white38),
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          border: InputBorder.none,
          prefixIcon: Padding(
            padding: EdgeInsets.only(left: 14, right: 8),
            child: Icon(
              Icons.edit_note_rounded,
              color: Colors.white38,
              size: 22,
            ),
          ),
          prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
        ),
        maxLines: 3,
        minLines: 1,
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  final StoryFilter selected;
  final File? image;
  final void Function(StoryFilter) onSelect;

  static const _filterNames = [
    'None',
    'Clarendon',
    'Gingham',
    'Moon',
    'Lark',
    'Reyes',
    'Juno',
    'Slumber',
    'Crema',
    'Ludwig',
    'Aden',
    'Perpetua',
  ];

  const _FilterStrip({
    required this.selected,
    required this.image,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      color: Colors.black.withValues(alpha: 0.5),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: StoryFilter.values.length,
        itemBuilder: (_, i) {
          final f = StoryFilter.values[i];
          final sel = f == selected;
          return GestureDetector(
            onTap: () {
              onSelect(f);
              HapticFeedback.selectionClick();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 60,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: image != null
                          ? Image.file(image!, fit: BoxFit.cover)
                          : Container(color: Colors.grey.shade800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _filterNames[i],
                    style: TextStyle(
                      color: sel ? Colors.white : Colors.white60,
                      fontSize: 9,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
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

class _PublishButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  final bool enabled;
  final String label;

  const _PublishButton({
    required this.loading,
    required this.onTap,
    this.enabled = true,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;

    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF7B61FF), Color(0xFF2196F3)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : LinearGradient(
                  colors: [Colors.grey.shade800, Colors.grey.shade700],
                ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF7B61FF).withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
