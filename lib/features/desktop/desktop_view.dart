import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'desktop_client.dart';
import 'desktop_input_handler.dart';
import '../../app/app_controller.dart';
import '../../runtime/gateway_acp_client.dart';
import '../../widgets/surface_card.dart';
import '../../i18n/app_language.dart';
import '../workspace_management/workspace_management_panel.dart';
import '../workspace_management/workspace_management_i18n.dart';

class DesktopView extends StatefulWidget {
  const DesktopView({
    super.key,
    required this.controller,
    this.isMaximized = false,
    this.onToggleMaximize,
  });

  final AppController controller;
  final bool isMaximized;
  final VoidCallback? onToggleMaximize;

  @override
  State<DesktopView> createState() => _DesktopViewState();
}

class _DesktopViewState extends State<DesktopView> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  late DesktopClient _client;
  DesktopInputHandler? _inputHandler;

  // Settings controllers
  final TextEditingController _displayController = TextEditingController(
    text: ':0.0',
  );
  final TextEditingController _widthController = TextEditingController(
    text: '1280',
  );
  final TextEditingController _heightController = TextEditingController(
    text: '720',
  );
  final TextEditingController _fpsController = TextEditingController(
    text: '30',
  );
  final TextEditingController _bitrateController = TextEditingController(
    text: '2000',
  );

  bool _useGpu = false;
  bool _adaptiveResolution = false;
  bool _showAdvancedOptions = false;
  bool _showControlPanel = true;
  String _connectionState = 'disconnected';
  bool _hasStream = false;
  bool _hasDecodedVideoFrame = false;
  bool _isFocused = false;
  Size _remoteDesktopSize = const Size(1280, 720);

  final FocusNode _viewportFocusNode = FocusNode();
  final GlobalKey _viewportKey = GlobalKey();

  StreamSubscription<MediaStream>? _streamSubscription;
  StreamSubscription<String>? _stateSubscription;
  Timer? _firstFrameStatsTimer;

  bool get _hasVideoFrame => desktopHasRenderedVideoFrame(
    hasStream: _hasStream,
    rendererVideoWidth: _localRenderer.videoWidth,
    rendererVideoHeight: _localRenderer.videoHeight,
    hasDecodedFrames: _hasDecodedVideoFrame,
  );

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _client = DesktopClient(
      controller: widget.controller,
      sessionId: desktopSessionId(),
    );
    _inputHandler = DesktopInputHandler(
      onSendInput: (event) {
        if (_connectionState == 'connected') {
          _client.sendInput(event);
        }
      },
    );

    _streamSubscription = _client.onRemoteStream.listen((stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
          _hasStream = true;
          _hasDecodedVideoFrame = false;
        });
        _startFirstFrameDiagnostics();
      }
    });

    _stateSubscription = _client.onConnectionState.listen((state) {
      if (mounted) {
        setState(() {
          _connectionState = state.toLowerCase();
          if (_connectionState == 'disconnected' ||
              _connectionState == 'failed') {
            _hasStream = false;
            _hasDecodedVideoFrame = false;
            _localRenderer.srcObject = null;
            _stopFirstFrameDiagnostics();
          }
        });
      }
    });
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
    _localRenderer.onFirstFrameRendered = () {
      _markRemoteDesktopFrameReady();
    };
    _localRenderer.onResize = () {
      if (_localRenderer.videoWidth > 0 && _localRenderer.videoHeight > 0) {
        _markRemoteDesktopFrameReady();
        return;
      }
      if (mounted) {
        setState(() {});
      }
    };
  }

  void _markRemoteDesktopFrameReady() {
    if (!_hasStream || _hasDecodedVideoFrame) {
      return;
    }
    _hasDecodedVideoFrame = true;
    _stopFirstFrameDiagnostics();
    if (mounted) {
      setState(() {});
    }
  }

  void _startFirstFrameDiagnostics() {
    _firstFrameStatsTimer?.cancel();
    unawaited(_collectFirstFrameStats());
    _firstFrameStatsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_hasStream || _hasVideoFrame || !mounted) {
        _stopFirstFrameDiagnostics();
        return;
      }
      unawaited(_collectFirstFrameStats());
    });
  }

  Future<void> _collectFirstFrameStats() async {
    try {
      final stats = await _client.collectVideoStats();
      if (stats == null || !mounted || !_hasStream) {
        return;
      }
      if (stats.hasDecodedFrames) {
        _markRemoteDesktopFrameReady();
        return;
      }
      debugPrint('Remote desktop waiting for first frame: $stats');
    } catch (error) {
      debugPrint('Remote desktop stats failed: $error');
    }
  }

  void _stopFirstFrameDiagnostics() {
    _firstFrameStatsTimer?.cancel();
    _firstFrameStatsTimer = null;
  }

  @override
  void dispose() {
    _stopFirstFrameDiagnostics();
    _streamSubscription?.cancel();
    _stateSubscription?.cancel();
    _client.disconnect();
    _localRenderer.onResize = null;
    _localRenderer.onFirstFrameRendered = null;
    _localRenderer.dispose();
    _displayController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _fpsController.dispose();
    _bitrateController.dispose();
    _viewportFocusNode.dispose();
    super.dispose();
  }

  void _toggleConnection() async {
    if (_connectionState == 'connected' || _connectionState == 'connecting') {
      await _client.disconnect();
    } else {
      final display = _displayController.text.trim();
      int width = int.tryParse(_widthController.text) ?? 1280;
      int height = int.tryParse(_heightController.text) ?? 720;

      if (_adaptiveResolution) {
        final viewportSize = _getViewportSize();
        if (viewportSize.width > 0 && viewportSize.height > 0) {
          width = (viewportSize.width.toInt() ~/ 2) * 2;
          height = (viewportSize.height.toInt() ~/ 2) * 2;
          _widthController.text = width.toString();
          _heightController.text = height.toString();
        }
      }

      final fps = int.tryParse(_fpsController.text) ?? 30;
      final bitrate = int.tryParse(_bitrateController.text) ?? 2000;
      _remoteDesktopSize = Size(width.toDouble(), height.toDouble());

      try {
        await _client.connect(
          display: display,
          width: width,
          height: height,
          fps: fps,
          bitrate: bitrate,
          useGpu: _useGpu,
        );
      } on GatewayAcpException catch (error) {
        if (mounted) {
          final message = _desktopConnectionErrorMessage(error);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                appText(
                  '连接AI工作空间失败: $message',
                  'Failed to connect AI Workspace: $message',
                ),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                appText('连接AI工作空间失败: $e', 'Failed to connect AI Workspace: $e'),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  String _desktopConnectionErrorMessage(GatewayAcpException error) {
    final code = (error.code ?? '').trim().toUpperCase();
    if (code == 'ACP_HTTP_401' || code == 'ACP_HTTP_403') {
      return appText(
        'Bridge 认证已过期或被拒绝，请点击“重新同步”后再连接。',
        'Bridge authorization expired or was rejected. Please re-sync, then connect again.',
      );
    }
    return error.message;
  }

  Size _getViewportSize() {
    final renderBox =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size ?? Size.zero;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasVideoFrame = _hasVideoFrame;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Control panel card
          if (_showControlPanel)
            SurfaceCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Connection Button
                        ElevatedButton.icon(
                          onPressed: _toggleConnection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _connectionState == 'connected'
                                ? Colors.redAccent
                                : (_connectionState == 'connecting'
                                      ? Colors.orangeAccent
                                      : theme.colorScheme.primary),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: Icon(
                            _connectionState == 'connected'
                                ? Icons.portable_wifi_off_rounded
                                : Icons.settings_remote_rounded,
                          ),
                          label: Text(
                            _connectionState == 'connected'
                                ? appText('断开连接', 'Disconnect')
                                : (_connectionState == 'connecting'
                                      ? appText('正在连接...', 'Connecting...')
                                      : appText(
                                          '连接AI工作空间',
                                          'Connect AI Workspace',
                                        )),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        // Status Indicator
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _connectionState == 'connected'
                                ? Colors.green.withValues(alpha: 0.15)
                                : (_connectionState == 'connecting'
                                      ? Colors.orange.withValues(alpha: 0.15)
                                      : Colors.grey.withValues(alpha: 0.15)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _connectionState == 'connected'
                                  ? Colors.green
                                  : (_connectionState == 'connecting'
                                        ? Colors.orange
                                        : Colors.grey),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _connectionState == 'connected'
                                      ? Colors.green
                                      : (_connectionState == 'connecting'
                                            ? Colors.orange
                                            : Colors.grey),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _connectionState == 'connected'
                                    ? appText('已连接', 'Connected')
                                    : (_connectionState == 'connecting'
                                          ? appText('连接中', 'Connecting')
                                          : appText('已断开', 'Disconnected')),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _connectionState == 'connected'
                                      ? Colors.green
                                      : (_connectionState == 'connecting'
                                            ? Colors.orange
                                            : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Advanced Options Toggle
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _showAdvancedOptions = !_showAdvancedOptions,
                          ),
                          icon: Icon(
                            _showAdvancedOptions
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          label: const Text('高级选项'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('desktop-workspace-management-button'),
                          onPressed: () => WorkspaceManagementPanel.show(
                            context,
                            widget.controller,
                          ),
                          icon: const Icon(Icons.dns_outlined),
                          label: Text(WorkspaceManagementText.button),
                        ),
                        // Maximize Toggle
                        if (widget.onToggleMaximize != null)
                          IconButton(
                            onPressed: widget.onToggleMaximize,
                            icon: Icon(
                              widget.isMaximized
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                            ),
                            tooltip: widget.isMaximized ? '恢复默认大小' : '最大化',
                          ),
                        // Collapse Toggle
                        IconButton(
                          onPressed: () =>
                              setState(() => _showControlPanel = false),
                          icon: const Icon(Icons.expand_less),
                          tooltip: '折叠面板',
                        ),
                      ],
                    ),
                    if (_showAdvancedOptions) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Display Selector
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _displayController,
                              enabled: _connectionState == 'disconnected',
                              decoration: const InputDecoration(
                                labelText: 'Display',
                                prefixIcon: Icon(
                                  Icons.monitor_rounded,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                          // Adaptive Resolution Toggle
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(appText('自适应分辨率', 'Adaptive Resolution')),
                              Switch(
                                value: _adaptiveResolution,
                                onChanged: _connectionState == 'disconnected'
                                    ? (val) => setState(
                                        () => _adaptiveResolution = val,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                          // Resolution settings
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: _widthController,
                              enabled:
                                  _connectionState == 'disconnected' &&
                                  !_adaptiveResolution,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '宽度',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: _heightController,
                              enabled:
                                  _connectionState == 'disconnected' &&
                                  !_adaptiveResolution,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '高度',
                              ),
                            ),
                          ),
                          // FPS / Bitrate
                          SizedBox(
                            width: 70,
                            child: TextField(
                              controller: _fpsController,
                              enabled: _connectionState == 'disconnected',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '帧率',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: _bitrateController,
                              enabled: _connectionState == 'disconnected',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '码率 (kbps)',
                              ),
                            ),
                          ),
                          // GPU accelerator toggle
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('GPU 加速'),
                              Switch(
                                value: _useGpu,
                                onChanged: _connectionState == 'disconnected'
                                    ? (val) => setState(() => _useGpu = val)
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

          if (!_showControlPanel)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: FilledButton.tonalIcon(
                  onPressed: () => setState(() => _showControlPanel = true),
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: const Text('展开控制面板'),
                ),
              ),
            ),

          if (_showControlPanel) const SizedBox(height: 16),

          // Stream Viewport Card
          Expanded(
            child: Focus(
              focusNode: _viewportFocusNode,
              onFocusChange: (focused) {
                setState(() {
                  _isFocused = focused;
                });
              },
              onKeyEvent: (node, event) {
                if (_isFocused &&
                    _connectionState == 'connected' &&
                    _inputHandler != null) {
                  _inputHandler!.handleKeyEvent(event);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                key: _viewportKey,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black26
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isFocused
                        ? theme.colorScheme.primary
                        : (isDark ? Colors.white10 : Colors.black12),
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Stream Viewport Renderer
                    if (_hasStream)
                      Positioned.fill(
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerHover: (event) {
                            if (_inputHandler != null) {
                              _inputHandler!.handlePointerMove(
                                event,
                                _getViewportSize(),
                                contentSize: _remoteDesktopSize,
                              );
                            }
                          },
                          onPointerMove: (event) {
                            if (_inputHandler != null) {
                              _inputHandler!.handlePointerMove(
                                event,
                                _getViewportSize(),
                                contentSize: _remoteDesktopSize,
                              );
                            }
                          },
                          onPointerDown: (event) {
                            if (!_viewportFocusNode.hasFocus) {
                              _viewportFocusNode.requestFocus();
                            }
                            if (_inputHandler != null) {
                              _inputHandler!.handlePointerDown(
                                event,
                                _getViewportSize(),
                                contentSize: _remoteDesktopSize,
                              );
                            }
                          },
                          onPointerUp: (event) {
                            if (_inputHandler != null) {
                              _inputHandler!.handlePointerUp(
                                event,
                                _getViewportSize(),
                              );
                            }
                          },
                          onPointerSignal: (event) {
                            if (event is PointerScrollEvent &&
                                _inputHandler != null) {
                              _inputHandler!.handleScroll(event);
                            }
                          },
                          child: RTCVideoView(
                            _localRenderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitContain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),

                    // Placeholder/Status UI overlay
                    if (!_hasStream)
                      Positioned.fill(
                        child: Container(
                          color: isDark ? Colors.black54 : Colors.grey[100],
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.monitor_rounded,
                                  size: 64,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _connectionState == 'connecting'
                                      ? appText(
                                          '正在建立 WebRTC 连接，请稍候...',
                                          'Establishing WebRTC connection, please wait...',
                                        )
                                      : appText(
                                          '未开启 AI 工作空间流。点击“连接AI工作空间”启动视频流。',
                                          'AI Workspace stream not enabled. Click "Connect AI Workspace" to start the video stream.',
                                        ),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    fontSize: 14,
                                  ),
                                ),
                                if (_connectionState == 'connecting') ...[
                                  const SizedBox(height: 24),
                                  const CircularProgressIndicator(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (_hasStream && !hasVideoFrame)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.56)
                                : Colors.white.withValues(alpha: 0.72),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    appText(
                                      'WebRTC 已连接，正在等待远程桌面首帧...',
                                      'WebRTC connected. Waiting for the first remote desktop frame...',
                                    ),
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Focus watermark badge
                    if (hasVideoFrame)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: AnimatedOpacity(
                          opacity: _isFocused ? 0.3 : 0.8,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isFocused
                                      ? Icons.keyboard_rounded
                                      : Icons.keyboard_hide_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isFocused ? '捕获键盘输入中' : '点击屏幕以捕获键盘',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
