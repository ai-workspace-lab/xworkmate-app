import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../app/app_controller.dart';
import '../../runtime/gateway_runtime_helpers.dart';

const String desktopReliableInputChannelLabel = 'input';
const String desktopMoveInputChannelLabel = 'input-move';
const int desktopReliableInputChannelId = 0;
const int desktopMoveInputChannelId = 1;
const int desktopMoveChannelMaxPacketLifeTimeMs = 100;
const int desktopMoveBufferedAmountLimit = 16 * 1024;
const Duration desktopOfferRequestTimeout = Duration(seconds: 15);

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

bool desktopShouldDropInputEvent(
  Map<String, dynamic> event, {
  required int bufferedAmount,
  int bufferedAmountLimit = desktopMoveBufferedAmountLimit,
}) {
  return event['type'] == 'mouse_move' && bufferedAmount > bufferedAmountLimit;
}

String desktopInputChannelLabelForEvent(Map<String, dynamic> event) {
  return event['type'] == 'mouse_move'
      ? desktopMoveInputChannelLabel
      : desktopReliableInputChannelLabel;
}

RTCDataChannelInit desktopReliableInputChannelConfig() {
  return RTCDataChannelInit()
    ..ordered = true
    ..id = desktopReliableInputChannelId;
}

RTCDataChannelInit desktopMoveInputChannelConfig() {
  return RTCDataChannelInit()
    ..ordered = false
    ..id = desktopMoveInputChannelId
    ..maxRetransmitTime = desktopMoveChannelMaxPacketLifeTimeMs;
}

bool desktopHasRenderedVideoFrame({
  required bool hasStream,
  required int rendererVideoWidth,
  required int rendererVideoHeight,
  required bool hasDecodedFrames,
}) {
  return hasStream &&
      (hasDecodedFrames || (rendererVideoWidth > 0 && rendererVideoHeight > 0));
}

String desktopSessionId() {
  return 'remote-desktop-${randomIdInternal()}';
}

Future<MediaStream?> desktopRemoteVideoStreamForTrack(
  RTCTrackEvent event, {
  required Future<MediaStream> Function(String label) createFallbackStream,
}) async {
  if (event.track.kind != 'video') {
    return null;
  }
  if (event.streams.isNotEmpty) {
    return event.streams.first;
  }
  final stream = await createFallbackStream('xworkmate-remote-desktop');
  await stream.addTrack(event.track);
  return stream;
}

class DesktopWebRtcStatsSnapshot {
  const DesktopWebRtcStatsSnapshot({
    required this.inboundVideoReports,
    required this.packetsReceived,
    required this.bytesReceived,
    required this.framesDecoded,
    required this.framesDropped,
    required this.keyFramesDecoded,
    required this.jitter,
    required this.jitterBufferDelay,
  });

  final int inboundVideoReports;
  final int? packetsReceived;
  final int? bytesReceived;
  final int? framesDecoded;
  final int? framesDropped;
  final int? keyFramesDecoded;
  final double? jitter;
  final double? jitterBufferDelay;

  bool get hasRtpPackets => (packetsReceived ?? 0) > 0;
  bool get hasDecodedFrames => (framesDecoded ?? 0) > 0;

  @override
  String toString() {
    return 'inboundVideoReports=$inboundVideoReports '
        'packetsReceived=${packetsReceived ?? 'unknown'} '
        'bytesReceived=${bytesReceived ?? 'unknown'} '
        'framesDecoded=${framesDecoded ?? 'unknown'} '
        'keyFramesDecoded=${keyFramesDecoded ?? 'unknown'} '
        'framesDropped=${framesDropped ?? 'unknown'} '
        'jitter=${jitter ?? 'unknown'} '
        'jitterBufferDelay=${jitterBufferDelay ?? 'unknown'}';
  }
}

DesktopWebRtcStatsSnapshot desktopVideoStatsSnapshotFromReports(
  List<StatsReport> reports,
) {
  int inboundVideoReports = 0;
  int? packetsReceived;
  int? bytesReceived;
  int? framesDecoded;
  int? framesDropped;
  int? keyFramesDecoded;
  double? jitter;
  double? jitterBufferDelay;

  for (final report in reports) {
    final values = report.values;
    final type = report.type.toString();
    final kind = values['kind']?.toString() ?? values['mediaType']?.toString();
    final isInboundVideo =
        type == 'inbound-rtp' && (kind == null || kind == 'video');
    if (!isInboundVideo) {
      continue;
    }
    inboundVideoReports += 1;
    packetsReceived ??= _statsInt(values['packetsReceived']);
    bytesReceived ??= _statsInt(values['bytesReceived']);
    framesDecoded ??= _statsInt(values['framesDecoded']);
    framesDropped ??= _statsInt(values['framesDropped']);
    keyFramesDecoded ??= _statsInt(values['keyFramesDecoded']);
    jitter ??= _statsDouble(values['jitter']);
    jitterBufferDelay ??= _statsDouble(values['jitterBufferDelay']);
  }

  return DesktopWebRtcStatsSnapshot(
    inboundVideoReports: inboundVideoReports,
    packetsReceived: packetsReceived,
    bytesReceived: bytesReceived,
    framesDecoded: framesDecoded,
    framesDropped: framesDropped,
    keyFramesDecoded: keyFramesDecoded,
    jitter: jitter,
    jitterBufferDelay: jitterBufferDelay,
  );
}

int? _statsInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double? _statsDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

class DesktopClient {
  DesktopClient({required this.controller, required this.sessionId});

  final AppController controller;
  final String sessionId;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _inputChannel;
  RTCDataChannel? _moveInputChannel;

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

  Future<DesktopWebRtcStatsSnapshot?> collectVideoStats() async {
    final peerConnection = _peerConnection;
    if (peerConnection == null) {
      return null;
    }
    final reports = await peerConnection.getStats();
    return desktopVideoStatsSnapshotFromReports(reports);
  }

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

      // Create input data channels BEFORE creating the offer.
      _inputChannel = await _peerConnection!.createDataChannel(
        desktopReliableInputChannelLabel,
        desktopReliableInputChannelConfig(),
      );
      _moveInputChannel = await _peerConnection!.createDataChannel(
        desktopMoveInputChannelLabel,
        desktopMoveInputChannelConfig(),
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

      // Bridge publishes a video-only desktop stream; keep SDP m-line mapping
      // simple so reconnects do not depend on rejected audio sections.
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      // Create SDP Offer
      final offer = await _peerConnection!.createOffer({});
      await _peerConnection!.setLocalDescription(offer);

      // Send SDP Offer to Bridge
      final response = await controller.gatewayAcpClientInternal
          .request(
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
          )
          .timeout(
            desktopOfferRequestTimeout,
            onTimeout: () => throw TimeoutException(
              'Timed out waiting for desktop SDP answer',
              desktopOfferRequestTimeout,
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
    final channel =
        desktopInputChannelLabelForEvent(event) == desktopMoveInputChannelLabel
        ? (_moveInputChannel ?? _inputChannel)
        : _inputChannel;
    if (channel != null &&
        channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      final bufferedAmount = channel.bufferedAmount ?? 0;
      if (desktopShouldDropInputEvent(event, bufferedAmount: bufferedAmount)) {
        return;
      }
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

    await _moveInputChannel?.close();
    await _inputChannel?.close();
    await _peerConnection?.close();
    _moveInputChannel = null;
    _inputChannel = null;
    _peerConnection = null;
    _stateController.add('disconnected');
  }
}
