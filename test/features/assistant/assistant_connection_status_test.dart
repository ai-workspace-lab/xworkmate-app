import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller_desktop_thread_sessions.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  group('Assistant connection status surfaces', () {
    test(
      'uses ACP readiness as the only connection truth and ignores stale runtime snapshot state',
      () {
        final state = resolveGatewayThreadConnectionStateInternal(
          target: AssistantExecutionTarget.agent,
          bridgeReady: true,
          bridgeLabel: 'xworkmate-bridge.svc.plus',
          accountSyncState: AccountSyncState.defaults().copyWith(
            syncState: 'blocked',
            syncMessage: 'Bridge authorization is unavailable',
            lastSyncError: 'Bridge authorization is unavailable',
          ),
          accountSignedIn: true,
          bridgeConfigured: true,
        );

        expect(state.connected, isTrue);
        expect(state.status, RuntimeConnectionStatus.connected);
        expect(state.primaryLabel, '已连接');
        expect(state.detailLabel, 'xworkmate-bridge.svc.plus');
        expect(state.gatewayTokenMissing, isFalse);
      },
    );

    test('requires the target capability contract before reporting ready', () {
      expect(
        bridgeCapabilityReadyForExecutionTargetInternal(
          target: AssistantExecutionTarget.gateway,
          bridgeConfigured: true,
          providers: const <SingleAgentProvider>[SingleAgentProvider.openclaw],
          availableTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
          ],
        ),
        isFalse,
      );

      expect(
        bridgeCapabilityReadyForExecutionTargetInternal(
          target: AssistantExecutionTarget.gateway,
          bridgeConfigured: true,
          providers: const <SingleAgentProvider>[SingleAgentProvider.openclaw],
          availableTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
        ),
        isTrue,
      );
    });

    test('maps blocked bridge authorization into the token-missing state', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.gateway,
        bridgeReady: false,
        bridgeLabel: 'xworkmate-bridge.svc.plus',
        accountSyncState: AccountSyncState.defaults().copyWith(
          syncState: 'blocked',
          syncMessage: 'Bridge authorization is unavailable',
          lastSyncError: 'Bridge authorization is unavailable',
          profileScope: 'bridge',
        ),
        accountSignedIn: true,
        bridgeConfigured: true,
      );

      expect(state.connected, isFalse);
      expect(state.status, RuntimeConnectionStatus.error);
      expect(state.primaryLabel, '缺少令牌');
      expect(state.detailLabel, 'xworkmate-bridge 授权不可用');
      expect(state.gatewayTokenMissing, isTrue);
    });

    test('stays offline when ACP contract is unavailable', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.gateway,
        bridgeReady: false,
        bridgeLabel: 'xworkmate-bridge.svc.plus',
        accountSyncState: null,
        accountSignedIn: true,
        bridgeConfigured: false,
      );

      expect(state.connected, isFalse);
      expect(state.status, RuntimeConnectionStatus.offline);
      expect(state.primaryLabel, '离线');
      expect(state.detailLabel, 'xworkmate-bridge 未连接');
      expect(state.gatewayTokenMissing, isFalse);
    });

    test('surfaces signed-out status when not signed in', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.gateway,
        bridgeReady: false,
        bridgeLabel: 'xworkmate-bridge.svc.plus',
        accountSyncState: null,
        accountSignedIn: false,
        bridgeConfigured: false,
      );

      expect(state.connected, isFalse);
      expect(state.status, RuntimeConnectionStatus.offline);
      expect(state.primaryLabel, '已退出登录');
      expect(state.detailLabel, '请先登录 svc.plus');
      expect(state.gatewayTokenMissing, isFalse);
    });

    test('surfaces discovering status when configured but not ready', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.gateway,
        bridgeReady: false,
        bridgeLabel: 'xworkmate-bridge.svc.plus',
        accountSyncState: null,
        accountSignedIn: true,
        bridgeConfigured: true,
      );

      expect(state.connected, isFalse);
      expect(state.status, RuntimeConnectionStatus.offline);
      expect(state.primaryLabel, '正在发现');
      expect(state.detailLabel, '正在加载 Bridge 能力...');
      expect(state.gatewayTokenMissing, isFalse);
    });

    test(
      'manual bridge discovery does not require a svc.plus account session',
      () {
        final state = resolveGatewayThreadConnectionStateInternal(
          target: AssistantExecutionTarget.gateway,
          bridgeReady: false,
          bridgeLabel: 'private-bridge.example.com',
          accountSyncState: null,
          accountSignedIn: false,
          bridgeConfigured: true,
        );

        expect(state.connected, isFalse);
        expect(state.status, RuntimeConnectionStatus.offline);
        expect(state.primaryLabel, '正在发现');
        expect(state.detailLabel, '正在加载 Bridge 能力...');
        expect(state.detailLabel, isNot(contains('svc.plus')));
      },
    );

    test('manual bridge discovery failure is shown while signed out', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.gateway,
        bridgeReady: false,
        bridgeLabel: 'private-bridge.example.com',
        accountSyncState: null,
        accountSignedIn: false,
        bridgeConfigured: true,
        bridgeDiscoveryAttempted: true,
        bridgeDiscoveryError: 'ACP_HTTP_CONNECT_FAILED',
        providerCatalogEmpty: true,
      );

      expect(state.status, RuntimeConnectionStatus.error);
      expect(state.primaryLabel, '连接失败');
      expect(state.detailLabel, 'ACP_HTTP_CONNECT_FAILED');
      expect(state.detailLabel, isNot(contains('svc.plus')));
    });

    test('surfaces failed discovery after capability refresh is attempted', () {
      final state = resolveGatewayThreadConnectionStateInternal(
        target: AssistantExecutionTarget.gateway,
        bridgeReady: false,
        bridgeLabel: 'xworkmate-bridge.svc.plus',
        accountSyncState: null,
        accountSignedIn: true,
        bridgeConfigured: true,
        bridgeDiscoveryAttempted: true,
        bridgeDiscoveryError: 'ACP_HTTP_502: upstream failed',
        providerCatalogEmpty: true,
      );

      expect(state.connected, isFalse);
      expect(state.status, RuntimeConnectionStatus.error);
      expect(state.primaryLabel, '连接失败');
      expect(state.detailLabel, 'ACP_HTTP_502: upstream failed');
      expect(state.lastError, 'ACP_HTTP_502: upstream failed');
    });
  });
}
