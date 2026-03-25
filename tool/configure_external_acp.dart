import 'dart:io';

import 'package:yaml/yaml.dart';

const Map<String, String> _providerLabels = <String, String>{
  'codex': 'Codex',
  'opencode': 'OpenCode',
  'claude': 'Claude',
  'gemini': 'Gemini',
};

const Map<String, String> _defaultEndpoints = <String, String>{
  'codex': 'ws://127.0.0.1:9001',
  'opencode': 'http://127.0.0.1:4096',
  'claude': 'ws://127.0.0.1:9011',
  'gemini': 'ws://127.0.0.1:9012',
};

const Map<String, String> _defaultLaunchCommands = <String, String>{
  'codex': 'codex app-server --listen ws://127.0.0.1:9001',
  'opencode': 'opencode serve --port 4096',
  'claude':
      'npx -y supergateway --stdio "mcp-bridge" --outputTransport ws --port 9011 --messagePath /',
  'gemini':
      'npx -y supergateway --stdio "uvx gemini-bridge" --outputTransport ws --port 9012 --messagePath /',
};

void main(List<String> args) async {
  final options = _CliOptions.parse(args);
  if (options.showHelp) {
    stdout.write(_usage());
    exit(0);
  }

  final settingsFile =
      options.settingsFile ??
      _defaultSettingsFile(
        environment: Platform.environment,
        operatingSystem: Platform.operatingSystem,
      );
  final resolvedEndpoints = <String, String>{
    for (final entry in _defaultEndpoints.entries)
      entry.key: options.endpoints[entry.key] ?? entry.value,
  };

  if (options.command == _Command.printPlan) {
    stdout.write(
      _renderPlan(
        settingsFile: settingsFile,
        endpoints: resolvedEndpoints,
        modeLabel: 'print-only',
      ),
    );
    return;
  }

  final existing = await _readExistingSettings(settingsFile);
  final updated = _mergeExternalAcpEndpoints(
    existing,
    endpoints: resolvedEndpoints,
    enableProviders: options.enableProviders,
  );

  if (options.dryRun) {
    stdout.write(encodeYamlDocument(updated));
    return;
  }

  await settingsFile.parent.create(recursive: true);
  if (await settingsFile.exists() && options.backup) {
    final backupFile = File(
      '${settingsFile.path}.bak.${DateTime.now().toUtc().millisecondsSinceEpoch}',
    );
    await settingsFile.copy(backupFile.path);
    stdout.writeln('Backup written: ${backupFile.path}');
  }

  await settingsFile.writeAsString(encodeYamlDocument(updated));
  stdout.writeln('Updated: ${settingsFile.path}');
  stdout.write(
    _renderPlan(
      settingsFile: settingsFile,
      endpoints: resolvedEndpoints,
      modeLabel: 'applied',
    ),
  );
}

String _usage() {
  return '''
Usage:
  dart tool/configure_external_acp.dart apply [options]
  dart tool/configure_external_acp.dart print [options]

Commands:
  apply    Update XWorkmate settings.yaml externalAcpEndpoints.
  print    Print the resolved endpoint plan and suggested launch commands.

Options:
  --settings-file <path>     Override settings.yaml path.
  --codex-endpoint <url>     Default: ${_defaultEndpoints['codex']}
  --opencode-endpoint <url>  Default: ${_defaultEndpoints['opencode']}
  --claude-endpoint <url>    Default: ${_defaultEndpoints['claude']}
  --gemini-endpoint <url>    Default: ${_defaultEndpoints['gemini']}
  --disable-codex            Mark the Codex slot as disabled.
  --disable-opencode         Mark the OpenCode slot as disabled.
  --disable-claude           Mark the Claude slot as disabled.
  --disable-gemini           Mark the Gemini slot as disabled.
  --no-backup                Skip settings.yaml backup on apply.
  --dry-run                  Print the resulting YAML instead of writing it.
  --help                     Show this help.

Notes:
  - This tool only updates the externalAcpEndpoints block and preserves all
    other settings keys.
  - App Store-safe usage means running this tool outside the shipped app bundle
    and keeping Codex/OpenCode/Supergateway/MCP bridge binaries outside the
    bundle as user-managed prerequisites.
  - Default macOS settings path:
    ~/Library/Application Support/xworkmate/config/settings.yaml
  - Default Linux settings path:
    ~/.config/xworkmate/config/settings.yaml
''';
}

String _renderPlan({
  required File settingsFile,
  required Map<String, String> endpoints,
  required String modeLabel,
}) {
  final buffer = StringBuffer()
    ..writeln()
    ..writeln('Settings file: ${settingsFile.path}')
    ..writeln('Mode: $modeLabel')
    ..writeln('Provider endpoint plan:');

  for (final provider in _providerLabels.keys) {
    buffer.writeln('- ${_providerLabels[provider]}: ${endpoints[provider]}');
    buffer.writeln('  launch: ${_defaultLaunchCommands[provider]}');
  }

  buffer
    ..writeln()
    ..writeln('Bridge notes:')
    ..writeln(
      '- Codex is configured for native app-server WebSocket on port 9001.',
    )
    ..writeln(
      '- OpenCode is configured to the native HTTP server on port 4096.',
    )
    ..writeln(
      '- Claude and Gemini are assigned local bridge slots; see docs/howto/external-acp-bridge-config.md for install and compatibility notes.',
    )
    ..writeln(
      '- App Store alignment: all bridge binaries stay outside the app bundle and must be started manually after install.',
    );
  return buffer.toString();
}

