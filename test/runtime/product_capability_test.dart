import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test('the role survives thread persistence without provider identity', () {
    for (final mode in AssistantMode.values) {
      final context = ThreadContextState.fromJson(<String, dynamic>{
        'productMode': mode.name,
        'selectedModelId': 'catalog-model',
      });
      expect(context.productMode, mode);
      expect(context.copyWith(selectedModelId: 'next').productMode, mode);
      expect(ThreadContextState.fromJson(context.toJson()).productMode, mode);
    }
  });

  test('six roles in escalation order; only Chat is a Gateway turn', () {
    expect(AssistantMode.values.map((mode) => mode.label), [
      'Chat',
      'Worker',
      'Engineer',
      'Architect',
      'Researcher',
      'Specialist',
    ]);
    expect(AssistantMode.chat.runsOnBotTeam, isFalse);
    expect(AssistantMode.chat.toTaskMetadata(model: ' catalog-model '), {
      'schemaVersion': 1,
      'mode': 'chat',
      'model': 'catalog-model',
    });
    for (final role in AssistantMode.values.skip(1)) {
      expect(role.runsOnBotTeam, isTrue);
      expect(() => role.toTaskMetadata(), throwsStateError);
    }
  });

  test('earlier Work / Coding / AutoBot records fall back to Chat', () {
    for (final legacy in ['work', 'coding', 'code', 'autoBot', 'unknown']) {
      expect(
        ThreadContextState.fromJson({'productMode': legacy}).productMode,
        AssistantMode.chat,
      );
    }
  });

  test('new threads default to Chat and Gateway', () {
    expect(ThreadContextState.fromJson({}).productMode, AssistantMode.chat);
    expect(
      SettingsSnapshot.defaults().assistantExecutionTarget,
      AssistantExecutionTarget.gateway,
    );
    expect(
      AssistantExecutionTargetCopy.fromJsonValue(null),
      AssistantExecutionTarget.gateway,
    );
    expect(AssistantMode.chat.toTaskMetadata(), {
      'schemaVersion': 1,
      'mode': 'chat',
    });
  });
}
