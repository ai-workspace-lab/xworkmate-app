import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../runtime/gateway_bot_service.dart';
import '../../runtime/runtime_models.dart';
import '../../runtime/central_gateway_catalog.dart';

Future<void> showAssistantBotDialog(
  BuildContext context,
  AppController controller, {
  String initialPrompt = '',
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      AssistantBotDialog(controller: controller, initialPrompt: initialPrompt),
);

class AssistantBotDialog extends StatefulWidget {
  const AssistantBotDialog({
    super.key,
    required this.controller,
    this.initialPrompt = '',
  });
  final String initialPrompt;
  final AppController controller;
  @override
  State<AssistantBotDialog> createState() => _AssistantBotDialogState();
}

class _AssistantBotDialogState extends State<AssistantBotDialog> {
  final name = TextEditingController();
  final prompt = TextEditingController();
  final minutes = TextEditingController(text: '60');
  final recipient = TextEditingController();
  String channel = '';
  String? error;
  String? notificationError;
  List<GatewayConnectorSummary> connectors = const [];
  bool busy = false;
  List<Map<String, dynamic>>? history;
  bool get connected =>
      widget.controller.runtime.isConnected &&
      widget.controller.runtime.canConnectBridgeSession;
  GatewayBotService get service => GatewayBotService(
    (method, params) =>
        widget.controller.runtime.request(method, params: params),
  );

  @override
  void initState() {
    super.initState();
    prompt.text = widget.initialPrompt;
    if (connected) {
      refresh();
    }
  }

  @override
  void dispose() {
    for (final field in [name, prompt, minutes, recipient]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> loadJobs() async {
    await widget.controller.cronJobsController.refresh();
    final failure = widget.controller.cronJobsController.error;
    if (failure != null) {
      throw StateError(failure);
    }
  }

  Future<void> refresh() => act(() async {
    await loadJobs();
    try {
      connectors = await widget.controller.runtime.listConnectors();
      notificationError = null;
    } catch (e) {
      connectors = const [];
      notificationError = '通知频道不可用：$e';
    }
  });

  @override
  Widget build(BuildContext context) {
    // Only currently configured channels are offered. This is Gateway delivery,
    // not a claim that native APNs/FCM push exists.
    final channels = connectors
        .where((item) => item.configured && item.enabled)
        .map((item) => item.id)
        .toSet();
    final models = connected
        ? centralGatewayModelRefs(widget.controller.models).toSet()
        : <String>{};
    final model = widget.controller.assistantModelForSession(
      widget.controller.sessionsController.currentSessionKey,
    );
    return AlertDialog(
      key: const Key('assistant-bot-dialog'),
      title: const Text('AutoBot'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!connected) const Text('请先连接 AI Workspace。'),
              if (notificationError != null) Text(notificationError!),
              if (error != null)
                Text(error!, key: const Key('assistant-bot-error')),
              for (final job in widget.controller.cronJobs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(job.name),
                  subtitle: Text(
                    '${job.scheduleLabel} · ${job.lastStatus ?? "尚未执行"}${job.lastError == null ? "" : " · ${job.lastError}"}',
                  ),
                  trailing: Wrap(
                    children: [
                      Switch(
                        value: job.enabled,
                        onChanged: connected && !busy
                            ? (value) => act(() async {
                                await service.setEnabled(job.id, value);
                                await loadJobs();
                              })
                            : null,
                      ),
                      IconButton(
                        tooltip: '执行记录',
                        icon: const Icon(Icons.history),
                        onPressed: connected && !busy
                            ? () => act(() async {
                                history = await service.runs(job.id);
                              })
                            : null,
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: connected && !busy
                            ? () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('删除 ${job.name}？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('删除'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && mounted) {
                                  await act(() async {
                                    await service.remove(job.id);
                                    await loadJobs();
                                  });
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              if (history != null) ...[
                const Text('执行记录'),
                if (history!.isEmpty) const Text('暂无执行记录'),
                for (final run in history!)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${run["status"] ?? "unknown"} · ${run["deliveryStatus"] ?? ""}',
                    ),
                    subtitle: Text('${run["summary"] ?? run["error"] ?? ""}'),
                  ),
              ],
              const Divider(),
              Text(models.contains(model) ? '集中模型：$model' : '集中模型目录不可用'),
              TextField(
                key: const Key('assistant-bot-name'),
                controller: name,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              TextField(
                key: const Key('assistant-bot-prompt'),
                controller: prompt,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '定时任务'),
              ),
              TextField(
                key: const Key('assistant-bot-interval'),
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '间隔（分钟）'),
              ),
              DropdownButtonFormField<String>(
                initialValue: channel,
                decoration: const InputDecoration(labelText: '通知频道'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('不发送通知')),
                  for (final id in channels)
                    DropdownMenuItem(value: id, child: Text(id)),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        channel = value ?? '';
                      }),
              ),
              if (channel.isNotEmpty)
                TextField(
                  controller: recipient,
                  decoration: const InputDecoration(labelText: '通知接收目标'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: connected && !busy ? refresh : null,
          child: const Text('刷新'),
        ),
        FilledButton(
          key: const Key('assistant-bot-create'),
          onPressed: connected && !busy && models.contains(model)
              ? () => act(() async {
                  await service.create(
                    name: name.text,
                    prompt: prompt.text,
                    everyMinutes: int.tryParse(minutes.text) ?? 0,
                    model: model,
                    availableModels: models,
                    deliveryChannel: channel,
                    deliveryTarget: recipient.text,
                    availableDeliveryChannels: channels,
                  );
                  name.clear();
                  prompt.clear();
                  await loadJobs();
                })
              : null,
          child: const Text('创建'),
        ),
      ],
    );
  }
}
