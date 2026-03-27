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
  final int txBitrate;
  final int rxBitrate;
  final int txPacketLoss;
  final int rxPacketLoss;
  final int rtt;
  final int duration;

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
  // ── State ──────────────────────────────────────────────
  RtcConnectionState _connectionState = RtcConnectionState.disconnected;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _remoteVideoOn = true;
  int? _remoteUid;
  RtcCallStats _stats = const RtcCallStats();
  bool _initialized = false;
  String? _currentChannel;
  bool _disposed = false;

  // ── Streams ────────────────────────────────────────────
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

  // ── Getters ────────────────────────────────────────────
  RtcConnectionState get connectionState => _connectionState;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isFrontCamera => _isFrontCamera;
  bool get remoteVideoOn => _remoteVideoOn;
  int? get remoteUid => _remoteUid;
  RtcCallStats get stats => _stats;
  bool get isConnected => _connectionState == RtcConnectionState.connected;
  bool get hasRemoteUser => _remoteUid != null;
  RtcEngine? get engine => _engine;
  String? get currentChannel => _currentChannel;

  RtcEngine? _engine;

  // ── Public API ─────────────────────────────────────────

  Future<bool> initialize() async {
    if (_initialized) return true;
    if (_disposed) return false;

    // Kiểm tra App ID hợp lệ
    if (kAgoraAppId == 'YOUR_AGORA_APP_ID_HERE' || kAgoraAppId.isEmpty) {
      debugPrint('❌ AgoraRtcManager: App ID chưa được cấu hình!');
      _errorController.add(
        'Agora App ID chưa được cấu hình. Vui lòng lấy App ID từ console.agora.io',
      );
      return false;
    }

    try {
      await _requestPermissions(video: true);
      await _initAgora();
      _initialized = true;
      debugPrint('✅ AgoraRtcManager initialized');
      return true;
    } catch (e) {
      debugPrint('❌ AgoraRtcManager init failed: $e');
      _errorController.add('Không thể khởi tạo call engine: $e');
      return false;
    }
  }

  Future<bool> joinChannel({
    required String channelName,
    required bool isVideoCall,
    String? token,
    int uid = 0,
  }) async {
    if (_disposed) return false;

    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    try {
      await _requestPermissions(video: isVideoCall);
      _currentChannel = channelName;
      _setConnectionState(RtcConnectionState.connecting);

      if (!isVideoCall) {
        await _engine?.disableVideo();
      } else {
        await _engine?.enableVideo();
      }

      await _engine?.joinChannel(
        token: token ?? '',
        channelId: channelName,
        uid: uid,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishCameraTrack: isVideoCall,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideoCall,
        ),
      );

      debugPrint('✅ Joined channel: $channelName');
      return true;
    } catch (e) {
      debugPrint('❌ Join channel failed: $e');
      _setConnectionState(RtcConnectionState.failed);
      _errorController.add('Không thể kết nối cuộc gọi: $e');
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

  // ── Controls ───────────────────────────────────────────

  Future<void> toggleMute() async {
    if (_disposed) return;
    _isMuted = !_isMuted;
    try {
      await _engine?.muteLocalAudioStream(_isMuted);
    } catch (e) {
      debugPrint('❌ Toggle mute error: $e');
    }
    _safeNotify();
  }

  Future<void> toggleCamera() async {
    if (_disposed) return;
    _isCameraOff = !_isCameraOff;
    try {
      await _engine?.muteLocalVideoStream(_isCameraOff);
    } catch (e) {
      debugPrint('❌ Toggle camera error: $e');
    }
    _safeNotify();
  }

  Future<void> toggleSpeaker() async {
    if (_disposed) return;
    _isSpeakerOn = !_isSpeakerOn;
    try {
      await _engine?.setEnableSpeakerphone(_isSpeakerOn);
    } catch (e) {
      debugPrint('❌ Toggle speaker error: $e');
    }
    _safeNotify();
  }

  Future<void> switchCamera() async {
    if (_disposed) return;
    _isFrontCamera = !_isFrontCamera;
    try {
      await _engine?.switchCamera();
    } catch (e) {
      debugPrint('❌ Switch camera error: $e');
    }
    _safeNotify();
  }

  // ── Dispose ────────────────────────────────────────────

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // Sync leave channel (fire-and-forget) trước khi dispose
    _engine?.leaveChannel().catchError((e) {
      debugPrint('⚠️ Leave channel on dispose: $e');
    });

    _remoteJoinedController.close();
    _remoteLeftController.close();
    _connectionController.close();
    _errorController.close();

    _engine?.release().catchError((e) {
      debugPrint('⚠️ Engine release error: $e');
    });
    _engine = null;

    super.dispose();
  }

  // ── Internal ───────────────────────────────────────────

  Future<void> _initAgora() async {
    _engine = createAgoraRtcEngine();

    await _engine!.initialize(RtcEngineContext(
      appId: kAgoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
      logConfig: const LogConfig(
        level: LogLevel.logLevelWarn, // Giảm log noise
      ),
    ));

    await _engine!.enableAudio();
    await _engine!.setEnableSpeakerphone(true);

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        debugPrint('✅ Joined channel: ${connection.channelId}');
        _setConnectionState(RtcConnectionState.connected);
      },
      onLeaveChannel: (RtcConnection connection, RtcStats stats) {
        debugPrint('✅ Left channel');
        _setConnectionState(RtcConnectionState.disconnected);
      },
      onUserJoined: (RtcConnection connection, int uid, int elapsed) {
        debugPrint('👤 Remote user joined: $uid');
        _remoteUid = uid;
        _remoteVideoOn = true;
        _remoteJoinedController.add(uid);
        _safeNotify();
      },
      onUserOffline:
          (RtcConnection connection, int uid, UserOfflineReasonType reason) {
        debugPrint('👤 Remote user left: $uid');
        _remoteUid = null;
        _remoteLeftController.add(uid);
        _safeNotify();
      },
      onConnectionStateChanged: (RtcConnection connection,
          ConnectionStateType state, ConnectionChangedReasonType reason) {
        _setConnectionState(_mapConnectionState(state));
      },
      onRemoteVideoStateChanged: (RtcConnection connection, int uid,
          RemoteVideoState state, RemoteVideoStateReason reason, int elapsed) {
        if (_remoteUid == uid) {
          _remoteVideoOn = state == RemoteVideoState.remoteVideoStateDecoding;
          _safeNotify();
        }
      },
      onRtcStats: (RtcConnection connection, RtcStats stats) {
        if (!_disposed) {
          _stats = RtcCallStats(
            txBitrate: stats.txKBitRate ?? 0,
            rxBitrate: stats.rxKBitRate ?? 0,
            txPacketLoss: stats.txPacketLossRate ?? 0,
            rxPacketLoss: stats.rxPacketLossRate ?? 0,
            rtt: stats.lastmileDelay ?? 0,
            duration: stats.duration ?? 0,
          );
          _safeNotify();
        }
      },
      onError: (ErrorCodeType err, String msg) {
        debugPrint('❌ Agora error [$err]: $msg');
        if (!_errorController.isClosed) {
          _errorController.add('Lỗi cuộc gọi: $msg');
        }
      },
    ));
  }

  void _setConnectionState(RtcConnectionState state) {
    if (_disposed) return;
    _connectionState = state;
    if (!_connectionController.isClosed) {
      _connectionController.add(state);
    }
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
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

    final statuses = await permissions.request();
    for (final entry in statuses.entries) {
      if (!entry.value.isGranted) {
        debugPrint('⚠️ Permission not granted: ${entry.key}');
      }
    }
  }
}
