import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart' hide AspectRatio;
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:simple_pip_mode/pip_widget.dart';
import 'package:simple_pip_mode/simple_pip.dart';

import '../models/call_model.dart';
import '../services/agora_rtc_manager.dart';
import '../services/call_service.dart';
import '../services/realtime_ai_service.dart';
import '../widgets/ai_call_shield.dart';
import '../widgets/call_control_bar.dart';
import '../widgets/call_quality_indicator.dart';
import '../widgets/call_timer_widget.dart';
// 💡 IMPORT WIDGET DEEPFAKE MỚI:
import '../widgets/deepfake_alert_overlay.dart';
import '../widgets/live_caption_overlay.dart';

// ══════════════════════════════════════════════════════
// DESIGN TOKENS
// ══════════════════════════════════════════════════════
const _kBg = Color(0xFF080C18);
const _kAccept = Color(0xFF34C759);
const _kDecline = Color(0xFFFF3B30);
const _kBlue = Color(0xFF0A84FF);
const _kSurface = Color(0x1AFFFFFF);
const _kBorder = Color(0x33FFFFFF);

// ══════════════════════════════════════════════════════
// CALL PAGE
// ══════════════════════════════════════════════════════
class CallPage extends StatefulWidget {
  final CallModel call;
  final bool isOutgoing;

  const CallPage({super.key, required this.call, required this.isOutgoing});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> with WidgetsBindingObserver {
  final _callService = CallService.instance;
  final _pip = SimplePip();
  late final AgoraRtcManager _rtc;

  // State
  CallStatus _status = CallStatus.calling;
  DateTime? _connectedAt;
  bool _callEnded = false;
  bool _showControls = true;
  bool _isInitializing = true;
  bool _isLiveCaptionOn = false;
  String? _errorMessage;

  // Local PiP drag position
  Offset _localPipPos = const Offset(double.infinity, double.infinity);
  bool _localPipDragging = false;

  // Controls auto-hide
  Timer? _hideTimer;

  // Subscriptions
  StreamSubscription? _statusSub;
  StreamSubscription? _remoteJoinSub;
  StreamSubscription? _remoteLeftSub;
  StreamSubscription? _errorSub;

  // Audio level for visualizer (0.0 – 1.0)
  final List<double> _audioLevels = List.filled(20, 0.05);
  StreamSubscription? _audioLevelSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _rtc = AgoraRtcManager();
    _status = widget.call.status;

    if (_status == CallStatus.connected || _status == CallStatus.accepted) {
      _connectedAt = DateTime.now();
    }

    _initCall();
    _watchStatus();
    _scheduleHide();
  }

  void _startAIProtection() {
    final peerId =
        widget.isOutgoing ? widget.call.calleeId : widget.call.callerId;
    RealtimeAIService().startProtection(peerId, widget.call.channelName);
  }

