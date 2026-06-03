import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../app/app_controller.dart';

class DesktopClient {
  DesktopClient({required this.controller, required this.sessionId});

  final AppController controller;
  final String sessionId;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _remoteStream;

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
          {'url': 'stun:stun.l.google.com:19302'}
        ],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(config);

      // Listen for remote streams
      _peerConnection!.onTrack = (event) {
        if (event.track.kind == 'video') {
          if (event.streams.isNotEmpty) {
            _remoteStream = event.streams.first;
            _streamController.add(_remoteStream!);
          }
        }
      };

      _peerConnection!.onConnectionState = (state) {
        _stateController.add(state.toString().split('.').last);
      };

      // Create data channel for inputs
      final dcConfig = RTCDataChannelInit()..ordered = true;
      _dataChannel =
          await _peerConnection!.createDataChannel('input', dcConfig);

      // Handle ICE Candidates generated locally
      _peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
        if (candidate != null) {
          _sendIceCandidate(candidate);
        }
      };

      // Create SDP Offer
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': true,
        'offerToReceiveAudio': false,
      });
      await _peerConnection!.setLocalDescription(offer);

      // Send SDP Offer to Bridge
      final response = await controller.gatewayAcpClientInternal.request(
        method: 'xworkmate.desktop.offer',
        params: {
          'sessionId': sessionId,
          'sdpOffer': offer.sdp,
          'display': display,
          'width': width.toString(),
          'height': height.toString(),
          'fps': fps.toString(),
          'bitrate': bitrate.toString(),
          'useGpu': useGpu.toString(),
        },
      );

      final sdpAnswer = response['result']?['sdpAnswer'] as String?;
      if (sdpAnswer == null) {
        throw Exception('Bridge failed to return SDP Answer');
      }

      // Apply SDP Answer
      final answer = RTCSessionDescription(sdpAnswer, 'answer');
      await _peerConnection!.setRemoteDescription(answer);

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
    } catch (_) {}
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
    } catch (_) {}

    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _remoteStream = null;
    _stateController.add('disconnected');
  }
}
