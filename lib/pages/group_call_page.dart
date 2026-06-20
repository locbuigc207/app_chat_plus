// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide AspectRatio;
import 'package:flutter/services.dart';
import 'package:flutter_chat_demo/models/models.dart';
import 'package:flutter_chat_demo/pages/pages.dart';
import 'package:flutter_chat_demo/providers/providers.dart';
import 'package:flutter_chat_demo/services/services.dart';
import 'package:flutter_chat_demo/widgets/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:simple_pip_mode/pip_widget.dart';
import 'package:simple_pip_mode/simple_pip.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
class _K {
  static const bg = Color(0xFF080E1C);
  static const surface = Color(0xFF111827);
  static const surface2 = Color(0xFF1C2333);
  static const surface3 = Color(0xFF242D3F);
  static const border = Color(0xFF1E2D40);
  static const accent = Color(0xFF3B82F6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const purple = Color(0xFF8B5CF6);
  static const speaking = Color(0xFF4ADE80);
  static const text = Color(0xFFF8FAFC);
  static const sub = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
}

// ─── Floating reaction ────────────────────────────────────────────────────────
class _FloatReaction {
  final String emoji;
  final String sender;
  final double x;
  final AnimationController ctrl;
  final Animation<double> opacity;
  final Animation<double> scale;
  final Animation<double> y;

  const _FloatReaction({
    required this.emoji,
    required this.sender,
    required this.x,
    required this.ctrl,
    required this.opacity,
    required this.scale,
    required this.y,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallPage v2 — Complete production-ready implementation
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallPage extends StatefulWidget {
  final GroupCallModel call;
  final bool isInitiator;
  final String currentUserId;
  final String currentUserName;
  final String currentUserAvatar;
  final bool isMiniMode;

  const GroupCallPage({
    super.key,
    required this.call,
    required this.isInitiator,
    required this.currentUserId,
    required this.currentUserName,
    this.currentUserAvatar = '',
    this.isMiniMode = false,
  });

  @override
  State<GroupCallPage> createState() => _GroupCallPageState();
}

class _GroupCallPageState extends State<GroupCallPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Services ──────────────────────────────────────────────────────────────
  final _svc = GroupCallService.instance;
  final _pip = SimplePip();
  late RtcEngine _engine;

  // ── Agora ─────────────────────────────────────────────────────────────────
  bool _engineReady = false;
  bool _joined = false;
  final Set<int> _remoteUids = {};
  final Map<int, bool> _audioMuted = {};
  final Map<int, bool> _videoMuted = {};
  final Map<int, int> _audioLevel = {};
  int? _activeSpeaker;

  // ── Local state ───────────────────────────────────────────────────────────
  bool _micMuted = false;
  bool _camOff = false;
  bool _speakerOn = true;
  bool _frontCam = true;
  bool _screenSharing = false;
  bool _handRaised = false;
  bool _callEnded = false;
  bool _statsExpanded = false;

  // ── UI panels ─────────────────────────────────────────────────────────────
  bool _showControls = true;
  bool _showParticipants = false;
  bool _showReactions = false;
  bool _showMoreMenu = false;
  bool _showChat = false;
  bool _showStatsPanel = false;
  bool _showCaptions = false;
  bool _showEndSummary = false;

  // ── Model / timing ────────────────────────────────────────────────────────
  late GroupCallModel _model;
  DateTime? _joinedAt;
  int? _spotUid; // local pinned uid (overrides server)
  bool _aiProtectionStarted = false;

  // ── States bổ sung ────────────────────────────────────────────────────────
  String? _recordingUrl;
  Map<CallReactionType, int> _reactionCounts = {};
  String? _recordingResourceId;
  String? _recordingSid;

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription? _callSub;
  Timer? _hideTimer;
  Timer? _speakerTimer;

  // ── Stats ─────────────────────────────────────────────────────────────────
  RtcCallStats _stats = const RtcCallStats();

  // ── Reactions ─────────────────────────────────────────────────────────────
  final List<_FloatReaction> _floatReactions = [];
  final Set<String> _seenRxKeys = {};
  final _rng = math.Random();

  // ── Participant join/leave toasts ─────────────────────────────────────────
  final List<({String name, String? avatar, bool joining})> _toasts = [];

  // ── Animations ────────────────────────────────────────────────────────────
  late AnimationController _ctrlsCtrl;
  late AnimationController _handCtrl;
  late AnimationController _recCtrl;
  late Animation<double> _ctrlsAnim;
  late Animation<double> _handAnim;
  late Animation<double> _recAnim;

  bool get _isAdmin =>
      _model.getParticipant(widget.currentUserId)?.isAdmin ?? false;
  bool get _isCoHost =>
      _model.getParticipant(widget.currentUserId)?.isCoHost ?? false;
  bool get _canModerate => _isAdmin || _isCoHost;

  // ── Init ──────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _model = widget.call;
    _joinedAt = DateTime.now();
    _setupAnims();
    _initCall();
    _watchFirestore();
    _schedHide();
  }

  void _setupAnims() {
    _ctrlsCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260), value: 1);
    _ctrlsAnim = CurvedAnimation(parent: _ctrlsCtrl, curve: Curves.easeOut);

    _handCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _handAnim = Tween<double>(begin: 0.86, end: 1.14).animate(_handCtrl);