  // ── Init call ─────────────────────────────────────────────────────────────
  Future<void> _initCall() async {
    _errorSub = _rtc.errorStream.listen((e) {
      if (mounted) setState(() => _errorMessage = e);
    });

    _remoteJoinSub = _rtc.remoteJoinedStream.listen((_) {
      if (mounted) {
        setState(() {
          _status = CallStatus.connected;
          _connectedAt ??= DateTime.now();
          _isInitializing = false;
        });
        _startAIProtection();
        _scheduleHide();
      }
    });

    _remoteLeftSub = _rtc.remoteLeftStream.listen((_) => _endCall());

    // Subscribe to audio levels for visualizer
    _audioLevelSub = _rtc.audioLevelStream.listen((level) {
      if (mounted && _status == CallStatus.connected) {
        setState(() {
          _audioLevels.removeAt(0);
          _audioLevels.add(level.clamp(0.0, 1.0));
        });
      }
    });

    final ok = await _rtc.initialize();
    if (!ok) {
      if (mounted)
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Không thể khởi tạo engine cuộc gọi.';
        });
      return;
    }

    if (widget.call.channelName.isNotEmpty) {
      final joined = await _rtc.joinChannel(
        channelName: widget.call.channelName,
        isVideoCall: widget.call.isVideoCall,
      );
      if (!joined && mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Không thể tham gia kênh cuộc gọi.';
        });
        return;
      }
    }

    if (mounted) setState(() => _isInitializing = false);
  }

  void _watchStatus() {
    _statusSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || _callEnded) return;
      if (mounted) setState(() => _status = call.status);
      if ((_status == CallStatus.connected || _status == CallStatus.accepted) &&
          _connectedAt == null) {
        if (mounted) setState(() => _connectedAt = DateTime.now());
      }
      if (call.status.isTerminal) _endCall(remote: true);
    });
  }

  Future<void> _endCall({bool remote = false}) async {
    if (_callEnded) return;
    _callEnded = true;
    await _rtc.leaveChannel();

    if (!remote) {
      final dur = _connectedAt != null
          ? DateTime.now().difference(_connectedAt!).inSeconds
          : null;
      await _callService.endCall(widget.call.callId, durationSeconds: dur);
    }

    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Navigator.of(context).pop();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (widget.call.isVideoCall && _isConnected) {
      _hideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _isConnected) setState(() => _showControls = false);
      });
    }
  }

  void _onTapScreen() {
    if (!widget.call.isVideoCall) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _toggleCaption() {
    setState(() => _isLiveCaptionOn = !_isLiveCaptionOn);
    Fluttertoast.showToast(
      msg: _isLiveCaptionOn ? 'Đã bật phụ đề AI' : 'Đã tắt phụ đề AI',
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );
  }

  bool get _isConnected =>
      _status == CallStatus.connected || _status == CallStatus.accepted;

  Future<void> _enterPip() async {
    final ok = await SimplePip.isPipAvailable;
    if (ok) {
      await _pip.enterPipMode(aspectRatio: (9, 16));
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.call.isVideoCall) {
      if (!_rtc.isCameraOff) _rtc.toggleCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealtimeAIService().stopProtection();
    _statusSub?.cancel();
    _remoteJoinSub?.cancel();
    _remoteLeftSub?.cancel();
    _errorSub?.cancel();
    _audioLevelSub?.cancel();
    _hideTimer?.cancel();
    _rtc.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ══════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null && !_isInitializing) return _buildError();

    if (widget.call.isVideoCall) {
      return PipWidget(
        pipBuilder: (_) => _buildPipRemoteView(),
        builder: (_) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (d, _) {
            if (!d) _enterPip();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: _buildVideoUI(),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (d, _) {
        if (!d) _endCall();
      },
      child: Scaffold(
        backgroundColor: _kBg,
        body: _buildVoiceUI(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  // VOICE CALL UI
  // ══════════════════════════════════════════════════════
  Widget _buildVoiceUI() {
    final name =
        widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;
    final avatar =
        widget.isOutgoing ? widget.call.calleeAvatar : widget.call.callerAvatar;

    return Stack(fit: StackFit.expand, children: [
      // Blurred background
      _VoiceBackground(avatarUrl: avatar),

      SafeArea(
        child: Column(children: [
          // Top status bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start, // Giữ các item sát mép trên
              children: [
                // 💡 TÍCH HỢP DEEPFAKE UI TẠI ĐÂY:
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AICallShield(),
                    SizedBox(height: 8),
                    DeepfakeStatusBadge(), // <- Widget Deepfake sẽ nằm ngay dưới Shield lừa đảo
                  ],
                ),
                const Spacer(),
                ListenableBuilder(
                  listenable: _rtc,
                  builder: (_, __) => CallQualityIndicator(stats: _rtc.stats),
                ),
              ],
            ),
          ),

          const Spacer(flex: 2),

          // Avatar with pulsing rings + audio visualizer
          Stack(alignment: Alignment.center, children: [
            // Audio visualizer ring
            if (_isConnected)
              ListenableBuilder(
                listenable: _rtc,
                builder: (_, __) => _AudioRing(
                  audioLevels: _audioLevels,
                  isActive: _isConnected,
                  baseSize: 180,
                ),
              ),
            // Pulsing avatar
            _PulsingCallAvatar(
              url: avatar,
              name: name,
              size: 148,
              isActive: _isConnected,
            ),
          ]),

          const SizedBox(height: 32),

          // Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Timer / Status
          if (_isConnected && _connectedAt != null)
            CallTimerWidget(
              startTime: _connectedAt!,
              style: const TextStyle(
                color: _kAccept,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            )
          else if (_isInitializing)
            const _ConnectingDots()
          else
            _StatusDots(status: _statusText()),

          const Spacer(flex: 2),

          // Live Caption Overlay
          if (_isLiveCaptionOn)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: LiveCaptionOverlay(),
            ),

          // Caption toggle
          if (_isConnected)
            _CaptionToggle(
              enabled: _isLiveCaptionOn,
              onToggle: _toggleCaption,
            ),

          // Control bar
          ListenableBuilder(
            listenable: _rtc,
            builder: (_, __) => CallControlBar(
              isVideoCall: false,
              isMuted: _rtc.isMuted,
              isCameraOff: _rtc.isCameraOff,
              isSpeakerOn: _rtc.isSpeakerOn,
              isFrontCamera: _rtc.isFrontCamera,
              onMuteTap: _rtc.toggleMute,
              onSpeakerTap: _rtc.toggleSpeaker,
              onEndCall: _endCall,
            ),
          ),
        ]),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════
  // VIDEO CALL UI
  // ══════════════════════════════════════════════════════
  Widget _buildVideoUI() {
    return GestureDetector(
      onTap: _onTapScreen,
      behavior: HitTestBehavior.opaque,
      child: Stack(children: [
        // Remote video
        Positioned.fill(child: _buildRemoteVideoView()),

        // Gradient overlays
        const _VideoGradientOverlays(),

        // Initializing overlay
        if (_isInitializing) const _ConnectingOverlay(),

        // Draggable local PiP
        if (_isConnected) _buildDraggableLocalPip(),

        // Top bar
        AnimatedOpacity(
          opacity: _showControls || !_isConnected ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: _buildVideoTopBar(),
        ),

        // AI shield + Deepfake + Quality
        if (_showControls || !_isConnected) ...[
          Positioned(
            top: MediaQuery.paddingOf(context).top + 72,
            left: 16,
            // 💡 TÍCH HỢP DEEPFAKE UI TẠI ĐÂY:
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AICallShield(),
                SizedBox(height: 8),
                DeepfakeStatusBadge(), // <- Widget Deepfake sẽ nằm ngay dưới Shield lừa đảo
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 72,
            right: 16,
            child: ListenableBuilder(
              listenable: _rtc,
              builder: (_, __) => CallQualityIndicator(stats: _rtc.stats),
            ),
          ),
        ],

        // Live Caption Overlay
        if (_isLiveCaptionOn)
          const Positioned(
            bottom: 140,
            left: 16,
            right: 16,
            child: LiveCaptionOverlay(),
          ),

        // Controls
        AnimatedOpacity(
          opacity: _showControls || !_isConnected ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_isConnected)
                _CaptionToggle(
                  enabled: _isLiveCaptionOn,
                  onToggle: _toggleCaption,
                ),
              ListenableBuilder(
                listenable: _rtc,
                builder: (_, __) => CallControlBar(
                  isVideoCall: true,
                  isMuted: _rtc.isMuted,
                  isCameraOff: _rtc.isCameraOff,
                  isSpeakerOn: _rtc.isSpeakerOn,
                  isFrontCamera: _rtc.isFrontCamera,
                  onMuteTap: _rtc.toggleMute,
                  onCameraTap: _rtc.toggleCamera,
                  onSpeakerTap: _rtc.toggleSpeaker,
                  onSwitchCameraTap: _rtc.switchCamera,
                  onEndCall: _endCall,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildVideoTopBar() {
    final name =
        widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: Colors.black.withOpacity(0.3),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.picture_in_picture_alt_rounded,
                        color: Colors.white70),
                    onPressed: _enterPip,
                    tooltip: 'Thu nhỏ',
                  ),
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (_isConnected && _connectedAt != null)
                    _TimerBadge(startTime: _connectedAt!),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteVideoView() {
    return ListenableBuilder(
      listenable: _rtc,
      builder: (_, __) {
        final show = _isConnected &&
            _rtc.hasRemoteUser &&
            _rtc.remoteVideoOn &&
            _rtc.engine != null &&
            widget.call.channelName.isNotEmpty;

        if (!show) return _buildRemotePlaceholder();

        return AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _rtc.engine!,
            canvas: VideoCanvas(uid: _rtc.remoteUid!),
            connection: RtcConnection(channelId: widget.call.channelName),
          ),
        );
      },
    );
  }

  Widget _buildRemotePlaceholder() {
    final name =
        widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;
    final avatar =
        widget.isOutgoing ? widget.call.calleeAvatar : widget.call.callerAvatar;

    return Stack(fit: StackFit.expand, children: [
      if (avatar.isNotEmpty)
        Image.network(avatar,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: _kBg)),
      BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Container(color: Colors.black.withOpacity(0.55)),
      ),
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _PulsingCallAvatar(
              url: avatar, name: name, size: 110, isActive: _isConnected),
          const SizedBox(height: 20),
          Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            _isConnected ? 'Camera đang tắt' : _statusText(),
            style:
                TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 15),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildDraggableLocalPip() {
    final size = MediaQuery.sizeOf(context);
    final topPadding = MediaQuery.paddingOf(context).top;

    if (_localPipPos.dx == double.infinity) {
      _localPipPos = Offset(size.width - 128, topPadding + 80);
    }

    return Positioned(
      left: _localPipPos.dx,
      top: _localPipPos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          final nx =
              (_localPipPos.dx + d.delta.dx).clamp(0.0, size.width - 112.0);
          final ny = (_localPipPos.dy + d.delta.dy)
              .clamp(topPadding.toDouble(), size.height - 190.0);
          _localPipPos = Offset(nx, ny);
          _localPipDragging = true;
        }),
        onPanEnd: (_) => setState(() => _localPipDragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 112,
          height: 168,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _localPipDragging
                  ? _kBlue.withOpacity(0.8)
                  : Colors.white.withOpacity(0.25),
              width: _localPipDragging ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.55),
                  blurRadius: 28,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: ListenableBuilder(
              listenable: _rtc,
              builder: (_, __) {
                if (_rtc.isCameraOff || _rtc.engine == null) {
                  return const Center(
                    child: Icon(Icons.videocam_off_rounded,
                        color: Colors.white38, size: 30),
                  );
                }
                return AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _rtc.engine!,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPipRemoteView() {
    return ListenableBuilder(
      listenable: _rtc,
      builder: (_, __) {
        if (!_isConnected || !_rtc.hasRemoteUser || _rtc.engine == null) {
          final name = widget.isOutgoing
              ? widget.call.calleeName
              : widget.call.callerName;
          final avatar = widget.isOutgoing
              ? widget.call.calleeAvatar
              : widget.call.callerAvatar;
          return ColoredBox(
            color: _kBg,
            child:
                Center(child: _AvatarCircle(url: avatar, name: name, size: 56)),
          );
        }
        return AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _rtc.engine!,
            canvas: VideoCanvas(uid: _rtc.remoteUid!),
            connection: RtcConnection(channelId: widget.call.channelName),
          ),
        );
      },
    );
  }

  Widget _buildError() {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: _kDecline.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: _kDecline.withOpacity(0.3), width: 2),
                ),
                child: const Icon(Icons.call_end_rounded,
                    color: _kDecline, size: 44),
              ),
              const SizedBox(height: 28),
              Text(_errorMessage ?? 'Đã xảy ra lỗi',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Quay lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kDecline,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  String _statusText() {
    switch (_status) {
      case CallStatus.dialing:
      case CallStatus.calling:
        return widget.isOutgoing ? 'Đang gọi…' : 'Cuộc gọi đến…';
      case CallStatus.ringing:
        return 'Đang đổ chuông…';
      case CallStatus.accepted:
      case CallStatus.connected:
        return 'Đã kết nối';
      case CallStatus.ended:
        return 'Cuộc gọi kết thúc';
      case CallStatus.declined:
        return 'Đã từ chối';
      case CallStatus.rejected:
        return 'Bị từ chối';
      case CallStatus.missed:
        return 'Cuộc gọi nhỡ';
      case CallStatus.failed:
        return 'Kết nối thất bại';
    }
  }
}

// ══════════════════════════════════════════════════════
// VOICE BACKGROUND
// ══════════════════════════════════════════════════════
class _VoiceBackground extends StatelessWidget {
  final String avatarUrl;
  const _VoiceBackground({required this.avatarUrl});

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        if (avatarUrl.isNotEmpty)
          Image.network(avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: _kBg)),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
          child: const SizedBox.expand(),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC060818),
                Color(0x88060818),
                Color(0x88060818),
                Color(0xF5000000)
              ],
              stops: [0, 0.3, 0.65, 1],
            ),
          ),
        ),
      ]);
}

