import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/models/app_models.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

void main() {
  test(
    'product capability survives thread persistence without provider identity',
    () {
      for (final mode in AssistantMode.values) {
        final context = ThreadContextState.fromJson(<String, dynamic>{
          'productMode': mode.name,
          'selectedModelId': 'catalog-model',
        });
        expect(context.productMode, mode);
        expect(context.copyWith(selectedModelId: 'next').productMode, mode);
        expect(ThreadContextState.fromJson(context.toJson()).productMode, mode);
        if (mode == AssistantMode.autoBot) {
          expect(() => mode.toTaskMetadata(), throwsStateError);
          continue;
        }
        expect(mode.toTaskMetadata(model: ' catalog-model '), <String, dynamic>{
          'schemaVersion': 1,
          'mode': mode == AssistantMode.coding ? 'code' : mode.name,
          'model': 'catalog-model',
        });
      }
    },
  );

  test('four product labels and persisted Code migrate to Coding', () {
    expect(AssistantMode.values.map((mode) => mode.label), [
      'Chat',
      'Work',
      'Coding',
      'AutoBot',
    ]);
    final restored = ThreadContextState.fromJson({'productMode': 'code'});
    expect(restored.productMode, AssistantMode.coding);
    expect(restored.toJson()['productMode'], 'coding');
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
