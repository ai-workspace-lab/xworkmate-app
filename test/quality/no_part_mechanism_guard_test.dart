import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository no longer uses Dart part mechanism', () {
    const allowedPartFiles = <String>{
      'lib/runtime/gateway_runtime_api.dart',
      'lib/runtime/gateway_runtime_core.dart',
      'lib/runtime/runtime_controllers_settings.dart',
      'lib/runtime/runtime_controllers_settings_account.dart',
      'lib/runtime/runtime_controllers_settings_secrets_impl.dart',
      'lib/widgets/sidebar_navigation.dart',
      'lib/widgets/sidebar_navigation_footer.dart',
      'lib/widgets/sidebar_navigation_task_section.dart',
    };

    final dartFiles = <File>[
      ..._collectDartFiles(Directory('lib')),
      ..._collectDartFiles(Directory('test')),
    ];

    final partFiles =
        dartFiles
            .where(
              (file) =>
                  file.path.endsWith('.part.dart') &&
                  !allowedPartFiles.contains(_relativePath(file.path)),
            )
            .map((file) => _relativePath(file.path))
            .toList()
          ..sort();

    final partDirectiveViolations = <String>[];
    for (final file in dartFiles) {
      final rel = _relativePath(file.path);
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i].trimLeft();
        if ((line.startsWith('part of ') ||
                (line.startsWith('part ') && line.contains("'"))) &&
            !allowedPartFiles.contains(rel)) {
          partDirectiveViolations.add('$rel:${i + 1}');
        }
      }
    }

    expect(partFiles, isEmpty, reason: partFiles.join('\n'));
    expect(
      partDirectiveViolations,
      isEmpty,
      reason: partDirectiveViolations.join('\n'),
    );
  });
}

String _relativePath(String path) {
  final root = Directory.current.path;
  if (path.startsWith(root)) {
    return path.substring(root.length + 1);
  }
  return path;
}

Iterable<File> _collectDartFiles(Directory directory) {
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}
