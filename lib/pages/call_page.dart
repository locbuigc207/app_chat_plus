// lib/pages/call_page.dart
import 'dart:async';

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

    if (widget.call.status == CallStatus.connected) {
      _callConnectedAt = DateTime.now();
    }

    _initCall();
    _watchCallStatus();
    _scheduleControlsHide();
  }

  Future<void> _initCall() async {
    // Lắng nghe lỗi từ Agora
    _errorSub = _rtcManager.errorStream.listen((error) {
      if (mounted) {
        setState(() => _errorMessage = error);
        _showErrorDialog(error);
      }
    });

    // Lắng nghe remote user join
    _remoteJoinedSub = _rtcManager.remoteJoinedStream.listen((_) {
      if (mounted) {
        setState(() {
          _callStatus = CallStatus.connected;
          _callConnectedAt ??= DateTime.now();
          _isInitializing = false;
        });
      }
    });

    // Lắng nghe remote user rời
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

    if (widget.call.channelName != null) {
      final joined = await _rtcManager.joinChannel(
        channelName: widget.call.channelName!,
        isVideoCall: widget.call.isVideoCall,
        token: widget.call.token,
      );

      if (!joined && mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Không thể tham gia kênh cuộc gọi.';
        });
        return;
      }
    }

    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  void _watchCallStatus() {
    _callStatusSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || _callEnded) return;

      if (mounted) {
        setState(() => _callStatus = call.status);
      }

      if (call.status == CallStatus.connected && _callConnectedAt == null) {
        if (mounted) {
          setState(() => _callConnectedAt = DateTime.now());
        }
      }

      if (call.status == CallStatus.ended ||
          call.status == CallStatus.declined ||
          call.status == CallStatus.missed ||
          call.status == CallStatus.failed) {
        _endCall(remote: true);
      }
    });
  }

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

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (widget.call.isVideoCall) {
      _controlsHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _callStatus == CallStatus.connected) {
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
    // Khi app vào background trong video call: tắt camera
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

  // ── BUILD ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _errorMessage != null && _isInitializing == false
            ? _buildErrorState()
            : widget.call.isVideoCall
                ? _buildVideoCallUI()
                : _buildVoiceCallUI(),
      ),
    );
  }

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
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── VIDEO CALL UI ──────────────────────────────────────

  Widget _buildVideoCallUI() {
    return GestureDetector(
      onTap: _onTapScreen,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Remote video (full screen)
          _buildRemoteVideoView(),

          // Local PiP
          if (_callStatus == CallStatus.connected) _buildLocalVideoPip(),

          // Gradient overlay
          _buildGradientOverlay(),

          // Initializing indicator
          if (_isInitializing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Đang kết nối...',
                      style: TextStyle(color: Colors.white)),
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

          // Controls
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
          final showVideo = _callStatus == CallStatus.connected &&
              _rtcManager.hasRemoteUser &&
              _rtcManager.remoteVideoOn &&
              _rtcManager.engine != null &&
              widget.call.channelName != null;

          if (!showVideo) {
            return _buildRemoteVideoPlaceholder(
              connected: _callStatus == CallStatus.connected &&
                  _rtcManager.hasRemoteUser,
            );
          }

          return AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _rtcManager.engine!,
              canvas: VideoCanvas(uid: _rtcManager.remoteUid!),
              connection: RtcConnection(channelId: widget.call.channelName!),
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

    return Container(
      color: const Color(0xFF1a1a2e),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAvatar(avatar, name, size: 100),
            const SizedBox(height: 20),
            Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              connected ? 'Camera đang tắt' : _statusLabel(),
              style:
                  TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalVideoPip() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      right: 16,
      child: Container(
        width: 100,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ListenableBuilder(
            listenable: _rtcManager,
            builder: (_, __) {
              if (_rtcManager.isCameraOff || _rtcManager.engine == null) {
                return Container(
                  color: Colors.grey[900],
                  child: const Center(
                    child: Icon(Icons.videocam_off,
                        color: Colors.white54, size: 32),
                  ),
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

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
            ),
          ],
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
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              if (_callStatus == CallStatus.connected &&
                  _callConnectedAt != null)
                CallTimerWidget(startTime: _callConnectedAt!),
            ],
          ),
        ),
      ),
    );
  }

  // ── VOICE CALL UI ──────────────────────────────────────

  Widget _buildVoiceCallUI() {
    final peerName =
        widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;
    final peerAvatar =
        widget.isOutgoing ? widget.call.calleeAvatar : widget.call.callerAvatar;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isOutgoing
              ? const [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1976D2)]
              : const [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF388E3C)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Quality + back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

            const Spacer(),

            // Avatar
            _buildAvatar(peerAvatar, peerName, size: 110),
            const SizedBox(height: 28),

            // Name
            Text(peerName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // Status
            if (_callStatus == CallStatus.connected && _callConnectedAt != null)
              CallTimerWidget(
                startTime: _callConnectedAt!,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
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
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                ],
              )
            else
              _buildStatusDots(),

            const Spacer(),

            // Controls
            _buildControlBar(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── SHARED CONTROL BAR ─────────────────────────────────

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

  // ── HELPERS ────────────────────────────────────────────

  Widget _buildAvatar(String url, String name, {double size = 90}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 2.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 16),
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
      color: Colors.blueGrey[700],
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDots() {
    return _StatusDotsWidget(label: _statusLabel());
  }

  String _statusLabel() {
    switch (_callStatus) {
      case CallStatus.calling:
        return widget.isOutgoing ? 'Đang gọi…' : 'Cuộc gọi đến…';
      case CallStatus.ringing:
        return 'Đang đổ chuông…';
      case CallStatus.connected:
        return 'Đã kết nối';
      case CallStatus.ended:
        return 'Cuộc gọi kết thúc';
      case CallStatus.declined:
        return 'Đã từ chối';
      case CallStatus.missed:
        return 'Cuộc gọi nhỡ';
      case CallStatus.failed:
        return 'Cuộc gọi thất bại';
    }
  }
}

// ── Animated status dots ───────────────────────────────────────

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
        fontSize: 16,
        letterSpacing: 1,
      ),
    );
  }
}