// ══════════════════════════════════════════════════════
// VIDEO GRADIENT OVERLAYS
// ══════════════════════════════════════════════════════
class _VideoGradientOverlays extends StatelessWidget {
  const _VideoGradientOverlays();

  @override
  Widget build(BuildContext context) => Stack(children: [
        // Top gradient
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 200,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        // Bottom gradient
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 280,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xDD000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
      ]);
}

// ══════════════════════════════════════════════════════
// AUDIO RING VISUALIZER
// ══════════════════════════════════════════════════════
class _AudioRing extends StatelessWidget {
  final List<double> audioLevels;
  final bool isActive;
  final double baseSize;

  const _AudioRing({
    required this.audioLevels,
    required this.isActive,
    required this.baseSize,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive) return const SizedBox.shrink();
    return CustomPaint(
      size: Size(baseSize + 80, baseSize + 80),
      painter: _AudioRingPainter(levels: audioLevels),
    );
  }
}

class _AudioRingPainter extends CustomPainter {
  final List<double> levels;
  _AudioRingPainter({required this.levels});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2 - 8;
    final count = levels.length;

    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi - math.pi / 2;
      final level = levels[i];
      final spike = 8 + level * 32;

      final paint = Paint()
        ..color = _kAccept.withOpacity(0.15 + level * 0.55)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final x1 = center.dx + baseRadius * math.cos(angle);
      final y1 = center.dy + baseRadius * math.sin(angle);
      final x2 = center.dx + (baseRadius + spike) * math.cos(angle);
      final y2 = center.dy + (baseRadius + spike) * math.sin(angle);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(_AudioRingPainter old) => true;
}