Map<String, dynamic> _mergeExternalAcpEndpoints(
  Map<String, dynamic> existing, {
  required Map<String, String> endpoints,
  required Map<String, bool> enableProviders,
}) {
  final updated = Map<String, dynamic>.from(existing);
  final incomingProfiles = (existing['externalAcpEndpoints'] is List)
      ? List<Object?>.from(existing['externalAcpEndpoints'] as List)
      : <Object?>[];

  final byKey = <String, Map<String, dynamic>>{};
  final extras = <Map<String, dynamic>>[];

  for (final item in incomingProfiles) {
    if (item is! Map) {
      continue;
    }
    final profile = item.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    final providerKey =
        profile['providerKey']?.toString().trim().toLowerCase() ?? '';
    if (_providerLabels.containsKey(providerKey)) {
      byKey[providerKey] = profile;
    } else if (providerKey.isNotEmpty) {
      extras.add(profile);
    }
  }

  final builtins = <Map<String, dynamic>>[
    for (final provider in _providerLabels.keys)
      <String, dynamic>{
        ...?byKey[provider],
        'providerKey': provider,
        'label': _providerLabels[provider],
        'endpoint': endpoints[provider] ?? '',
        'enabled': enableProviders[provider] ?? true,
      },
  ];

  updated['externalAcpEndpoints'] = <Object>[...builtins, ...extras];
  return updated;
}

Future<Map<String, dynamic>> _readExistingSettings(File settingsFile) async {
  if (!await settingsFile.exists()) {
    return <String, dynamic>{};
  }
  try {
    final raw = await settingsFile.readAsString();
    final decoded = decodeYamlDocument(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
    }
  } catch (error) {
    stderr.writeln(
      'Warning: failed to parse ${settingsFile.path}; starting from an empty map. $error',
    );
  }
  return <String, dynamic>{};
}

File _defaultSettingsFile({
  required Map<String, String> environment,
  required String operatingSystem,
}) {
  final home = environment['HOME']?.trim() ?? '';
  if (operatingSystem == 'macos' && home.isNotEmpty) {
    return File(
      '$home/Library/Application Support/xworkmate/config/settings.yaml',
    );
  }
  if (operatingSystem == 'linux' && home.isNotEmpty) {
    final xdgConfigHome = environment['XDG_CONFIG_HOME']?.trim() ?? '';
    final base = xdgConfigHome.isNotEmpty ? xdgConfigHome : '$home/.config';
    return File('$base/xworkmate/config/settings.yaml');
  }
  if (operatingSystem == 'windows') {
    final appData = environment['APPDATA']?.trim() ?? '';
    if (appData.isNotEmpty) {
      return File('$appData\\xworkmate\\config\\settings.yaml');
    }
    final userProfile = environment['USERPROFILE']?.trim() ?? '';
    if (userProfile.isNotEmpty) {
      return File('$userProfile\\.xworkmate\\config\\settings.yaml');
    }
  }
  if (home.isNotEmpty) {
    return File('$home/.xworkmate/config/settings.yaml');
  }
  return File('settings.yaml');
}

enum _Command { apply, printPlan }

class _CliOptions {
  const _CliOptions({
    required this.command,
    required this.showHelp,
    required this.dryRun,
    required this.backup,
    required this.settingsFile,
    required this.endpoints,
    required this.enableProviders,
  });

  final _Command command;
  final bool showHelp;
  final bool dryRun;
  final bool backup;
  final File? settingsFile;
  final Map<String, String> endpoints;
  final Map<String, bool> enableProviders;