    _recCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _recAnim = Tween<double>(begin: 0.4, end: 1.0).animate(_recCtrl);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_engineReady) _engine.muteLocalVideoStream(true);
    } else if (state == AppLifecycleState.resumed) {
      if (_engineReady && !_camOff && !_screenSharing) {
        _engine.muteLocalVideoStream(false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealtimeAIService().stopProtection();
    _ctrlsCtrl.dispose();
    _handCtrl.dispose();
    _recCtrl.dispose();
    for (final r in _floatReactions) r.ctrl.dispose();
    _cleanup();
    super.dispose();
  }

  // ── Agora init ────────────────────────────────────────────────────────────
  Future<void> _initCall() async {
    // FIX BUG 2: Bọc toàn bộ khởi tạo vào khối Try-Catch
    try {
      await _requestPerms();
      await _buildEngine();
      await _joinChannel();
    } catch (e) {
      debugPrint('❌ [GroupCallPage] Init error: $e');
      if (mounted) {
        // Hiển thị Dialog báo lỗi thay vì màn hình đen
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: _K.surface2,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: _K.red),
                SizedBox(width: 8),
                Text('Lỗi kết nối',
                    style: TextStyle(color: _K.text, fontSize: 18)),
              ],
            ),
            content: Text(
              e.toString().replaceAll('Exception: ', ''),
              style: const TextStyle(color: _K.sub, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  _callEnded = true;
                  if (widget.isInitiator) {
                    await _svc.endCallForAll(widget.call.callId,
                        startTime: _joinedAt);
                  } else {
                    await _svc.leaveCall(widget.call.callId);
                  }
                  _cleanup();
                  if (mounted) Navigator.pop(context);
                },
                child:
                const Text('Quay lại', style: TextStyle(color: _K.accent)),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _requestPerms() async {
    if (kIsWeb) return;
    final p = [Permission.microphone];
    if (widget.call.isVideo) p.add(Permission.camera);
    await p.request();
  }

  Future<void> _buildEngine() async {
    final appId = dotenv.env['AGORA_APP_ID'] ?? '';
    // FIX BUG 2: Kiểm tra cấu hình App ID
    if (appId.isEmpty) {
      throw Exception(
          'AGORA_APP_ID chưa được cấu hình trong file .env. Không thể khởi tạo cuộc gọi.');
    }

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (_, __) {
        if (mounted) setState(() => _joined = true);
      },
      onUserJoined: (_, uid, __) {
        if (!mounted) return;
        setState(() => _remoteUids.add(uid));
        _startAIProtection();
        _showJoinToast(uid);
      },
      onUserOffline: (_, uid, reason) {
        if (!mounted) return;
        setState(() {
          _remoteUids.remove(uid);
          _audioMuted.remove(uid);
          _videoMuted.remove(uid);
          _audioLevel.remove(uid);
          if (_spotUid == uid) _spotUid = null;
          if (_activeSpeaker == uid) _activeSpeaker = null;
        });
        _showLeaveToast(uid);
        if (_remoteUids.isEmpty && !widget.isInitiator && mounted) _hangUp();
      },
      onRemoteAudioStateChanged: (_, uid, state, __, ___) {
        if (mounted)
          setState(() {
            _audioMuted[uid] =
                state == RemoteAudioState.remoteAudioStateStopped;
          });
      },
      onRemoteVideoStateChanged: (_, uid, state, __, ___) {
        if (mounted)
          setState(() {
            _videoMuted[uid] =
                state == RemoteVideoState.remoteVideoStateStopped;
          });
      },
      onActiveSpeaker: (_, uid) {
        if (!mounted) return;
        setState(() => _activeSpeaker = uid);
        _speakerTimer?.cancel();
        _speakerTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _activeSpeaker = null);
        });
      },
      onAudioVolumeIndication: (_, speakers, __, ___) {
        if (!mounted) return;
        for (final s in speakers) {
          if (s.uid != null)
            setState(() => _audioLevel[s.uid!] = s.volume ?? 0);
        }
      },
      onRtcStats: (_, s) {
        if (mounted)
          setState(() => _stats = RtcCallStats(
            txBitrate: s.txKBitRate ?? 0,
            rxBitrate: s.rxKBitRate ?? 0,
            txPacketLoss: s.txPacketLossRate ?? 0,
            rxPacketLoss: s.rxPacketLossRate ?? 0,
            rtt: s.lastmileDelay ?? 0,
            duration: s.duration ?? 0,
          ));
      },
      onError: (err, msg) => debugPrint('❌ Agora[$err]: $msg'),
    ));

    if (widget.call.isVideo) {
      await _engine.enableVideo();
      await _engine.startPreview();
      await _engine
          .setVideoEncoderConfiguration(const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 1280, height: 720),
        frameRate: 30,
        bitrate: 1500,
      ));
    }
    await _engine.enableAudio();

    // SỬA LỖI 2A TẠI ĐÂY: Bọc setEnableSpeakerphone vào try-catch
    try {
      await _engine.setEnableSpeakerphone(true);
    } catch (e) {
      debugPrint(
          '⚠️ setEnableSpeakerphone before join: $e (sẽ retry sau join)');
    }

    await _engine.enableAudioVolumeIndication(
        interval: 300, smooth: 3, reportVad: true);

    // =========================================================================
    // 💡 TÍCH HỢP DEEPFAKE DETECTION CHO NHÓM TẠI ĐÂY
    // =========================================================================
    try {
      await _engine.setRecordingAudioFrameParameters(
        sampleRate: 16000,
        channel: 1,
        mode: RawAudioFrameOpModeType.rawAudioFrameOpModeReadOnly,
        // Đã sửa lại samplesPerCall từ 1024 thành 2048 để AI AudioFeatureExtractor hoạt động (Cần tối thiểu 2048 samples)
        samplesPerCall: 2048,
      );

      _engine.getMediaEngine().registerAudioFrameObserver(
        AudioFrameObserver(
          onRecordAudioFrame: (String channelId, AudioFrame audioFrame) {
            if (audioFrame.buffer != null) {
              try {
                final bytes = audioFrame.buffer!;
                final pcm16Data = Int16List.view(
                  bytes.buffer,
                  bytes.offsetInBytes,
                  bytes.lengthInBytes ~/ 2,
                );
                RealtimeAIService().feedAudioBuffer(pcm16Data);
              } catch (e) {
                debugPrint(
                    '[Deepfake] Lỗi khi xử lý Audio Frame Group: $e');
              }
            }
          },
          onPlaybackAudioFrame:
              (String channelId, AudioFrame audioFrame) {},
          onMixedAudioFrame: (String channelId, AudioFrame audioFrame) {},
          onEarMonitoringAudioFrame: (AudioFrame audioFrame) {},
          onPlaybackAudioFrameBeforeMixing:
              (String channelId, int uid, AudioFrame audioFrame) {},
        ),
      );
      debugPrint('✅ [Agora] Đã đăng ký AudioFrameObserver (Group Call)');
    } catch (e) {
      debugPrint('❌ [Agora] Không thể đăng ký AudioFrameObserver (Group): $e');
    }
    // =========================================================================

    setState(() => _engineReady = true);
  }

  Future<void> _joinChannel() async {
    // Lấy token từ server thay vì để trống
    String token = '';
    try {
      final tokenServer = dotenv.env['AGORA_TOKEN_SERVER'] ?? '';
      if (tokenServer.isNotEmpty) {
        // SỬA LỖI 2B TẠI ĐÂY: Sử dụng đúng định dạng Query String `?channelName=X&uid=0`
        final uri = Uri.parse(
            '$tokenServer?channelName=${widget.call.channelName}&uid=0');
        final resp = await HttpClient().getUrl(uri);
        final response = await resp.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        token = data['rtcToken'] as String? ?? data['token'] as String? ?? '';
      }
    } catch (e) {
      debugPrint('⚠️ Token fetch: $e');
    }

    // FIX BUG 2: Bắt lỗi nếu Token bị rỗng để tránh kẹt mãi ở màn hình Loading
    if (token.isEmpty) {
      throw Exception(
          'Lỗi Token rỗng. Nếu Agora Console đang bật "App Certificate", vui lòng kiểm tra lại biến môi trường AGORA_TOKEN_SERVER của bạn.');
    }

    await _engine.joinChannel(
      token: token,
      channelId: widget.call.channelName,
      uid: 0,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishCameraTrack: widget.call.isVideo && !_camOff,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
        autoSubscribeVideo: widget.call.isVideo,
      ),
    );
  }

  void _startAIProtection() {
    if (_aiProtectionStarted) return;
    _aiProtectionStarted = true;
    RealtimeAIService().startProtection(
        'GROUP_${widget.call.callId}', widget.call.channelName);
  }

  // ── Firestore watch ───────────────────────────────────────────────────────
  void _watchFirestore() {
    _callSub = _svc.watchCall(widget.call.callId).listen((call) {
      if (call == null || _callEnded) return;
      if (mounted) setState(() => _model = call);
      if (call.isEnded) _handleRemoteEnd();

      // Aggregate reaction counts
      final counts = <CallReactionType, int>{};
      for (final r in call.recentReactions) {
        counts[r.type] = (counts[r.type] ?? 0) + 1;
      }
      if (mounted) setState(() => _reactionCounts = counts);

      // Reactions animation
      for (final r in call.recentReactions) {
        final key = '${r.userId}_${r.sentAt.millisecondsSinceEpoch}';
        if (!_seenRxKeys.contains(key) &&
            r.sentAt
                .isAfter(DateTime.now().subtract(const Duration(seconds: 5)))) {
          _seenRxKeys.add(key);
          _spawnReaction(r.type.emoji, r.userName);
        }
      }
    });
  }

  void _handleRemoteEnd() {
    if (_callEnded) return;
    _callEnded = true;
    _cleanup();
    if (mounted) {
      GroupCallEndSummary.show(
        context,
        call: _model,
        startTime: _joinedAt ?? DateTime.now(),
        wasHost: widget.isInitiator,
        recordingUrl: _recordingUrl,
        reactionCounts: _reactionCounts,
        onClose: () {
          Navigator.of(context)
            ..pop()
            ..pop();
        },
      );
    }
  }

  // ── Controls hide timer ───────────────────────────────────────────────────
  void _schedHide() {
    _hideTimer?.cancel();
    if (widget.call.isVideo) {
      _hideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted &&
            _joined &&
            !_showReactions &&
            !_showMoreMenu &&
            !_showChat) {
          _ctrlsCtrl.reverse();
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _onTap() {
    if (!widget.call.isVideo) return;
    setState(() {
      _showControls = true;
      _showReactions = false;
      _showMoreMenu = false;
    });
    _ctrlsCtrl.forward();
    _schedHide();
  }

  // ── Agora controls ────────────────────────────────────────────────────────
  Future<void> _toggleMic() async {
    final next = !_micMuted;
    await _engine.muteLocalAudioStream(next);
    setState(() => _micMuted = next);
    await _svc.updateParticipantState(
      callId: widget.call.callId,
      userId: widget.currentUserId,
      isMuted: next,
      isCameraOff: _camOff,
    );
    HapticFeedback.lightImpact();
  }

  Future<void> _toggleCam() async {
    if (!widget.call.isVideo) return;
    final next = !_camOff;
    await _engine.muteLocalVideoStream(next);
    setState(() => _camOff = next);
    await _svc.updateParticipantState(
      callId: widget.call.callId,
      userId: widget.currentUserId,
      isMuted: _micMuted,
      isCameraOff: next,
    );
    HapticFeedback.lightImpact();
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    await _engine.setEnableSpeakerphone(next);
    setState(() => _speakerOn = next);
    _toast(next ? '🔊 Loa ngoài' : '🎧 Tai nghe');
  }

  Future<void> _flipCamera() async {
    if (_camOff) return;
    await _engine.switchCamera();
    setState(() => _frontCam = !_frontCam);
    HapticFeedback.selectionClick();
  }

  Future<void> _toggleHand() async {
    final next = !_handRaised;
    setState(() => _handRaised = next);
    await _svc.toggleRaiseHand(
        callId: widget.call.callId, userId: widget.currentUserId, raised: next);
    _toast(next ? '✋ Đã giơ tay' : 'Đã hạ tay');
  }

  Future<void> _toggleScreen() async {
    final next = !_screenSharing;
    setState(() => _screenSharing = next);
    if (next) {
      await _engine.startScreenCapture(const ScreenCaptureParameters2(
          captureAudio: true, captureVideo: true));
    } else {
      await _engine.stopScreenCapture();
    }
    await _svc.updateScreenShare(
        callId: widget.call.callId,
        userId: widget.currentUserId,
        isSharing: next);
    _toast(next ? '📺 Đang chia sẻ màn hình' : 'Đã dừng chia sẻ');
  }

  Future<void> _toggleRecording() async {
    if (!_canModerate) return;
    HapticFeedback.mediumImpact();

    try {
      final provider = context.read<GroupCallProvider>();
      await provider.toggleRecording(
        channelName: widget.call.channelName,
        agoraUid: '0',
      );
      _toast(_model.isRecording ? '⏹ Đã dừng ghi âm' : '🔴 Bắt đầu ghi âm');
    } catch (e) {
      _toast('Lỗi recording: $e');
    }
  }

  void _sendReaction(CallReactionType type) {
    setState(() {
      _showReactions = false;
      _showMoreMenu = false;
    });
    _svc.sendReaction(
        callId: widget.call.callId,
        userId: widget.currentUserId,
        userName: widget.currentUserName,
        reaction: type);
    _spawnReaction(type.emoji, 'Bạn');
    _schedHide();
  }

  Future<void> _hangUp() async {
    if (_callEnded) return;

    // Hiện dialog xác nhận nếu là host và có participants
    if (widget.isInitiator && _model.participantCount > 1 && mounted) {
      await CallEndConfirmDialog.show(
        context,
        isHost: true,
        participantCount: _model.participantCount,
        onLeaveOnly: () {
          Navigator.pop(context);
          _doHangUp(endForAll: false);
        },
        onEndForAll: () {
          Navigator.pop(context);
          _doHangUp(endForAll: true);
        },
        onCancel: () => Navigator.pop(context),
      );
      return;
    }
    _doHangUp(endForAll: widget.isInitiator);
  }

  Future<void> _doHangUp({required bool endForAll}) async {
    if (_callEnded) return;
    _callEnded = true;
    HapticFeedback.mediumImpact();

    if (endForAll) {
      await _svc.endCallForAll(widget.call.callId, startTime: _joinedAt);
    } else {
      await _svc.leaveCall(widget.call.callId);
    }

    // Dismiss mini widget nếu đang hiển thị
    try {
      GroupCallMiniManager.of(context)?.dismiss();
    } catch (_) {}

    _cleanup();

    // Hiện post-call summary thay vì pop ngay
    if (mounted) {
      GroupCallEndSummary.show(
        context,
        call: _model,
        startTime: _joinedAt ?? DateTime.now(),
        wasHost: widget.isInitiator,
        recordingUrl: _recordingUrl,
        reactionCounts: _reactionCounts,
        onClose: () {
          Navigator.of(context)
            ..pop() // close summary sheet
            ..pop(); // exit call page
        },
      );
    }
  }

  void _cleanup() {
    _callSub?.cancel();
    _hideTimer?.cancel();
    _speakerTimer?.cancel();

    // Giải phóng AudioFrameObserver tránh leak
    try {
      _engine.getMediaEngine().registerAudioFrameObserver(
        AudioFrameObserver(
          onRecordAudioFrame: (String channelId, AudioFrame audioFrame) {},
          onPlaybackAudioFrame:
              (String channelId, AudioFrame audioFrame) {},
          onMixedAudioFrame: (String channelId, AudioFrame audioFrame) {},
          onEarMonitoringAudioFrame: (AudioFrame audioFrame) {},
          onPlaybackAudioFrameBeforeMixing:
              (String channelId, int uid, AudioFrame audioFrame) {},
        ),
      );
    } catch (_) {}

    try {
      _engine.leaveChannel();
      _engine.release();
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ── Reaction animation ────────────────────────────────────────────────────
  void _spawnReaction(String emoji, String sender) {
    if (!mounted) return;
    final x = 0.06 + _rng.nextDouble() * 0.88;
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800));

    final opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 62),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 28),
    ]).animate(ctrl);

    final scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.2, end: 1.3)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 22),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 8),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9), weight: 70),
    ]).animate(ctrl);

    final y = Tween<double>(begin: 0, end: -240)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOutCubic));

    final r = _FloatReaction(
        emoji: emoji,
        sender: sender,
        x: x,
        ctrl: ctrl,
        opacity: opacity,
        scale: scale,
        y: y);
    setState(() => _floatReactions.add(r));
    ctrl.forward().then((_) {
      if (mounted) {
        setState(() => _floatReactions.remove(r));
        r.ctrl.dispose();
      }
    });
  }

  // ── Join/Leave toasts ─────────────────────────────────────────────────────
  void _showJoinToast(int uid) {
    final p = _model.participants.firstWhere(
            (x) => x.userId.hashCode.abs() % 100000 == uid % 100000,
        orElse: () => GroupCallParticipant(
            userId: '$uid',
            userName: 'Người dùng',
            userAvatar: '',
            joinedAt: DateTime.now(),
            isAdmin: false));
    _addToast(p.userName, p.userAvatar, true);
  }

  void _showLeaveToast(int uid) {
    final p = _model.participants.firstWhere(
            (x) => x.userId.hashCode.abs() % 100000 == uid % 100000,
        orElse: () => GroupCallParticipant(
            userId: '$uid',
            userName: 'Người dùng',
            userAvatar: '',
            joinedAt: DateTime.now(),
            isAdmin: false));
    _addToast(p.userName, p.userAvatar, false);
  }

  void _addToast(String name, String avatar, bool joining) {
    if (!mounted) return;
    setState(() => _toasts.add((
    name: name,
    avatar: avatar.isNotEmpty ? avatar : null,
    joining: joining
    )));
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toasts.isNotEmpty) setState(() => _toasts.removeAt(0));
    });
  }

  void _toast(String msg) => Fluttertoast.showToast(
      msg: msg,
      backgroundColor: _K.surface2,
      textColor: _K.text,
      fontSize: 13,
      gravity: ToastGravity.TOP,
      toastLength: Toast.LENGTH_SHORT);

  Future<void> _enterPip() async {
    final ok = await SimplePip.isPipAvailable;
    if (ok) {
      // Replaced [3, 4] with (3, 4)
      await _pip.enterPipMode(aspectRatio: (3, 4));
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (widget.call.isVideo) {
      return PipWidget(
        pipBuilder: (_) => _buildPip(),
        builder: (_) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (d, _) async {
            if (!d) await _enterPip();
          },
          child: Scaffold(backgroundColor: _K.bg, body: _buildVideoUI()),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (d, _) async {
        if (!d) await _hangUp();
      },
      child: Scaffold(backgroundColor: _K.bg, body: _buildVoiceUI()),
    );
  }

  // ── PiP ───────────────────────────────────────────────────────────────────
  Widget _buildPip() {
    if (!_engineReady)
      return const ColoredBox(
          color: _K.bg,
          child: Center(
              child: CircularProgressIndicator(
                  color: Colors.white24, strokeWidth: 2)));
    final uid = _spotUid ?? (_remoteUids.isNotEmpty ? _remoteUids.first : null);
    if (uid == null) {
      return Container(
          color: _K.bg,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.group_rounded, color: Colors.white24, size: 30),
              const SizedBox(height: 6),
              Text(widget.call.groupName,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  textAlign: TextAlign.center),
            ],
          ));
    }
    return AgoraVideoView(
        controller: VideoViewController.remote(
            rtcEngine: _engine,
            canvas: VideoCanvas(uid: uid),
            connection: RtcConnection(channelId: widget.call.channelName)));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VIDEO UI
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildVideoUI() {
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(fit: StackFit.expand, children: [
        // Grid / waiting
        _remoteUids.isEmpty ? _buildWaiting() : _buildGrid(),

        // Gradients
        _buildGrads(),

        // Screen share toolbar (khi đang share)
        if (_screenSharing)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 0,
            right: 0,
            child: Center(
              child: ScreenShareToolbar(
                viewerCount: _remoteUids.length,
                onStop: _toggleScreen,
              ),
            ),
          ),

        // Screen share viewer banner (khi người khác đang share)
        if (!_screenSharing &&
            _model.screenShareUserId != null &&
            _model.screenShareUserId != widget.currentUserId)
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 12,
            child: () {
              final sharer = _model.getParticipant(_model.screenShareUserId!);
              return ScreenShareViewerBanner(
                sharerName: sharer?.userName ?? 'Ai đó',
                sharerAvatar: sharer?.userAvatar,
                onPinTap: () {
                  // Pin the sharer's uid
                  final uid = _remoteUids.firstWhere(
                          (u) => u
                          .toString()
                          .contains(_model.screenShareUserId!.substring(0, 4)),
                      orElse: () => -1);
                  if (uid > 0) setState(() => _spotUid = uid);
                },
              );
            }(),
          ),

        // Floating reactions
        ..._floatReactions.map(_buildFloatRx),

        // Reaction picker
        if (_showReactions) _buildRxPicker(),

        // More menu
        if (_showMoreMenu) _buildMoreMenu(),

        // Top bar
        FadeTransition(opacity: _ctrlsAnim, child: _buildTopBar()),

        // AI Shield & Deepfake Status (top-left)
        Positioned(
          top: MediaQuery.of(context).padding.top + 66,
          left: 12,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AICallShield(alignRight: false),
              SizedBox(height: 8),
              DeepfakeStatusBadge(),
            ],
          ),
        ),

        // Stats (top-right)
        Positioned(
          top: MediaQuery.of(context).padding.top + 66,
          right: 12,
          child: GestureDetector(
            onTap: () => setState(() => _statsExpanded = !_statsExpanded),
            child: GroupCallStatsOverlay(
              stats: _stats,
              isExpanded: _statsExpanded,
              onToggle: () => setState(() => _statsExpanded = !_statsExpanded),
            ),
          ),
        ),

        // Recording badge
        if (_model.isRecording)
          Positioned(
              top: MediaQuery.of(context).padding.top + 66,
              left: 0,
              right: 0,
              child: Center(child: _buildRecBadge())),

        // Raised hand badge
        if (_handRaised)
          Positioned(
              top: MediaQuery.of(context).padding.top + 132,
              left: 0,
              right: 0,
              child: Center(child: _buildHandBadge())),

        // Raise hand queue (admin sees who raised hand)
        if (_model.raisedHandUserIds.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).padding.top + 160,
            left: 12,
            child: RaiseHandQueuePanel(
              call: _model,
              currentUserId: widget.currentUserId,
              isAdmin: _canModerate,
            ),
          ),

        // Participants panel
        if (_showParticipants) _buildParticipantsPanel(),

        // Chat panel
        if (_showChat)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: GroupCallChatPanel(
              callId: widget.call.callId,
              currentUserId: widget.currentUserId,
              currentUserName: widget.currentUserName,
              currentUserAvatar: widget.currentUserAvatar,
              onClose: () => setState(() => _showChat = false),
            ),
          ),

        // Live captions
        if (_showCaptions)
          const Positioned(
              bottom: 164, left: 16, right: 16, child: LiveCaptionOverlay()),

        // Join/leave toasts
        Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            left: 12,
            right: 12,
            child: _buildToasts()),

        // Bottom controls
        FadeTransition(opacity: _ctrlsAnim, child: _buildBottomCtrl()),
      ]),
    );
  }

  // ── Waiting screen ────────────────────────────────────────────────────────
  Widget _buildWaiting() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.5,
            colors: [Color(0xFF162240), Color(0xFF060A14)]),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _avatarWidget(58),
        const SizedBox(height: 22),
        Text(widget.call.groupName,
            style: const TextStyle(
                color: _K.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4)),
        const SizedBox(height: 10),
        _PulsingDots(color: _K.accent),
        const SizedBox(height: 6),
        const Text('Đang chờ mọi người tham gia…',
            style: TextStyle(color: _K.sub, fontSize: 14)),
        const SizedBox(height: 18),
        if (_joinedAt != null)
          CallTimerWidget(
              startTime: _joinedAt!,
              showPulse: true,
              style: const TextStyle(
                  color: _K.muted, fontSize: 14, letterSpacing: 1.1)),
      ]),
    );
  }

  // ── Video grid ────────────────────────────────────────────────────────────
  Widget _buildGrid() {
    if (!_engineReady)
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    final uids = _remoteUids.toList();
    final pinned = _spotUid;
    if (pinned != null && uids.contains(pinned))
      return _buildSpotlight(uids, pinned);
    return _buildAdaptive(uids);
  }

  Widget _buildSpotlight(List<int> all, int spot) {
    final others = all.where((u) => u != spot).toList();
    return Column(children: [
      Expanded(
          flex: 3,
          child: GestureDetector(
              onDoubleTap: () => setState(() => _spotUid = null),
              child: _remoteTile(spot, big: true))),
      SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [_localThumb(), ...others.map(_remoteThumb)],
          )),
    ]);
  }

  Widget _buildAdaptive(List<int> uids) {
    final n = uids.length;
    if (n == 1) {
      return Stack(fit: StackFit.expand, children: [
        GestureDetector(
            onDoubleTap: () => setState(() => _spotUid = uids[0]),
            child: _remoteTile(uids[0], big: true)),
        Positioned(
            top: MediaQuery.of(context).padding.top + 112,
            right: 12,
            child: _localPip()),
      ]);
    }
    final cols = n <= 2 ? 1 : (n <= 4 ? 2 : 3);
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          childAspectRatio: cols == 1 ? 0.75 : 0.9),
      itemCount: uids.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return _localGridTile();
        final uid = uids[i - 1];
        return GestureDetector(
            onDoubleTap: () => setState(() => _spotUid = uid),
            child: _remoteTile(uid));
      },
    );
  }

  // ── Remote tile ───────────────────────────────────────────────────────────
  Widget _remoteTile(int uid, {bool big = false}) {
    final videoOff = _videoMuted[uid] ?? false;
    final audioOff = _audioMuted[uid] ?? false;
    final speaking = _activeSpeaker == uid;
    final level = (_audioLevel[uid] ?? 0) / 255.0;
    final p = _model.participants.cast<GroupCallParticipant?>().firstWhere(
            (x) => x != null && x.userId.hashCode.abs() % 100000 == uid % 100000,
        orElse: () => null);

    return Stack(fit: StackFit.expand, children: [
      // Video / avatar
      ClipRRect(
          borderRadius: BorderRadius.circular(big ? 0 : 12),
          child: videoOff
              ? _videoOffHolder(
              name: p?.userName,
              avatar: p?.userAvatar,
              big: big,
              speaking: speaking)
              : AgoraVideoView(
              controller: VideoViewController.remote(
                  rtcEngine: _engine,
                  canvas: VideoCanvas(uid: uid),
                  connection:
                  RtcConnection(channelId: widget.call.channelName)))),

      // Speaking border
      if (speaking && !videoOff)
        Positioned.fill(
            child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(big ? 0 : 12),
                      border: Border.all(color: _K.speaking, width: 2.5)),
                ))),

      // Audio level bar
      if (speaking && level > 0.05)
        Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(big ? 0 : 12),
                  bottomRight: Radius.circular(big ? 0 : 12)),
              child: LinearProgressIndicator(
                  value: level,
                  minHeight: 2.5,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation(_K.speaking)),
            )),

      // Status icons
      Positioned(
          bottom: 8,
          left: 8,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (audioOff) _badge(Icons.mic_off_rounded, _K.red),
            if (videoOff) ...[
              const SizedBox(width: 3),
              _badge(Icons.videocam_off_rounded, const Color(0xFFFF9F0A))
            ],
            if (p?.isScreenSharing ?? false) ...[
              const SizedBox(width: 3),
              _badge(Icons.screen_share_rounded, _K.accent)
            ],
          ])),

      // Name
      if (p != null)
        Positioned(
            bottom: 8,
            right: 8,
            child: _nameBadge(p.userName, p.isAdmin, p.isCoHost)),

      // Raised hand
      if (p != null && _model.hasRaisedHand(p.userId))
        Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: _K.amber,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: _K.amber.withOpacity(0.4), blurRadius: 8)
                  ]),
              child: const Text('✋', style: TextStyle(fontSize: 13)),
            )),

      // Network quality dots
      if (p != null)
        Positioned(top: 8, left: 8, child: _NetDots(quality: p.networkQuality)),
    ]);
  }

  Widget _videoOffHolder(
      {String? name, String? avatar, bool big = false, bool speaking = false}) {
    final r = big ? 44.0 : 28.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: const Color(0xFF0D1524),
      child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color:
                        speaking ? _K.speaking : Colors.white.withOpacity(0.1),
                        width: speaking ? 2.5 : 1.5),
                    boxShadow: speaking
                        ? [
                      BoxShadow(
                          color: _K.speaking.withOpacity(0.4),
                          blurRadius: 16,
                          spreadRadius: 2)
                    ]
                        : null),
                child: CircleAvatar(
                    radius: r,
                    backgroundImage: (avatar?.isNotEmpty ?? false)
                        ? NetworkImage(avatar!)
                        : null,
                    backgroundColor: _K.surface2,
                    child: (avatar?.isNotEmpty ?? false)
                        ? null
                        : Icon(Icons.person, size: r, color: _K.muted))),
            if (name != null) ...[
              const SizedBox(height: 8),
              Text(name, style: const TextStyle(color: _K.sub, fontSize: 12))
            ],
          ])),
    );
  }

  // ── Local widgets ─────────────────────────────────────────────────────────
  Widget _localGridTile() => Stack(fit: StackFit.expand, children: [
    ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _camOff
            ? Container(
            color: const Color(0xFF0D1524),
            child: const Center(
                child: Icon(Icons.videocam_off_rounded,
                    color: _K.muted, size: 34)))
            : (_engineReady
            ? AgoraVideoView(
            controller: VideoViewController(
                rtcEngine: _engine,
                canvas: const VideoCanvas(uid: 0)))
            : Container(color: _K.bg))),
    if (_micMuted)
      Positioned(
          bottom: 8, left: 8, child: _badge(Icons.mic_off_rounded, _K.red)),
    Positioned(bottom: 8, right: 8, child: _nameBadge('Bạn', false, false)),
  ]);

  Widget _localPip() => Container(
    width: 100,
    height: 148,
    decoration: BoxDecoration(
        color: _K.bg,
        borderRadius: BorderRadius.circular(14),
        border:
        Border.all(color: Colors.white.withOpacity(0.18), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ]),
    child: ClipRRect(
        borderRadius: BorderRadius.circular(12.5),
        child: _camOff
            ? Container(
            color: const Color(0xFF0D1524),
            child: const Center(
                child: Icon(Icons.videocam_off_rounded,
                    color: _K.muted, size: 24)))
            : (_engineReady
            ? AgoraVideoView(
            controller: VideoViewController(
                rtcEngine: _engine,
                canvas: const VideoCanvas(uid: 0)))
            : Container(color: _K.bg))),
  );

  Widget _localThumb() => _thumbWrap(
      child: _camOff
          ? Container(
          color: const Color(0xFF0D1524),
          child: const Center(
              child: Icon(Icons.person, color: _K.muted, size: 20)))
          : (_engineReady
          ? AgoraVideoView(
          controller: VideoViewController(
              rtcEngine: _engine, canvas: const VideoCanvas(uid: 0)))
          : Container(color: _K.bg)));

  Widget _remoteThumb(int uid) => GestureDetector(
    onTap: () => setState(() => _spotUid = uid),
    child: _thumbWrap(
        child: AgoraVideoView(
            controller: VideoViewController.remote(
                rtcEngine: _engine,
                canvas: VideoCanvas(uid: uid),
                connection:
                RtcConnection(channelId: widget.call.channelName)))),
  );

  Widget _thumbWrap({required Widget child}) => Container(
    width: 66,
    height: 92,
    margin: const EdgeInsets.only(right: 6),
    decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.12))),
    child: ClipRRect(borderRadius: BorderRadius.circular(9), child: child),
  );

  // ── Badges ────────────────────────────────────────────────────────────────
  Widget _badge(IconData icon, Color color) => Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4), width: 0.5)),
      child: Icon(icon, color: color, size: 12));

  Widget _nameBadge(String name, bool isAdmin, bool isCoHost) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.62),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isAdmin
                  ? _K.amber.withOpacity(0.4)
                  : Colors.white.withOpacity(0.08),
              width: 0.5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isAdmin || isCoHost)
          Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(isAdmin ? Icons.star_rounded : Icons.shield_rounded,
                  size: 9, color: isAdmin ? _K.amber : _K.accent)),
        Text(name,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500)),
      ]));

  Widget _buildRecBadge() => AnimatedBuilder(
      animation: _recAnim,
      builder: (_, child) =>
          Opacity(opacity: 0.7 + _recAnim.value * 0.3, child: child),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
              color: _K.red.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: _K.red.withOpacity(0.45), blurRadius: 10)
              ]),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.fiber_manual_record_rounded,
                color: Colors.white, size: 9),
            SizedBox(width: 4),
            Text('REC',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
          ])));

  Widget _buildHandBadge() => AnimatedBuilder(
      animation: _handAnim,
      builder: (_, child) =>
          Transform.scale(scale: _handAnim.value, child: child),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
              color: _K.amber.withOpacity(0.92),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: _K.amber.withOpacity(0.45), blurRadius: 14)
              ]),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('✋', style: TextStyle(fontSize: 14)),
            SizedBox(width: 5),
            Text('Đang giơ tay',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ])));

  // ── Gradients ─────────────────────────────────────────────────────────────
  Widget _buildGrads() => Positioned.fill(
      child: IgnorePointer(
          child: Column(children: [
            Container(
                height: 180,
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.78),
                          Colors.transparent
                        ]))),
            const Spacer(),
            Container(
                height: 260,
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.9),
                          Colors.transparent
                        ]))),
          ])));

  // ── Floating reaction ─────────────────────────────────────────────────────
  Widget _buildFloatRx(_FloatReaction r) => Positioned(
      bottom: 210,
      left: 0,
      right: 0,
      child: LayoutBuilder(builder: (_, c) {
        final x = r.x * c.maxWidth - 28;
        return AnimatedBuilder(
            animation: r.ctrl,
            builder: (_, __) => Opacity(
                opacity: r.opacity.value.clamp(0.0, 1.0),
                child: Transform.translate(
                    offset: Offset(x, r.y.value),
                    child: Transform.scale(
                        scale: r.scale.value,
                        child:
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(r.emoji, style: const TextStyle(fontSize: 36)),
                          Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(r.sender,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 9))),
                        ])))));
      }));

  // ── Toast stack ───────────────────────────────────────────────────────────
  Widget _buildToasts() => Column(
      mainAxisSize: MainAxisSize.min,
      children: _toasts
          .map((t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _ParticipantToast(
            name: t.name, avatar: t.avatar, joining: t.joining),
      ))
          .toList());

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() => Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              color: Colors.black.withOpacity(0.22),
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: Row(children: [
                      _topBtn(Icons.picture_in_picture_alt_rounded, _enterPip,
                          'Thu nhỏ'),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(widget.call.groupName,
                                    style: const TextStyle(
                                        color: _K.text,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3),
                                    overflow: TextOverflow.ellipsis),
                                if (_joinedAt != null)
                                  CallTimerWidget(
                                      startTime: _joinedAt!,
                                      showPulse: _joined,
                                      style: const TextStyle(
                                          color: _K.sub,
                                          fontSize: 11,
                                          letterSpacing: 0.3)),
                              ])),
                      if (_screenSharing) _screenBadge(),
                      const SizedBox(width: 6),
                      _participantChip(),
                      const SizedBox(width: 6),
                      // Chat button
                      _chatChip(),
                    ]),
                  )),
            ),
          )));

  Widget _topBtn(IconData icon, VoidCallback tap, String tip) => Tooltip(
      message: tip,
      child: GestureDetector(
          onTap: tap,
          child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 20))));

  Widget _screenBadge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: _K.red.withOpacity(0.85),
          borderRadius: BorderRadius.circular(9)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.screen_share_rounded, color: Colors.white, size: 12),
        SizedBox(width: 4),
        Text('Đang chia sẻ',
            style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ]));

  Widget _participantChip() => GestureDetector(
      onTap: () => setState(() => _showParticipants = !_showParticipants),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
              color: _showParticipants
                  ? _K.accent.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _showParticipants
                      ? _K.accent.withOpacity(0.5)
                      : Colors.white.withOpacity(0.13),
                  width: 0.5)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.people_rounded, color: Colors.white, size: 13),
            const SizedBox(width: 4),
            Text('${_model.participantCount}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ])));

  Widget _chatChip() => GestureDetector(
      onTap: () => setState(() => _showChat = !_showChat),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: _showChat
                  ? _K.accent.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _showChat
                      ? _K.accent.withOpacity(0.5)
                      : Colors.white.withOpacity(0.12),
                  width: 0.5)),
          child:
          const Icon(Icons.chat_rounded, color: Colors.white, size: 18)));

  // ── Participants panel ────────────────────────────────────────────────────
  Widget _buildParticipantsPanel() => Positioned(
      top: 0,
      right: _showChat ? 300 : 0,
      bottom: 0,
      width: 272,
      child: GestureDetector(
          onTap: () {},
          child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  color: Colors.black.withOpacity(0.84),
                  child: SafeArea(
                      child: Column(children: [
                        _panelHeader(),
                        if (_canModerate) _adminBar(),
                        Divider(color: Colors.white.withOpacity(0.07), height: 1),
                        Expanded(
                            child: ListView.separated(
                              itemCount: _model.participants.length,
                              separatorBuilder: (_, __) =>
                                  Divider(color: Colors.white.withOpacity(0.04), height: 1),
                              itemBuilder: (_, i) =>
                                  _participantTile(_model.participants[i]),
                            )),
                        if (_model.waitingRoomUserIds.isNotEmpty && _canModerate)
                          _waitingSection(),
                      ])),
                ),
              ))));

  Widget _panelHeader() => Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
      child: Row(children: [
        const Text('Thành viên',
            style: TextStyle(
                color: _K.text, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(width: 8),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: _K.accent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10)),
            child: Text('${_model.participantCount}',
                style: const TextStyle(
                    color: _K.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700))),
        const Spacer(),
        GestureDetector(
            onTap: () => setState(() => _showParticipants = false),
            child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(9)),
                child:
                const Icon(Icons.close_rounded, color: _K.sub, size: 16))),
      ]));

  Widget _adminBar() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(spacing: 8, children: [
        _adminChip(Icons.mic_off_rounded, 'Tắt tất cả',
                () => _svc.muteAll(widget.call.callId)),
      ]));

  Widget _adminChip(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: _K.sub, size: 12),
                const SizedBox(width: 5),
                Text(label,
                    style: const TextStyle(
                        color: _K.sub,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ])));

  Widget _participantTile(GroupCallParticipant p) {
    final isSelf = p.userId == widget.currentUserId;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      leading: Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: p.isSpeaking ? _K.speaking : Colors.transparent,
                    width: 2),
                boxShadow: p.isSpeaking
                    ? [
                  BoxShadow(
                      color: _K.speaking.withOpacity(0.3), blurRadius: 8)
                ]
                    : null),
            child: CircleAvatar(
                radius: 18,
                backgroundImage:
                p.userAvatar.isNotEmpty ? NetworkImage(p.userAvatar) : null,
                backgroundColor: _K.surface2,
                child: p.userAvatar.isEmpty
                    ? Text(
                    p.userName.isNotEmpty
                        ? p.userName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13))
                    : null)),
        if (p.isAdmin || p.isCoHost)
          Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                      color: p.isAdmin ? _K.amber : _K.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5)),
                  child: Icon(
                      p.isAdmin ? Icons.star_rounded : Icons.shield_rounded,
                      size: 7,
                      color: Colors.white))),
      ]),
      title: Text(isSelf ? '${p.userName} (Bạn)' : p.userName,
          style: TextStyle(
              color: isSelf ? _K.accent : _K.text,
              fontSize: 13,
              fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis),
      subtitle: p.isAdmin
          ? const Text('Admin', style: TextStyle(color: _K.amber, fontSize: 10))
          : p.isCoHost
          ? const Text('Co-host',
          style: TextStyle(color: _K.accent, fontSize: 10))
          : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_model.hasRaisedHand(p.userId))
          const Text('✋', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 3),
        Icon(p.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            color: p.isMuted ? _K.red : _K.green, size: 14),
        if (widget.call.isVideo && p.isCameraOff)
          const Padding(
              padding: EdgeInsets.only(left: 3),
              child: Icon(Icons.videocam_off_rounded,
                  color: Color(0xFFFF9F0A), size: 14)),
        if (_canModerate && !isSelf)
          PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: _K.muted, size: 15),
              color: _K.surface2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                switch (v) {
                  case 'mute':
                    _svc.muteParticipant(
                        callId: widget.call.callId,
                        targetUserId: p.userId,
                        mute: true);
                    break;
                  case 'kick':
                    _svc.kickParticipant(
                        callId: widget.call.callId, targetUserId: p.userId);
                    break;
                  case 'pin':
                    _svc.pinParticipant(widget.call.callId, p.userId);
                    break;
                  case 'cohost':
                    _svc.promoteToCoHost(widget.call.callId, p.userId);
                    break;
                }
              },
              itemBuilder: (_) => [
                _pop('mute', Icons.mic_off_rounded, 'Tắt mic'),
                _pop('pin', Icons.push_pin_rounded, 'Ghim'),
                _pop('cohost', Icons.shield_rounded, 'Đặt Co-host'),
                _pop('kick', Icons.person_remove_rounded, 'Xoá khỏi phòng',
                    color: _K.red),
              ]),
      ]),
    );
  }

  PopupMenuItem<String> _pop(String v, IconData icon, String label,
      {Color? color}) =>
      PopupMenuItem<String>(
          value: v,
          child: Row(children: [
            Icon(icon, size: 15, color: color ?? _K.sub),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(color: color ?? _K.text, fontSize: 13)),
          ]));

  Widget _waitingSection() => WaitingRoomAdminPanel(
    callId: _model.callId,
    onAdmitAll: () async {
      for (final uid in _model.waitingRoomUserIds) {
        await _svc.admitFromWaitingRoom(
            callId: widget.call.callId, targetUserId: uid);
      }
    },
  );

  // ── Reaction picker ───────────────────────────────────────────────────────
  Widget _buildRxPicker() => Positioned(
      bottom: 182,
      right: 16,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                      color: _K.surface.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 24,
                            offset: const Offset(0, 8))
                      ]),
                  child: Wrap(
                      spacing: 2,
                      children: CallReactionType.values
                          .map((t) => GestureDetector(
                          onTap: () => _sendReaction(t),
                          child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                  child: Text(t.emoji,
                                      style:
                                      const TextStyle(fontSize: 26))))))
                          .toList())))));

  // ── More menu ─────────────────────────────────────────────────────────────
  Widget _buildMoreMenu() => Positioned(
      bottom: 182,
      left: 16,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                  width: 210,
                  decoration: BoxDecoration(
                      color: _K.surface.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 24,
                            offset: const Offset(0, 8))
                      ]),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _menuItem(
                        Icons.screen_share_rounded,
                        _screenSharing ? 'Dừng chia sẻ' : 'Chia sẻ màn hình',
                        _screenSharing,
                        _K.purple, () {
                      setState(() => _showMoreMenu = false);
                      _toggleScreen();
                    }),
                    _menuItem(
                        Icons.back_hand_rounded,
                        _handRaised ? 'Hạ tay' : 'Giơ tay',
                        _handRaised,
                        _K.amber, () {
                      setState(() => _showMoreMenu = false);
                      _toggleHand();
                    }),
                    _menuItem(Icons.flip_camera_android_rounded, 'Đổi camera',
                        false, _K.sub, () {
                          setState(() => _showMoreMenu = false);
                          _flipCamera();
                        }),
                    _menuItem(
                        _showCaptions
                            ? Icons.subtitles_rounded
                            : Icons.subtitles_off_rounded,
                        _showCaptions ? 'Tắt phụ đề AI' : 'Bật phụ đề AI',
                        _showCaptions,
                        _K.accent, () {
                      setState(() {
                        _showMoreMenu = false;
                        _showCaptions = !_showCaptions;
                      });
                    }),
                    _menuItem(
                        Icons.wallpaper_rounded, 'Nền ảo', false, _K.purple,
                            () async {
                          setState(() => _showMoreMenu = false);
                          await VirtualBackgroundPicker.show(
                            context,
                            current: VirtualBackground.none,
                          );
                        }),
                    _menuItem(Icons.bar_chart_rounded, 'Xem thống kê',
                        _statsExpanded, _K.accent, () {
                          setState(() {
                            _showMoreMenu = false;
                            _statsExpanded = !_statsExpanded;
                          });
                        }),
                    if (_canModerate)
                      _menuItem(Icons.mic_off_rounded, 'Tắt mic tất cả', false,
                          _K.red, () {
                            setState(() => _showMoreMenu = false);
                            _svc.muteAll(widget.call.callId);
                          }),
                  ])))));

  Widget _menuItem(IconData icon, String label, bool active, Color color,
      VoidCallback onTap) =>
      InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: color.withOpacity(active ? 0.25 : 0.08),
                        borderRadius: BorderRadius.circular(9)),
                    child:
                    Icon(icon, color: active ? color : _K.sub, size: 16)),
                const SizedBox(width: 11),
                Expanded(
                    child: Text(label,
                        style: TextStyle(
                            color: active ? color : _K.text,
                            fontSize: 13,
                            fontWeight:
                            active ? FontWeight.w700 : FontWeight.w500))),
                if (active)
                  Container(
                      width: 7,
                      height: 7,
                      decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              ])));

  // ── Bottom controls ───────────────────────────────────────────────────────
  Widget _buildBottomCtrl() => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _secBtn(
                    Icons.emoji_emotions_rounded,
                    _showReactions,
                        () => setState(() {
                      _showReactions = !_showReactions;
                      _showMoreMenu = false;
                    })),
                const SizedBox(width: 8),
                _secBtn(
                    Icons.more_horiz_rounded,
                    _showMoreMenu,
                        () => setState(() {
                      _showMoreMenu = !_showMoreMenu;
                      _showReactions = false;
                    })),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(38),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(38),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.09)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _primBtn(
                          icon: _micMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: _micMuted ? 'Mở Mic' : 'Mic',
                          active: _micMuted,
                          activeColor: _K.red,
                          onTap: _toggleMic),
                      if (widget.call.isVideo)
                        _primBtn(
                            icon: _camOff
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded,
                            label: _camOff ? 'Bật Cam' : 'Cam',
                            active: _camOff,
                            activeColor: const Color(0xFFFF9F0A),
                            onTap: _toggleCam),
                      _primBtn(
                          icon: _speakerOn
                              ? Icons.volume_up_rounded
                              : Icons.hearing_rounded,
                          label: _speakerOn ? 'Loa' : 'Tai nghe',
                          active: _speakerOn,
                          activeColor: _K.accent,
                          onTap: _toggleSpeaker),
                      _endBtn(),
                      if (_canModerate)
                        _primBtn(
                            icon: _model.isRecording
                                ? Icons.fiber_manual_record_rounded
                                : Icons.radio_button_unchecked_rounded,
                            label: _model.isRecording ? 'Dừng REC' : 'REC',
                            active: _model.isRecording,
                            activeColor: _K.red,
                            onTap: _toggleRecording),
                      if (widget.call.isVideo)
                        _primBtn(
                            icon: Icons.flip_camera_android_rounded,
                            label: 'Xoay',
                            active: false,
                            activeColor: _K.sub,
                            onTap: _flipCamera)
                      else
                        _primBtn(
                            icon: _handRaised
                                ? Icons.back_hand_rounded
                                : Icons.back_hand_outlined,
                            label: _handRaised ? 'Hạ tay' : 'Giơ tay',
                            active: _handRaised,
                            activeColor: _K.amber,
                            onTap: _toggleHand),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _secBtn(IconData icon, bool active,
      VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color:
                  active
                      ? Colors.white.withOpacity(0.22)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border:
                  Border.all(
                      color: Colors.white.withOpacity(active ? 0.4 : 0.1),
                      width: 0.5)),
              child: Icon(icon,
                  color: active ? Colors.white : Colors.white60, size: 18)));

  Widget _primBtn(
      {required IconData icon,
        required String label,
        required bool active,
        required Color activeColor,
        required VoidCallback onTap}) =>
      GestureDetector(
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    color: active
                        ? activeColor.withOpacity(0.22)
                        : Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: active
                            ? activeColor.withOpacity(0.55)
                            : Colors.white.withOpacity(0.16)),
                    boxShadow: active
                        ? [
                      BoxShadow(
                          color: activeColor.withOpacity(0.22),
                          blurRadius: 12)
                    ]
                        : null),
                child: Icon(icon,
                    color: active ? activeColor : Colors.white, size: 22)),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    color: active
                        ? activeColor.withOpacity(0.9)
                        : Colors.white.withOpacity(0.65),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1)),
          ]));

  Widget _endBtn() => GestureDetector(
      onTap: _hangUp,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
                color: _K.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: _K.red.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 6))
                ]),
            child: const Icon(Icons.call_end_rounded,
                color: Colors.white, size: 27)),
        const SizedBox(height: 5),
        const Text('Rời',
            style: TextStyle(
                color: _K.red, fontSize: 9.5, fontWeight: FontWeight.w700)),
      ]));

  // ══════════════════════════════════════════════════════════════════════════
  // VOICE UI
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildVoiceUI() => Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF090F1E), Color(0xFF060A13), Color(0xFF060A13)],
              stops: [0, 0.5, 1])),
      child: SafeArea(
          child: Column(children: [
            _voiceTopBar(),
            const Spacer(flex: 2),
            Text(widget.call.groupName,
                style: const TextStyle(
                    color: _K.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            if (_joinedAt != null)
              CallTimerWidget(
                  startTime: _joinedAt!,
                  showPulse: true,
                  style: const TextStyle(
                      color: _K.green,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
            const Spacer(flex: 1),
            _voiceParticipants(),
            const Spacer(flex: 2),
            if (_model.raisedHandUserIds.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RaiseHandQueuePanel(
                      call: _model,
                      currentUserId: widget.currentUserId,
                      isAdmin: _canModerate)),
            if (_floatReactions.isNotEmpty)
              Container(
                  height: 48,
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                          children: _floatReactions
                              .map((r) => Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 5),
                              child: Text(r.emoji,
                                  style: const TextStyle(fontSize: 30))))
                              .toList()))),

            // Hiển thị Live Caption ở UI Voice nếu được bật
            if (_showCaptions)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: LiveCaptionOverlay(),
              ),

            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _voiceChip(
                      icon: Icons.emoji_emotions_rounded,
                      label: 'React',
                      active: _showReactions,
                      onTap: () =>
                          setState(() => _showReactions = !_showReactions)),
                  const SizedBox(width: 10),
                  _voiceChip(
                      icon: _handRaised
                          ? Icons.back_hand_rounded
                          : Icons.back_hand_outlined,
                      label: 'Giơ tay',
                      active: _handRaised,
                      onTap: _toggleHand),
                  const SizedBox(width: 10),
                  _voiceChip(
                      icon: Icons.chat_rounded,
                      label: 'Chat',
                      active: _showChat,
                      onTap: () => setState(() => _showChat = !_showChat)),
                  const SizedBox(width: 10),
                  _voiceChip(
                      icon: _showCaptions
                          ? Icons.subtitles_rounded
                          : Icons.subtitles_off_rounded,
                      label: 'Phụ đề',
                      active: _showCaptions,
                      onTap: () => setState(() => _showCaptions = !_showCaptions)),
                ])),
            if (_showReactions) ...[const SizedBox(height: 10), _voiceRxRow()],
            const SizedBox(height: 18),
            _voiceControls(),
            const SizedBox(height: 30),
            // Overlay chat as bottom sheet
            if (_showChat) _voiceChatSheet(),
          ])));

  Widget _voiceTopBar() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AICallShield(alignRight: false),
            SizedBox(height: 8),
            DeepfakeStatusBadge(),
          ],
        ),
        const Spacer(),
        GroupCallStatsOverlay(stats: _stats),
        const SizedBox(width: 10),
        _participantChip(),
      ]));

  Widget _voiceParticipants() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Wrap(
          spacing: 18,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: _model.participants.map(_voiceAvatar).toList()));

  Widget _voiceAvatar(GroupCallParticipant p) {
    final isSelf = p.userId == widget.currentUserId;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, children: [
        AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: p.isSpeaking
                        ? _K.speaking
                        : p.isMuted
                        ? _K.red.withOpacity(0.5)
                        : Colors.white.withOpacity(0.14),
                    width: p.isSpeaking ? 3 : 2),
                boxShadow: p.isSpeaking
                    ? [
                  BoxShadow(
                      color: _K.speaking.withOpacity(0.4),
                      blurRadius: 18,
                      spreadRadius: 3)
                ]
                    : null),
            child: CircleAvatar(
                radius: 34,
                backgroundImage:
                p.userAvatar.isNotEmpty ? NetworkImage(p.userAvatar) : null,
                backgroundColor: _K.surface2,
                child: p.userAvatar.isEmpty
                    ? Text(
                    p.userName.isNotEmpty
                        ? p.userName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 22))
                    : null)),
        Positioned(
            right: -2,
            bottom: -2,
            child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: p.isMuted ? _K.red : _K.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: _K.bg, width: 1.5)),
                child: Icon(
                    p.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    size: 10,
                    color: Colors.white))),
        if (_model.hasRaisedHand(p.userId))
          Positioned(
              left: -3,
              top: -3,
              child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                      color: _K.amber,
                      shape: BoxShape.circle,
                      border: Border.all(color: _K.bg, width: 1.5)),
                  child: const Text('✋', style: TextStyle(fontSize: 8)))),
      ]),
      const SizedBox(height: 7),
      Text(isSelf ? 'Bạn' : p.userName,
          style: TextStyle(
              color: isSelf ? _K.accent : _K.text,
              fontSize: 11,
              fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center),
      if (p.isAdmin)
        Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: _K.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(5),
                border:
                Border.all(color: _K.amber.withOpacity(0.35), width: 0.5)),
            child: const Text('admin',
                style: TextStyle(color: _K.amber, fontSize: 8))),
    ]);
  }

  Widget _voiceChip(
      {required IconData icon,
        required String label,
        required bool active,
        required VoidCallback onTap}) =>
      GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withOpacity(0.18)
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(active ? 0.3 : 0.08),
                      width: 0.5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    color: active ? Colors.white : Colors.white60, size: 14),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ])));

  Widget _voiceRxRow() => Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: _K.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: CallReactionType.values
              .map((t) => GestureDetector(
              onTap: () => _sendReaction(t),
              child: Text(t.emoji, style: const TextStyle(fontSize: 28))))
              .toList()));

  Widget _voiceControls() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _primBtn(
            icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: _micMuted ? 'Mở Mic' : 'Mic',
            active: _micMuted,
            activeColor: _K.red,
            onTap: _toggleMic),
        _endBtn(),
        _primBtn(
            icon: _speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
            label: _speakerOn ? 'Loa' : 'Tai nghe',
            active: _speakerOn,
            activeColor: _K.accent,
            onTap: _toggleSpeaker),
      ]));

  Widget _voiceChatSheet() => Container(
      height: 340,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: GroupCallChatPanel(
              callId: widget.call.callId,
              currentUserId: widget.currentUserId,
              currentUserName: widget.currentUserName,
              currentUserAvatar: widget.currentUserAvatar,
              onClose: () => setState(() => _showChat = false))));

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _avatarWidget(double r) => widget.call.groupAvatarUrl.isNotEmpty
      ? CircleAvatar(
      radius: r, backgroundImage: NetworkImage(widget.call.groupAvatarUrl))
      : CircleAvatar(
      radius: r,
      backgroundColor: _K.surface2,
      child: Icon(Icons.group_rounded, size: r * 0.85, color: _K.muted));
}

