import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:xworkmate/features/desktop/desktop_client.dart';

void main() {
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
  });
}
