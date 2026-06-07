import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xworkmate/features/desktop/desktop_client.dart';

class FakeMediaStream extends MediaStream {
  FakeMediaStream(String id) : super(id, 'test');

  final List<MediaStreamTrack> tracks = [];
  final List<bool> addToNativeValues = [];

  @override
  bool? get active => true;

  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    tracks.add(track);
    addToNativeValues.add(addToNative);
  }

  @override
  Future<void> getMediaTracks() async {}

  @override
  List<MediaStreamTrack> getAudioTracks() =>
      tracks.where((track) => track.kind == 'audio').toList();

  @override
  MediaStreamTrack? getTrackById(String trackId) {
    for (final track in tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  @override
  List<MediaStreamTrack> getTracks() => List.unmodifiable(tracks);

  @override
  List<MediaStreamTrack> getVideoTracks() =>
      tracks.where((track) => track.kind == 'video').toList();

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    tracks.remove(track);
  }
}

class FakeMediaStreamTrack extends MediaStreamTrack {
  FakeMediaStreamTrack({required this.trackId, required this.trackKind});

  final String trackId;
  final String trackKind;
  bool _enabled = true;

  @override
  Future<ByteBuffer> captureFrame() {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {}

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool b) {
    _enabled = b;
  }

  @override
  Future<bool> hasTorch() async => false;

  @override
  String? get id => trackId;

  @override
  String? get kind => trackKind;

  @override
  String? get label => trackKind;

  @override
  bool? get muted => false;

  @override
  Future<void> setTorch(bool torch) async {}

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopClient protocol helpers', () {
    test('normalizes WebRTC connection states for view gating', () {
      expect(
        desktopConnectionStateName(
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
        ),
        'connected',
      );
      expect(
        desktopConnectionStateName(
          RTCPeerConnectionState.RTCPeerConnectionStateFailed,
        ),
        'failed',
      );
    });

    test('builds desktop offer params with native numeric values', () {
      final params = desktopOfferParams(
        sessionId: 'desktop-session-1',
        sdpOffer: 'v=0',
        display: ':0.0',
        width: 1280,
        height: 720,
        fps: 30,
        bitrate: 2000,
        useGpu: false,
      );

      expect(params['sessionId'], 'desktop-session-1');
      expect(params['sdpOffer'], 'v=0');
      expect(params['display'], ':0.0');
      expect(params['width'], isA<int>());
      expect(params['height'], isA<int>());
      expect(params['fps'], isA<int>());
      expect(params['bitrate'], isA<int>());
      expect(params['useGpu'], isA<bool>());
      expect(params['width'], 1280);
      expect(params['height'], 720);
    });

    test('uses bridge-provided remote stream when present', () async {
      var fallbackCreated = false;
      final providedStream = FakeMediaStream('provided-stream');
      final track = FakeMediaStreamTrack(
        trackId: 'video-track-1',
        trackKind: 'video',
      );

      final stream = await desktopRemoteVideoStreamForTrack(
        RTCTrackEvent(streams: [providedStream], track: track),
        createFallbackStream: (label) async {
          fallbackCreated = true;
          return FakeMediaStream(label);
        },
      );

      expect(stream, same(providedStream));
      expect(fallbackCreated, isFalse);
      expect(providedStream.tracks, isEmpty);
    });

    test('synthesizes stream for streamless remote video track', () async {
      final track = FakeMediaStreamTrack(
        trackId: 'video-track-1',
        trackKind: 'video',
      );
      final fallbackStream = FakeMediaStream('fallback-stream');

      final stream = await desktopRemoteVideoStreamForTrack(
        RTCTrackEvent(streams: const [], track: track),
        createFallbackStream: (label) async => fallbackStream,
      );

      expect(stream, same(fallbackStream));
      expect(fallbackStream.tracks, [same(track)]);
      expect(fallbackStream.addToNativeValues, [isTrue]);
    });

    test('ignores streamless non-video tracks', () async {
      var fallbackCreated = false;
      final track = FakeMediaStreamTrack(
        trackId: 'audio-track-1',
        trackKind: 'audio',
      );

      final stream = await desktopRemoteVideoStreamForTrack(
        RTCTrackEvent(streams: const [], track: track),
        createFallbackStream: (label) async {
          fallbackCreated = true;
          return FakeMediaStream(label);
        },
      );

      expect(stream, isNull);
      expect(fallbackCreated, isFalse);
    });

    test('summarizes inbound video stats for first-frame diagnostics', () {
      final snapshot = desktopVideoStatsSnapshotFromReports([
        StatsReport('RTCInboundRTPVideoStream_1', 'inbound-rtp', 1, {
          'id': 'RTCInboundRTPVideoStream_1',
          'type': 'inbound-rtp',
          'kind': 'video',
          'packetsReceived': 120,
          'bytesReceived': 48000,
          'framesDecoded': 0,
          'framesDropped': 0,
          'keyFramesDecoded': 0,
          'jitter': 0.003,
          'jitterBufferDelay': 0.12,
        }),
      ]);

      expect(snapshot.inboundVideoReports, 1);
      expect(snapshot.packetsReceived, 120);
      expect(snapshot.bytesReceived, 48000);
      expect(snapshot.framesDecoded, 0);
      expect(snapshot.keyFramesDecoded, 0);
      expect(snapshot.hasRtpPackets, isTrue);
      expect(snapshot.hasDecodedFrames, isFalse);
      expect(snapshot.toString(), contains('packetsReceived=120'));
    });
  });
}
