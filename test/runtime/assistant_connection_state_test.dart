import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/app/app_controller.dart';
import 'package:xworkmate/runtime/gateway_acp_client.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/runtime/secure_config_store.dart';

void main() {
  group('Assistant connection state', () {
    test('does not report bridge runtime configured by default', () async {
      final controller = await _isolatedController(
        initialBridgeProviderCatalog: const <SingleAgentProvider>[
          SingleAgentProvider.codex,
        ],
        initialGatewayProviderCatalog: const <SingleAgentProvider>[
          SingleAgentProvider.openclaw,
        ],
        initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
          AssistantExecutionTarget.agent,
          AssistantExecutionTarget.gateway,
        ],
      );
      addTearDown(controller.dispose);

      expect(controller.isBridgeAcpRuntimeConfiguredInternal(), isFalse);
    });

    test(
      'keeps signed-out sessions disconnected even when provider catalogs exist',
      () async {
        final controller = await _isolatedController(
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
          initialGatewayProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.openclaw,
          ],
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('draft:unit-task-a');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final state = controller.currentAssistantConnectionState;
        expect(state.connected, isFalse);
        expect(state.status, RuntimeConnectionStatus.offline);
        expect(state.detailLabel, '请先登录 svc.plus');
      },
    );

    test(
      'uses the same gateway capability readiness for status and send guard',
      () async {
        final controller = await _isolatedController(
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
          initialGatewayProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.openclaw,
          ],
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
          environmentOverride: const <String, String>{
            'BRIDGE_AUTH_TOKEN': 'bridge-token',
          },
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('draft:unit-task-a');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        final state = controller.currentAssistantConnectionState;
        expect(state.connected, isTrue);
        expect(
          controller.bridgeCapabilityRefreshNeededForAssistantTargetInternal(
            AssistantExecutionTarget.gateway,
          ),
          isFalse,
        );
      },
    );

    test(
      'refreshes gateway capabilities when previous discovery missed openclaw',
      () async {
        final controller = await _isolatedController(
          initialBridgeProviderCatalog: const <SingleAgentProvider>[
            SingleAgentProvider.codex,
          ],
          initialAvailableExecutionTargets: const <AssistantExecutionTarget>[
            AssistantExecutionTarget.agent,
            AssistantExecutionTarget.gateway,
          ],
          environmentOverride: const <String, String>{
            'BRIDGE_AUTH_TOKEN': 'bridge-token',
          },
        );
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('draft:unit-task-a');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        expect(controller.currentAssistantConnectionState.connected, isFalse);
        expect(
          controller.bridgeCapabilityRefreshNeededForAssistantTargetInternal(
            AssistantExecutionTarget.gateway,
          ),
          isTrue,
        );
      },
    );

    test(
      'labels gateway offline errors as OpenClaw runtime failures',
      () async {
        final controller = await _isolatedController();
        addTearDown(controller.dispose);

        final label = controller.gatewayExecutionErrorLabelInternal(
          'gateway not connected',
          target: AssistantExecutionTarget.gateway,
        );

        expect(label, contains('OpenClaw Gateway 当前未连接'));
        expect(label, isNot(contains('xworkmate-bridge 未连接')));
      },
    );

    test(
      'labels OpenClaw socket close without exposing raw JSON-RPC error',
      () async {
        final controller = await _isolatedController();
        addTearDown(controller.dispose);

        final label = controller.gatewayExecutionErrorLabelInternal(
          const GatewayAcpException(
            'OPENCLAW_GATEWAY_SOCKET_CLOSED: OpenClaw gateway connection closed during task execution',
            code: '-32002',
            detailCode: 'OPENCLAW_GATEWAY_SOCKET_CLOSED',
          ),
          target: AssistantExecutionTarget.gateway,
        );

        expect(label, contains('OpenClaw Gateway 连接在任务执行中断开'));
        expect(label, isNot(contains('-32002')));
        expect(label, isNot(contains('socket closed')));
      },
    );

    test('labels interrupted ACP HTTP reads as incomplete results', () async {
      final controller = await _isolatedController();
      addTearDown(controller.dispose);

      final label = controller.gatewayExecutionErrorLabelInternal(
        const GatewayAcpException(
          'ACP HTTP connection closed before the response finished arriving',
          code: 'ACP_HTTP_CONNECTION_CLOSED',
        ),
        target: AssistantExecutionTarget.gateway,
      );

      expect(
        label,
        'Bridge 响应读取中断，本轮结果未完成。请重新发送请求。错误码：ACP_HTTP_CONNECTION_CLOSED',
      );
      expect(label, isNot(contains('下一次发送会继续同一会话')));
      expect(label, isNot(contains('closed before the response')));
    });

    test(
      'labels interrupted ACP HTTP handshakes as incomplete requests',
      () async {
        final controller = await _isolatedController();
        addTearDown(controller.dispose);

        final label = controller.gatewayExecutionErrorLabelInternal(
          const GatewayAcpException(
            'ACP HTTP handshake was interrupted before the response started',
            code: gatewayAcpHttpHandshakeInterruptedCode,
          ),
          target: AssistantExecutionTarget.gateway,
        );

        expect(
          label,
          'Bridge 握手中断，本轮请求未完成。请重新发送请求。错误码：ACP_HTTP_HANDSHAKE_INTERRUPTED',
        );
        expect(label, isNot(contains('下一次发送会继续同一会话')));
        expect(
          label,
          isNot(contains('Connection terminated during handshake')),
        );
        expect(label, isNot(contains('handshake was interrupted')));
      },
    );

    test(
      'labels ACP HTTP connect timeouts as unconfirmed retryable requests',
      () async {
        final controller = await _isolatedController();
        addTearDown(controller.dispose);

        final label = controller.gatewayExecutionErrorLabelInternal(
          const GatewayAcpException(
            'SocketException: HTTP connection timed out after 0:00:08.000000, host: xworkmate-bridge.svc.plus, port: 443',
            code: gatewayAcpHttpConnectTimeoutCode,
          ),
          target: AssistantExecutionTarget.gateway,
        );

        expect(label, 'Bridge 连接超时，本轮请求未确认，可重试。错误码：ACP_HTTP_CONNECT_TIMEOUT');
        expect(label, isNot(contains('SocketException')));
        expect(label, isNot(contains('0:00:08')));
      },
    );

    test(
      'labels ACP HTTP connect failures as unconfirmed retryable requests',
      () async {
        final controller = await _isolatedController();
        addTearDown(controller.dispose);

        final label = controller.gatewayExecutionErrorLabelInternal(
          const GatewayAcpException(
            'Connection refused',
            code: gatewayAcpHttpConnectFailedCode,
          ),
          target: AssistantExecutionTarget.gateway,
        );

        expect(label, 'Bridge 连接失败，本轮请求未确认，可重试。错误码：ACP_HTTP_CONNECT_FAILED');
        expect(label, isNot(contains('Connection refused')));
      },
    );

    test(
      'labels unavailable session continuation without starting a new flow',
      () async {
        final controller = await _isolatedController();
        addTearDown(controller.dispose);

        final label = controller.gatewayExecutionErrorLabelInternal(
          const GatewayAcpException(
            'SESSION_CONTINUATION_UNAVAILABLE: provider session state is unavailable',
            code: '-32002',
            detailCode: 'SESSION_CONTINUATION_UNAVAILABLE',
          ),
          target: AssistantExecutionTarget.agent,
        );

        expect(label, contains('会话状态不可续写'));
        expect(label, contains('SESSION_CONTINUATION_UNAVAILABLE'));
        expect(label, isNot(contains('-32002')));
      },
    );

    test('keeps signed-out generic runtime failures disconnected', () async {
      final controller = await _isolatedController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('draft:unit-task-a');
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.gateway,
      );

      controller.runtimeInternal.snapshotInternal = controller
          .runtimeInternal
          .snapshot
          .copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Connection failed',
            remoteAddress: 'openclaw.svc.plus:443',
            lastError: 'unsupported Ed25519 private key length: 0',
            lastErrorCode: 'DEVICE_IDENTITY_SIGN_FAILED',
            lastErrorDetailCode: null,
          );

      final state = controller.currentAssistantConnectionState;
      expect(state.status, RuntimeConnectionStatus.offline);
      expect(state.primaryLabel, '已退出登录');
      expect(state.detailLabel, '请先登录 svc.plus');
    });

    test('keeps true offline state as bridge not connected', () async {
      final controller = await _isolatedController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('draft:unit-task-a');
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.gateway,
      );

      controller.runtimeInternal.snapshotInternal =
          GatewayConnectionSnapshot.initial(
            mode: controller.runtimeInternal.snapshot.mode,
          );

      final state = controller.currentAssistantConnectionState;
      expect(state.status, RuntimeConnectionStatus.offline);
      expect(state.primaryLabel, '已退出登录');
      expect(state.detailLabel, '请先登录 svc.plus');
    });

    test(
      'keeps signed-out generic failures without address disconnected',
      () async {
        final controller = await _isolatedController();
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('draft:unit-task-a');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        controller.runtimeInternal.snapshotInternal = controller
            .runtimeInternal
            .snapshot
            .copyWith(
              status: RuntimeConnectionStatus.error,
              statusText: 'Connection failed',
              lastError: 'socket closed',
              lastErrorCode: 'SOCKET_CLOSED',
              lastErrorDetailCode: null,
              clearRemoteAddress: true,
            );

        final state = controller.currentAssistantConnectionState;
        expect(state.status, RuntimeConnectionStatus.offline);
        expect(state.primaryLabel, '已退出登录');
        expect(state.detailLabel, '请先登录 svc.plus');
      },
    );

    test(
      'keeps gateway token missing as dedicated app-visible state',
      () async {
        final controller = await _isolatedController();
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('draft:unit-task-a');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        controller.runtimeInternal.snapshotInternal = controller
            .runtimeInternal
            .snapshot
            .copyWith(
              status: RuntimeConnectionStatus.error,
              statusText: 'Connection failed',
              lastError: 'gateway token missing',
              lastErrorCode: 'AUTH_FAILED',
              lastErrorDetailCode: 'AUTH_TOKEN_MISSING',
              clearRemoteAddress: true,
            );

        final state = controller.currentAssistantConnectionState;
        expect(state.status, RuntimeConnectionStatus.offline);
        expect(state.primaryLabel, '已退出登录');
        expect(state.detailLabel, '请先登录 svc.plus');
      },
    );

    test(
      'treats missing endpoint as true offline instead of bridge failure',
      () async {
        final controller = await _isolatedController();
        addTearDown(controller.dispose);

        await controller.sessionsController.switchSession('draft:unit-task-a');
        await controller.setAssistantExecutionTarget(
          AssistantExecutionTarget.gateway,
        );

        controller.runtimeInternal.snapshotInternal = controller
            .runtimeInternal
            .snapshot
            .copyWith(
              status: RuntimeConnectionStatus.error,
              statusText: 'Missing gateway endpoint',
              lastError: 'Configure setup code or manual host / port first.',
              lastErrorCode: 'MISSING_ENDPOINT',
              clearRemoteAddress: true,
            );

        final state = controller.currentAssistantConnectionState;
        expect(state.status, RuntimeConnectionStatus.offline);
        expect(state.primaryLabel, '已退出登录');
        expect(state.detailLabel, '请先登录 svc.plus');
      },
    );

    test('desktop snapshot uses derived assistant connection labels', () async {
      final controller = await _isolatedController();
      addTearDown(controller.dispose);

      await controller.sessionsController.switchSession('draft:unit-task-a');
      await controller.setAssistantExecutionTarget(
        AssistantExecutionTarget.gateway,
      );

      controller.runtimeInternal.snapshotInternal = controller
          .runtimeInternal
          .snapshot
          .copyWith(
            status: RuntimeConnectionStatus.error,
            statusText: 'Connection failed',
            remoteAddress: 'openclaw.svc.plus:443',
            lastError: 'unsupported Ed25519 private key length: 0',
            lastErrorCode: 'DEVICE_IDENTITY_SIGN_FAILED',
          );

      final snapshot = controller.desktopStatusSnapshot();
      expect(snapshot['connectionStatus'], 'disconnected');
      expect(snapshot['connectionLabel'], '已退出登录');
    });
  });
}

