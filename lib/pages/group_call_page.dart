import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide AspectRatio;
import 'package:flutter/services.dart';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:simple_pip_mode/pip_widget.dart';
import 'package:simple_pip_mode/simple_pip.dart';

import '../models/group_call_model.dart';
import '../services/agora_rtc_manager.dart';
import '../services/group_call_service.dart';
import '../services/realtime_ai_service.dart';
import '../widgets/ai_call_shield.dart';
import '../widgets/call_quality_indicator.dart';
import '../widgets/call_timer_widget.dart';
import '../widgets/live_caption_overlay.dart';

class _FloatingReaction {
  final String emoji;
  final String senderName;
  final double xFraction;
  final DateTime createdAt;
  final AnimationController ctrl;
  final Animation<double> opacity;
  final Animation<double> translateY;

  _FloatingReaction({
    required this.emoji,
    required this.senderName,
    required this.xFraction,
    required this.createdAt,
    required this.ctrl,
    required this.opacity,
    required this.translateY,
  });
}

class GroupCallPage extends StatefulWidget {
  final GroupCallModel call;
  final bool isInitiator;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;

  const GroupCallPage({
    super.key,
    required this.call,
    required this.isInitiator,
    required this.currentUserId,
    required this.currentUserName,
    this.currentUserAvatar = '',
  });

  @override
  State<GroupCallPage> createState() => _GroupCallPageState();
}

