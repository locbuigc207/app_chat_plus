import 'dart:async';
import 'dart:convert';
import 'dart:typed_data'; // MỚI: Cần cho Int16List

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import 'realtime_ai_service.dart'; // MỚI: Import service AI của bạn

// ──────────────────────────────────────────────────────────────────────────────
// CUSTOM EXCEPTIONS (FIX BUG 2)
// ──────────────────────────────────────────────────────────────────────────────
class AgoraInitException implements Exception {
  final String message;
  AgoraInitException(this.message);
  @override
  String toString() => message;
}

class AgoraTokenException implements Exception {
  final String message;
  AgoraTokenException(this.message);
  @override
  String toString() => message;
}

// ──────────────────────────────────────────────────────────────────────────────
// MODELS
// ──────────────────────────────────────────────────────────────────────────────

enum RtcConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed
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

// ──────────────────────────────────────────────────────────────────────────────
// AGORA RTC MANAGER
// ──────────────────────────────────────────────────────────────────────────────
class AgoraRtcManager extends ChangeNotifier {
  // ── State ─────────────────────────────────────────────────────────────────
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

  // ── Streams ────────────────────────────────────────────────────────────────
  final _remoteJoinedCtrl = StreamController<int>.broadcast();
  final _remoteLeftCtrl = StreamController<int>.broadcast();
  final _connectionCtrl = StreamController<RtcConnectionState>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _networkQualityCtrl = StreamController<NetworkQuality>.broadcast();
  final _activeSpeakerCtrl = StreamController<int>.broadcast();
  final _audioLevelCtrl = StreamController<double>.broadcast();

  Stream<int> get remoteJoinedStream => _remoteJoinedCtrl.stream;
  Stream<int> get remoteLeftStream => _remoteLeftCtrl.stream;
  Stream<RtcConnectionState> get connectionStream => _connectionCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;
  Stream<NetworkQuality> get networkQualityStream => _networkQualityCtrl.stream;
  Stream<int> get activeSpeakerStream => _activeSpeakerCtrl.stream;
  Stream<double> get audioLevelStream => _audioLevelCtrl.stream;

  // ── Getters ────────────────────────────────────────────────────────────────
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

  String get _tokenServerBase => (dotenv.env['AGORA_TOKEN_SERVER'] ??
          'https://asia-southeast1-flutter-chat-app-3e625.cloudfunctions.net/generateAgoraToken')
      .trim();
  String get _appId => (dotenv.env['AGORA_APP_ID'] ?? '').trim();

  // ── Initialize ────────────────────────────────────────────────────────────
  Future<bool> initialize() async {
    if (_initialized) return true;
    if (_disposed) return false;

    // FIX BUG 2: Ném Exception thay vì fail silent nếu không có App ID
    if (_appId.isEmpty) {
      _emitError('AGORA_APP_ID chưa cấu hình trong .env');
      throw AgoraInitException(
          'Lỗi hệ thống: AGORA_APP_ID chưa được cấu hình. Không thể khởi tạo cuộc gọi.');
    }

    try {
      await _requestPermissions(video: true);
      await _initEngine();
      _initialized = true;
      debugPrint('✅ [AgoraRtcManager] Initialized');
      return true;
    } catch (e, st) {
      debugPrint('❌ [AgoraRtcManager] initialize: $e\n$st');
      _emitError('Không thể khởi tạo engine: $e');
      throw AgoraInitException('Lỗi khởi tạo Agora Engine: $e');
    }
  }

