import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Trang phát video toàn màn hình.
///
/// Nhận [videoUrl] là URL Firebase Storage của video.
/// Nếu có thumbnail (định dạng "videoUrl|thumbnailUrl"), chỉ lấy phần đầu.
///
/// Thêm vào pubspec.yaml:
///   video_player: ^2.8.6
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.videoUrl});

  /// URL gốc của video (hoặc "videoUrl|thumbnailUrl" — phần sau | bị bỏ qua).
  final String videoUrl;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isError = false;
  bool _showControls = true;

  /// Lấy URL video thuần (bỏ phần thumbnail nếu có).
  String get _cleanVideoUrl => widget.videoUrl.split('|').first;

  @override
  void initState() {
    super.initState();
    // Xoay ngang khi mở video (tùy chọn — xóa 2 dòng dưới nếu không muốn).
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initController();
  }

  Future<void> _initController() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(_cleanVideoUrl),
      );
      await _controller.initialize();
      _controller.addListener(_onVideoListener);
      if (mounted) {
        setState(() => _isInitialized = true);
        _controller.play();
      }
    } catch (e) {
      print('❌ VideoPlayerPage init error: $e');
      if (mounted) setState(() => _isError = true);
    }
  }

  void _onVideoListener() {
    // Khi video kết thúc → hiện lại controls
    if (_controller.value.position >= _controller.value.duration) {
      if (mounted) setState(() => _showControls = true);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoListener);
    _controller.dispose();
    // Khôi phục về portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _showControls = true;
      } else {
        _controller.play();
        // Ẩn controls sau 2 giây khi bắt đầu play
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _controller.value.isPlaying) {
            setState(() => _showControls = false);
          }
        });
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls && _controller.value.isPlaying) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _controller.value.isPlaying) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Video hoặc trạng thái loading/lỗi ──────────────
            if (_isError)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Colors.white54, size: 56),
                    SizedBox(height: 12),
                    Text(
                      'Không thể phát video',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ],
                ),
              )
            else if (!_isInitialized)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else
              GestureDetector(
                onTap: _toggleControls,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),

            // ── Overlay controls ────────────────────────────────
            if (_isInitialized && _showControls)
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black54,
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black54,
                      ],
                    ),
                  ),
                ),
              ),

            // ── AppBar tự tạo (nút back + tên file) ────────────
            if (_showControls || !_isInitialized)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Video',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Play / Pause button ─────────────────────────────
            if (_isInitialized && _showControls)
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),

            // ── Progress bar + thời gian ────────────────────────
            if (_isInitialized && _showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _controller,
                    builder: (_, value, __) {
                      final position = value.position;
                      final duration = value.duration;
                      final progress = duration.inMilliseconds > 0
                          ? position.inMilliseconds / duration.inMilliseconds
                          : 0.0;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12),
                              trackHeight: 3,
                              activeTrackColor: const Color(0xFF007AFF),
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: progress.clamp(0.0, 1.0),
                              onChanged: (val) {
                                final newPos = Duration(
                                  milliseconds:
                                      (val * duration.inMilliseconds).round(),
                                );
                                _controller.seekTo(newPos);
                              },
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
