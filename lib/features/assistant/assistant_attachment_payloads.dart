import 'dart:convert';
import 'dart:io';

import '../../runtime/runtime_models.dart';
import 'assistant_page_composer_clipboard.dart';

const int assistantAttachmentMaxFileBytesInternal = 10 * 1024 * 1024;
const int assistantAttachmentMaxTotalBytesInternal = 25 * 1024 * 1024;

class AssistantAttachmentLimitException implements Exception {
  const AssistantAttachmentLimitException({
    required this.code,
    required this.fileName,
    required this.sizeBytes,
    required this.limitBytes,
  });

  final String code;
  final String fileName;
  final int sizeBytes;
  final int limitBytes;

  @override
  String toString() =>
      'AssistantAttachmentLimitException($code, $fileName, $sizeBytes, $limitBytes)';
}

Future<List<GatewayChatAttachmentPayload>>
buildAssistantAttachmentPayloadsInternal(
  List<ComposerAttachmentInternal> attachments, {
  int maxFileBytes = assistantAttachmentMaxFileBytesInternal,
  int maxTotalBytes = assistantAttachmentMaxTotalBytesInternal,
}) async {
  final payloads = <GatewayChatAttachmentPayload>[];
  var totalBytes = 0;
  for (final attachment in attachments) {
    final file = File(attachment.path);
    if (!await file.exists()) {
      continue;
    }
    final stat = await file.stat();
    final sizeBytes = stat.size;
    if (sizeBytes > maxFileBytes) {
      throw AssistantAttachmentLimitException(
        code: 'file',
        fileName: attachment.name,
        sizeBytes: sizeBytes,
        limitBytes: maxFileBytes,
      );
    }
    if (totalBytes + sizeBytes > maxTotalBytes) {
      throw AssistantAttachmentLimitException(
        code: 'total',
        fileName: attachment.name,
        sizeBytes: totalBytes + sizeBytes,
        limitBytes: maxTotalBytes,
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxFileBytes) {
      throw AssistantAttachmentLimitException(
        code: 'file',
        fileName: attachment.name,
        sizeBytes: bytes.length,
        limitBytes: maxFileBytes,
      );
    }
    if (totalBytes + bytes.length > maxTotalBytes) {
      throw AssistantAttachmentLimitException(
        code: 'total',
        fileName: attachment.name,
        sizeBytes: totalBytes + bytes.length,
        limitBytes: maxTotalBytes,
      );
    }
    totalBytes += bytes.length;
    final mimeType = attachment.mimeType;
    payloads.add(
      GatewayChatAttachmentPayload(
        type: mimeType.startsWith('image/') ? 'image' : 'file',
        mimeType: mimeType,
        fileName: attachment.name,
        content: base64Encode(bytes),
      ),
    );
  }
  return payloads;
}

String formatAssistantAttachmentBytesInternal(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
