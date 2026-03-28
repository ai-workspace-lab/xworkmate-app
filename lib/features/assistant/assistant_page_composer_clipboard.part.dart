part of 'assistant_page.dart';

class _ComposerAttachment {
  const _ComposerAttachment({
    required this.name,
    required this.path,
    required this.icon,
    required this.mimeType,
  });

  final String name;
  final String path;
  final IconData icon;
  final String mimeType;

  factory _ComposerAttachment.fromXFile(XFile file) {
    final extension = file.name.split('.').last.toLowerCase();
    final mimeType = switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'json' => 'application/json',
      'csv' => 'text/csv',
      'txt' || 'log' || 'md' || 'yaml' || 'yml' => 'text/plain',
      'pdf' => 'application/pdf',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
    final icon = switch (extension) {
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => Icons.image_outlined,
      'log' || 'txt' || 'json' || 'csv' => Icons.description_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

    return _ComposerAttachment(
      name: file.name,
      path: file.path,
      icon: icon,
      mimeType: mimeType,
    );
  }
}

class AssistantPasteIntent extends Intent {
  const AssistantPasteIntent();
}

Future<XFile?> _readClipboardImageAsXFile() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) {
    return null;
  }
  final reader = await clipboard.read();
  return await _readClipboardImageForFormat(
        reader,
        format: Formats.png,
        extension: 'png',
        mimeType: 'image/png',
      ) ??
      await _readClipboardImageForFormat(
        reader,
        format: Formats.jpeg,
        extension: 'jpg',
        mimeType: 'image/jpeg',
      ) ??
      await _readClipboardImageForFormat(
        reader,
        format: Formats.gif,
        extension: 'gif',
        mimeType: 'image/gif',
      ) ??
      await _readClipboardImageForFormat(
        reader,
        format: Formats.webp,
        extension: 'webp',
        mimeType: 'image/webp',
      );
}

Future<XFile?> _readClipboardImageForFormat(
  ClipboardReader reader, {
  required FileFormat format,
  required String extension,
  required String mimeType,
}) async {
  if (!reader.canProvide(format)) {
    return null;
  }
  final bytes = await _readClipboardFileBytes(reader, format);
  if (bytes == null || bytes.isEmpty) {
    return null;
  }
  final temporaryDirectory = await _resolveClipboardAttachmentTempDirectory();
  final fileName =
      'clipboard-image-${DateTime.now().microsecondsSinceEpoch}.$extension';
  final file = File('${temporaryDirectory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path, mimeType: mimeType, name: fileName);
}

Future<Uint8List?> _readClipboardFileBytes(
  ClipboardReader reader,
  FileFormat format,
) {
  final completer = Completer<Uint8List?>();
  final progress = reader.getFile(
    format,
    (file) async {
      try {
        final bytes = await file.readAll();
        if (!completer.isCompleted) {
          completer.complete(bytes);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    },
    onError: (error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    },
  );
  if (progress == null) {
    return Future<Uint8List?>.value(null);
  }
  return completer.future;
}

Future<Directory> _resolveClipboardAttachmentTempDirectory() async {
  Directory rootDirectory;
  try {
    rootDirectory = await getTemporaryDirectory();
  } catch (_) {
    rootDirectory = Directory.systemTemp;
  }
  final clipboardDirectory = Directory(
    '${rootDirectory.path}/xworkmate-clipboard-attachments',
  );
  await clipboardDirectory.create(recursive: true);
  return clipboardDirectory;
}
