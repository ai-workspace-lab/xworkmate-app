import 'dart:io';

enum RuntimeHostPlatform { macos, windows, linux, ios, android, other }

RuntimeHostPlatform detectRuntimeHostPlatform({String? operatingSystem}) {
  return switch (operatingSystem ?? Platform.operatingSystem) {
    'macos' => RuntimeHostPlatform.macos,
    'windows' => RuntimeHostPlatform.windows,
    'linux' => RuntimeHostPlatform.linux,
    'ios' => RuntimeHostPlatform.ios,
    'android' => RuntimeHostPlatform.android,
    _ => RuntimeHostPlatform.other,
  };
}

String resolveUserHomeDirectory({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final host = detectRuntimeHostPlatform(operatingSystem: operatingSystem);

  if (host == RuntimeHostPlatform.windows) {
    final userProfile = env['USERPROFILE']?.trim() ?? '';
    if (userProfile.isNotEmpty) {
      return userProfile;
    }
    final homeDrive = env['HOMEDRIVE']?.trim() ?? '';
    final homePath = env['HOMEPATH']?.trim() ?? '';
    if (homeDrive.isNotEmpty && homePath.isNotEmpty) {
      return '$homeDrive$homePath';
    }
  }

  final home = env['HOME']?.trim() ?? '';
  if (home.isNotEmpty) {
    return home;
  }

  return env['USERPROFILE']?.trim() ?? '';
}

String resolveCodexHomeDirectory({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final explicit = env['CODEX_HOME']?.trim() ?? '';
  if (explicit.isNotEmpty) {
    return explicit;
  }

  final home = resolveUserHomeDirectory(
    environment: env,
    operatingSystem: operatingSystem,
  );
  if (home.isEmpty) {
    return '.codex';
  }
  return joinPlatformPath(home, '.codex', operatingSystem: operatingSystem);
}

String joinPlatformPath(String base, String child, {String? operatingSystem}) {
  if (base.isEmpty) {
    return child;
  }
  final separator =
      detectRuntimeHostPlatform(operatingSystem: operatingSystem) ==
          RuntimeHostPlatform.windows
      ? r'\'
      : '/';
  final normalizedBase = base.endsWith(separator)
      ? base.substring(0, base.length - 1)
      : base;
  return '$normalizedBase$separator$child';
}

List<String> defaultCodexBinaryCandidates({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final host = detectRuntimeHostPlatform(operatingSystem: operatingSystem);
  final home = resolveUserHomeDirectory(
    environment: env,
    operatingSystem: operatingSystem,
  );

  if (host == RuntimeHostPlatform.windows) {
    final appData = env['APPDATA']?.trim() ?? '';
    final localAppData = env['LOCALAPPDATA']?.trim() ?? '';
    return <String>[
      if (home.isNotEmpty)
        joinPlatformPath(
          home,
          r'.cargo\bin\codex.exe',
          operatingSystem: operatingSystem,
        ),
      if (appData.isNotEmpty)
        joinPlatformPath(
          appData,
          r'npm\codex.cmd',
          operatingSystem: operatingSystem,
        ),
      if (localAppData.isNotEmpty)
        joinPlatformPath(
          localAppData,
          r'Programs\codex\codex.exe',
          operatingSystem: operatingSystem,
        ),
      if (home.isNotEmpty)
        joinPlatformPath(
          home,
          r'scoop\shims\codex.cmd',
          operatingSystem: operatingSystem,
        ),
    ];
  }

  return <String>[
    '/usr/local/bin/codex',
    '/opt/homebrew/bin/codex',
    if (home.isNotEmpty)
      joinPlatformPath(
        home,
        '.cargo/bin/codex',
        operatingSystem: operatingSystem,
      ),
    if (home.isNotEmpty)
      joinPlatformPath(
        home,
        '.local/bin/codex',
        operatingSystem: operatingSystem,
      ),
    if (host == RuntimeHostPlatform.linux) '/usr/bin/codex',
  ];
}

String resolveGatewayClientId({String? operatingSystem}) {
  return switch (detectRuntimeHostPlatform(operatingSystem: operatingSystem)) {
    RuntimeHostPlatform.macos => 'openclaw-macos',
    RuntimeHostPlatform.windows => 'openclaw-windows',
    RuntimeHostPlatform.ios => 'openclaw-ios',
    RuntimeHostPlatform.android => 'openclaw-android',
    RuntimeHostPlatform.linux => 'openclaw-linux',
    RuntimeHostPlatform.other => 'gateway-client',
  };
}
