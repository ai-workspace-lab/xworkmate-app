/// OpenClaw 2026.5.28 cron contracts. The runtime supplies the authenticated
/// Bridge RPC transport; schedules never execute on the App device.
typedef GatewayBotRequest =
    Future<dynamic> Function(String method, Map<String, dynamic> params);

class GatewayBotService {
  const GatewayBotService(this.request);
  final GatewayBotRequest request;

  Future<void> create({
    required String name,
    required String prompt,
    required int everyMinutes,
    required String model,
    required Set<String> availableModels,
    String? deliveryChannel,
    String? deliveryTarget,
    Set<String> availableDeliveryChannels = const <String>{},
  }) async {
    if (name.trim().isEmpty ||
        prompt.trim().isEmpty ||
        everyMinutes < 1 ||
        everyMinutes > 525600) {
      throw ArgumentError('Name, task and a valid interval are required.');
    }
    final modelRef = model.trim();
    if (!modelRef.startsWith('xworkmate/') ||
        modelRef.substring('xworkmate/'.length).isEmpty ||
        !availableModels.contains(modelRef)) {
      throw ArgumentError('A model from the live central catalog is required.');
    }
    final channel = deliveryChannel?.trim() ?? '';
    final target = deliveryTarget?.trim() ?? '';
    if (channel.isNotEmpty &&
        (!availableDeliveryChannels.contains(channel) || target.isEmpty)) {
      throw ArgumentError('Select a configured channel and a recipient.');
    }
    await request('cron.add', <String, dynamic>{
      'name': name.trim(),
      'enabled': true,
      'schedule': {'kind': 'every', 'everyMs': everyMinutes * 60000},
      'sessionTarget': 'isolated',
      'wakeMode': 'now',
      'payload': {
        'kind': 'agentTurn',
        'message': prompt.trim(),
        'model': modelRef,
      },
      'delivery': channel.isEmpty
          ? {'mode': 'none'}
          : {'mode': 'announce', 'channel': channel, 'to': target},
    });
  }

  String _jobId(String value) {
    final id = value.trim();
    if (id.isEmpty || id.contains('/') || id.contains('\\')) {
      throw ArgumentError('Invalid job identifier.');
    }
    return id;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await request('cron.update', {
      'id': _jobId(id),
      'patch': {'enabled': enabled},
    });
  }

  Future<List<Map<String, dynamic>>> runs(String id) async {
    final result = await request('cron.runs', {
      'id': _jobId(id),
      'scope': 'job',
      'limit': 30,
      'sortDir': 'desc',
    });
    if (result is! Map || result['entries'] is! List) return const [];
    return (result['entries'] as List)
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<void> remove(String id) async {
    await request('cron.remove', {'id': _jobId(id)});
  }
}
