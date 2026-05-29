import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' hide AspectRatio;
import 'package:flutter/services.dart';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
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
import '../widgets/live_caption_overlay.dart';





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
  
  final _callService = CallService.instance;
  final _pip = SimplePip();
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
  bool _isLiveCaptionEnabled = false;

  
  Offset _localPipOffset = const Offset(double.infinity, double.infinity);
  bool _localPipDragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _rtcManager = AgoraRtcManager();
    _callStatus = widget.call.status;

    if (widget.call.status == CallStatus.connected || widget.call.status == CallStatus.accepted) {
      _callConnectedAt = DateTime.now();
    }

    _initCall();
    _watchCallStatus();
    _scheduleControlsHide();
  }

  

  Future<void> _enterPiPMode() async {
    final available = await SimplePip.isPipAvailable;
    if (available) {
      await _pip.enterPipMode(aspectRatio: (9, 16));
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  

  void _startAIProtection() {
    final peerId = widget.isOutgoing ? widget.call.calleeId : widget.call.callerId;
    RealtimeAIService().startProtection(peerId, widget.call.channelName);
  }

  

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
        _startAIProtection();
      }
    });

    _remoteLeftSub = _rtcManager.remoteLeftStream.listen((_) => _endCall());

    final ok = await _rtcManager.initialize();
    if (!ok) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Không thể khởi tạo cuộc gọi.\nKiểm tra Agora App ID.';
        });
      }
      return;
    }

    if (widget.call.channelName.isNotEmpty) {
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

  void _watchCallStatus() {
    _callStatusSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || _callEnded) return;
      if (mounted) setState(() => _callStatus = call.status);

      if ((call.status == CallStatus.connected || call.status == CallStatus.accepted) &&
          _callConnectedAt == null) {
        if (mounted) setState(() => _callConnectedAt = DateTime.now());
      }

      if (call.status.isTerminal) _endCall(remote: true);
    });
  }

  Future<void> _endCall({bool remote = false}) async {
    if (_callEnded) return;
    _callEnded = true;
    await _rtcManager.leaveChannel();

    if (!remote) {
      final duration =
          _callConnectedAt != null ? DateTime.now().difference(_callConnectedAt!).inSeconds : null;
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
        backgroundColor: const Color(0xFF1A1F36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Lỗi cuộc gọi', style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _endCall();
            },
            child: const Text('Đóng', style: TextStyle(color: Color(0xFF5C6BC0))),
          ),
        ],
      ),
    );
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (widget.call.isVideoCall) {
      _controlsHideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _isConnected) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _onTapScreen() {
    if (!widget.call.isVideoCall) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleControlsHide();
  }

  bool get _isConnected =>
      _callStatus == CallStatus.connected || _callStatus == CallStatus.accepted;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.call.isVideoCall) {
      if (!_rtcManager.isCameraOff) _rtcManager.toggleCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealtimeAIService().stopProtection();
    _callStatusSub?.cancel();
    _remoteJoinedSub?.cancel();
    _remoteLeftSub?.cancel();
    _errorSub?.cancel();
    _controlsHideTimer?.cancel();
    _rtcManager.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  
  
  

  @override
  Widget build(BuildContext context) {
    if (widget.call.isVideoCall) {
      return PipWidget(
        pipBuilder: (context) => _buildRemoteVideoOnly(),
        builder: (context) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _enterPiPMode();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: _errorMessage != null && !_isInitializing
                ? _buildErrorState()
                : _buildVideoCallUI(),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _errorMessage != null && !_isInitializing ? _buildErrorState() : _buildVoiceCallUI(),
      ),
    );
  }

  

  Widget _buildRemoteVideoOnly() {
    return ListenableBuilder(
      listenable: _rtcManager,
      builder: (_, __) {
        final show = _isConnected &&
            _rtcManager.hasRemoteUser &&
            _rtcManager.remoteVideoOn &&
            _rtcManager.engine != null;

        if (!show) {
          final name = widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;
          final avatar = widget.isOutgoing ? widget.call.calleeAvatar : widget.call.callerAvatar;
          return ColoredBox(
            color: const Color(0xFF0A0E1A),
            child: Center(child: _buildAvatar(avatar, name, size: 60)),
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
    );
  }

  

  Widget _buildErrorState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1F36), Color(0xFF0A0E1A)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 2),
                  ),
                  child: const Icon(Icons.call_end_rounded, color: Colors.redAccent, size: 44),
                ),
                const SizedBox(height: 28),
                Text(
                  _errorMessage ?? 'Đã xảy ra lỗi',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Quay lại'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  

  Widget _buildVideoCallUI() {
    return GestureDetector(
      onTap: _onTapScreen,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          
          Positioned.fill(child: _buildRemoteVideoView()),

          
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 180,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 260,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xDD000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          
          if (_isInitializing)
            const Positioned.fill(
              child: _ConnectingOverlay(),
            ),

          
          if (_isConnected) _buildDraggableLocalPip(),

          
          if (_showControls || !_isConnected) _buildVideoTopBar(),

          
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            left: 16,
            child: const AICallShield(),
          ),

          
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            right: 16,
            child: ListenableBuilder(
              listenable: _rtcManager,
              builder: (_, __) => CallQualityIndicator(stats: _rtcManager.stats),
            ),
          ),

          
          if (_isLiveCaptionEnabled)
            const Positioned(
              bottom: 140,
              left: 16,
              right: 16,
              child: LiveCaptionOverlay(),
            ),

          
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCaptionToggle(),
                  _buildControlBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggableLocalPip() {
    final size = MediaQuery.of(context).size;
    
    if (_localPipOffset.dx == double.infinity) {
      _localPipOffset = Offset(size.width - 126, MediaQuery.of(context).padding.top + 110);
    }

    return Positioned(
      left: _localPipOffset.dx,
      top: _localPipOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final nx = (_localPipOffset.dx + details.delta.dx).clamp(0.0, size.width - 110.0);
            final ny = (_localPipOffset.dy + details.delta.dy)
                .clamp(MediaQuery.of(context).padding.top.toDouble(), size.height - 180.0);
            _localPipOffset = Offset(nx, ny);
            _localPipDragging = true;
          });
        },
        onPanEnd: (_) => setState(() => _localPipDragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 110,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _localPipDragging
                  ? const Color(0xFF5C6BC0)
                  : Colors.white.withValues(alpha: 0.25),
              width: _localPipDragging ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ListenableBuilder(
              listenable: _rtcManager,
              builder: (_, __) {
                if (_rtcManager.isCameraOff || _rtcManager.engine == null) {
                  return const Center(
                    child: Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 32),
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
      ),
    );
  }

  Widget _buildRemoteVideoView() {
    return ListenableBuilder(
      listenable: _rtcManager,
      builder: (_, __) {
        final show = _isConnected &&
            _rtcManager.hasRemoteUser &&
            _rtcManager.remoteVideoOn &&
            _rtcManager.engine != null &&
            widget.call.channelName.isNotEmpty;

        if (!show) {
          return _buildRemoteVideoPlaceholder(
            connected: _isConnected && _rtcManager.hasRemoteUser,
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
    );
  }

  Widget _buildRemoteVideoPlaceholder({bool connected = false}) {
    final name = widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;
    final avatar = widget.isOutgoing ? widget.call.calleeAvatar : widget.call.callerAvatar;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (avatar.isNotEmpty)
          Image.network(avatar,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0A0E1A))),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
          child: Container(color: Colors.black.withValues(alpha: 0.6)),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAvatar(avatar, name, size: 120),
              const SizedBox(height: 24),
              Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5)),
              const SizedBox(height: 10),
              Text(
                connected ? 'Camera đang tắt' : _statusLabel(),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoTopBar() {
    final name = widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: Colors.black.withValues(alpha: 0.25),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white70),
                      onPressed: _enterPiPMode,
                      tooltip: 'Thu nhỏ',
                    ),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (_isConnected && _callConnectedAt != null)
                      _TimerBadge(startTime: _callConnectedAt!),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  

  Widget _buildVoiceCallUI() {
    final name = widget.isOutgoing ? widget.call.calleeName : widget.call.callerName;
    final avatar = widget.isOutgoing ? widget.call.calleeAvatar : widget.call.callerAvatar;

    return Stack(
      fit: StackFit.expand,
      children: [
        
        if (avatar.isNotEmpty)
          Image.network(avatar,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0A0E1A))),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC0D1B4B), Color(0xDD000000)],
              ),
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const AICallShield(),
                    ListenableBuilder(
                      listenable: _rtcManager,
                      builder: (_, __) => CallQualityIndicator(stats: _rtcManager.stats),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),

              
              _PulsingAvatar(
                url: avatar,
                name: name,
                size: 148,
                isActive: _isConnected,
              ),
              const SizedBox(height: 32),

              
              Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5)),
              const SizedBox(height: 12),

              
              if (_isConnected && _callConnectedAt != null)
                CallTimerWidget(
                  startTime: _callConnectedAt!,
                  style: const TextStyle(
                      color: Color(0xFF81C784),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1),
                )
              else if (_isInitializing)
                const _ConnectingText()
              else
                _StatusDotsWidget(label: _statusLabel()),

              const Spacer(flex: 2),

              
              if (_isLiveCaptionEnabled)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: LiveCaptionOverlay(),
                ),
              const Spacer(),

              
              _buildCaptionToggle(),

              
              _buildControlBar(),
            ],
          ),
        ),
      ],
    );
  }

  

  Widget _buildCaptionToggle() {
    return Padding(
      padding: const EdgeInsets.only(right: 20, bottom: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () {
            setState(() => _isLiveCaptionEnabled = !_isLiveCaptionEnabled);
            Fluttertoast.showToast(
              msg: _isLiveCaptionEnabled ? 'Đã bật phụ đề AI' : 'Đã tắt phụ đề AI',
              backgroundColor: Colors.black87,
              textColor: Colors.white,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isLiveCaptionEnabled ? const Color(0xFF81C784) : Colors.white24,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isLiveCaptionEnabled ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
                  size: 16,
                  color: _isLiveCaptionEnabled ? const Color(0xFF81C784) : Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  'Phụ đề AI',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isLiveCaptionEnabled ? const Color(0xFF81C784) : Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    return ListenableBuilder(
      listenable: _rtcManager,
      builder: (_, __) => CallControlBar(
        isVideoCall: widget.call.isVideoCall,
        isMuted: _rtcManager.isMuted,
        isCameraOff: _rtcManager.isCameraOff,
        isSpeakerOn: _rtcManager.isSpeakerOn,
        isFrontCamera: _rtcManager.isFrontCamera,
        onMuteTap: _rtcManager.toggleMute,
        onCameraTap: widget.call.isVideoCall ? _rtcManager.toggleCamera : null,
        onSpeakerTap: _rtcManager.toggleSpeaker,
        onSwitchCameraTap: widget.call.isVideoCall ? _rtcManager.switchCamera : null,
        onEndCall: _endCall,
      ),
    );
  }

  Widget _buildAvatar(String url, String name, {double size = 90}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 28, spreadRadius: 6),
        ],
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(url,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultAvatar(name, size))
            : _defaultAvatar(name, size),
      ),
    );
  }

  Widget _defaultAvatar(String name, double size) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF3949AB), Color(0xFF1E88E5)]),
      ),
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

  String _statusLabel() {
    switch (_callStatus) {
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





class _TimerBadge extends StatelessWidget {
  final DateTime startTime;
  const _TimerBadge({required this.startTime});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: CallTimerWidget(startTime: startTime),
    );
  }
}

