import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/gateway_bot_service.dart';

void main() {
  test(
    'Bot uses actual cron schemas and never invents notification delivery',
    () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final service = GatewayBotService((method, params) async {
        calls.add((method, params));
        return {
          'entries': [
            {'status': 'ok'},
          ],
        };
      });
      await service.create(
        name: 'Daily report',
        prompt: 'Write a report',
        everyMinutes: 60,
        model: 'xworkmate/model-1',
        availableModels: {'xworkmate/model-1'},
      );
      expect(calls.first.$1, 'cron.add');
      expect(calls.first.$2, <String, dynamic>{
        'name': 'Daily report',
        'enabled': true,
        'schedule': {'kind': 'every', 'everyMs': 3600000},
        'sessionTarget': 'isolated',
        'wakeMode': 'now',
        'payload': {
          'kind': 'agentTurn',
          'message': 'Write a report',
          'model': 'xworkmate/model-1',
        },
        'delivery': {'mode': 'none'},
      });
      await service.setEnabled('job-1', false);
      expect(calls.last.$1, 'cron.update');
      expect(calls.last.$2, <String, dynamic>{
        'id': 'job-1',
        'patch': {'enabled': false},
      });
      expect(await service.runs('job-1'), [
        {'status': 'ok'},
      ]);
      expect(calls.last.$1, 'cron.runs');
      expect(calls.last.$2, <String, dynamic>{
        'id': 'job-1',
        'scope': 'job',
        'limit': 30,
        'sortDir': 'desc',
      });
      await service.remove('job-1');
      expect(calls.last.$1, 'cron.remove');
      expect(calls.last.$2, {'id': 'job-1'});
    },
  );

  test('invalid scheduling and job identifiers fail before RPC', () async {
    var calls = 0;
    final service = GatewayBotService((method, params) async {
      calls++;
      return {};
    });
    await expectLater(
      service.create(
        name: 'x',
        prompt: 'x',
        everyMinutes: 0,
        model: 'xworkmate/model-1',
        availableModels: {'xworkmate/model-1'},
      ),
      throwsArgumentError,
    );
    await expectLater(
      service.create(
        name: 'x',
        prompt: 'x',
        everyMinutes: 60,
        model: 'xworkmate/model-1',
        availableModels: {},
      ),
      throwsArgumentError,
    );
    await expectLater(
      service.create(
        name: 'x',
        prompt: 'x',
        everyMinutes: 60,
        model: 'vendor/model-1',
        availableModels: {'vendor/model-1'},
      ),
      throwsArgumentError,
    );
    await expectLater(service.runs('../other'), throwsArgumentError);
    await expectLater(service.setEnabled('', false), throwsArgumentError);
    expect(calls, 0);
  });
}
