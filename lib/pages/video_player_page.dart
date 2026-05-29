import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:video_player/video_player.dart';

const _kSeekSeconds = 10;
const _kControlsTimeout = Duration(seconds: 3);
const _kAnimDuration = Duration(milliseconds: 220);
const _kLongPressSpeed = 2.0;

const _kAccent = Color(0xFF00E5FF);
const _kAccentDim = Color(0x4400E5FF);
const _kSurface = Color(0xCC0A0A0F);
const _kOverlayGrad = [Color(0xE0000000), Colors.transparent];

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.videoUrl,
    this.title,
    this.autoPlay = true,
    this.allowFullscreenRotation = true,
  });

  final String videoUrl;
  final String? title;
  final bool autoPlay;
  final bool allowFullscreenRotation;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> with TickerProviderStateMixin {
  late VideoPlayerController _ctrl;
  Timer? _hideTimer;
  Timer? _longPressTimer;

  late final AnimationController _controlsAc;
  late final Animation<double> _controlsFade;

  late final AnimationController _seekLeftAc;
  late final AnimationController _seekRightAc;

  late final AnimationController _playPauseAc;

  bool _initialized = false;
  bool _hasError = false;
  bool _showControls = true;
  bool _isLocked = false;
  bool _isDragging = false;
  bool _isLongPressFastForward = false;
  bool _isFullscreen = false;
  bool _showSpeedPanel = false;
  bool _showBrightnessBanner = false;
  bool _showVolumeBanner = false;

  double? _dragSeekFraction;
  Duration? _dragSeekDuration;

  double _volume = 1.0;
  double _brightness = 0.5;
  double _verticalDragStartY = 0;
  double _verticalDragStartValue = 0;
  bool _isVolumeDrag = false;

  double _playbackSpeed = 1.0;
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  String? _thumbnailUrl;

  int _retryCount = 0;
  static const _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _parseUrl();
    _applySystemUi(dark: true);
    if (widget.allowFullscreenRotation) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _initController();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _longPressTimer?.cancel();
    _controlsAc.dispose();
    _seekLeftAc.dispose();
    _seekRightAc.dispose();
    _playPauseAc.dispose();
    _ctrl
      ..removeListener(_videoListener)
      ..dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _applySystemUi(dark: false);
    super.dispose();
  }

  void _setupAnimations() {
    _controlsAc = AnimationController(vsync: this, duration: _kAnimDuration);
    _controlsFade = CurvedAnimation(parent: _controlsAc, curve: Curves.easeInOut);
    _controlsAc.value = 1;

    _seekLeftAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _seekRightAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

    _playPauseAc = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  void _parseUrl() {
    final parts = widget.videoUrl.split('|');
    if (parts.length >= 2) _thumbnailUrl = parts[1].trim();
  }

  Future<void> _initController() async {
    final url = widget.videoUrl.split('|').first.trim();
    try {
      _ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      await _ctrl.initialize();
      _ctrl.addListener(_videoListener);
      if (!mounted) return;
      setState(() => _initialized = true);
      if (widget.autoPlay) {
        await _ctrl.play();
        _playPauseAc.forward();
      }
      await _ctrl.setVolume(_volume);
      await _ctrl.setPlaybackSpeed(_playbackSpeed);
      _scheduleHide();
    } catch (e) {
      debugPrint('❌ VideoPlayerPage init: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _applySystemUi({required bool dark}) {
    SystemChrome.setSystemUIOverlayStyle(
      dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );
    SystemChrome.setEnabledSystemUIMode(
      dark ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _videoListener() {
    if (!mounted) return;
    final v = _ctrl.value;
    if (v.position >= v.duration && v.duration > Duration.zero && !v.isLooping) {
      _cancelHide();
      if (!_showControls) _setControls(true);
    }
    setState(() {});
  }

  void _setControls(bool visible) {
    if (!mounted) return;
    setState(() => _showControls = visible);
    if (visible) {
      _controlsAc.forward();
    } else {
      _controlsAc.reverse();
      setState(() => _showSpeedPanel = false);
    }
  }

  void _scheduleHide() {
    _cancelHide();
    if (_isLocked || _showSpeedPanel) return;
    _hideTimer = Timer(_kControlsTimeout, () {
      if (mounted && (_ctrl.value.isPlaying || _isLocked)) {
        _setControls(false);
      }
    });
  }

  void _cancelHide() => _hideTimer?.cancel();

  void _onTapScreen() {
    if (_isLocked) {
      setState(() => _showControls = !_showControls);
      if (_showControls) {
        _controlsAc.forward();
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _isLocked) _setControls(false);
        });
      } else {
        _controlsAc.reverse();
      }
      return;
    }
    final nowVisible = !_showControls;
    _setControls(nowVisible);
    if (nowVisible) _scheduleHide();
  }

  Future<void> _togglePlayPause() async {
    _cancelHide();
    if (_ctrl.value.isPlaying) {
      await _ctrl.pause();
      _playPauseAc.reverse();
      _setControls(true);
    } else {
      if (_ctrl.value.position >= _ctrl.value.duration && _ctrl.value.duration > Duration.zero) {
        await _ctrl.seekTo(Duration.zero);
      }
      await _ctrl.play();
      _playPauseAc.forward();
      _scheduleHide();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final pos = _ctrl.value.position + Duration(seconds: seconds);
    final clamped = pos.inMilliseconds.clamp(0, _ctrl.value.duration.inMilliseconds);
    await _ctrl.seekTo(Duration(milliseconds: clamped));
    _scheduleHide();
  }

  Future<void> _seekToFraction(double fraction) async {
    final ms = (fraction * _ctrl.value.duration.inMilliseconds).round();
    await _ctrl.seekTo(Duration(milliseconds: ms.clamp(0, _ctrl.value.duration.inMilliseconds)));
  }

  void _startFastForward() {
    _isLongPressFastForward = true;
    _ctrl.setPlaybackSpeed(_kLongPressSpeed);
    setState(() {});
  }

  void _stopFastForward() {
    _isLongPressFastForward = false;
    _ctrl.setPlaybackSpeed(_playbackSpeed);
    setState(() {});
  }

  void _toggleLock() {
    setState(() => _isLocked = !_isLocked);
    if (_isLocked) {
      _cancelHide();
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _isLocked) _setControls(false);
      });
    } else {
      _setControls(true);
      _scheduleHide();
    }
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _scheduleHide();
  }

  Future<void> _setSpeed(double speed) async {
    setState(() {
      _playbackSpeed = speed;
      _showSpeedPanel = false;
    });
    await _ctrl.setPlaybackSpeed(speed);
    _scheduleHide();
  }

  void _onVerticalDragStart(DragStartDetails d, bool isLeft) {
    _cancelHide();
    _verticalDragStartY = d.globalPosition.dy;
    _verticalDragStartValue = isLeft ? _volume : _brightness;
    _isVolumeDrag = isLeft;
    setState(() => isLeft ? _showVolumeBanner = true : _showBrightnessBanner = true);
  }

  void _onVerticalDragUpdate(DragUpdateDetails d, Size size) {
    final delta = -d.delta.dy / (size.height * 0.6);
    if (_isVolumeDrag) {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      _ctrl.setVolume(_volume);
      setState(() {});
    } else {
      _brightness = (_brightness + delta).clamp(0.0, 1.0);
      setState(() {});
    }
  }

  void _onVerticalDragEnd(DragEndDetails _) {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showVolumeBanner = false;
          _showBrightnessBanner = false;
        });
      }
    });
    _scheduleHide();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  double get _progress {
    final dur = _ctrl.value.duration.inMilliseconds;
    if (dur == 0) return 0;
    return (_dragSeekFraction ?? _ctrl.value.position.inMilliseconds / dur).clamp(0.0, 1.0);
  }

  double get _bufferProgress {
    final dur = _ctrl.value.duration.inMilliseconds;
    if (dur == 0) return 0;
    final ranges = _ctrl.value.buffered;
    if (ranges.isEmpty) return 0;
    return (ranges.last.end.inMilliseconds / dur).clamp(0.0, 1.0);
  }

  Duration get _displayPosition {
    if (_isDragging && _dragSeekFraction != null) {
      return Duration(
          milliseconds: (_dragSeekFraction! * _ctrl.value.duration.inMilliseconds).round());
    }
    return _ctrl.value.position;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_initialized)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: 1 - _brightness,
                duration: Duration.zero,
                child: Container(color: Colors.black),
              ),
            ),
          _buildVideoOrState(),
          if (_initialized) _buildGestureLayer(size),
          if (_initialized) _buildSeekFeedback(),
          if (_showVolumeBanner) _buildSideBanner(isVolume: true),
          if (_showBrightnessBanner) _buildSideBanner(isVolume: false),
          if (_initialized)
            FadeTransition(
              opacity: _controlsFade,
              child: _buildControls(size),
            ),
          if (_initialized && _isLocked) _buildLockOverlay(),
          if (_isLongPressFastForward) _buildFastForwardBadge(),
        ],
      ),
    );
  }

  Widget _buildVideoOrState() {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 40),
            ),
            const SizedBox(height: 18),
            const Text('Không thể phát video',
                style: TextStyle(color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            if (_retryCount >= _maxRetries)
              const Text('Đã thử lại nhiều lần. Kiểm tra kết nối mạng.',
                  style: TextStyle(color: Colors.white30, fontSize: 12)),
            const SizedBox(height: 24),
            if (_retryCount < _maxRetries)
              _GlassButton(
                icon: Icons.refresh_rounded,
                label: 'Thử lại (${_maxRetries - _retryCount} lần)',
                onTap: () {
                  setState(() {
                    _hasError = false;
                    _initialized = false;
                    _retryCount++;
                  });
                  _initController();
                },
              ),
            const SizedBox(height: 12),
            _GlassButton(
              icon: Icons.arrow_back_rounded,
              label: 'Quay lại',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }

    if (!_initialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_thumbnailUrl != null)
              Opacity(
                opacity: 0.4,
                child: Image.network(
                  _thumbnailUrl!,
                  fit: BoxFit.contain,
                  width: 200,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            const SizedBox(height: 20),
            const _PulsingLoader(),
          ],
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _ctrl.value.aspectRatio,
        child: VideoPlayer(_ctrl),
      ),
    );
  }

  Widget _buildGestureLayer(Size size) {
    return Positioned.fill(
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onTapScreen,
              onDoubleTap: () async {
                await _seekRelative(-_kSeekSeconds);
                _seekLeftAc.forward(from: 0);
              },
              onLongPressStart: (_) => _startFastForward(),
              onLongPressEnd: (_) => _stopFastForward(),
              onVerticalDragStart: (d) => _onVerticalDragStart(d, true),
              onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, size),
              onVerticalDragEnd: _onVerticalDragEnd,
              onHorizontalDragStart: (_) {
                _cancelHide();
                setState(() => _isDragging = true);
              },
              onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, size),
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onTapScreen,
              onDoubleTap: () async {
                await _seekRelative(_kSeekSeconds);
                _seekRightAc.forward(from: 0);
              },
              onLongPressStart: (_) => _startFastForward(),
              onLongPressEnd: (_) => _stopFastForward(),
              onVerticalDragStart: (d) => _onVerticalDragStart(d, false),
              onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, size),
              onVerticalDragEnd: _onVerticalDragEnd,
              onHorizontalDragStart: (_) {
                _cancelHide();
                setState(() => _isDragging = true);
              },
              onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, size),
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d, Size size) {
    final delta = d.delta.dx / size.width;
    final cur = _ctrl.value.duration.inMilliseconds == 0
        ? 0.0
        : _ctrl.value.position.inMilliseconds / _ctrl.value.duration.inMilliseconds;
    final newFraction = (cur + delta * 1.5).clamp(0.0, 1.0);
    setState(() {
      _dragSeekFraction = newFraction;
      _dragSeekDuration =
          Duration(milliseconds: (newFraction * _ctrl.value.duration.inMilliseconds).round());
    });
  }

  Future<void> _onHorizontalDragEnd(DragEndDetails _) async {
    if (_dragSeekFraction != null) {
      await _seekToFraction(_dragSeekFraction!);
      setState(() {
        _dragSeekFraction = null;
        _dragSeekDuration = null;
        _isDragging = false;
      });
      _scheduleHide();
    }
  }

  Widget _buildSeekFeedback() {
    return Stack(children: [
      Positioned(
        left: 16,
        top: 0,
        bottom: 0,
        child: Center(
          child: _SeekRipple(
            controller: _seekLeftAc,
            isLeft: true,
            label: '${_kSeekSeconds}s',
          ),
        ),
      ),
      Positioned(
        right: 16,
        top: 0,
        bottom: 0,
        child: Center(
          child: _SeekRipple(
            controller: _seekRightAc,
            isLeft: false,
            label: '${_kSeekSeconds}s',
          ),
        ),
      ),
      if (_isDragging && _dragSeekDuration != null)
        Center(
          child: _DragSeekBadge(
            current: _dragSeekDuration!,
            total: _ctrl.value.duration,
            fmt: _fmt,
          ),
        ),
    ]);
  }

  Widget _buildSideBanner({required bool isVolume}) {
    final value = isVolume ? _volume : _brightness;
    final icon = isVolume
        ? (value == 0
            ? Icons.volume_off_rounded
            : value < 0.5
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded)
        : (value < 0.3
            ? Icons.brightness_low_rounded
            : value < 0.7
                ? Icons.brightness_medium_rounded
                : Icons.brightness_high_rounded);

    return Positioned(
      top: 0,
      bottom: 0,
      left: isVolume ? 0 : null,
      right: isVolume ? null : 0,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(
            left: isVolume ? 20 : 0,
            right: isVolume ? 0 : 20,
          ),
          child: _GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(height: 10),
                SizedBox(
                  height: 80,
                  child: RotatedBox(
                    quarterTurns: -1,
                    child: LinearProgressIndicator(
                      value: value,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(_kAccent),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(value * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(Size size) {
    if (_isLocked) return const SizedBox();
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xCC000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                ],
                stops: [0, 0.22, 0.75, 1],
              ),
            ),
          ),
        ),
      ),
      Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
      Center(child: _buildCenterControls()),
      Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
      if (_showSpeedPanel) Positioned(top: 0, right: 0, bottom: 0, child: _buildSpeedPanel()),
    ]);
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            if (widget.title != null)
              Expanded(
                child: Text(
                  widget.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              )
            else
              const Spacer(),
            GestureDetector(
              onTap: () {
                _cancelHide();
                setState(() => _showSpeedPanel = !_showSpeedPanel);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _playbackSpeed != 1.0
                      ? _kAccent.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _playbackSpeed != 1.0 ? _kAccent.withValues(alpha: 0.5) : Colors.white24,
                    width: 1,
                  ),
                ),
                child: Text(
                  '$_playbackSpeed×',
                  style: TextStyle(
                    color: _playbackSpeed != 1.0 ? _kAccent : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: _toggleLock,
            ),
            IconButton(
              icon: Icon(
                _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                color: Colors.white,
                size: 22,
              ),
              onPressed: _toggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: AnimatedContainer(
        duration: _kAnimDuration,
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: AnimatedBuilder(
          animation: _playPauseAc,
          builder: (_, __) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _ctrl.value.isPlaying
                ? const Icon(Icons.pause_rounded,
                    key: ValueKey('pause'), color: Colors.white, size: 36)
                : const Icon(Icons.play_arrow_rounded,
                    key: ValueKey('play'), color: Colors.white, size: 36),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProgressBar(),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  _fmt(_displayPosition),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() => _volume = _volume > 0 ? 0 : 1.0);
                    _ctrl.setVolume(_volume);
                    _scheduleHide();
                  },
                  child: Icon(
                    _volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white60,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _fmt(_ctrl.value.duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        activeTrackColor: _kAccent,
        inactiveTrackColor: Colors.white12,
        thumbColor: Colors.white,
        overlayColor: _kAccentDim,
        trackShape: _BufferedTrackShape(bufferFraction: _bufferProgress),
      ),
      child: Slider(
        value: _progress,
        onChangeStart: (_) {
          _cancelHide();
          setState(() => _isDragging = true);
        },
        onChanged: (v) {
          setState(() {
            _dragSeekFraction = v;
            _dragSeekDuration =
                Duration(milliseconds: (v * _ctrl.value.duration.inMilliseconds).round());
          });
        },
        onChangeEnd: (v) async {
          await _seekToFraction(v);
          setState(() {
            _dragSeekFraction = null;
            _dragSeekDuration = null;
            _isDragging = false;
          });
          _scheduleHide();
        },
      ),
    );
  }

  Widget _buildSpeedPanel() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(top: 60, bottom: 60, right: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8, top: 12),
              child: Text('Tốc độ',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ),
            ..._speeds.map((s) => _SpeedTile(
                  speed: s,
                  selected: _playbackSpeed == s,
                  onTap: () => _setSpeed(s),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLockOverlay() {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: _kAnimDuration,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: GestureDetector(
            onTap: _toggleLock,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFastForwardBadge() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: _kAccent.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fast_forward_rounded, color: _kAccent, size: 20),
            const SizedBox(width: 6),
            Text(
              '${_kLongPressSpeed.toStringAsFixed(0)}×',
              style: const TextStyle(color: _kAccent, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _kAccent, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: child,
    );
  }
}

class _PulsingLoader extends StatefulWidget {
  const _PulsingLoader();
  @override
  State<_PulsingLoader> createState() => _PulsingLoaderState();
}

class _PulsingLoaderState extends State<_PulsingLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      reverseDuration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) => Opacity(
        opacity: 0.4 + _ac.value * 0.6,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            color: _kAccent,
            strokeWidth: 2.5,
          ),
        ),
      ),
    );
  }
}

