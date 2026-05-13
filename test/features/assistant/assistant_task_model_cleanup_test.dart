import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_page_task_models.dart';

void main() {
  group('assistant task model cleanup', () {
    test('session key matching is exact and does not alias runtime main', () {
      expect(
        sessionKeysMatchInternal('draft:test-task', 'draft:test-task'),
        isTrue,
      );
      expect(sessionKeysMatchInternal('agent:main:main', 'main'), isFalse);
      expect(sessionKeysMatchInternal('main', 'agent:main:main'), isFalse);
    });

    test('main runtime ids are displayed as ids, not app default tasks', () {
      expect(fallbackSessionTitleInternal('main'), 'main');
      expect(
        fallbackSessionTitleInternal('agent:main:main'),
        'agent:main:main',
      );
    });
  });
}
