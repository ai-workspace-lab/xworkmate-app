import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xworkmate/features/desktop/desktop_client.dart';

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

    test('creates a synthetic media stream when the bridge omits streams', () async {
      final track = _FakeMediaStreamTrack(
        id: 'track-1',
        kind: 'video',
      );
      final createdStreams = <_FakeMediaStream>[];

      final stream = await desktopRemoteStreamFromTrack(
        track: track,
        streams: const <MediaStream>[],
        streamFactory: (streamId) async {
          final stream = _FakeMediaStream(streamId);
          createdStreams.add(stream);
          return stream;
        },
      );

      expect(stream, isNotNull);
      expect(createdStreams, hasLength(1));
      expect(stream, same(createdStreams.single));
      expect(createdStreams.single.getVideoTracks(), hasLength(1));
      expect(createdStreams.single.getVideoTracks().single, same(track));
    });

    test('prefers the attached remote stream when one is present', () async {
      final track = _FakeMediaStreamTrack(
        id: 'track-2',
        kind: 'video',
      );
      final attachedStream = _FakeMediaStream('attached-stream');

      final stream = await desktopRemoteStreamFromTrack(
        track: track,
        streams: <MediaStream>[attachedStream],
        streamFactory: (streamId) async => _FakeMediaStream(streamId),
      );

      expect(stream, same(attachedStream));
      expect(stream!.getVideoTracks(), isEmpty);
    });
  });
}

class _FakeMediaStreamTrack extends MediaStreamTrack {
  _FakeMediaStreamTrack({required this.id, required this.kind});

  @override
  final String id;

  @override
  final String kind;

  @override
  String? get label => 'fake';

  @override
  bool get enabled => true;

  @override
  set enabled(bool b) {}

  @override
  bool? get muted => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeMediaStream extends MediaStream {
  _FakeMediaStream(String id) : super(id, 'test-owner');

  final List<MediaStreamTrack> _tracks = <MediaStreamTrack>[];

  @override
  bool? get active => _tracks.isNotEmpty;

  @override
  Future<void> getMediaTracks() async {}

  @override
  Future<void> addTrack(MediaStreamTrack track, {bool addToNative = true}) async {
    _tracks.add(track);
  }

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    _tracks.remove(track);
  }

  @override
  List<MediaStreamTrack> getTracks() => List<MediaStreamTrack>.unmodifiable(_tracks);

  @override
  List<MediaStreamTrack> getAudioTracks() =>
      _tracks.where((track) => track.kind == 'audio').toList(growable: false);

  @override
  List<MediaStreamTrack> getVideoTracks() =>
      _tracks.where((track) => track.kind == 'video').toList(growable: false);

  @override
  Future<MediaStream> clone() async => _FakeMediaStream('${id}_clone');
}