class _DragSeekBadge extends StatelessWidget {
  final Duration current;
  final Duration total;
  final String Function(Duration) fmt;
  const _DragSeekBadge({required this.current, required this.total, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final fraction =
        total.inMilliseconds == 0 ? 0.0 : current.inMilliseconds / total.inMilliseconds;
    final isForward = fraction > 0.5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
            color: _kAccent,
            size: 18,
          ),
          const SizedBox(height: 4),
          Text(
            fmt(current),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            '/ ${fmt(total)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SeekRipple extends StatelessWidget {
  final AnimationController controller;
  final bool isLeft;
  final String label;
  const _SeekRipple({required this.controller, required this.isLeft, required this.label});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        if (t == 0) return const SizedBox();
        final opacity = t < 0.5 ? 1.0 : 1 - (t - 0.5) * 2;
        final scale = 0.8 + t * 0.4;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(48),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLeft ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
                    color: _kAccent,
                    size: 30,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLeft ? '−$label' : '+$label',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpeedTile extends StatelessWidget {
  final double speed;
  final bool selected;
  final VoidCallback onTap;
  const _SpeedTile({required this.speed, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kAccent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kAccent.withValues(alpha: 0.4) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) const Icon(Icons.check_rounded, color: _kAccent, size: 14),
            if (selected) const SizedBox(width: 4),
            Text(
              '$speed×',
              style: TextStyle(
                color: selected ? _kAccent : Colors.white60,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BufferedTrackShape extends RoundedRectSliderTrackShape {
  final double bufferFraction;
  const _BufferedTrackShape({required this.bufferFraction});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final bufferPaint = Paint()
      ..color = Colors.white30
      ..style = PaintingStyle.fill;
    final bufW = trackRect.width * bufferFraction.clamp(0.0, 1.0);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackRect.left, trackRect.top, bufW, trackRect.height),
        const Radius.circular(3),
      ),
      bufferPaint,
    );

    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
      textDirection: textDirection,
    );
  }
}
