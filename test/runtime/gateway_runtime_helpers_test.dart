import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/runtime/gateway_runtime_helpers.dart';

void main() {
  test('history text retains file and image attachment context', () {
    final text = extractMessageText({
      'content': [
        {'type': 'text', 'text': '主海报已经生成好了！'},
        {
          'type': 'file',
          'fileName': 'ai-news-poster-2026-07-18.png',
          'mimeType': 'image/png',
        },
        {
          'type': 'image_url',
          'image_url': {'name': 'preview.jpg'},
        },
      ],
    });

    expect(text, contains('主海报已经生成好了！'));
    expect(text, contains('🖼 ai-news-poster-2026-07-18.png'));
    expect(text, contains('🖼 preview.jpg'));
  });

  test('history text ignores non-display tool metadata', () {
    final text = extractMessageText({
      'content': [
        {'type': 'tool_result', 'name': 'debug-only'},
      ],
    });

    expect(text, isEmpty);
  });
}
