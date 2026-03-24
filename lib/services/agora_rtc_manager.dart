// lib/services/agora_rtc_manager.dart
import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

const String kAgoraAppId = '11d7a5c344694ee5ad835a7e0d388871';

enum RtcConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

class RtcCallStats {
  final int txBitrate; // kbps
  final int rxBitrate; // kbps
  final int txPacketLoss; // %
  final int rxPacketLoss; // %
  final int rtt; // ms round-trip
  final int duration; // seconds

  const RtcCallStats({
    this.txBitrate = 0,
    this.rxBitrate = 0,
    this.txPacketLoss = 0,
    this.rxPacketLoss = 0,
    this.rtt = 0,
    this.duration = 0,
  });
}

class AgoraRtcManager extends ChangeNotifier {
  RtcConnectionState _connectionState = RtcConnectionState.disconnected;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _isScreenSharing = false;
  bool _remoteVideoOn = true;
  int? _remoteUid;
  RtcCallStats _stats = const RtcCallStats();
  bool _initialized = false;
  String? _currentChannel;

  final _remoteJoinedController = StreamController<int>.broadcast();
  final _remoteLeftController = StreamController<int>.broadcast();
  final _connectionController =
      StreamController<RtcConnectionState>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<int> get remoteJoinedStream => _remoteJoinedController.stream;
  Stream<int> get remoteLeftStream => _remoteLeftController.stream;
  Stream<RtcConnectionState> get connectionStream =>
      _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;

  RtcConnectionState get connectionState => _connectionState;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isFrontCamera => _isFrontCamera;
  bool get isScreenSharing => _isScreenSharing;
  bool get remoteVideoOn => _remoteVideoOn;
  int? get remoteUid => _remoteUid;
  RtcCallStats get stats => _stats;
  bool get isConnected => _connectionState == RtcConnectionState.connected;
  bool get hasRemoteUser => _remoteUid != null;

  /// Real Agora engine — exposed so CallPage can build AgoraVideoView.
  RtcEngine? _engine;
  RtcEngine? get engine => _engine;

  /// Current channel name — exposed for VideoViewController.remote.
  String? get currentChannel => _currentChannel;