// ─── Supporting widgets ───────────────────────────────────────────────────────
class _PulsingDots extends StatefulWidget {
  final Color color;
  const _PulsingDots({required this.color});
  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final t = (_c.value - i * 0.2).clamp(0.0, 1.0);
              final s = math.sin(t * math.pi);
              return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withOpacity(0.3 + s * 0.7)));
            })));
  }
}

class _NetDots extends StatelessWidget {
  final int quality;
  const _NetDots({required this.quality});
  @override
  Widget build(BuildContext context) {
    if (quality == 0) return const SizedBox.shrink();
    final c = quality >= 3
        ? _K.green
        : quality == 2
        ? const Color(0xFFFF9F0A)
        : _K.red;
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
            4,
                (i) => Container(
                width: 3,
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < quality ? c : c.withOpacity(0.2)))));
  }
}

class _ParticipantToast extends StatefulWidget {
  final String name;
  final String? avatar;
  final bool joining;
  const _ParticipantToast(
      {required this.name, this.avatar, required this.joining});
  @override
  State<_ParticipantToast> createState() => _ParticipantToastState();
}

class _ParticipantToastState extends State<_ParticipantToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.joining ? _K.green : _K.sub;
    return FadeTransition(
        opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.68),
                    borderRadius: BorderRadius.circular(22),
                    border:
                    Border.all(color: color.withOpacity(0.25), width: 0.5)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                      radius: 11,
                      backgroundImage: widget.avatar != null
                          ? NetworkImage(widget.avatar!)
                          : null,
                      backgroundColor: _K.surface2,
                      child: widget.avatar == null
                          ? Text(
                          widget.name.isNotEmpty
                              ? widget.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 8))
                          : null),
                  const SizedBox(width: 6),
                  Text(
                      widget.joining
                          ? '${widget.name} đã tham gia'
                          : '${widget.name} đã rời',
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]))));
  }
}