Future<AppController> _isolatedController({
  List<SingleAgentProvider>? initialBridgeProviderCatalog,
  List<SingleAgentProvider>? initialGatewayProviderCatalog,
  List<AssistantExecutionTarget>? initialAvailableExecutionTargets,
  Map<String, String> environmentOverride = const <String, String>{},
}) async {
  final storeRoot = await Directory.systemTemp.createTemp(
    'xworkmate-assistant-connection-state-',
  );
  addTearDown(() async {
    if (await storeRoot.exists()) {
      try {
        await storeRoot.delete(recursive: true);
      } on FileSystemException {
        // Temp cleanup is best effort here.
      }
    }
  });
  final store = SecureConfigStore(
    secretRootPathResolver: () async => '${storeRoot.path}/secrets',
    appDataRootPathResolver: () async => '${storeRoot.path}/app-data',
    supportRootPathResolver: () async => '${storeRoot.path}/support',
    enableSecureStorage: false,
  );
  await store.initialize();
  return AppController(
    environmentOverride: environmentOverride,
    store: store,
    initialBridgeProviderCatalog: initialBridgeProviderCatalog,
    initialGatewayProviderCatalog: initialGatewayProviderCatalog,
    initialAvailableExecutionTargets: initialAvailableExecutionTargets,
  );
}
