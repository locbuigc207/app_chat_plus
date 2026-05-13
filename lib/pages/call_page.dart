// lib/pages/call_page.dart
import 'dart:async';
import 'dart:ui';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/call_model.dart';
import '../services/agora_rtc_manager.dart';
import '../services/call_service.dart';
import '../widgets/call_control_bar.dart';
import '../widgets/call_quality_indicator.dart';
import '../widgets/call_timer_widget.dart';

class CallPage extends StatefulWidget {
  final CallModel call;
  final bool isOutgoing;

  const CallPage({
    super.key,
    required this.call,
    required this.isOutgoing,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> with WidgetsBindingObserver {
  final _callService = CallService();
  late final AgoraRtcManager _rtcManager;

  CallStatus _callStatus = CallStatus.calling;
  StreamSubscription? _callStatusSub;
  StreamSubscription? _remoteJoinedSub;
  StreamSubscription? _remoteLeftSub;
  StreamSubscription? _errorSub;

  DateTime? _callConnectedAt;
  bool _callEnded = false;
  bool _showControls = true;
  Timer? _controlsHideTimer;
  bool _isInitializing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _rtcManager = AgoraRtcManager();
    _callStatus = widget.call.status;

    if (widget.call.status == CallStatus.connected ||
        widget.call.status == CallStatus.accepted) {
      _callConnectedAt = DateTime.now();
    }

    _initCall();
    _watchCallStatus();
    _scheduleControlsHide();
  }

  // ── Init ───────────────────────────────────────
  Future<void> _initCall() async {
    _errorSub = _rtcManager.errorStream.listen((error) {
      if (mounted) {
        setState(() => _errorMessage = error);
        _showErrorDialog(error);
      }
    });

    _remoteJoinedSub = _rtcManager.remoteJoinedStream.listen((_) {
      if (mounted) {
        setState(() {
          _callStatus = CallStatus.connected;
          _callConnectedAt ??= DateTime.now();
          _isInitializing = false;
        });
      }
    });

    _remoteLeftSub = _rtcManager.remoteLeftStream.listen((_) {
      _endCall();
    });

    final ok = await _rtcManager.initialize();
    if (!ok) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage =
              'Không thể khởi tạo cuộc gọi.\nKiểm tra Agora App ID.';
        });
      }
      return;
    }

    if (widget.call.channelName.isNotEmpty) {
      // FIX: Bỏ tham số 'token' — joinChannel tự lấy token từ server
      final joined = await _rtcManager.joinChannel(
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

  // ── Watch Call Status ──────────────────────────
  void _watchCallStatus() {
    _callStatusSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || _callEnded) return;

      if (mounted) setState(() => _callStatus = call.status);

      // FIX: Bắt cả 'accepted' như 'connected'
      if ((call.status == CallStatus.connected ||
              call.status == CallStatus.accepted) &&
          _callConnectedAt == null) {
        if (mounted) setState(() => _callConnectedAt = DateTime.now());
      }

      if (call.status == CallStatus.ended ||
          call.status == CallStatus.declined ||
          call.status == CallStatus.rejected ||
          call.status == CallStatus.missed ||
          call.status == CallStatus.failed) {
        _endCall(remote: true);
      }
    });
  }

  // ── End Call ───────────────────────────────────
  Future<void> _endCall({bool remote = false}) async {
    if (_callEnded) return;
    _callEnded = true;

    await _rtcManager.leaveChannel();

    if (!remote) {
      final duration = _callConnectedAt != null
          ? DateTime.now().difference(_callConnectedAt!).inSeconds
          : null;
      await _callService.endCall(widget.call.callId, durationSeconds: duration);
    }

    if (mounted) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Navigator.of(context).pop();
    }
  }

  // ── Error Dialog ───────────────────────────────
  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Lỗi cuộc gọi'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _endCall();
            },
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  // ── Controls Hide ──────────────────────────────
  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (widget.call.isVideoCall) {
      _controlsHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isConnectedStatus(_callStatus)) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _onTapScreen() {
    if (!widget.call.isVideoCall) return;
    setState(() => _showControls = true);
    _scheduleControlsHide();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.call.isVideoCall) {
      if (!_rtcManager.isCameraOff) {
        _rtcManager.toggleCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callStatusSub?.cancel();
    _remoteJoinedSub?.cancel();
    _remoteLeftSub?.cancel();
    _errorSub?.cancel();
    _controlsHideTimer?.cancel();
    _rtcManager.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── BUILD ──────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _errorMessage != null && !_isInitializing
            ? _buildErrorState()
            : widget.call.isVideoCall
                ? _buildVideoCallUI()
                : _buildVoiceCallUI(),
      ),
    );
  }

  // ── Error State ────────────────────────────────
  Widget _buildErrorState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a1a2e), Color(0xFF0f3460)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.call_end, color: Colors.red, size: 72),
                const SizedBox(height: 24),
                Text(
                  _errorMessage ?? 'Đã xảy ra lỗi',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Quay lại'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Video Call UI ──────────────────────────────
  Widget _buildVideoCallUI() {
    return GestureDetector(
      onTap: _onTapScreen,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Remote video (full screen)
          _buildRemoteVideoView(),

          // Local PiP
          if (_isConnectedStatus(_callStatus)) _buildLocalVideoPip(),

          // Gradient overlays
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 200,
            child: IgnorePointer(
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
          ),

          // Initializing indicator
          if (_isInitializing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Đang kết nối...',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),

          // Top bar
          if (_showControls) _buildVideoTopBar(),

          // Quality indicator
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            right: 16,
            child: ListenableBuilder(
              listenable: _rtcManager,
              builder: (_, __) =>
                  CallQualityIndicator(stats: _rtcManager.stats),
            ),
          ),

          // Control bar
          AnimatedOpacity(
            opacity: _showControls ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _buildControlBar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteVideoView() {
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: _rtcManager,
        builder: (_, __) {
          final showVideo = _isConnectedStatus(_callStatus) &&
              _rtcManager.hasRemoteUser &&
              _rtcManager.remoteVideoOn &&
              _rtcManager.engine != null &&
              widget.call.channelName.isNotEmpty;

          if (!showVideo) {
            return _buildRemoteVideoPlaceholder(
              connected:
                  _isConnectedStatus(_callStatus) && _rtcManager.hasRemoteUser,
            );
          }

          return AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _rtcManager.engine!,
              canvas: VideoCanvas(uid: _rtcManager.remoteUid!),
              connection: RtcConnection(channelId: widget.call.channelName),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRemoteVideoPlaceholder({bool connected = false}) {
    final name =
        widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;
    final avatar =
        widget.isOutgoing ? widget.call.calleeAvatar : widget.call.callerAvatar;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (avatar.isNotEmpty)
          Image.network(avatar,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF1a1a2e))),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(color: Colors.black.withOpacity(0.45)),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAvatar(avatar, name, size: 120),
              const SizedBox(height: 24),
              Text(
                name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Text(
                connected ? 'Camera đang tắt' : _statusLabel(),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocalVideoPip() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      right: 16,
      child: Container(
        width: 110,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: ListenableBuilder(
            listenable: _rtcManager,
            builder: (_, __) {
              if (_rtcManager.isCameraOff || _rtcManager.engine == null) {
                return const Center(
                  child: Icon(Icons.videocam_off_rounded,
                      color: Colors.white54, size: 36),
                );
              }
              return AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: _rtcManager.engine!,
                  canvas: const VideoCanvas(uid: 0),
                ),
              );
            },
          ),
        ),
      ),
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
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withOpacity(0.2),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_isConnectedStatus(_callStatus) &&
                        _callConnectedAt != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CallTimerWidget(startTime: _callConnectedAt!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Voice Call UI ──────────────────────────────
  Widget _buildVoiceCallUI() {
    final peerName =
        widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;
    final peerAvatar =
        widget.isOutgoing ? widget.call.calleeAvatar : widget.call.callerAvatar;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (peerAvatar.isNotEmpty)
          Image.network(peerAvatar,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF1a1a2e))),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(color: Colors.black.withOpacity(0.5)),
        ),
        SafeArea(
          child: Column(
            children: [
              // Quality indicator
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ListenableBuilder(
                      listenable: _rtcManager,
                      builder: (_, __) =>
                          CallQualityIndicator(stats: _rtcManager.stats),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              _buildAvatar(peerAvatar, peerName, size: 140),
              const SizedBox(height: 32),

              Text(
                peerName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 12),

              if (_isConnectedStatus(_callStatus) && _callConnectedAt != null)
                CallTimerWidget(
                  startTime: _callConnectedAt!,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.w500),
                )
              else if (_isInitializing)
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white70),
                    ),
                    SizedBox(width: 8),
                    Text('Đang kết nối...',
                        style: TextStyle(color: Colors.white70, fontSize: 18)),
                  ],
                )
              else
                _buildStatusDots(),

              const Spacer(flex: 3),

              _buildControlBar(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Control Bar ────────────────────────────────
  Widget _buildControlBar() {
    return ListenableBuilder(
      listenable: _rtcManager,
      builder: (_, __) => CallControlBar(
        isVideoCall: widget.call.isVideoCall,
        isMuted: _rtcManager.isMuted,
        isCameraOff: _rtcManager.isCameraOff,
        isSpeakerOn: _rtcManager.isSpeakerOn,
        isFrontCamera: _rtcManager.isFrontCamera,
        onMuteTap: () => _rtcManager.toggleMute(),
        onCameraTap:
            widget.call.isVideoCall ? () => _rtcManager.toggleCamera() : null,
        onSpeakerTap: () => _rtcManager.toggleSpeaker(),
        onSwitchCameraTap:
            widget.call.isVideoCall ? () => _rtcManager.switchCamera() : null,
        onEndCall: _endCall,
      ),
    );
  }

  // ── Helpers ────────────────────────────────────

  /// Trả về true nếu trạng thái hiện tại tương đương "đã kết nối".
  /// Bao gồm cả 'accepted' (schema cũ) và 'connected' (schema mới).
  bool _isConnectedStatus(CallStatus s) =>
      s == CallStatus.connected || s == CallStatus.accepted;

  Widget _buildAvatar(String url, String name, {double size = 90}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 2.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              spreadRadius: 4),
        ],
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultAvatar(name, size))
            : _defaultAvatar(name, size),
      ),
    );
  }

  Widget _defaultAvatar(String name, double size) {
    return Container(
      color: Colors.blueGrey[800],
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDots() {
    return _StatusDotsWidget(label: _statusLabel());
  }

  // FIX: Exhaustive switch — bao gồm tất cả các case của CallStatus
  String _statusLabel() {
    switch (_callStatus) {
      case CallStatus.dialing:
        return widget.isOutgoing ? 'Đang gọi…' : 'Cuộc gọi đến…';
      case CallStatus.calling:
        return widget.isOutgoing ? 'Đang gọi…' : 'Cuộc gọi đến…';
      case CallStatus.ringing:
        return 'Đang đổ chuông…';
      case CallStatus.accepted:
      case CallStatus.connected:
        return 'Đã kết nối';
      case CallStatus.ended:
        return 'Cuộc gọi kết thúc';
      case CallStatus.rejected:
      case CallStatus.declined:
        return 'Đã từ chối';
      case CallStatus.missed:
        return 'Cuộc gọi nhỡ';
      case CallStatus.failed:
        return 'Cuộc gọi thất bại';
    }
  }
}

// ── Animated Status Dots ───────────────────────
class _StatusDotsWidget extends StatefulWidget {
  final String label;
  const _StatusDotsWidget({required this.label});

  @override
  State<_StatusDotsWidget> createState() => _StatusDotsWidgetState();
}

class _StatusDotsWidgetState extends State<_StatusDotsWidget> {
  int _dotCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _dotCount = (_dotCount + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${widget.label}${'.' * _dotCount}',
      style: TextStyle(
        color: Colors.white.withOpacity(0.75),
        fontSize: 18,
        letterSpacing: 1,
      ),
    );
  }
}
