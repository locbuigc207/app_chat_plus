// lib/pages/group_call_page.dart
import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/group_call_model.dart';
import '../services/agora_rtc_manager.dart';
import '../services/group_call_service.dart';
import '../widgets/call_quality_indicator.dart';
import '../widgets/call_timer_widget.dart';

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
  // ── Services ─────────────────────────────────────────────────────
  final _callService = GroupCallService();
  late RtcEngine _engine;

  // ── State ─────────────────────────────────────────────────────────
  bool _engineInitialized = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _showControls = true;
  bool _callEnded = false;
  bool _isConnected = false;
  bool _showParticipantsList = false;

  // Agora remote UIDs
  final Set<int> _remoteUids = {};

  // Call metadata
  late GroupCallModel _callModel;
  DateTime? _connectedAt;

  // Streams
  StreamSubscription? _callSub;
  Timer? _controlsHideTimer;
  Timer? _statsTimer;

  // Stats
  RtcCallStats _stats = const RtcCallStats();

  // Selected speaker (for spotlight)
  int? _spotlightUid; // null = grid layout

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
  }

  // ─── Init Agora ────────────────────────────────────────────────────
  Future<void> _initCall() async {
    await _requestPermissions();
    await _initEngine();
    await _joinChannel();
  }

  Future<void> _requestPermissions() async {
    final perms = [Permission.microphone];
    if (widget.call.isVideo) perms.add(Permission.camera);
    await perms.request();
  }

  Future<void> _initEngine() async {
    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(
      appId: kAgoraAppId,
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
        // If all remote left and we're not the initiator, end
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

  // ─── Watch Firestore ───────────────────────────────────────────────
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
      const SnackBar(content: Text('Call ended'), duration: Duration(seconds: 2)),
    );
  }

  // ─── Controls ─────────────────────────────────────────────────────
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

  Future<void> _toggleMute() async {
    final next = !_isMuted;
    await _engine.muteLocalAudioStream(next);
    setState(() => _isMuted = next);
    await _callService.updateParticipantState(
        callId: widget.call.callId,
        isMuted: next,
        isCameraOff: _isCameraOff);
  }

  Future<void> _toggleCamera() async {
    if (!widget.call.isVideo) return;
    final next = !_isCameraOff;
    await _engine.muteLocalVideoStream(next);
    setState(() => _isCameraOff = next);
    await _callService.updateParticipantState(
        callId: widget.call.callId,
        isMuted: _isMuted,
        isCameraOff: next);
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

  // ─── Hang up ───────────────────────────────────────────────────────
  Future<void> _hangUp() async {
    if (_callEnded) return;
    _callEnded = true;

    if (widget.isInitiator) {
      // End for everyone
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

  // ─── Spotlight / Grid toggle ──────────────────────────────────────
  void _setSpotlight(int? uid) {
    setState(() => _spotlightUid = uid);
  }

  // ─── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _hangUp();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: widget.call.isVideo ? _buildVideoUI() : _buildVoiceUI(),
      ),
    );
  }

  // ─── Video UI ──────────────────────────────────────────────────────
  Widget _buildVideoUI() {
    return GestureDetector(
      onTap: _onTapScreen,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Main video area
          _remoteUids.isEmpty ? _buildWaitingScreen() : _buildVideoGrid(),

          // Gradient overlays
          _buildGradients(),

          // Top bar
          if (_showControls) _buildVideoTopBar(),

          // Quality indicator
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            right: 16,
            child: CallQualityIndicator(stats: _stats),
          ),

          // Participants panel
          if (_showParticipantsList) _buildParticipantsPanel(),

          // Bottom controls
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: _buildBottomControls(),
          ),
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
            CircleAvatar(
              radius: 56,
              backgroundImage: widget.call.groupName.isNotEmpty ? null : null,
              backgroundColor: Colors.blueGrey,
              child: const Icon(Icons.group, size: 56, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(widget.call.groupName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Waiting for others to join...',
                style: TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 8),
            if (_connectedAt != null)
              CallTimerWidget(
                startTime: _connectedAt!,
                style:
                const TextStyle(color: Colors.white54, fontSize: 14),
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

    // Spotlight mode: one big, rest small
    if (_spotlightUid != null && allUids.contains(_spotlightUid)) {
      return _buildSpotlightLayout(allUids);
    }

    // Grid layout
    return _buildGridLayout(allUids);
  }

  Widget _buildSpotlightLayout(List<int> allUids) {
    final others = allUids.where((u) => u != _spotlightUid).toList();
    return Column(
      children: [
        // Big spotlight view
        Expanded(
          flex: 3,
          child: GestureDetector(
            onDoubleTap: () => _setSpotlight(null),
            child: _buildRemoteVideoTile(_spotlightUid!, big: true),
          ),
        ),
        // Strip of others + local
        SizedBox(
          height: 110,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              _buildLocalThumbnail(),
              ...others.map(
                      (uid) => _buildRemoteThumbTile(uid)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridLayout(List<int> allUids) {
    // Up to 2x2 then scrollable
    final count = allUids.length;

    if (count == 1) {
      // 1 remote: remote full + local PIP
      return Stack(
        children: [
          GestureDetector(
            onDoubleTap: () => _setSpotlight(allUids[0]),
            child: _buildRemoteVideoTile(allUids[0], big: true),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            right: 16,
            child: _buildLocalPip(),
          ),
        ],
      );
    }

    // 2+ remotes: grid
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
            itemCount: allUids.length + 1, // +1 for local
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
        // Video
        ClipRRect(
          borderRadius: BorderRadius.circular(big ? 0 : 8),
          child: AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine,
              canvas: VideoCanvas(uid: uid),
              connection:
              RtcConnection(channelId: widget.call.channelName),
            ),
          ),
        ),
        // Muted indicator
        if (participant?.isMuted == true)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.mic_off, color: Colors.white, size: 16),
            ),
          ),
        // Camera off overlay
        if (participant?.isCameraOff == true)
          Container(
            color: Colors.black87,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: big ? 40 : 24,
                    backgroundColor: Colors.blueGrey,
                    child: Icon(Icons.person, color: Colors.white, size: big ? 40 : 24),
                  ),
                  if (participant?.userName != null) ...[
                    const SizedBox(height: 6),
                    Text(participant!.userName,
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
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
          color: Colors.black87,
          child: const Center(
            child: Icon(Icons.videocam_off, color: Colors.white54, size: 40),
          ),
        )
            : ClipRRect(
          borderRadius: BorderRadius.circular(8),
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
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.mic_off, color: Colors.white, size: 16),
            ),
          ),
        Positioned(
          bottom: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8)),
            child: const Text('You',
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
        width: 90,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white38)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: _isCameraOff
            ? Container(
            color: Colors.blueGrey[900],
            child: const Center(
                child: Icon(Icons.person, color: Colors.white54, size: 28)))
            : (_engineInitialized
            ? AgoraVideoView(
            controller: VideoViewController(
                rtcEngine: _engine,
                canvas: const VideoCanvas(uid: 0)))
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
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white38)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
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
              height: 130,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.65), Colors.transparent],
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
                  colors: [Colors.black.withOpacity(0.75), Colors.transparent],
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
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
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
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                  ],
                ),
              ),
              // Participants count
              GestureDetector(
                onTap: () => setState(
                        () => _showParticipantsList = !_showParticipantsList),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      const Icon(Icons.people, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text('${_callModel.participants.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ],
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
      width: 220,
      child: GestureDetector(
        onTap: () {}, // Consume taps
        child: Container(
          color: Colors.black.withOpacity(0.85),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Text('Participants',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () =>
                            setState(() => _showParticipantsList = false),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white24),
                Expanded(
                  child: ListView(
                    children: _callModel.participants.map((p) {
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundImage: p.userAvatar.isNotEmpty
                              ? NetworkImage(p.userAvatar)
                              : null,
                          backgroundColor: Colors.blueGrey,
                          child: p.userAvatar.isEmpty
                              ? const Icon(Icons.person, color: Colors.white, size: 18)
                              : null,
                        ),
                        title: Text(
                          p.userName,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: p.isAdmin
                            ? const Text('Admin',
                            style: TextStyle(color: Colors.amber, fontSize: 11))
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (p.isMuted)
                              const Icon(Icons.mic_off, color: Colors.red, size: 16),
                            if (p.isCameraOff && widget.call.isVideo)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.videocam_off,
                                    color: Colors.red, size: 16),
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
    );
  }

  // ─── Bottom Controls ───────────────────────────────────────────────
  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Secondary controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _controlBtn(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    active: _isMuted,
                    onTap: _toggleMute,
                  ),
                  _controlBtn(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
                    label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                    active: _isSpeakerOn,
                    onTap: _toggleSpeaker,
                  ),
                  if (widget.call.isVideo)
                    _controlBtn(
                      icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                      label: _isCameraOff ? 'Cam Off' : 'Camera',
                      active: _isCameraOff,
                      onTap: _toggleCamera,
                    ),
                  if (widget.call.isVideo)
                    _controlBtn(
                      icon: Icons.flip_camera_android,
                      label: 'Flip',
                      active: false,
                      onTap: _switchCamera,
                    ),
                  _controlBtn(
                    icon: Icons.people,
                    label: 'Members',
                    active: _showParticipantsList,
                    onTap: () => setState(
                            () => _showParticipantsList = !_showParticipantsList),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // End call
              GestureDetector(
                onTap: _hangUp,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFFE53935).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: const Icon(Icons.call_end, color: Colors.white, size: 28),
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
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withOpacity(0.25)
                  : Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label,
              style:
              TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11)),
        ],
      ),
    );
  }

  // ─── Voice-only UI ─────────────────────────────────────────────────
  Widget _buildVoiceUI() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFF1976D2)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.call.groupName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        if (_connectedAt != null)
                          CallTimerWidget(
                            startTime: _connectedAt!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                          ),
                      ],
                    ),
                  ),
                  CallQualityIndicator(stats: _stats),
                ],
              ),
            ),
            const Spacer(),
            // Participants circles
            _buildVoiceParticipantsGrid(),
            const Spacer(),
            // Controls
            _buildVoiceControls(),
            const SizedBox(height: 24),
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
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: participants.map((p) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundImage: p.userAvatar.isNotEmpty
                        ? NetworkImage(p.userAvatar)
                        : null,
                    backgroundColor: Colors.blueGrey,
                    child: p.userAvatar.isEmpty
                        ? const Icon(Icons.person, size: 36, color: Colors.white)
                        : null,
                  ),
                  if (p.isMuted)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.mic_off, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                p.userId == widget.call.initiatorId ? 'You' : p.userName,
                style: const TextStyle(color: Colors.white, fontSize: 12),
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
              label: _isMuted ? 'Unmute' : 'Mute',
              active: _isMuted,
              onTap: _toggleMute),
          // End call
          GestureDetector(
            onTap: _hangUp,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFE53935),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFE53935).withOpacity(0.4),
                      blurRadius: 12)
                ],
              ),
              child: const Icon(Icons.call_end, color: Colors.white, size: 28),
            ),
          ),
          _controlBtn(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.hearing,
              label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
              active: _isSpeakerOn,
              onTap: _toggleSpeaker),
        ],
      ),
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
    _cleanup();
    super.dispose();
  }
}