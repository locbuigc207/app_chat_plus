import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/group_call_model.dart';
import '../services/group_call_recording_service.dart';
import '../services/group_call_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GroupCallProvider
// Central ChangeNotifier managing the lifecycle and state of an active group
// call session. Use with Provider/Consumer for reactive UI updates.
// ══════════════════════════════════════════════════════════════════════════════
class GroupCallProvider extends ChangeNotifier {
  GroupCallProvider({required this.currentUserId});

  final String currentUserId;

  // ── Active call state ──────────────────────────────────────────────────────
  GroupCallModel? _activeCall;
  bool _isInitiator = false;
  bool _isMuted = false;
  bool _isCamOff = false;
  bool _isSpeakerOn = true;
  bool _isScreenSharing = false;
  bool _handRaised = false;
  bool _isRecording = false;
  bool _chatOpen = false;
  bool _participantsOpen = false;
  int _unreadChatCount = 0;

  // ── Pending state ──────────────────────────────────────────────────────────
  bool _loading = false;
  String? _error;

  // ── Stream subscriptions ───────────────────────────────────────────────────
  StreamSubscription? _callSub;

  // ── Getters ────────────────────────────────────────────────────────────────
  GroupCallModel? get activeCall => _activeCall;
  bool get hasActiveCall => _activeCall != null;
  bool get isInitiator => _isInitiator;
  bool get isMuted => _isMuted;
  bool get isCamOff => _isCamOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isScreenSharing => _isScreenSharing;
  bool get handRaised => _handRaised;
  bool get isRecording => _isRecording;
  bool get chatOpen => _chatOpen;
  bool get participantsOpen => _participantsOpen;
  int get unreadChatCount => _unreadChatCount;
  bool get loading => _loading;
  String? get error => _error;

  bool get isAdmin =>
      _activeCall?.getParticipant(currentUserId)?.isAdmin ?? false;
  bool get isCoHost =>
      _activeCall?.getParticipant(currentUserId)?.isCoHost ?? false;
  bool get canModerate => isAdmin || isCoHost;

