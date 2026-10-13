import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/central_gateway_catalog.dart';
import 'package:xworkmate/runtime/runtime_models.dart';

GatewayModelSummary model(String provider, String id) => GatewayModelSummary(
  id: id,
  name: id,
  provider: provider,
  contextWindow: null,
  maxOutputTokens: null,
);
void main() {
  test('product selections use only actual central Gateway namespace', () {
    expect(
      centralGatewayModelRefs([
        model('openai', 'gpt'),
        model('xworkmate', 'gpt'),
        model('xworkmate', 'xworkmate/qwen'),
      ]),
      ['xworkmate/gpt', 'xworkmate/qwen'],
    );
    expect(centralGatewayModelRefs([]), isEmpty);
    expect(centralGatewayModelRefs([model('other', 'xworkmate/gpt')]), isEmpty);
  });
}