  static _CliOptions parse(List<String> args) {
    if (args.isEmpty) {
      return _CliOptions(
        command: _Command.apply,
        showHelp: true,
        dryRun: false,
        backup: true,
        settingsFile: null,
        endpoints: const <String, String>{},
        enableProviders: const <String, bool>{},
      );
    }

    final normalizedCommand = switch (args.first.trim().toLowerCase()) {
      'apply' => _Command.apply,
      'print' => _Command.printPlan,
      '--help' || '-h' || 'help' => _Command.apply,
      _ => _Command.apply,
    };
    final showHelp = <String>{
      '--help',
      '-h',
      'help',
    }.contains(args.first.trim().toLowerCase());
    final rest = showHelp ? args.skip(1).toList(growable: false) : args.skip(1);

    var dryRun = false;
    var backup = true;
    File? settingsFile;
    final endpoints = <String, String>{};
    final enableProviders = <String, bool>{};

    final values = rest.toList(growable: false);
    for (var index = 0; index < values.length; index += 1) {
      final argument = values[index].trim();
      if (argument.isEmpty) {
        continue;
      }
      if (argument == '--help' || argument == '-h') {
        return _CliOptions(
          command: normalizedCommand,
          showHelp: true,
          dryRun: dryRun,
          backup: backup,
          settingsFile: settingsFile,
          endpoints: endpoints,
          enableProviders: enableProviders,
        );
      }
      if (argument == '--dry-run') {
        dryRun = true;
        continue;
      }
      if (argument == '--no-backup') {
        backup = false;
        continue;
      }
      if (argument.startsWith('--disable-')) {
        final provider = argument.substring('--disable-'.length).trim();
        if (_providerLabels.containsKey(provider)) {
          enableProviders[provider] = false;
          continue;
        }
      }

      if (!argument.startsWith('--')) {
        stderr.writeln('Ignoring unexpected argument: $argument');
        continue;
      }

      if (index + 1 >= values.length) {
        throw ArgumentError('Missing value for $argument');
      }

      final value = values[index + 1].trim();
      index += 1;
      switch (argument) {
        case '--settings-file':
          settingsFile = File(value);
          break;
        case '--codex-endpoint':
          endpoints['codex'] = value;
          break;
        case '--opencode-endpoint':
          endpoints['opencode'] = value;
          break;
        case '--claude-endpoint':
          endpoints['claude'] = value;
          break;
        case '--gemini-endpoint':
          endpoints['gemini'] = value;
          break;
        default:
          stderr.writeln('Ignoring unknown option: $argument');
          break;
      }
    }

    return _CliOptions(
      command: normalizedCommand,
      showHelp: showHelp,
      dryRun: dryRun,
      backup: backup,
      settingsFile: settingsFile,
      endpoints: endpoints,
      enableProviders: enableProviders,
    );
  }
}

Object? decodeYamlDocument(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    return _yamlToObject(loadYaml(trimmed));
  } catch (_) {
    return null;
  }
}

Object? _yamlToObject(Object? value) {
  if (value is YamlMap) {
    return value.map(
      (Object? key, Object? item) =>
          MapEntry(key?.toString() ?? '', _yamlToObject(item)),
    );
  }
  if (value is YamlList) {
    return value.map(_yamlToObject).toList(growable: false);
  }
  return value;
}

String encodeYamlDocument(Object? value) {
  final buffer = StringBuffer('---\n');
  _writeYamlValue(buffer, value, 0, listItem: false);
  if (!buffer.toString().endsWith('\n')) {
    buffer.writeln();
  }
  return buffer.toString();
}

void _writeYamlValue(
  StringBuffer buffer,
  Object? value,
  int indent, {
  required bool listItem,
}) {
  final prefix = '  ' * indent;
  if (value is Map) {
    if (value.isEmpty) {
      if (listItem) {
        buffer.writeln('{}');
      } else {
        buffer.writeln('$prefix{}');
      }
      return;
    }
    if (listItem) {
      buffer.writeln();
    }
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final item = entry.value;
      if (_isInlineYamlValue(item)) {
        buffer.writeln('$prefix$key: ${_yamlInlineValue(item)}');
      } else if (item is String && item.contains('\n')) {
        buffer.writeln('$prefix$key: |-');
        for (final line in item.split('\n')) {
          buffer.writeln('${'  ' * (indent + 1)}$line');
        }
      } else {
        buffer.writeln('$prefix$key:');
        _writeYamlValue(buffer, item, indent + 1, listItem: false);
      }
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      if (listItem) {
        buffer.writeln('[]');
      } else {
        buffer.writeln('$prefix[]');
      }
      return;
    }
    if (listItem) {
      buffer.writeln();
    }
    for (final item in value) {
      if (_isInlineYamlValue(item)) {
        buffer.writeln('$prefix- ${_yamlInlineValue(item)}');
      } else if (item is String && item.contains('\n')) {
        buffer.writeln('$prefix- |-');
        for (final line in item.split('\n')) {
          buffer.writeln('${'  ' * (indent + 1)}$line');
        }
      } else {
        buffer.writeln('$prefix-');
        _writeYamlValue(buffer, item, indent + 1, listItem: false);
      }
    }
    return;
  }
  if (listItem) {
    buffer.writeln(_yamlInlineValue(value));
    return;
  }
  buffer.writeln('$prefix${_yamlInlineValue(value)}');
}

bool _isInlineYamlValue(Object? value) {
  if (value == null || value is bool || value is num) {
    return true;
  }
  if (value is String) {
    return !value.contains('\n');
  }
  if (value is List) {
    return value.isEmpty;
  }
  if (value is Map) {
    return value.isEmpty;
  }
  return false;
}

String _yamlInlineValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool || value is num) {
    return value.toString();
  }
  if (value is List && value.isEmpty) {
    return '[]';
  }
  if (value is Map && value.isEmpty) {
    return '{}';
  }
  final stringValue = value.toString();
  if (stringValue.isEmpty) {
    return "''";
  }
  final safe = RegExp(r'^[A-Za-z0-9_./:@+%-]+$');
  final reserved = <String>{'null', 'true', 'false', '~'};
  if (safe.hasMatch(stringValue) && !reserved.contains(stringValue)) {
    return stringValue;
  }
  final escaped = stringValue.replaceAll("'", "''");
  return "'$escaped'";
}