class _GroupCallPageState extends State<GroupCallPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _callService = GroupCallService.instance;
  final _pip = SimplePip();
  late RtcEngine _engine;

  bool _engineInitialized = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _isScreenSharing = false;
  bool _hasRaisedHand = false;
  bool _showControls = true;
  bool _callEnded = false;
  bool _isConnected = false;
  bool _showParticipantsList = false;
  bool _isLiveCaptionEnabled = false;
  bool _aiProtectionStarted = false;
  bool _showReactionPicker = false;

  final Set<int> _remoteUids = {};
  final Map<int, bool> _remoteAudioMuted = {};
  final Map<int, bool> _remoteVideoMuted = {};

  late GroupCallModel _callModel;
  DateTime? _connectedAt;

  StreamSubscription? _callSub;
  Timer? _controlsHideTimer;

  RtcCallStats _stats = const RtcCallStats();

  int? _spotlightUid;

  late AnimationController _controlsAnimCtrl;
  late Animation<double> _controlsAnim;
  late AnimationController _raisedHandCtrl;
  late Animation<double> _raisedHandAnim;

  final List<_FloatingReaction> _floatingReactions = [];
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _callModel = widget.call;
    _connectedAt = DateTime.now();

    _controlsAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _controlsAnim = CurvedAnimation(parent: _controlsAnimCtrl, curve: Curves.easeOut);

    _raisedHandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _raisedHandAnim = Tween<double>(begin: 0.9, end: 1.1).animate(_raisedHandCtrl);

    _initCall();
    _watchCall();
    _scheduleControlsHide();
  }

  Future<void> _enterPiPMode() async {
    final available = await SimplePip.isPipAvailable;
    if (available) {
      await _pip.enterPipMode(aspectRatio: (3, 4));
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  void _startAIProtection() {
    if (_aiProtectionStarted) return;
    _aiProtectionStarted = true;
    RealtimeAIService().startProtection(
      'GROUP_CALL_${widget.call.callId}',
      widget.call.channelName,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _engine.muteLocalVideoStream(true);
    } else if (state == AppLifecycleState.resumed) {
      if (!_isCameraOff && !_isScreenSharing) {
        _engine.muteLocalVideoStream(false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealtimeAIService().stopProtection();
    _controlsAnimCtrl.dispose();
    _raisedHandCtrl.dispose();
    for (final r in _floatingReactions) {
      r.ctrl.dispose();
    }
    _cleanup();
    super.dispose();
  }

  Future<void> _initCall() async {
    await _requestPermissions();
    await _initEngine();
    await _joinChannel();
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    final perms = [Permission.microphone];
    if (widget.call.isVideo) perms.add(Permission.camera);
    await perms.request();
  }

  Future<void> _initEngine() async {
    _engine = createAgoraRtcEngine();
    final appId = dotenv.env['AGORA_APP_ID'] ?? '';

    await _engine.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, elapsed) {
        if (mounted) setState(() => _isConnected = true);
      },
      onUserJoined: (conn, uid, elapsed) {
        if (mounted) {
          setState(() => _remoteUids.add(uid));
          _startAIProtection();
        }
      },
      onUserOffline: (conn, uid, reason) {
        if (mounted) {
          setState(() {
            _remoteUids.remove(uid);
            _remoteAudioMuted.remove(uid);
            _remoteVideoMuted.remove(uid);
            if (_spotlightUid == uid) _spotlightUid = null;
          });
        }
        if (_remoteUids.isEmpty && !widget.isInitiator && mounted) _hangUp();
      },
      onRemoteAudioStateChanged: (conn, uid, state, reason, elapsed) {
        if (mounted) {
          setState(() {
            _remoteAudioMuted[uid] = state == RemoteAudioState.remoteAudioStateStopped;
          });
        }
      },
      onRemoteVideoStateChanged: (conn, uid, state, reason, elapsed) {
        if (mounted) {
          setState(() {
            _remoteVideoMuted[uid] = state == RemoteVideoState.remoteVideoStateStopped;
          });
        }
      },
      onRtcStats: (conn, stats) {
        if (mounted) {
          setState(() => _stats = RtcCallStats(
                txBitrate: stats.txKBitRate ?? 0,
                rxBitrate: stats.rxKBitRate ?? 0,
                txPacketLoss: stats.txPacketLossRate ?? 0,
                rxPacketLoss: stats.rxPacketLossRate ?? 0,
                rtt: stats.lastmileDelay ?? 0,
                duration: stats.duration ?? 0,
              ));
        }
      },
      onError: (err, msg) => debugPrint('❌ Agora [$err]: $msg'),
    ));

    if (widget.call.isVideo) {
      await _engine.enableVideo();
      await _engine.startPreview();
      await _engine.setVideoEncoderConfiguration(const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 1280, height: 720),
        frameRate: 30,
        bitrate: 1500,
      ));
    }
    await _engine.enableAudio();
    await _engine.setEnableSpeakerphone(true);
    await _engine.enableAudioVolumeIndication(interval: 200, smooth: 3, reportVad: true);

    setState(() => _engineInitialized = true);
  }

  Future<void> _joinChannel() async {
    await _engine.joinChannel(
      token: '',
      channelId: widget.call.channelName,
      uid: 0,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishCameraTrack: widget.call.isVideo && !_isCameraOff,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
        autoSubscribeVideo: widget.call.isVideo,
      ),
    );
  }

  void _watchCall() {
    _callSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || _callEnded) return;
      if (mounted) setState(() => _callModel = call);
      if (call.status == GroupCallStatus.ended) _handleCallEnded();

      for (final r in call.recentReactions) {
        if (r.sentAt.isAfter(DateTime.now().subtract(const Duration(seconds: 3)))) {
          _showFloatingReaction(r.type.emoji, r.userName);
        }
      }
    });
  }

  void _handleCallEnded() {
    if (_callEnded) return;
    _callEnded = true;
    _cleanup();
    if (mounted) {
      _showCallEndedSheet();
    }
  }

  void _showCallEndedSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _CallEndedSheet(
        duration: _callModel.durationSeconds ?? 0,
        participantCount: _callModel.participantCount,
        onDismiss: () {
          Navigator.of(context)
            ..pop()
            ..pop();
        },
      ),
    );
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (widget.call.isVideo) {
      _controlsHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isConnected && !_showReactionPicker) {
          _controlsAnimCtrl.reverse();
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _onTapScreen() {
    if (!widget.call.isVideo) return;
    setState(() {
      _showControls = true;
      _showReactionPicker = false;
    });
    _controlsAnimCtrl.forward();
    _scheduleControlsHide();
  }

  Future<void> _toggleMute() async {
    final next = !_isMuted;
    await _engine.muteLocalAudioStream(next);
    setState(() => _isMuted = next);
    await _callService.updateParticipantState(
      callId: widget.call.callId,
      isMuted: next,
      isCameraOff: _isCameraOff,
    );
  }

  Future<void> _toggleCamera() async {
    if (!widget.call.isVideo) return;
    final next = !_isCameraOff;
    await _engine.muteLocalVideoStream(next);
    setState(() => _isCameraOff = next);
    await _callService.updateParticipantState(
      callId: widget.call.callId,
      isMuted: _isMuted,
      isCameraOff: next,
    );
  }

  Future<void> _toggleSpeaker() async {
    final next = !_isSpeakerOn;
    await _engine.setEnableSpeakerphone(next);
    setState(() => _isSpeakerOn = next);
  }

  Future<void> _switchCamera() async {
    if (_isCameraOff) return;
    await _engine.switchCamera();
    setState(() => _isFrontCamera = !_isFrontCamera);
    _showToast(_isFrontCamera ? 'Camera trước' : 'Camera sau');
  }

  Future<void> _toggleRaiseHand() async {
    final next = !_hasRaisedHand;
    setState(() => _hasRaisedHand = next);
    await _callService.toggleRaiseHand(
        callId: widget.call.callId, userId: widget.currentUserId, raised: next);
    _showToast(next ? '✋ Đã giơ tay' : 'Đã hạ tay');
  }

  Future<void> _toggleScreenShare() async {
    final next = !_isScreenSharing;
    setState(() => _isScreenSharing = next);
    if (next) {
      await _engine.startScreenCapture(
        const ScreenCaptureParameters2(captureAudio: true, captureVideo: true),
      );
    } else {
      await _engine.stopScreenCapture();
    }
    await _callService.updateScreenShare(
      callId: widget.call.callId,
      userId: widget.currentUserId,
      isSharing: next,
    );
    _showToast(next ? '📺 Đang chia sẻ màn hình' : 'Đã dừng chia sẻ');
  }

  void _toggleLiveCaption() {
    setState(() => _isLiveCaptionEnabled = !_isLiveCaptionEnabled);
    _showToast(_isLiveCaptionEnabled ? 'Đã bật phụ đề AI' : 'Đã tắt phụ đề AI');
  }

  void _sendReaction(CallReactionType type) {
    setState(() => _showReactionPicker = false);
    _callService.sendReaction(
      callId: widget.call.callId,
      userId: widget.currentUserId,
      userName: widget.currentUserName,
      reaction: type,
    );
    _showFloatingReaction(type.emoji, 'Bạn');
    _scheduleControlsHide();
  }

  void _showFloatingReaction(String emoji, String sender) {
    if (!mounted) return;
    final x = 0.1 + _random.nextDouble() * 0.8;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    final opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(ctrl);
    final translateY = Tween<double>(begin: 0, end: -180).animate(
      CurvedAnimation(parent: ctrl, curve: Curves.easeOut),
    );

    final reaction = _FloatingReaction(
      emoji: emoji,
      senderName: sender,
      xFraction: x,
      createdAt: DateTime.now(),
      ctrl: ctrl,
      opacity: opacity,
      translateY: translateY,
    );

    setState(() => _floatingReactions.add(reaction));

    ctrl.forward().then((_) {
      if (mounted) {
        setState(() => _floatingReactions.remove(reaction));
        reaction.ctrl.dispose();
      }
    });
  }

  Future<void> _hangUp() async {
    if (_callEnded) return;
    _callEnded = true;

    if (widget.isInitiator) {
      await _callService.endCallForAll(widget.call.callId,
          startTime: _connectedAt ?? DateTime.now());
    } else {
      await _callService.leaveCall(widget.call.callId);
    }

    _cleanup();
    if (mounted) Navigator.of(context).pop();
  }

  void _cleanup() {
    _callSub?.cancel();
    _controlsHideTimer?.cancel();
    try {
      _engine.leaveChannel();
      _engine.release();
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _setSpotlight(int? uid) => setState(() => _spotlightUid = uid);

  void _showToast(String msg) => Fluttertoast.showToast(
        msg: msg,
        backgroundColor: const Color(0xFF1e293b),
        textColor: Colors.white,
        fontSize: 13,
        gravity: ToastGravity.TOP,
        toastLength: Toast.LENGTH_SHORT,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.call.isVideo) {
      return PipWidget(
        pipBuilder: (_) => _buildPipContent(),
        builder: (_) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) await _enterPiPMode();
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
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _hangUp();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _buildVoiceUI(),
      ),
    );
  }

  Widget _buildPipContent() {
    if (!_engineInitialized) {
      return const ColoredBox(
        color: Color(0xFF0f172a),
        child: Center(child: CircularProgressIndicator(color: Colors.white38)),
      );
    }
    final uid = _spotlightUid ?? (_remoteUids.isNotEmpty ? _remoteUids.first : null);
    if (uid == null) {
      return ColoredBox(
        color: const Color(0xFF0f172a),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.group, color: Colors.white38, size: 28),
              const SizedBox(height: 4),
              Text(
                widget.call.groupName,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: widget.call.channelName),
      ),
    );
  }

  Widget _buildVideoUI() {
    return GestureDetector(
      onTap: _onTapScreen,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _remoteUids.isEmpty ? _buildWaitingScreen() : _buildVideoGrid(),
          _buildGradients(),
          ..._floatingReactions.map(_buildFloatingReaction),
          if (_showReactionPicker) _buildReactionPicker(),
          FadeTransition(
            opacity: _controlsAnim,
            child: _buildVideoTopBar(),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            left: 12,
            child: const AICallShield(),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            right: 12,
            child: CallQualityIndicator(stats: _stats),
          ),
          if (_hasRaisedHand)
            Positioned(
              top: MediaQuery.of(context).padding.top + 120,
              left: 0,
              right: 0,
              child: Center(child: _buildRaisedHandBadge()),
            ),
          if (_showParticipantsList) _buildParticipantsPanel(),
          if (_isLiveCaptionEnabled)
            Positioned(
              bottom: 150,
              left: 16,
              right: 16,
              child: const LiveCaptionOverlay(),
            ),
          FadeTransition(
            opacity: _controlsAnim,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingReaction(_FloatingReaction r) {
    return Positioned(
      bottom: 180,
      left: 0,
      right: 0,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final x = r.xFraction * constraints.maxWidth - 30;
          return AnimatedBuilder(
            animation: r.ctrl,
            builder: (_, __) => Opacity(
              opacity: r.opacity.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(x, r.translateY.value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.emoji, style: const TextStyle(fontSize: 34)),
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        r.senderName,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRaisedHandBadge() {
    return AnimatedBuilder(
      animation: _raisedHandAnim,
      builder: (_, child) => Transform.scale(scale: _raisedHandAnim.value, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
              blurRadius: 12,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('✋', style: TextStyle(fontSize: 16)),
            SizedBox(width: 6),
            Text('Bạn đang giơ tay',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [Color(0xFF1e3a5f), Color(0xFF0a0a1a)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGroupAvatar(80),
            const SizedBox(height: 24),
            Text(
              widget.call.groupName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Đang chờ mọi người tham gia…',
              style: TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 16),
            if (_connectedAt != null)
              CallTimerWidget(
                startTime: _connectedAt!,
                style: const TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 1),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupAvatar(double radius) {
    return widget.call.groupAvatarUrl.isNotEmpty
        ? CircleAvatar(
            radius: radius,
            backgroundImage: NetworkImage(widget.call.groupAvatarUrl),
          )
        : CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFF334155),
            child: Icon(Icons.group, size: radius, color: Colors.white70),
          );
  }

  Widget _buildVideoGrid() {
    if (!_engineInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final uids = _remoteUids.toList();
    if (_spotlightUid != null && uids.contains(_spotlightUid)) {
      return _buildSpotlightLayout(uids);
    }
    return _buildAdaptiveGrid(uids);
  }

  Widget _buildSpotlightLayout(List<int> all) {
    final others = all.where((u) => u != _spotlightUid).toList();
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: GestureDetector(
            onDoubleTap: () => _setSpotlight(null),
            child: _buildRemoteVideoTile(_spotlightUid!, big: true),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            children: [
              _buildLocalThumb(),
              ...others.map((uid) => _buildRemoteThumb(uid)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdaptiveGrid(List<int> uids) {
    final count = uids.length;
    if (count == 1) {
      return Stack(
        children: [
          GestureDetector(
            onDoubleTap: () => _setSpotlight(uids[0]),
            child: _buildRemoteVideoTile(uids[0], big: true),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 110,
            right: 12,
            child: _buildLocalPip(),
          ),
        ],
      );
    }

    final crossCount = count <= 2 ? 1 : (count <= 4 ? 2 : 3);
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: crossCount == 1 ? 0.75 : 0.85,
      ),
      itemCount: uids.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return _buildLocalGridTile();
        final uid = uids[i - 1];
        return GestureDetector(
          onDoubleTap: () => _setSpotlight(uid),
          child: _buildRemoteVideoTile(uid),
        );
      },
    );
  }

  Widget _buildRemoteVideoTile(int uid, {bool big = false}) {
    final participant = _callModel.participants.cast<GroupCallParticipant?>().firstWhere(
          (p) => p != null,
          orElse: () => null,
        );
    final videoMuted = _remoteVideoMuted[uid] ?? false;
    final audioMuted = _remoteAudioMuted[uid] ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(big ? 0 : 10),
          child: videoMuted
              ? _buildVideoOffPlaceholder(
                  name: participant?.userName,
                  avatarUrl: participant?.userAvatar,
                  big: big,
                )
              : AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: _engine,
                    canvas: VideoCanvas(uid: uid),
                    connection: RtcConnection(channelId: widget.call.channelName),
                  ),
                ),
        ),
        Positioned(
          bottom: 8,
          left: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (audioMuted) _statusBadge(Icons.mic_off, Colors.red.shade600),
              if (videoMuted) ...[
                const SizedBox(width: 4),
                _statusBadge(Icons.videocam_off, Colors.orange.shade700),
              ],
            ],
          ),
        ),
        if (participant?.userName != null)
          Positioned(
            bottom: 8,
            right: 8,
            child: _nameBadge(participant!.userName),
          ),
        if (participant != null && _callModel.hasRaisedHand(participant.userId))
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('✋', style: TextStyle(fontSize: 14)),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoOffPlaceholder({String? name, String? avatarUrl, bool big = false}) {
    return Container(
      color: const Color(0xFF1e293b),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: big ? 44 : 26,
              backgroundImage: (avatarUrl?.isNotEmpty ?? false) ? NetworkImage(avatarUrl!) : null,
              backgroundColor: const Color(0xFF334155),
              child: (avatarUrl?.isNotEmpty ?? false)
                  ? null
                  : Icon(Icons.person, size: big ? 44 : 26, color: Colors.white54),
            ),
            if (name != null) ...[
              const SizedBox(height: 8),
              Text(name, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocalGridTile() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _isCameraOff
              ? Container(
                  color: const Color(0xFF1e293b),
                  child: const Center(
                    child: Icon(Icons.videocam_off, color: Colors.white38, size: 36),
                  ),
                )
              : (_engineInitialized
                  ? AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    )
                  : Container(color: const Color(0xFF0f172a))),
        ),
        if (_isMuted)
          Positioned(
            bottom: 8,
            left: 8,
            child: _statusBadge(Icons.mic_off, Colors.red.shade600),
          ),
        Positioned(
          bottom: 8,
          right: 8,
          child: _nameBadge('Bạn'),
        ),
      ],
    );
  }

  Widget _buildLocalPip() {
    return Container(
      width: 100,
      height: 148,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.5),
        child: _isCameraOff
            ? Container(
                color: const Color(0xFF1e293b),
                child:
                    const Center(child: Icon(Icons.videocam_off, color: Colors.white38, size: 26)),
              )
            : (_engineInitialized
                ? AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: _engine,
                      canvas: const VideoCanvas(uid: 0),
                    ),
                  )
                : Container(color: const Color(0xFF0f172a))),
      ),
    );
  }

  Widget _buildLocalThumb() {
    return _thumbContainer(
      child: _isCameraOff
          ? Container(
              color: const Color(0xFF1e293b),
              child: const Center(child: Icon(Icons.person, color: Colors.white38, size: 24)))
          : (_engineInitialized
              ? AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _engine,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                )
              : Container(color: const Color(0xFF0f172a))),
    );
  }

  Widget _buildRemoteThumb(int uid) {
    return GestureDetector(
      onTap: () => _setSpotlight(uid),
      child: _thumbContainer(
        child: AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _engine,
            canvas: VideoCanvas(uid: uid),
            connection: RtcConnection(channelId: widget.call.channelName),
          ),
        ),
      ),
    );
  }

  Widget _thumbContainer({required Widget child}) {
    return Container(
      width: 62,
      height: 88,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: child,
      ),
    );
  }

  Widget _statusBadge(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(icon, color: Colors.white, size: 13),
    );
  }

  Widget _nameBadge(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }

  Widget _buildGradients() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              height: 160,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: 240,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.88),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: Colors.black.withValues(alpha: 0.15),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _iconBtn(
                      Icons.picture_in_picture_alt_rounded,
                      onTap: _enterPiPMode,
                      tooltip: 'Thu nhỏ',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.call.groupName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_connectedAt != null)
                            CallTimerWidget(
                              startTime: _connectedAt!,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    if (_isScreenSharing)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.screen_share, color: Colors.white, size: 13),
                            SizedBox(width: 4),
                            Text('Đang chia sẻ',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    GestureDetector(
                      onTap: () => setState(() => _showParticipantsList = !_showParticipantsList),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.people_rounded, color: Colors.white, size: 15),
                            const SizedBox(width: 5),
                            Text(
                              '${_callModel.participants.length}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
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

  Widget _iconBtn(IconData icon, {required VoidCallback onTap, String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildParticipantsPanel() {
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 270,
      child: GestureDetector(
        onTap: () {},
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              color: Colors.black.withValues(alpha: 0.78),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                      child: Row(
                        children: [
                          const Text('Thành viên',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                            onPressed: () => setState(() => _showParticipantsList = false),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _callModel.participants.length,
                        itemBuilder: (_, i) {
                          final p = _callModel.participants[i];
                          return _buildParticipantTile(p);
                        },
                      ),
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

  Widget _buildParticipantTile(GroupCallParticipant p) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundImage: p.userAvatar.isNotEmpty ? NetworkImage(p.userAvatar) : null,
            backgroundColor: const Color(0xFF334155),
            child: p.userAvatar.isEmpty
                ? const Icon(Icons.person, color: Colors.white54, size: 18)
                : null,
          ),
          if (p.isSpeaking)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF4ADE80), width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        p.userName,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: p.isAdmin
          ? const Text('Admin', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 10))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_callModel.hasRaisedHand(p.userId)) const Text('✋', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          if (p.isMuted) const Icon(Icons.mic_off, color: Colors.redAccent, size: 14),
          if (p.isCameraOff && widget.call.isVideo)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.videocam_off, color: Colors.orangeAccent, size: 14),
            ),
          if (p.isScreenSharing)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.screen_share, color: Colors.blueAccent, size: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildReactionPicker() {
    return Positioned(
      bottom: 170,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1e293b).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: CallReactionType.values.map((type) {
            return GestureDetector(
              onTap: () => _sendReaction(type),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(type.emoji, style: const TextStyle(fontSize: 26)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _secondaryBtn(
                    icon: _isLiveCaptionEnabled
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_off_rounded,
                    active: _isLiveCaptionEnabled,
                    label: 'CC',
                    onTap: _toggleLiveCaption,
                  ),
                  const SizedBox(width: 8),
                  _secondaryBtn(
                    icon: Icons.emoji_emotions_outlined,
                    active: _showReactionPicker,
                    label: '😊',
                    onTap: () => setState(() => _showReactionPicker = !_showReactionPicker),
                  ),
                  const SizedBox(width: 8),
                  _secondaryBtn(
                    icon: _hasRaisedHand ? Icons.back_hand : Icons.back_hand_outlined,
                    active: _hasRaisedHand,
                    label: '✋',
                    onTap: _toggleRaiseHand,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _controlBtn(
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _isMuted ? 'Mở Mic' : 'Mic',
                    active: _isMuted,
                    onTap: _toggleMute,
                  ),
                  _controlBtn(
                    icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
                    label: _isSpeakerOn ? 'Loa' : 'Tai nghe',
                    active: _isSpeakerOn,
                    onTap: _toggleSpeaker,
                  ),
                  GestureDetector(
                    onTap: _hangUp,
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                  _controlBtn(
                    icon: _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                    label: _isCameraOff ? 'Bật Cam' : 'Cam',
                    active: _isCameraOff,
                    onTap: _toggleCamera,
                  ),
                  _controlBtn(
                    icon: Icons.flip_camera_android_rounded,
                    label: 'Xoay',
                    active: false,
                    onTap: _switchCamera,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secondaryBtn({
    required IconData icon,
    required bool active,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              active ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? Colors.white : Colors.white70, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceUI() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0b1437), Color(0xFF1a2f4e), Color(0xFF0b1437)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const AICallShield(),
                  const Spacer(),
                  CallQualityIndicator(stats: _stats),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.call.groupName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            if (_connectedAt != null)
              CallTimerWidget(
                startTime: _connectedAt!,
                style: const TextStyle(
                  color: Color(0xFF4ADE80),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            const Spacer(),
            _buildVoiceParticipantsGrid(),
            const Spacer(),
            if (_floatingReactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _floatingReactions
                      .map((r) => Text(r.emoji, style: const TextStyle(fontSize: 28)))
                      .toList(),
                ),
              ),
            if (_isLiveCaptionEnabled)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: LiveCaptionOverlay(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _secondaryBtn(
                    icon: _isLiveCaptionEnabled
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_off_rounded,
                    active: _isLiveCaptionEnabled,
                    label: 'Phụ đề',
                    onTap: _toggleLiveCaption,
                  ),
                  const SizedBox(width: 10),
                  _secondaryBtn(
                    icon: Icons.emoji_emotions_outlined,
                    active: _showReactionPicker,
                    label: 'React',
                    onTap: () => setState(() => _showReactionPicker = !_showReactionPicker),
                  ),
                  const SizedBox(width: 10),
                  _secondaryBtn(
                    icon: _hasRaisedHand ? Icons.back_hand : Icons.back_hand_outlined,
                    active: _hasRaisedHand,
                    label: 'Giơ tay',
                    onTap: _toggleRaiseHand,
                  ),
                ],
              ),
            ),
            if (_showReactionPicker)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildVoiceReactionRow(),
              ),
            _buildVoiceControls(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceReactionRow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: CallReactionType.values.map((type) {
          return GestureDetector(
            onTap: () => _sendReaction(type),
            child: Text(type.emoji, style: const TextStyle(fontSize: 28)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVoiceParticipantsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        alignment: WrapAlignment.center,
        children: _callModel.participants.map(_buildVoiceParticipantAvatar).toList(),
      ),
    );
  }

  Widget _buildVoiceParticipantAvatar(GroupCallParticipant p) {
    final isSelf = p.userId == widget.currentUserId;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: p.isSpeaking
                      ? const Color(0xFF4ADE80)
                      : (p.isMuted
                          ? Colors.red.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.2)),
                  width: p.isSpeaking ? 3 : 2,
                ),
                boxShadow: p.isSpeaking
                    ? [
                        BoxShadow(
                          color: const Color(0xFF4ADE80).withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: CircleAvatar(
                radius: 36,
                backgroundImage: p.userAvatar.isNotEmpty ? NetworkImage(p.userAvatar) : null,
                backgroundColor: const Color(0xFF334155),
                child: p.userAvatar.isEmpty
                    ? const Icon(Icons.person, size: 36, color: Colors.white54)
                    : null,
              ),
            ),
            if (p.isMuted)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                  child: const Icon(Icons.mic_off, size: 12, color: Colors.white),
                ),
              ),
            if (_callModel.hasRaisedHand(p.userId))
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
                  child: const Text('✋', style: TextStyle(fontSize: 10)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isSelf ? 'Bạn' : p.userName,
          style: TextStyle(
            color: isSelf ? const Color(0xFF93C5FD) : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        if (p.isAdmin)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
            ),
            child: const Text('admin', style: TextStyle(color: Color(0xFFFBBF24), fontSize: 9)),
          ),
      ],
    );
  }

  Widget _buildVoiceControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlBtn(
            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: _isMuted ? 'Mở Mic' : 'Mic',
            active: _isMuted,
            onTap: _toggleMute,
          ),
          GestureDetector(
            onTap: _hangUp,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
            ),
          ),
          _controlBtn(
            icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
            label: _isSpeakerOn ? 'Loa' : 'Tai nghe',
            active: _isSpeakerOn,
            onTap: _toggleSpeaker,
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallEndedSheet extends StatelessWidget {
  final int duration;
  final int participantCount;
  final VoidCallback onDismiss;

  const _CallEndedSheet({
    required this.duration,
    required this.participantCount,
    required this.onDismiss,
  });

  String get _formattedDuration {
    final d = Duration(seconds: duration);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      decoration: const BoxDecoration(
        color: Color(0xFF0f172a),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF1e293b),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Icon(Icons.call_end_rounded, color: Color(0xFFEF4444), size: 30),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cuộc gọi đã kết thúc',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statCard(
                icon: Icons.access_time_rounded,
                label: 'Thời gian',
                value: _formattedDuration,
              ),
              const SizedBox(width: 16),
              _statCard(
                icon: Icons.people_rounded,
                label: 'Thành viên',
                value: '$participantCount',
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onDismiss,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child:
                  const Text('Đóng', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF93C5FD), size: 20),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
