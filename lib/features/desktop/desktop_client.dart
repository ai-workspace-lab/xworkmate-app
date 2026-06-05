import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../app/app_controller.dart';

String desktopConnectionStateName(RTCPeerConnectionState state) {
  final value = state.toString().split('.').last;
  return value.replaceFirst('RTCPeerConnectionState', '').toLowerCase();
}

Map<String, Object?> desktopOfferParams({
  required String sessionId,
  required String? sdpOffer,
  required String display,
  required int width,
  required int height,
  required int fps,
  required int bitrate,
  required bool useGpu,
}) {
  return {
    'sessionId': sessionId,
    'sdpOffer': sdpOffer,
    'display': display,
    'width': width,
    'height': height,
    'fps': fps,
    'bitrate': bitrate,
    'useGpu': useGpu,
  };
}

Future<MediaStream?> desktopRemoteVideoStreamForTrack(
  RTCTrackEvent event, {
  required Future<MediaStream> Function(String label) createFallbackStream,
}) async {
  if (event.track.kind != 'video') {
    return null;
  }
  final stream = await createFallbackStream('xworkmate-remote-desktop');
  await stream.addTrack(event.track);
  return stream;
}

class DesktopClient {
  DesktopClient({required this.controller, required this.sessionId});

  final AppController controller;
  final String sessionId;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;

  final StreamController<MediaStream> _streamController =
      StreamController<MediaStream>.broadcast();
  Stream<MediaStream> get onRemoteStream => _streamController.stream;

  final StreamController<String> _stateController =
      StreamController<String>.broadcast();
  Stream<String> get onConnectionState => _stateController.stream;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;
  bool get isConnected =>
      _peerConnection?.connectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  Future<void> connect({
    String display = '',
    int width = 1280,
    int height = 720,
    int fps = 30,
    int bitrate = 2000,
    bool useGpu = false,
  }) async {
    if (_isConnecting || isConnected) return;
    _isConnecting = true;
    _stateController.add('connecting');

    try {
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(config);

      // Listen for remote video tracks. Some Unified Plan servers send
      // streamless tracks, so synthesize a stream for RTCVideoView when needed.
      _peerConnection!.onTrack = (event) {
        unawaited(() async {
          final stream = await desktopRemoteVideoStreamForTrack(
            event,
            createFallbackStream: createLocalMediaStream,
          );
          if (stream != null) {
            _streamController.add(stream);
          }
        }());
      };

      _peerConnection!.onConnectionState = (state) {
        _stateController.add(desktopConnectionStateName(state));
      };

      // Create data channel for inputs BEFORE creating offer
      final dcConfig = RTCDataChannelInit()..ordered = true;
      _dataChannel = await _peerConnection!.createDataChannel(
        'input',
        dcConfig,
      );

      // Handle ICE Candidates generated locally
      final List<RTCIceCandidate> iceQueue = [];
      bool isRemoteSet = false;

      _peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
        if (candidate != null) {
          if (isRemoteSet) {
            unawaited(_sendIceCandidate(candidate));
          } else {
            iceQueue.add(candidate);
          }
        }
      };

      // Add transceivers for receiving video and audio
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      // Create SDP Offer
      final offer = await _peerConnection!.createOffer({});
      await _peerConnection!.setLocalDescription(offer);

      // Send SDP Offer to Bridge
      final response = await controller.gatewayAcpClientInternal.request(
        method: 'xworkmate.desktop.offer',
        params: desktopOfferParams(
          sessionId: sessionId,
          sdpOffer: offer.sdp,
          display: display,
          width: width,
          height: height,
          fps: fps,
          bitrate: bitrate,
          useGpu: useGpu,
        ),
      );

      final sdpAnswerData = response['result']?['sdpAnswer'];
      if (sdpAnswerData == null) {
        throw Exception('Bridge failed to return SDP Answer');
      }

      // Apply SDP Answer
      late RTCSessionDescription answer;
      if (sdpAnswerData is Map) {
        answer = RTCSessionDescription(
          sdpAnswerData['sdp'] as String?,
          sdpAnswerData['type'] as String? ?? 'answer',
        );
      } else {
        answer = RTCSessionDescription(sdpAnswerData.toString(), 'answer');
      }
      await _peerConnection!.setRemoteDescription(answer);
      isRemoteSet = true;
      for (final candidate in iceQueue) {
        unawaited(_sendIceCandidate(candidate));
      }
      iceQueue.clear();

      _isConnecting = false;
    } catch (e) {
      _isConnecting = false;
      _stateController.add('failed');
      await disconnect();
      rethrow;
    }
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    try {
      await controller.gatewayAcpClientInternal.request(
        method: 'xworkmate.desktop.ice',
        params: {
          'sessionId': sessionId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        },
      );
    } catch (error) {
      debugPrint('Desktop ICE candidate send failed: $error');
    }
  }

  void sendInput(Map<String, dynamic> event) {
    final channel = _dataChannel;
    if (channel != null &&
        channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      final jsonStr = jsonEncode(event);
      channel.send(RTCDataChannelMessage(jsonStr));
    }
  }

  Future<void> disconnect() async {
    try {
      await controller.gatewayAcpClientInternal.request(
        method: 'xworkmate.desktop.close',
        params: {'sessionId': sessionId},
      );
    } catch (error) {
      debugPrint('Desktop close request failed: $error');
    }

    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _stateController.add('disconnected');
  }
}
