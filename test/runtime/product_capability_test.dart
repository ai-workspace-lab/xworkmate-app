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
        expect(mode.toTaskMetadata(model: ' catalog-model '), <String, dynamic>{
          'schemaVersion': 1,
          'mode': mode.name,
          'model': 'catalog-model',
        });
      }
    },
  );

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