class _ConnectingOverlay extends StatelessWidget {
  const _ConnectingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black38,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            ),
            const SizedBox(height: 20),
            Text(
              'Đang kết nối an toàn…',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectingText extends StatelessWidget {
  const _ConnectingText();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
        SizedBox(width: 10),
        Text('Đang kết nối an toàn…', style: TextStyle(color: Colors.white54, fontSize: 15)),
      ],
    );
  }
}

class _PulsingAvatar extends StatefulWidget {
  final String url;
  final String name;
  final double size;
  final bool isActive;

  const _PulsingAvatar({
    required this.url,
    required this.name,
    required this.size,
    required this.isActive,
  });

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.isActive)
          ...List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                final progress = (_controller.value + (i * 0.33)) % 1.0;
                return Opacity(
                  opacity: ((1.0 - progress) * 0.4).clamp(0, 1),
                  child: Container(
                    width: widget.size + (progress * 80),
                    height: widget.size + (progress * 80),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF81C784), width: 1.5),
                    ),
                  ),
                );
              },
            );
          }),
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5), blurRadius: 32, spreadRadius: 8),
            ],
          ),
          child: ClipOval(
            child: widget.url.isNotEmpty
                ? Image.network(widget.url,
                    fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultAvatar())
                : _defaultAvatar(),
          ),
        ),
      ],
    );
  }

  Widget _defaultAvatar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF3949AB), Color(0xFF1E88E5)]),
      ),
      child: Center(
        child: Text(
          widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: Colors.white, fontSize: widget.size * 0.38, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

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
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 16,
        letterSpacing: 0.5,
      ),
    );
  }
}
