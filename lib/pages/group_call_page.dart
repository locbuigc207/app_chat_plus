// lib/pages/group_call_page.dart
import 'dart:async';
import 'dart:ui';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/group_call_model.dart';
import '../services/agora_rtc_manager.dart';
import '../services/group_call_service.dart';
import '../services/realtime_ai_service.dart';
import '../widgets/ai_call_shield.dart';
import '../widgets/call_quality_indicator.dart';
import '../widgets/call_timer_widget.dart';
import '../widgets/live_caption_overlay.dart';

class GroupCallPage extends StatefulWidget {
  final GroupCallModel call;
  final bool isInitiator;

  const GroupCallPage({
    super.key,
    required this.call,
    required this.isInitiator,
  });

  @override
  State<GroupCallPage> createState() => _GroupCallPageState();
}

class _GroupCallPageState extends State<GroupCallPage>
    with WidgetsBindingObserver {
  // ── Services ───────────────────────────────────
  final _callService = GroupCallService();
  late RtcEngine _engine;

  // ── UI State ───────────────────────────────────
  bool _engineInitialized = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _showControls = true;
  bool _callEnded = false;
  bool _isConnected = false;
  bool _showParticipantsList = false;
  bool _isLiveCaptionEnabled = false;

  // ── Remote Participants ────────────────────────
  final Set<int> _remoteUids = {};

  // ── Call Data ──────────────────────────────────
  late GroupCallModel _callModel;
  DateTime? _connectedAt;

  // ── Subscriptions & Timers ─────────────────────
  StreamSubscription? _callSub;
  Timer? _controlsHideTimer;
  Timer? _statsTimer;

  // ── Stats ──────────────────────────────────────
  RtcCallStats _stats = const RtcCallStats();

  // ── Spotlight ──────────────────────────────────
  int? _spotlightUid;

  // ── Lifecycle ──────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _callModel = widget.call;
    _connectedAt = DateTime.now();
    _initCall();
    _watchCall();
    _scheduleControlsHide();
    _startAIProtection();
  }

  void _startAIProtection() {
    RealtimeAIService().startProtection(
      "GROUP_CALL_${widget.call.callId}",
      widget.call.channelName,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _engine.muteLocalVideoStream(true);
    } else if (state == AppLifecycleState.resumed) {
      if (!_isCameraOff) _engine.muteLocalVideoStream(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealtimeAIService().stopProtection();
    _cleanup();
    super.dispose();
  }

  // ── Init ───────────────────────────────────────
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

    final String agoraAppId = dotenv.env['AGORA_APP_ID'] ?? '';
    if (agoraAppId.isEmpty) {
      debugPrint('❌ LỖI: AGORA_APP_ID chưa được cài đặt trong file .env');
    }

    await _engine.initialize(RtcEngineContext(
      appId: agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, elapsed) {
        debugPrint('✅ Joined group call channel');
        if (mounted) setState(() => _isConnected = true);
      },
      onUserJoined: (conn, uid, elapsed) {
        debugPrint('👤 Remote user joined: $uid');
        if (mounted) setState(() => _remoteUids.add(uid));
      },
      onUserOffline: (conn, uid, reason) {
        debugPrint('👤 Remote user left: $uid');
        if (mounted) {
          setState(() {
            _remoteUids.remove(uid);
            if (_spotlightUid == uid) _spotlightUid = null;
          });
        }
        if (_remoteUids.isEmpty && !widget.isInitiator && mounted) {
          _hangUp();
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
      onError: (err, msg) => debugPrint('❌ Agora error [$err]: $msg'),
    ));

    if (widget.call.isVideo) {
      await _engine.enableVideo();
      await _engine.startPreview();
    }
    await _engine.enableAudio();
    await _engine.setEnableSpeakerphone(true);

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
        publishCameraTrack: widget.call.isVideo,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
        autoSubscribeVideo: widget.call.isVideo,
      ),
    );
  }

  // ── Watch Call Status ──────────────────────────
  void _watchCall() {
    _callSub = _callService.watchCall(widget.call.callId).listen((call) {
      if (call == null || _callEnded) return;
      if (mounted) setState(() => _callModel = call);
      if (call.status == GroupCallStatus.ended) {
        _handleCallEnded();
      }
    });
  }

  void _handleCallEnded() {
    if (_callEnded) return;
    _callEnded = true;
    _cleanup();
    if (mounted) {
      _showEndedSnackbar();
      Navigator.of(context).pop();
    }
  }

  void _showEndedSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Cuộc gọi đã kết thúc'),
          duration: Duration(seconds: 2)),
    );
  }

  // ── Controls Visibility ────────────────────────
  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (widget.call.isVideo) {
      _controlsHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isConnected) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _onTapScreen() {
    if (!widget.call.isVideo) return;
    setState(() => _showControls = true);
    _scheduleControlsHide();
  }

  // ── Controls Actions ───────────────────────────
  Future<void> _toggleMute() async {
    final next = !_isMuted;
    await _engine.muteLocalAudioStream(next);
    setState(() => _isMuted = next);
    await _callService.updateParticipantState(
        callId: widget.call.callId, isMuted: next, isCameraOff: _isCameraOff);
  }

  Future<void> _toggleCamera() async {
    if (!widget.call.isVideo) return;
    final next = !_isCameraOff;
    await _engine.muteLocalVideoStream(next);
    setState(() => _isCameraOff = next);
    await _callService.updateParticipantState(
        callId: widget.call.callId, isMuted: _isMuted, isCameraOff: next);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_isSpeakerOn;
    await _engine.setEnableSpeakerphone(next);
    setState(() => _isSpeakerOn = next);
  }

  Future<void> _switchCamera() async {
    await _engine.switchCamera();
    setState(() => _isFrontCamera = !_isFrontCamera);
  }

  void _toggleLiveCaption() {
    setState(() => _isLiveCaptionEnabled = !_isLiveCaptionEnabled);
    Fluttertoast.showToast(
        msg: _isLiveCaptionEnabled ? 'Đã bật phụ đề AI' : 'Đã tắt phụ đề AI');
  }

  // ── Hang Up ────────────────────────────────────
  Future<void> _hangUp() async {
    if (_callEnded) return;
    _callEnded = true;

    if (widget.isInitiator) {
      await _callService.endCallForAll(
          widget.call.callId, _connectedAt ?? DateTime.now());
    } else {
      await _callService.leaveCall(widget.call.callId);
    }

    _cleanup();
    if (mounted) Navigator.of(context).pop();
  }

  void _cleanup() {
    _callSub?.cancel();
    _controlsHideTimer?.cancel();
    _statsTimer?.cancel();
    try {
      _engine.leaveChannel();
      _engine.release();
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _setSpotlight(int? uid) {
    setState(() => _spotlightUid = uid);
  }

  // ── BUILD ──────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _hangUp();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: widget.call.isVideo ? _buildVideoUI() : _buildVoiceUI(),
      ),
    );
  }

  // ── Video Call UI ──────────────────────────────
  Widget _buildVideoUI() {
    return GestureDetector(
      onTap: _onTapScreen,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // 1. Video Grid / Spotlight / Waiting
          _remoteUids.isEmpty ? _buildWaitingScreen() : _buildVideoGrid(),

          // 2. Gradient overlays
          _buildGradients(),

          // 3. Top bar (group name, timer, participants count)
          if (_showControls) _buildVideoTopBar(),

          // 4. AI Shield (top-left)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 16,
            child: const AICallShield(),
          ),

          // 5. Call Quality Indicator (top-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            right: 16,
            child: CallQualityIndicator(stats: _stats),
          ),

          // 6. Participants panel (slide-in from right)
          if (_showParticipantsList) _buildParticipantsPanel(),

          // 7. Live Caption overlay
          if (_isLiveCaptionEnabled)
            Positioned(
              bottom: 140,
              left: 16,
              right: 16,
              child: const LiveCaptionOverlay(),
            ),

          // 8. Bottom controls
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildWaitingScreen() {
    return Container(
      color: const Color(0xFF1a1a2e),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 56,
              backgroundColor: Colors.blueGrey,
              child: Icon(Icons.group, size: 56, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(widget.call.groupName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Đang đợi mọi người tham gia...',
                style: TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 8),
            if (_connectedAt != null)
              CallTimerWidget(
                startTime: _connectedAt!,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoGrid() {
    if (!_engineInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    final allUids = _remoteUids.toList();

    if (_spotlightUid != null && allUids.contains(_spotlightUid)) {
      return _buildSpotlightLayout(allUids);
    }

    return _buildGridLayout(allUids);
  }

  Widget _buildSpotlightLayout(List<int> allUids) {
    final others = allUids.where((u) => u != _spotlightUid).toList();
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
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              _buildLocalThumbnail(),
              ...others.map((uid) => _buildRemoteThumbTile(uid)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridLayout(List<int> allUids) {
    final count = allUids.length;

    if (count == 1) {
      return Stack(
        children: [
          GestureDetector(
            onDoubleTap: () => _setSpotlight(allUids[0]),
            child: _buildRemoteVideoTile(allUids[0], big: true),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 110,
            right: 16,
            child: _buildLocalPip(),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count <= 2 ? 1 : 2,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: allUids.length + 1, // +1 for local tile
            itemBuilder: (_, i) {
              if (i == 0) return _buildLocalTile();
              final uid = allUids[i - 1];
              return GestureDetector(
                onDoubleTap: () => _setSpotlight(uid),
                child: _buildRemoteVideoTile(uid),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteVideoTile(int uid, {bool big = false}) {
    final participant = _callModel.participants
        .cast<GroupCallParticipant?>()
        .firstWhere((p) => p?.userId != null, orElse: () => null);

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(big ? 0 : 12),
          child: AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine,
              canvas: VideoCanvas(uid: uid),
              connection: RtcConnection(channelId: widget.call.channelName),
            ),
          ),
        ),
        if (participant?.isMuted == true)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.mic_off, color: Colors.white, size: 16),
            ),
          ),
        if (participant?.isCameraOff == true)
          Container(
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(big ? 0 : 12),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: big ? 40 : 24,
                    backgroundColor: Colors.blueGrey,
                    child: Icon(Icons.person,
                        color: Colors.white, size: big ? 40 : 24),
                  ),
                  if (participant?.userName != null) ...[
                    const SizedBox(height: 6),
                    Text(participant!.userName,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLocalTile() {
    return Stack(
      children: [
        _isCameraOff
            ? Container(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child:
                      Icon(Icons.videocam_off, color: Colors.white54, size: 40),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _engineInitialized
                    ? AgoraVideoView(
                        controller: VideoViewController(
                          rtcEngine: _engine,
                          canvas: const VideoCanvas(uid: 0),
                        ),
                      )
                    : Container(color: Colors.black54),
              ),
        if (_isMuted)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.mic_off, color: Colors.white, size: 16),
            ),
          ),
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(10)),
            child: const Text('Bạn',
                style: TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalPip() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 110,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 24,
                offset: const Offset(0, 10))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _isCameraOff
              ? Container(
                  color: Colors.blueGrey[900],
                  child: const Center(
                      child: Icon(Icons.videocam_off,
                          color: Colors.white54, size: 28)),
                )
              : (_engineInitialized
                  ? AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    )
                  : Container(color: Colors.black54)),
        ),
      ),
    );
  }

  Widget _buildLocalThumbnail() {
    return Container(
      width: 70,
      height: 90,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white38)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: _isCameraOff
            ? Container(
                color: Colors.blueGrey[900],
                child: const Center(
                    child: Icon(Icons.person, color: Colors.white54, size: 28)))
            : (_engineInitialized
                ? AgoraVideoView(
                    controller: VideoViewController(
                        rtcEngine: _engine, canvas: const VideoCanvas(uid: 0)))
                : Container(color: Colors.black54)),
      ),
    );
  }

  Widget _buildRemoteThumbTile(int uid) {
    return GestureDetector(
      onTap: () => _setSpotlight(uid),
      child: Container(
        width: 70,
        height: 90,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white38)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine,
              canvas: VideoCanvas(uid: uid),
              connection: RtcConnection(channelId: widget.call.channelName),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGradients() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: 220,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.85), Colors.transparent],
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
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withOpacity(0.2),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.call.groupName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          if (_connectedAt != null)
                            CallTimerWidget(
                              startTime: _connectedAt!,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(
                          () => _showParticipantsList = !_showParticipantsList),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          children: [
                            const Icon(Icons.people,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text('${_callModel.participants.length}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
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

  Widget _buildParticipantsPanel() {
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 260,
      child: GestureDetector(
        onTap: () {}, // absorb taps to prevent closing grid
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              color: Colors.black.withOpacity(0.75),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Text('Thành viên',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 20),
                            onPressed: () =>
                                setState(() => _showParticipantsList = false),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    Expanded(
                      child: ListView(
                        children: _callModel.participants.map((p) {
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundImage: p.userAvatar.isNotEmpty
                                  ? NetworkImage(p.userAvatar)
                                  : null,
                              backgroundColor: Colors.blueGrey,
                              child: p.userAvatar.isEmpty
                                  ? const Icon(Icons.person,
                                      color: Colors.white, size: 18)
                                  : null,
                            ),
                            title: Text(
                              p.userName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: p.isAdmin
                                ? const Text('Admin',
                                    style: TextStyle(
                                        color: Colors.amber, fontSize: 11))
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (p.isMuted)
                                  const Icon(Icons.mic_off,
                                      color: Colors.redAccent, size: 16),
                                if (p.isCameraOff && widget.call.isVideo)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(Icons.videocam_off,
                                        color: Colors.redAccent, size: 16),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
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

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Live Caption toggle (top-right of controls area)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 20, bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white24, width: 0.5),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isLiveCaptionEnabled
                            ? Icons.subtitles
                            : Icons.subtitles_off,
                        color: _isLiveCaptionEnabled
                            ? Colors.greenAccent
                            : Colors.white70,
                      ),
                      onPressed: _toggleLiveCaption,
                      tooltip: 'Live Caption AI',
                    ),
                  ),
                ],
              ),

              // Main control row + hang-up button
              Padding(
                padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _controlBtn(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          label: _isMuted ? 'Mở Mic' : 'Tắt Mic',
                          active: _isMuted,
                          onTap: _toggleMute,
                        ),
                        _controlBtn(
                          icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
                          label: _isSpeakerOn ? 'Loa ngoài' : 'Loa trong',
                          active: _isSpeakerOn,
                          onTap: _toggleSpeaker,
                        ),
                        if (widget.call.isVideo)
                          _controlBtn(
                            icon: _isCameraOff
                                ? Icons.videocam_off
                                : Icons.videocam,
                            label: _isCameraOff ? 'Mở Cam' : 'Tắt Cam',
                            active: _isCameraOff,
                            onTap: _toggleCamera,
                          ),
                        if (widget.call.isVideo)
                          _controlBtn(
                            icon: Icons.flip_camera_android,
                            label: 'Xoay',
                            active: false,
                            onTap: _switchCamera,
                          ),
                        _controlBtn(
                          icon: Icons.people,
                          label: 'Thành viên',
                          active: _showParticipantsList,
                          onTap: () => setState(() =>
                              _showParticipantsList = !_showParticipantsList),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _hangUp,
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFFE53935).withOpacity(0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 6))
                          ],
                        ),
                        child: const Icon(Icons.call_end,
                            color: Colors.white, size: 30),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withOpacity(0.3)
                  : Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── Voice Call UI ──────────────────────────────
  Widget _buildVoiceUI() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar: AI Shield + Quality Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AICallShield(),
                  const Spacer(),
                  CallQualityIndicator(stats: _stats),
                ],
              ),
            ),

            // Group name + timer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Text(widget.call.groupName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_connectedAt != null)
                    CallTimerWidget(
                      startTime: _connectedAt!,
                      style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),

            const Spacer(),

            // Participants grid
            _buildVoiceParticipantsGrid(),

            const Spacer(),

            // Live Caption overlay
            if (_isLiveCaptionEnabled)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: LiveCaptionOverlay(),
              ),

            // Live Caption toggle button
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(30),
              ),
              child: IconButton(
                icon: Icon(
                  _isLiveCaptionEnabled ? Icons.subtitles : Icons.subtitles_off,
                  color: _isLiveCaptionEnabled
                      ? Colors.greenAccent
                      : Colors.white70,
                ),
                onPressed: _toggleLiveCaption,
              ),
            ),

            // Control buttons
            _buildVoiceControls(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceParticipantsGrid() {
    final participants = _callModel.participants;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 24,
        runSpacing: 24,
        alignment: WrapAlignment.center,
        children: participants.map((p) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: p.isMuted
                            ? Colors.red.withOpacity(0.5)
                            : Colors.greenAccent.withOpacity(0.8),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundImage: p.userAvatar.isNotEmpty
                          ? NetworkImage(p.userAvatar)
                          : null,
                      backgroundColor: Colors.blueGrey,
                      child: p.userAvatar.isEmpty
                          ? const Icon(Icons.person,
                              size: 40, color: Colors.white)
                          : null,
                    ),
                  ),
                  if (p.isMuted)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.redAccent, shape: BoxShape.circle),
                        child: const Icon(Icons.mic_off,
                            size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                p.userId == widget.call.initiatorId ? 'Bạn' : p.userName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVoiceControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlBtn(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              label: _isMuted ? 'Mở Mic' : 'Tắt Mic',
              active: _isMuted,
              onTap: _toggleMute),

          // Hang-up button
          GestureDetector(
            onTap: _hangUp,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE53935),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFE53935).withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ],
              ),
              child: const Icon(Icons.call_end, color: Colors.white, size: 32),
            ),
          ),

          _controlBtn(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
              label: _isSpeakerOn ? 'Loa ngoài' : 'Loa trong',
              active: _isSpeakerOn,
              onTap: _toggleSpeaker),
        ],
      ),
    );
  }
}