  // ── Join channel ──────────────────────────────────────────────────────────
  Future<bool> joinChannel({
    required String channelName,
    required bool isVideoCall,
    int uid = 0,
    String? token,
  }) async {
    if (_disposed || _joining) return false;

    final ch = channelName.trim();
    if (ch.isEmpty) {
      _emitError('Tên kênh không hợp lệ');
      return false;
    }

    if (!_initialized) {
      // Vì initialize() giờ có thể throw Exception, ta để nó sập vào catch bên dưới nếu lỗi
      await initialize();
    }

    _joining = true;
    _isVideoCall = isVideoCall;

    try {
      await _requestPermissions(video: isVideoCall);
      _currentChannel = ch;
      _setConnectionState(RtcConnectionState.connecting);

      final rtcToken = token ?? await _fetchToken(ch, uid: uid);

      // FIX BUG 2: Ném Exception nếu token rỗng (đề phòng Agora Console đã bật Token Auth)
      if (rtcToken == null || rtcToken.isEmpty) {
        throw AgoraTokenException(
            'Token rỗng hoặc không hợp lệ. Vui lòng kiểm tra lại cấu hình Token Authentication.');
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

      debugPrint('✅ [AgoraRtcManager] joinChannel dispatched: $ch');
      return true;
    } catch (e, st) {
      debugPrint('❌ [AgoraRtcManager] joinChannel: $e\n$st');
      _setConnectionState(RtcConnectionState.failed);
      _emitError('Không thể kết nối cuộc gọi: $e');
      // FIX BUG 2: Bắt buộc rethrow để UI gọi hàm này bắt được lỗi và show Dialog
      rethrow;
    } finally {
      _joining = false;
    }
  }

  // ── Leave channel ─────────────────────────────────────────────────────────
  Future<void> leaveChannel() async {
    if (!_initialized || _engine == null) return;
    try {
      await _engine!.leaveChannel();
    } catch (e) {
      debugPrint('⚠️ [AgoraRtcManager] leaveChannel: $e');
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

  // ── Controls ──────────────────────────────────────────────────────────────
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
    await _safeCall(
      () => _engine?.adjustUserPlaybackSignalVolume(
          uid: uid, volume: volume.clamp(0, 400)),
    );
  }

  Future<void> muteRemoteVideo(int uid, {required bool mute}) async {
    if (_disposed) return;
    await _safeCall(() => _engine?.muteRemoteVideoStream(uid: uid, mute: mute));
    if (_remoteUsers.containsKey(uid)) {
      _remoteUsers[uid] = _remoteUsers[uid]!.copyWith(videoOn: !mute);
      _safeNotify();
    }
  }

  // ── Engine init ───────────────────────────────────────────────────────────
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

    // Echo cancellation & noise suppression
    await _engine!.setParameters('{"che.audio.enable.aec":true}');
    await _engine!.setParameters('{"che.audio.enable.agc":true}');
    await _engine!.setParameters('{"che.audio.enable.ns":true}');

    // Enable audio volume indication for visualizer (200ms interval)
    await _engine!.enableAudioVolumeIndication(
      interval: 200,
      smooth: 3,
      reportVad: true,
    );

// =========================================================================
    // 💡 TÍCH HỢP DEEPFAKE DETECTION TẠI ĐÂY
    // Cấu hình Agora để xuất luồng Raw Audio 16kHz, 1 Channel
    // =========================================================================
    try {
      await _engine!.setRecordingAudioFrameParameters(
        sampleRate: 16000,
        channel: 1,
        mode: RawAudioFrameOpModeType.rawAudioFrameOpModeReadOnly,
        samplesPerCall: 1024,
      );

      _engine!.getMediaEngine().registerAudioFrameObserver(
            AudioFrameObserver(
              onRecordAudioFrame: (String channelId, AudioFrame audioFrame) {
                if (audioFrame.buffer != null) {
                  try {
                    // Chuyển đổi mảng Uint8List từ C++ sang Int16List (Zero-copy)
                    final bytes = audioFrame.buffer!;
                    final pcm16Data = Int16List.view(
                      bytes.buffer,
                      bytes.offsetInBytes,
                      bytes.lengthInBytes ~/ 2,
                    );

                    // Gửi dữ liệu âm thanh thô vào Engine AI
                    RealtimeAIService().feedAudioBuffer(pcm16Data);
                  } catch (e) {
                    debugPrint('[Deepfake] Lỗi khi xử lý Audio Frame: $e');
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
      debugPrint('✅ [Agora] Đã đăng ký AudioFrameObserver cho Deepfake Engine');
    } catch (e) {
      debugPrint('❌ [Agora] Không thể đăng ký AudioFrameObserver: $e');
    }
    // =========================================================================
    // =========================================================================

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, elapsed) {
        debugPrint('✅ [Agora] Joined: ${conn.channelId} (${elapsed}ms)');
        _setConnectionState(RtcConnectionState.connected);
      },
      onRejoinChannelSuccess: (conn, elapsed) {
        debugPrint('✅ [Agora] Rejoined: ${conn.channelId}');
        _setConnectionState(RtcConnectionState.connected);
      },
      onLeaveChannel: (conn, stats) {
        debugPrint('✅ [Agora] Left channel');
        _setConnectionState(RtcConnectionState.disconnected);
      },
      onUserJoined: (conn, uid, elapsed) {
        debugPrint('✅ [Agora] Remote joined: $uid');
        _remoteUsers[uid] = RemoteUserState(uid: uid);
        if (!_remoteJoinedCtrl.isClosed) _remoteJoinedCtrl.add(uid);
        _safeNotify();
      },
      onUserOffline: (conn, uid, reason) {
        debugPrint('✅ [Agora] Remote left: $uid (reason: $reason)');
        _remoteUsers.remove(uid);
        if (!_remoteLeftCtrl.isClosed) _remoteLeftCtrl.add(uid);
        _safeNotify();
      },
      onConnectionStateChanged: (conn, state, reason) {
        debugPrint('ℹ️ [Agora] Connection state: $state (reason: $reason)');
        _setConnectionState(_mapConnState(state));
      },
      onConnectionLost: (conn) {
        debugPrint('⚠️ [Agora] Connection lost');
        _setConnectionState(RtcConnectionState.reconnecting);
      },
      onRemoteVideoStateChanged: (conn, uid, state, reason, elapsed) {
        if (_remoteUsers.containsKey(uid)) {
          final on = state == RemoteVideoState.remoteVideoStateDecoding ||
              state == RemoteVideoState.remoteVideoStateStarting;
          _remoteUsers[uid] = _remoteUsers[uid]!.copyWith(videoOn: on);
          _safeNotify();
        }
      },
      onRemoteAudioStateChanged: (conn, uid, state, reason, elapsed) {
        if (_remoteUsers.containsKey(uid)) {
          final on = state == RemoteAudioState.remoteAudioStateDecoding ||
              state == RemoteAudioState.remoteAudioStateStarting;
          _remoteUsers[uid] = _remoteUsers[uid]!.copyWith(audioOn: on);
          _safeNotify();
        }
      },
      onActiveSpeaker: (conn, uid) {
        if (!_activeSpeakerCtrl.isClosed) _activeSpeakerCtrl.add(uid);
      },
      onAudioVolumeIndication: (conn, speakers, speakerNum, totalVolume) {
        if (_disposed || _audioLevelCtrl.isClosed) return;
        // totalVolume: 0-255; normalize to 0.0-1.0
        final normalized = (totalVolume / 255.0).clamp(0.0, 1.0);
        _audioLevelCtrl.add(normalized.toDouble());
      },
      onNetworkQuality: (conn, uid, txQuality, rxQuality) {
        if (uid == 0) {
          final worst =
              txQuality.index > rxQuality.index ? txQuality : rxQuality;
          final q = _mapNetQuality(worst);
          if (q != _networkQuality) {
            _networkQuality = q;
            if (!_networkQualityCtrl.isClosed) _networkQualityCtrl.add(q);
          }
        }
      },
      onRtcStats: (conn, rtcStats) {
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
      onTokenPrivilegeWillExpire: (conn, token) async {
        debugPrint('⚠️ [Agora] Token expiring — refreshing');
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

  // ── Token fetch ───────────────────────────────────────────────────────────
  Future<String?> _fetchToken(String channelName, {int uid = 0}) async {
    const maxRetries = 3;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final url =
            Uri.parse('$_tokenServerBase?channelName=$channelName&uid=$uid');
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
        debugPrint('❌ [Agora] Token attempt ${attempt + 1}: $e');
      }
      if (attempt < maxRetries - 1) {
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }

    debugPrint('❌ [Agora] Could not fetch token after $maxRetries attempts');
    // FIX BUG 2: Ném exception sau khi đã retries tối đa mà vẫn không có token
    throw AgoraTokenException(
        'Không thể kết nối đến máy chủ Token sau $maxRetries lần thử.');
  }

  // ── Permissions ───────────────────────────────────────────────────────────
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

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _setConnectionState(RtcConnectionState s) {
    if (_disposed || _connectionState == s) return;
    _connectionState = s;
    if (!_connectionCtrl.isClosed) _connectionCtrl.add(s);
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

  RtcConnectionState _mapConnState(ConnectionStateType s) {
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

  NetworkQuality _mapNetQuality(QualityType q) {
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

// ── Dispose ───────────────────────────────────────────────────────────────
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    try {
      _engine?.getMediaEngine().registerAudioFrameObserver(AudioFrameObserver(
            onRecordAudioFrame: (channelId, audioFrame) {},
            onPlaybackAudioFrame: (channelId, audioFrame) {},
            onMixedAudioFrame: (channelId, audioFrame) {},
            onEarMonitoringAudioFrame: (audioFrame) {},
            onPlaybackAudioFrameBeforeMixing: (channelId, uid, audioFrame) {},
          ));
    } catch (_) {}

    _engine?.leaveChannel().catchError((_) {});

    _remoteJoinedCtrl.close();
    _remoteLeftCtrl.close();
    _connectionCtrl.close();
    _errorCtrl.close();
    _networkQualityCtrl.close();
    _activeSpeakerCtrl.close();
    _audioLevelCtrl.close();

    _engine?.release().catchError((_) {});
    _engine = null;

    super.dispose();
  }
}
