import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/go_task_service_client.dart';

void main() {
  group('goTaskServiceResultFromAcpResponse', () {
    test('uses resultSummary when output summary and message are empty', () {
      final result = goTaskServiceResultFromAcpResponse(
        <String, dynamic>{
          'result': <String, dynamic>{
            'success': true,
            'resultSummary': 'bridge result summary',
            'resolvedExecutionTarget': 'single-agent',
          },
        },
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      expect(result.success, isTrue);
      expect(result.message, 'bridge result summary');
    });

    test('still prefers output over resultSummary when both exist', () {
      final result = goTaskServiceResultFromAcpResponse(
        <String, dynamic>{
          'result': <String, dynamic>{
            'success': true,
            'output': 'primary output',
            'resultSummary': 'bridge result summary',
            'resolvedExecutionTarget': 'single-agent',
          },
        },
        route: GoTaskServiceRoute.externalAcpSingle,
      );

      expect(result.message, 'primary output');
    });
  });
}