  // ─────────────────────────────────────────────────────────────────
  //  PUBLIC API
  // ─────────────────────────────────────────────────────────────────

  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      await _requestPermissions(video: true);
      await _initAgora();
      _initialized = true;
      debugPrint('✅ AgoraRtcManager initialized');
      return true;
    } catch (e) {
      debugPrint('❌ AgoraRtcManager init failed: $e');
      _errorController.add('Failed to initialize call engine: $e');
      return false;
    }
  }

  Future<bool> joinChannel({
    required String channelName,
    required bool isVideoCall,
    String? token,
    int uid = 0,
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return false;
    }
    try {
      await _requestPermissions(video: isVideoCall);
      _currentChannel = channelName;
      _setConnectionState(RtcConnectionState.connecting);

      await _joinAgoraChannel(
        channelName: channelName,
        token: token,
        uid: uid,
        isVideoCall: isVideoCall,
      );

      if (!isVideoCall) {
        await _engine!.disableVideo();
      }

      debugPrint('✅ Joined channel: $channelName');
      return true;
    } catch (e) {
      debugPrint('❌ Join channel failed: $e');
      _setConnectionState(RtcConnectionState.failed);
      _errorController.add('Could not join call: $e');
      return false;
    }
  }

  Future<void> leaveChannel() async {
    if (!_initialized || _engine == null) return;
    try {
      await _engine!.leaveChannel();
      _currentChannel = null;
      _remoteUid = null;
      _setConnectionState(RtcConnectionState.disconnected);
      debugPrint('✅ Left channel');
    } catch (e) {
      debugPrint('❌ Leave channel error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  //  CONTROLS
  // ─────────────────────────────────────────────────────────────────

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _engine?.muteLocalAudioStream(_isMuted);
    debugPrint('🎤 Mute local audio: $_isMuted');
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    _isCameraOff = !_isCameraOff;
    await _engine?.muteLocalVideoStream(_isCameraOff);
    debugPrint('📷 Mute local video: $_isCameraOff');
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await _engine?.setEnableSpeakerphone(_isSpeakerOn);
    debugPrint('🔊 Speaker: $_isSpeakerOn');
    notifyListeners();
  }

  Future<void> switchCamera() async {
    _isFrontCamera = !_isFrontCamera;
    await _engine?.switchCamera();
    debugPrint('🔄 Switch camera');
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────
  //  DISPOSE
  // ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    leaveChannel();
    _remoteJoinedController.close();
    _remoteLeftController.close();
    _connectionController.close();
    _errorController.close();
    _engine?.release();
    _engine = null;
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  //  INTERNAL – Agora SDK
  // ─────────────────────────────────────────────────────────────────

  Future<void> _initAgora() async {
    _engine = createAgoraRtcEngine();

    await _engine!.initialize(RtcEngineContext(
      appId: kAgoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, elapsed) {
        onConnectionStateChanged(RtcConnectionState.connected);
      },
      onLeaveChannel: (conn, stats) {
        onConnectionStateChanged(RtcConnectionState.disconnected);
      },
      onUserJoined: (conn, uid, elapsed) => onRemoteUserJoined(uid),
      onUserOffline: (conn, uid, reason) => onRemoteUserLeft(uid),
      onConnectionStateChanged: (conn, state, reason) {
        onConnectionStateChanged(_mapConnectionState(state));
      },
      onRemoteVideoStateChanged: (conn, uid, state, reason, elapsed) {
        final on = state == RemoteVideoState.remoteVideoStateDecoding;
        onRemoteVideoStateChanged(uid, on);
      },
      onRtcStats: (conn, stats) {
        onRtcStats(RtcCallStats(
          txBitrate: stats.txKBitRate ?? 0,
          rxBitrate: stats.rxKBitRate ?? 0,
          txPacketLoss: stats.txPacketLossRate ?? 0,
          rxPacketLoss: stats.rxPacketLossRate ?? 0,
          rtt: stats.lastmileDelay ?? 0,
          duration: stats.duration ?? 0,
        ));
      },
      onError: (err, msg) {
        debugPrint('❌ Agora error [$err]: $msg');
        _errorController.add('Agora error: $msg');
      },
    ));

    await _engine!.enableAudio();
  }

  Future<void> _joinAgoraChannel({
    required String channelName,
    required bool isVideoCall,
    String? token,
    int uid = 0,
  }) async {
    await _engine!.joinChannel(
      token: token ?? '',
      channelId: channelName,
      uid: uid,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishCameraTrack: isVideoCall,
        publishMicrophoneTrack: true,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  SDK EVENT CALLBACKS
  // ─────────────────────────────────────────────────────────────────

  void onRemoteUserJoined(int uid) {
    _remoteUid = uid;
    _remoteVideoOn = true;
    _remoteJoinedController.add(uid);
    notifyListeners();
    debugPrint('👤 Remote user joined: $uid');
  }

  void onRemoteUserLeft(int uid) {
    _remoteUid = null;
    _remoteLeftController.add(uid);
    notifyListeners();
    debugPrint('👤 Remote user left: $uid');
  }

  void onConnectionStateChanged(RtcConnectionState state) {
    _setConnectionState(state);
  }

  void onRtcStats(RtcCallStats s) {
    _stats = s;
    notifyListeners();
  }

  void onRemoteVideoStateChanged(int uid, bool videoOn) {
    if (_remoteUid == uid) {
      _remoteVideoOn = videoOn;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────────────────────────

  void _setConnectionState(RtcConnectionState state) {
    _connectionState = state;
    _connectionController.add(state);
    notifyListeners();
  }

  RtcConnectionState _mapConnectionState(ConnectionStateType state) {
    switch (state) {
      case ConnectionStateType.connectionStateDisconnected:
        return RtcConnectionState.disconnected;
      case ConnectionStateType.connectionStateConnecting:
        return RtcConnectionState.connecting;
      case ConnectionStateType.connectionStateConnected:
        return RtcConnectionState.connected;
      case ConnectionStateType.connectionStateReconnecting:
        return RtcConnectionState.reconnecting;
      case ConnectionStateType.connectionStateFailed:
        return RtcConnectionState.failed;
      default:
        return RtcConnectionState.disconnected;
    }
  }

  Future<void> _requestPermissions({bool video = false}) async {
    final permissions = [Permission.microphone];
    if (video) permissions.add(Permission.camera);
    await permissions.request();
  }
}
