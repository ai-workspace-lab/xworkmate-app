import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/features/assistant/assistant_attachment_payloads.dart';
import 'package:xworkmate/features/assistant/assistant_page_composer_clipboard.dart';

void main() {
  test('builds base64 inline attachment payloads with content', () async {
    final directory = await Directory.systemTemp.createTemp(
      'xworkmate-attachment-payloads-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/note.txt');
    await file.writeAsString('hello attachment');

    final payloads = await buildAssistantAttachmentPayloadsInternal(
      <ComposerAttachmentInternal>[
        ComposerAttachmentInternal(
          name: 'note.txt',
          path: file.path,
          icon: Icons.description_outlined,
          mimeType: 'text/plain',
        ),
      ],
    );

    expect(payloads, hasLength(1));
    expect(payloads.single.fileName, 'note.txt');
    expect(payloads.single.mimeType, 'text/plain');
    expect(payloads.single.type, 'file');
    expect(payloads.single.sourcePath, file.path);
    expect(
      base64Decode(payloads.single.content),
      utf8.encode('hello attachment'),
    );
  });

  test('rejects a single attachment above the per-file limit', () async {
    final directory = await Directory.systemTemp.createTemp(
      'xworkmate-attachment-file-limit-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/large.bin');
    await file.writeAsBytes(List<int>.filled(6, 1));

    await expectLater(
      buildAssistantAttachmentPayloadsInternal(<ComposerAttachmentInternal>[
        ComposerAttachmentInternal(
          name: 'large.bin',
          path: file.path,
          icon: Icons.insert_drive_file_outlined,
          mimeType: 'application/octet-stream',
        ),
      ], maxFileBytes: 5),
      throwsA(
        isA<AssistantAttachmentLimitException>()
            .having((error) => error.code, 'code', 'file')
            .having((error) => error.fileName, 'fileName', 'large.bin'),
      ),
    );
  });

  test('rejects attachments above the per-message total limit', () async {
    final directory = await Directory.systemTemp.createTemp(
      'xworkmate-attachment-total-limit-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final first = File('${directory.path}/a.txt');
    final second = File('${directory.path}/b.txt');
    await first.writeAsString('1234');
    await second.writeAsString('5678');

    await expectLater(
      buildAssistantAttachmentPayloadsInternal(<ComposerAttachmentInternal>[
        ComposerAttachmentInternal(
          name: 'a.txt',
          path: first.path,
          icon: Icons.description_outlined,
          mimeType: 'text/plain',
        ),
        ComposerAttachmentInternal(
          name: 'b.txt',
          path: second.path,
          icon: Icons.description_outlined,
          mimeType: 'text/plain',
        ),
      ], maxTotalBytes: 7),
      throwsA(
        isA<AssistantAttachmentLimitException>()
            .having((error) => error.code, 'code', 'total')
            .having((error) => error.fileName, 'fileName', 'b.txt'),
      ),
    );
  });
}
