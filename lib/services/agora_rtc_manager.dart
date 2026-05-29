import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

enum RtcConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum NetworkQuality { unknown, excellent, good, poor, bad, veryBad, down }

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

class RemoteUserState {
  final int uid;
  final bool videoOn;
  final bool audioOn;

  const RemoteUserState({
    required this.uid,
    this.videoOn = true,
    this.audioOn = true,
  });

  RemoteUserState copyWith({bool? videoOn, bool? audioOn}) => RemoteUserState(
        uid: uid,
        videoOn: videoOn ?? this.videoOn,
        audioOn: audioOn ?? this.audioOn,
      );
}

class AgoraRtcManager extends ChangeNotifier {
  RtcConnectionState _connectionState = RtcConnectionState.disconnected;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _isVideoCall = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _joining = false;

  String? _currentChannel;
  RtcCallStats _stats = const RtcCallStats();
  NetworkQuality _networkQuality = NetworkQuality.unknown;
  Map<int, RemoteUserState> _remoteUsers = {};

  RtcEngine? _engine;

  final _remoteJoinedCtrl = StreamController<int>.broadcast();
  final _remoteLeftCtrl = StreamController<int>.broadcast();
  final _connectionCtrl = StreamController<RtcConnectionState>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _networkQualityCtrl = StreamController<NetworkQuality>.broadcast();
  final _activeSpeakerCtrl = StreamController<int>.broadcast();

  Stream<int> get remoteJoinedStream => _remoteJoinedCtrl.stream;
  Stream<int> get remoteLeftStream => _remoteLeftCtrl.stream;
  Stream<RtcConnectionState> get connectionStream => _connectionCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;
  Stream<NetworkQuality> get networkQualityStream => _networkQualityCtrl.stream;
  Stream<int> get activeSpeakerStream => _activeSpeakerCtrl.stream;

  RtcConnectionState get connectionState => _connectionState;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isFrontCamera => _isFrontCamera;
  bool get isVideoCall => _isVideoCall;
  bool get isConnected => _connectionState == RtcConnectionState.connected;
  bool get hasRemoteUser => _remoteUsers.isNotEmpty;
  int? get remoteUid => _remoteUsers.keys.firstOrNull;

  bool get remoteVideoOn {
    final uid = remoteUid;
    if (uid == null) return false;
    return _remoteUsers[uid]?.videoOn ?? false;
  }

  RtcCallStats get stats => _stats;
  NetworkQuality get networkQuality => _networkQuality;
  Map<int, RemoteUserState> get remoteUsers => Map.unmodifiable(_remoteUsers);
  String? get currentChannel => _currentChannel;
  RtcEngine? get engine => _engine;

  String get _tokenServerBase =>
      dotenv.env['AGORA_TOKEN_SERVER'] ?? 'https://agora-token-service-boa9.onrender.com';

  String get _appId => (dotenv.env['AGORA_APP_ID'] ?? '').trim();

  Future<bool> initialize() async {
    if (_initialized) return true;
    if (_disposed) return false;

    if (_appId.isEmpty) {
      _emitError('AGORA_APP_ID chưa được cấu hình trong .env');
      return false;
    }

    try {
      await _requestPermissions(video: true);
      await _initEngine();
      _initialized = true;
      debugPrint('✅ [Agora] Initialized');
      return true;
    } catch (e, st) {
      debugPrint('❌ [Agora] initialize: $e\n$st');
      _emitError('Không thể khởi tạo call engine: $e');
      return false;
    }
  }