  // ── Start call ─────────────────────────────────────────────────────────────
  Future<GroupCallModel?> startCall({
    required String groupId,
    required String groupName,
    required String groupAvatarUrl,
    required List<String> memberIds,
    required GroupCallType callType,
    bool waitingRoomEnabled = false,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final call = await GroupCallService.instance.initiateCall(
        groupId: groupId,
        groupName: groupName,
        groupAvatarUrl: groupAvatarUrl,
        memberIds: memberIds,
        callType: callType,
        waitingRoomEnabled: waitingRoomEnabled,
      );

      if (call == null) {
        _setError('Không thể bắt đầu cuộc gọi. Có thể đang có cuộc gọi khác.');
        return null;
      }

      _isInitiator = true;
      _setActiveCall(call);
      return call;
    } catch (e) {
      _setError('Lỗi khi bắt đầu cuộc gọi: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  // ── Join call ──────────────────────────────────────────────────────────────
  Future<bool> joinCall(String callId) async {
    _setLoading(true);
    _clearError();

    try {
      final ok = await GroupCallService.instance.joinCall(callId);
      if (!ok) {
        _setError('Không thể tham gia cuộc gọi.');
        return false;
      }

      final call = await GroupCallService.instance.getCall(callId);
      if (call != null) {
        _isInitiator = false;
        _setActiveCall(call);
      }
      return true;
    } catch (e) {
      _setError('Lỗi khi tham gia cuộc gọi: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ── Leave / End ────────────────────────────────────────────────────────────
  Future<void> leaveCall() async {
    final call = _activeCall;
    if (call == null) return;

    if (_isInitiator) {
      await GroupCallService.instance.endCallForAll(call.callId);
    } else {
      await GroupCallService.instance.leaveCall(call.callId);
    }
    _clearCall();
  }

  Future<void> endCallForAll() async {
    final call = _activeCall;
    if (call == null) return;
    await GroupCallService.instance.endCallForAll(call.callId);
    _clearCall();
  }

  // ── Watch live updates ─────────────────────────────────────────────────────
  void _setActiveCall(GroupCallModel call) {
    _activeCall = call;
    _callSub?.cancel();
    _callSub =
        GroupCallService.instance.watchCall(call.callId).listen((updated) {
      if (updated == null) {
        _clearCall();
        return;
      }
      _activeCall = updated;
      if (updated.isEnded) _clearCall();
      notifyListeners();
    });
    notifyListeners();
  }

  // ── Local media toggles ────────────────────────────────────────────────────
  Future<void> toggleMute() async {
    final call = _activeCall;
    if (call == null) return;
    _isMuted = !_isMuted;
    await GroupCallService.instance.updateParticipantState(
      callId: call.callId,
      isMuted: _isMuted,
      isCameraOff: _isCamOff,
    );
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final call = _activeCall;
    if (call == null) return;
    _isCamOff = !_isCamOff;
    await GroupCallService.instance.updateParticipantState(
      callId: call.callId,
      isMuted: _isMuted,
      isCameraOff: _isCamOff,
    );
    notifyListeners();
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    notifyListeners();
  }

  Future<void> toggleScreenShare() async {
    final call = _activeCall;
    if (call == null) return;
    _isScreenSharing = !_isScreenSharing;
    await GroupCallService.instance.updateScreenShare(
      callId: call.callId,
      userId: currentUserId,
      isSharing: _isScreenSharing,
    );
    notifyListeners();
  }

  Future<void> toggleHand() async {
    final call = _activeCall;
    if (call == null) return;
    _handRaised = !_handRaised;
    await GroupCallService.instance.toggleRaiseHand(
      callId: call.callId,
      userId: currentUserId,
      raised: _handRaised,
    );
    notifyListeners();
  }

  // ── Chat panel ─────────────────────────────────────────────────────────────
  void toggleChat() {
    _chatOpen = !_chatOpen;
    if (_chatOpen) _unreadChatCount = 0;
    notifyListeners();
  }

  void incrementUnread() {
    if (!_chatOpen) {
      _unreadChatCount++;
      notifyListeners();
    }
  }

  // ── Participants panel ─────────────────────────────────────────────────────
  void toggleParticipants() {
    _participantsOpen = !_participantsOpen;
    notifyListeners();
  }

  // ── Recording ──────────────────────────────────────────────────────────────
  Future<void> toggleRecording({
    required String channelName,
    required String agoraUid,
  }) async {
    final call = _activeCall;
    if (call == null || !isAdmin) return;

    if (_isRecording) {
      await GroupCallRecordingService.instance
          .stopRecording(callId: call.callId);
      _isRecording = false;
    } else {
      final ok = await GroupCallRecordingService.instance.startRecording(
        callId: call.callId,
        channelName: channelName,
        uid: agoraUid,
      );
      _isRecording = ok;
    }
    notifyListeners();
  }

  // ── Admin actions ──────────────────────────────────────────────────────────
  Future<void> muteParticipant(String targetId) async {
    final call = _activeCall;
    if (call == null || !canModerate) return;
    await GroupCallService.instance.muteParticipant(
        callId: call.callId, targetUserId: targetId, mute: true);
  }

  Future<void> kickParticipant(String targetId) async {
    final call = _activeCall;
    if (call == null || !isAdmin) return;
    await GroupCallService.instance
        .kickParticipant(callId: call.callId, targetUserId: targetId);
  }

  Future<void> muteAll() async {
    final call = _activeCall;
    if (call == null || !canModerate) return;
    await GroupCallService.instance.muteAll(call.callId);
  }

  Future<void> pinParticipant(String? userId) async {
    final call = _activeCall;
    if (call == null) return;
    await GroupCallService.instance.pinParticipant(call.callId, userId);
  }

  Future<void> admitFromWaiting(String userId) async {
    final call = _activeCall;
    if (call == null || !canModerate) return;
    await GroupCallService.instance
        .admitFromWaitingRoom(callId: call.callId, targetUserId: userId);
  }

  Future<void> promoteCoHost(String userId) async {
    final call = _activeCall;
    if (call == null || !isAdmin) return;
    await GroupCallService.instance.promoteToCoHost(call.callId, userId);
  }

  Future<void> sendReaction(CallReactionType type, String userName) async {
    final call = _activeCall;
    if (call == null) return;
    await GroupCallService.instance.sendReaction(
      callId: call.callId,
      userId: currentUserId,
      userName: userName,
      reaction: type,
    );
  }

  // ── Reset ──────────────────────────────────────────────────────────────────
  void _clearCall() {
    _callSub?.cancel();
    _callSub = null;
    _activeCall = null;
    _isInitiator = false;
    _isMuted = false;
    _isCamOff = false;
    _isSpeakerOn = true;
    _isScreenSharing = false;
    _handRaised = false;
    _isRecording = false;
    _chatOpen = false;
    _participantsOpen = false;
    _unreadChatCount = 0;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void _setError(String e) {
    _error = e;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
  }
}
