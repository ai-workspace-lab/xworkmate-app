// ignore_for_file: unused_import, unnecessary_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../../app/app_controller.dart';
import '../../app/app_metadata.dart';
import '../../app/ui_feature_manifest.dart';
import '../../i18n/app_language.dart';
import '../../models/app_models.dart';
import '../../runtime/multi_agent_orchestrator.dart';
import '../../runtime/runtime_models.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';
import '../../widgets/assistant_focus_panel.dart';
import '../../widgets/assistant_artifact_sidebar.dart';
import '../../widgets/desktop_workspace_scaffold.dart';
import '../../widgets/pane_resize_handle.dart';
import '../../widgets/surface_card.dart';
import 'assistant_page_main.dart';
import 'assistant_page_components.dart';
import 'assistant_page_composer_bar.dart';
import 'assistant_page_composer_state_helpers.dart';
import 'assistant_page_composer_support.dart';
import 'assistant_page_tooltip_labels.dart';
import 'assistant_page_message_widgets.dart';
import 'assistant_page_task_models.dart';
import 'assistant_page_composer_skill_models.dart';
import 'assistant_page_composer_skill_picker.dart';
import 'assistant_page_components_core.dart';

class ComposerAttachmentInternal {
  const ComposerAttachmentInternal({
    required this.name,
    required this.path,
    required this.icon,
    required this.mimeType,
  });

  final String name;
  final String path;
  final IconData icon;
  final String mimeType;

  factory ComposerAttachmentInternal.fromXFile(XFile file) {
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

    return ComposerAttachmentInternal(
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

Future<XFile?> readClipboardImageAsXFileInternal() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) {
    return null;
  }
  final reader = await clipboard.read();
  return await readClipboardImageForFormatInternal(
        reader,
        format: Formats.png,
        extension: 'png',
        mimeType: 'image/png',
      ) ??
      await readClipboardImageForFormatInternal(
        reader,
        format: Formats.jpeg,
        extension: 'jpg',
        mimeType: 'image/jpeg',
      ) ??
      await readClipboardImageForFormatInternal(
        reader,
        format: Formats.gif,
        extension: 'gif',
        mimeType: 'image/gif',
      ) ??
      await readClipboardImageForFormatInternal(
        reader,
        format: Formats.webp,
        extension: 'webp',
        mimeType: 'image/webp',
      );
}

Future<XFile?> readClipboardImageForFormatInternal(
  ClipboardReader reader, {
  required FileFormat format,
  required String extension,
  required String mimeType,
}) async {
  if (!reader.canProvide(format)) {
    return null;
  }
  final bytes = await readClipboardFileBytesInternal(reader, format);
  if (bytes == null || bytes.isEmpty) {
    return null;
  }
  final temporaryDirectory =
      await resolveClipboardAttachmentTempDirectoryInternal();
  final fileName =
      'clipboard-image-${DateTime.now().microsecondsSinceEpoch}.$extension';
  final file = File('${temporaryDirectory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path, mimeType: mimeType, name: fileName);
}

Future<Uint8List?> readClipboardFileBytesInternal(
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

Future<Directory> resolveClipboardAttachmentTempDirectoryInternal() async {
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