  Future<bool> joinChannel({
    required String channelName,
    required bool isVideoCall,
    int uid = 0,
    String? token,
  }) async {
    if (_disposed) return false;
    if (_joining) return false;

    final ch = channelName.trim();
    if (ch.isEmpty) {
      _emitError('Tên kênh không hợp lệ');
      return false;
    }

    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    _joining = true;
    _isVideoCall = isVideoCall;

    try {
      await _requestPermissions(video: isVideoCall);
      _currentChannel = ch;
      _setConnectionState(RtcConnectionState.connecting);

      final rtcToken = token ?? await _fetchToken(ch, uid: uid);
      if (rtcToken == null || rtcToken.isEmpty) {
        _emitError('Không thể lấy Token cuộc gọi. Vui lòng thử lại.');
        _setConnectionState(RtcConnectionState.failed);
        return false;
      }

      if (isVideoCall) {
        await _engine?.enableVideo();
        await _engine?.startPreview();
      } else {
        await _engine?.disableVideo();
      }

      await _engine?.joinChannel(
        token: rtcToken,
        channelId: ch,
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

      debugPrint('✅ [Agora] joinChannel dispatched: $ch');
      return true;
    } catch (e, st) {
      debugPrint('❌ [Agora] joinChannel: $e\n$st');
      _setConnectionState(RtcConnectionState.failed);
      _emitError('Không thể kết nối cuộc gọi: $e');
      return false;
    } finally {
      _joining = false;
    }
  }

  Future<void> leaveChannel() async {
    if (!_initialized || _engine == null) return;
    try {
      await _engine!.leaveChannel();
    } catch (e) {
      debugPrint('⚠️ [Agora] leaveChannel: $e');
    } finally {
      _remoteUsers = {};
      _currentChannel = null;
      _isVideoCall = false;
      _isMuted = false;
      _isCameraOff = false;
      _setConnectionState(RtcConnectionState.disconnected);
      _safeNotify();
    }
  }

  Future<void> toggleMute() async {
    if (_disposed) return;
    _isMuted = !_isMuted;
    await _safeCall(() => _engine?.muteLocalAudioStream(_isMuted));
    _safeNotify();
  }

  Future<void> setMuted(bool muted) async {
    if (_disposed || _isMuted == muted) return;
    _isMuted = muted;
    await _safeCall(() => _engine?.muteLocalAudioStream(_isMuted));
    _safeNotify();
  }

  Future<void> toggleCamera() async {
    if (_disposed || !_isVideoCall) return;
    _isCameraOff = !_isCameraOff;
    await _safeCall(() => _engine?.muteLocalVideoStream(_isCameraOff));
    _safeNotify();
  }

  Future<void> toggleSpeaker() async {
    if (_disposed) return;
    _isSpeakerOn = !_isSpeakerOn;
    await _safeCall(() => _engine?.setEnableSpeakerphone(_isSpeakerOn));
    _safeNotify();
  }

  Future<void> switchCamera() async {
    if (_disposed || !_isVideoCall) return;
    _isFrontCamera = !_isFrontCamera;
    await _safeCall(() => _engine?.switchCamera());
    _safeNotify();
  }

  Future<void> adjustRemoteVolume(int uid, int volume) async {
    if (_disposed) return;
    final v = volume.clamp(0, 400);
    await _safeCall(() => _engine?.adjustUserPlaybackSignalVolume(uid: uid, volume: v));
  }

  Future<void> muteRemoteVideo(int uid, {required bool mute}) async {
    if (_disposed) return;
    await _safeCall(
      () => _engine?.muteRemoteVideoStream(uid: uid, mute: mute),
    );
    if (_remoteUsers.containsKey(uid)) {
      _remoteUsers[uid] = _remoteUsers[uid]!.copyWith(videoOn: !mute);
      _safeNotify();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _engine?.leaveChannel().catchError((_) {});

    _remoteJoinedCtrl.close();
    _remoteLeftCtrl.close();
    _connectionCtrl.close();
    _errorCtrl.close();
    _networkQualityCtrl.close();
    _activeSpeakerCtrl.close();

    _engine?.release().catchError((_) {});
    _engine = null;

    super.dispose();
  }

  Future<void> _initEngine() async {
    _engine = createAgoraRtcEngine();

    await _engine!.initialize(RtcEngineContext(
      appId: _appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
      logConfig: const LogConfig(
        level: LogLevel.logLevelWarn,
        filePath: '/agora_rtc.log',
        fileSizeInKB: 512,
      ),
    ));

    await _engine!.enableAudio();
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileMusicHighQualityStereo,
      scenario: AudioScenarioType.audioScenarioChatroom,
    );
    await _engine!.setEnableSpeakerphone(true);

    await _engine!.setParameters('{"che.audio.enable.aec":true}');
    await _engine!.setParameters('{"che.audio.enable.agc":true}');
    await _engine!.setParameters('{"che.audio.enable.ns":true}');

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        debugPrint('✅ [Agora] Joined: ${connection.channelId} (${elapsed}ms)');
        _setConnectionState(RtcConnectionState.connected);
      },
      onRejoinChannelSuccess: (connection, elapsed) {
        debugPrint('✅ [Agora] Rejoined: ${connection.channelId}');
        _setConnectionState(RtcConnectionState.connected);
      },
      onLeaveChannel: (connection, rtcStats) {
        debugPrint('✅ [Agora] Left channel');
        _setConnectionState(RtcConnectionState.disconnected);
      },
      onUserJoined: (connection, uid, elapsed) {
        debugPrint('✅ [Agora] Remote user joined: $uid');
        _remoteUsers[uid] = RemoteUserState(uid: uid);
        if (!_remoteJoinedCtrl.isClosed) _remoteJoinedCtrl.add(uid);
        _safeNotify();
      },
      onUserOffline: (connection, uid, reason) {
        debugPrint('✅ [Agora] Remote user left: $uid (reason: $reason)');
        _remoteUsers.remove(uid);
        if (!_remoteLeftCtrl.isClosed) _remoteLeftCtrl.add(uid);
        _safeNotify();
      },
      onConnectionStateChanged: (connection, state, reason) {
        debugPrint('ℹ️ [Agora] Connection state: $state (reason: $reason)');
        _setConnectionState(_mapConnectionState(state));
      },
      onConnectionLost: (connection) {
        debugPrint('⚠️ [Agora] Connection lost');
        _setConnectionState(RtcConnectionState.reconnecting);
      },
      onRemoteVideoStateChanged: (connection, uid, state, reason, elapsed) {
        if (_remoteUsers.containsKey(uid)) {
          final isOn = state == RemoteVideoState.remoteVideoStateDecoding ||
              state == RemoteVideoState.remoteVideoStateStarting;
          _remoteUsers[uid] = _remoteUsers[uid]!.copyWith(videoOn: isOn);
          _safeNotify();
        }
      },
      onRemoteAudioStateChanged: (connection, uid, state, reason, elapsed) {
        if (_remoteUsers.containsKey(uid)) {
          final isOn = state == RemoteAudioState.remoteAudioStateDecoding ||
              state == RemoteAudioState.remoteAudioStateStarting;
          _remoteUsers[uid] = _remoteUsers[uid]!.copyWith(audioOn: isOn);
          _safeNotify();
        }
      },
      onActiveSpeaker: (connection, uid) {
        if (!_activeSpeakerCtrl.isClosed) _activeSpeakerCtrl.add(uid);
      },
      onNetworkQuality: (connection, uid, txQuality, rxQuality) {
        if (uid == 0) {
          final worst = txQuality.index > rxQuality.index ? txQuality : rxQuality;
          final q = _mapNetworkQuality(worst);
          if (q != _networkQuality) {
            _networkQuality = q;
            if (!_networkQualityCtrl.isClosed) _networkQualityCtrl.add(q);
          }
        }
      },
      onRtcStats: (connection, rtcStats) {
        if (_disposed) return;
        _stats = RtcCallStats(
          txBitrate: rtcStats.txKBitRate ?? 0,
          rxBitrate: rtcStats.rxKBitRate ?? 0,
          txPacketLoss: rtcStats.txPacketLossRate ?? 0,
          rxPacketLoss: rtcStats.rxPacketLossRate ?? 0,
          rtt: rtcStats.lastmileDelay ?? 0,
          duration: rtcStats.duration ?? 0,
        );
        _safeNotify();
      },
      onTokenPrivilegeWillExpire: (connection, token) async {
        debugPrint('⚠️ [Agora] Token will expire — refreshing');
        if (_currentChannel != null) {
          final newToken = await _fetchToken(_currentChannel!);
          if (newToken != null) {
            await _engine?.renewToken(newToken);
          }
        }
      },
      onError: (err, msg) {
        debugPrint('❌ [Agora] Error $err: $msg');
        _emitError('Lỗi cuộc gọi ($err): $msg');
      },
    ));
  }

  Future<String?> _fetchToken(String channelName, {int uid = 0}) async {
    const maxRetries = 3;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final url = Uri.parse(
          '$_tokenServerBase/rtc/$channelName/publisher/uid/$uid',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          final token = (body['rtcToken'] ?? body['token']) as String?;
          if (token != null && token.isNotEmpty) {
            debugPrint('✅ [Agora] Token fetched (attempt ${attempt + 1})');
            return token;
          }
        } else {
          debugPrint('❌ [Agora] Token server ${res.statusCode}: ${res.body}');
        }
      } catch (e) {
        debugPrint('❌ [Agora] Token fetch attempt ${attempt + 1}: $e');
      }
      if (attempt < maxRetries - 1) {
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    debugPrint('❌ [Agora] Could not fetch token after $maxRetries attempts');
    return null;
  }

  Future<void> _requestPermissions({bool video = false}) async {
    if (kIsWeb) return;
    final perms = [Permission.microphone];
    if (video) perms.add(Permission.camera);
    final statuses = await perms.request();
    for (final e in statuses.entries) {
      if (!e.value.isGranted) {
        debugPrint('⚠️ [Agora] Permission not granted: ${e.key}');
      }
    }
  }

  void _setConnectionState(RtcConnectionState state) {
    if (_disposed || _connectionState == state) return;
    _connectionState = state;
    if (!_connectionCtrl.isClosed) _connectionCtrl.add(state);
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _emitError(String msg) {
    if (!_disposed && !_errorCtrl.isClosed) _errorCtrl.add(msg);
  }

  Future<void> _safeCall(Future<void>? Function() fn) async {
    try {
      await fn();
    } catch (e) {
      debugPrint('⚠️ [Agora] _safeCall: $e');
    }
  }

  RtcConnectionState _mapConnectionState(ConnectionStateType s) {
    switch (s) {
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

  NetworkQuality _mapNetworkQuality(QualityType q) {
    switch (q) {
      case QualityType.qualityExcellent:
        return NetworkQuality.excellent;
      case QualityType.qualityGood:
        return NetworkQuality.good;
      case QualityType.qualityPoor:
        return NetworkQuality.poor;
      case QualityType.qualityBad:
        return NetworkQuality.bad;
      case QualityType.qualityVbad:
        return NetworkQuality.veryBad;
      case QualityType.qualityDown:
        return NetworkQuality.down;
      default:
        return NetworkQuality.unknown;
    }
  }
}