// ══════════════════════════════════════════════════════
// PULSING AVATAR
// ══════════════════════════════════════════════════════
class _PulsingCallAvatar extends StatefulWidget {
  final String url, name;
  final double size;
  final bool isActive;

  const _PulsingCallAvatar({
    required this.url,
    required this.name,
    required this.size,
    required this.isActive,
  });

  @override
  State<_PulsingCallAvatar> createState() => _PulsingCallAvatarState();
}

class _PulsingCallAvatarState extends State<_PulsingCallAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      // Pulse rings (only when active)
      if (widget.isActive)
        ...List.generate(
            3,
            (i) => AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) {
                    final progress = (_ctrl.value + i / 3) % 1.0;
                    return Opacity(
                      opacity: ((1 - progress) * 0.35).clamp(0, 1),
                      child: Container(
                        width: widget.size + progress * 70,
                        height: widget.size + progress * 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _kAccept, width: 1.5),
                        ),
                      ),
                    );
                  },
                )),

      // Avatar
      Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.75), width: 3),
          boxShadow: [
            BoxShadow(
              color:
                  (widget.isActive ? _kAccept : Colors.black).withOpacity(0.3),
              blurRadius: 32,
              spreadRadius: 6,
            ),
          ],
        ),
        child: ClipOval(
          child: widget.url.isNotEmpty
              ? Image.network(widget.url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _AvatarFallback(name: widget.name, size: widget.size))
              : _AvatarFallback(name: widget.name, size: widget.size),
        ),
      ),
    ]);
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;
  final double size;
  const _AvatarFallback({required this.name, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3949AB), Color(0xFF1E88E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
            child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.38,
              fontWeight: FontWeight.w800),
        )),
      );
}

class _AvatarCircle extends StatelessWidget {
  final String url, name;
  final double size;
  const _AvatarCircle(
      {required this.url, required this.name, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white38),
        ),
        child: ClipOval(
          child: url.isNotEmpty
              ? Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _AvatarFallback(name: name, size: size))
              : _AvatarFallback(name: name, size: size),
        ),
      );
}

// ══════════════════════════════════════════════════════
// MISC WIDGETS
// ══════════════════════════════════════════════════════
class _TimerBadge extends StatelessWidget {
  final DateTime startTime;
  const _TimerBadge({required this.startTime});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: CallTimerWidget(
              startTime: startTime,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      );
}

class _ConnectingOverlay extends StatelessWidget {
  const _ConnectingOverlay();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black45,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 20),
            Text('Đang kết nối an toàn…',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                )),
          ]),
        ),
      );
}

class _ConnectingDots extends StatefulWidget {
  const _ConnectingDots();

  @override
  State<_ConnectingDots> createState() => _ConnectingDotsState();
}

class _ConnectingDotsState extends State<_ConnectingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white54),
          ),
          const SizedBox(width: 10),
          const Text('Đang kết nối…',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
        ],
      );
}

class _StatusDots extends StatefulWidget {
  final String status;
  const _StatusDots({required this.status});

  @override
  State<_StatusDots> createState() => _StatusDotsState();
}

class _StatusDotsState extends State<_StatusDots> {
  int _count = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (mounted) setState(() => _count = (_count + 1) % 4);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        '${widget.status}${'.' * _count}',
        style: TextStyle(
          color: Colors.white.withOpacity(0.65),
          fontSize: 16,
          letterSpacing: 0.3,
        ),
      );
}

class _CaptionToggle extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggle;

  const _CaptionToggle({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 20, bottom: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: onToggle,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: enabled ? _kAccept.withOpacity(0.15) : Colors.black45,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: enabled ? _kAccept.withOpacity(0.5) : Colors.white24,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    enabled
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_off_rounded,
                    size: 16,
                    color: enabled ? _kAccept : Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Text('Phụ đề AI',
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? _kAccept : Colors.white54,
                        fontWeight: FontWeight.w500,
                      )),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
