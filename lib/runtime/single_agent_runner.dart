import 'dart:convert';
import 'dart:io';

import 'multi_agent_orchestrator.dart';
import 'runtime_models.dart';

class SingleAgentProviderResolution {
  const SingleAgentProviderResolution({
    required this.selection,
    required this.resolvedProvider,
    required this.fallbackReason,
  });

  final SingleAgentProvider selection;
  final SingleAgentProvider? resolvedProvider;
  final String? fallbackReason;
}

class SingleAgentRunRequest {
  const SingleAgentRunRequest({
    required this.provider,
    required this.prompt,
    required this.model,
    required this.workingDirectory,
    required this.attachments,
    required this.selectedSkills,
    required this.aiGatewayBaseUrl,
    required this.aiGatewayApiKey,
    required this.config,
    this.configuredCodexCliPath = '',
  });

  final SingleAgentProvider provider;
  final String prompt;
  final String model;
  final String workingDirectory;
  final List<CollaborationAttachment> attachments;
  final List<String> selectedSkills;
  final String aiGatewayBaseUrl;
  final String aiGatewayApiKey;
  final MultiAgentConfig config;
  final String configuredCodexCliPath;
}

class SingleAgentRunResult {
  const SingleAgentRunResult({
    required this.provider,
    required this.output,
    required this.success,
    required this.errorMessage,
    required this.shouldFallbackToAiChat,
    this.fallbackReason,
  });

  final SingleAgentProvider provider;
  final String output;
  final bool success;
  final String errorMessage;
  final bool shouldFallbackToAiChat;
  final String? fallbackReason;
}

abstract class SingleAgentRunner {
  Future<SingleAgentProviderResolution> resolveProvider({
    required SingleAgentProvider selection,
    required String configuredCodexCliPath,
  });

  Future<SingleAgentRunResult> run(SingleAgentRunRequest request);
}

class DefaultSingleAgentRunner implements SingleAgentRunner {
  DefaultSingleAgentRunner({
    Future<bool> Function(String command)? binaryExistsResolver,
    CliProcessStarter? processStarter,
  }) : _binaryExistsResolver = binaryExistsResolver,
       _processStarter =
           processStarter ??
           ((executable, arguments, {environment, workingDirectory}) {
             return Process.start(
               executable,
               arguments,
               environment: environment,
               workingDirectory: workingDirectory,
             );
           });

  static const List<SingleAgentProvider> _autoOrder = <SingleAgentProvider>[
    SingleAgentProvider.codex,
    SingleAgentProvider.opencode,
    SingleAgentProvider.claude,
    SingleAgentProvider.gemini,
  ];

  final Future<bool> Function(String command)? _binaryExistsResolver;
  final CliProcessStarter _processStarter;

  @override
  Future<SingleAgentProviderResolution> resolveProvider({
    required SingleAgentProvider selection,
    required String configuredCodexCliPath,
  }) async {
    if (selection != SingleAgentProvider.auto) {
      final available = await _isProviderAvailable(
        selection,
        configuredCodexCliPath: configuredCodexCliPath,
      );
      return SingleAgentProviderResolution(
        selection: selection,
        resolvedProvider: available ? selection : null,
        fallbackReason: available
            ? null
            : '${selection.label} CLI is unavailable on this device.',
      );
    }

    for (final provider in _autoOrder) {
      if (await _isProviderAvailable(
        provider,
        configuredCodexCliPath: configuredCodexCliPath,
      )) {
        return SingleAgentProviderResolution(
          selection: selection,
          resolvedProvider: provider,
          fallbackReason: null,
        );
      }
    }

    return const SingleAgentProviderResolution(
      selection: SingleAgentProvider.auto,
      resolvedProvider: null,
      fallbackReason: 'No supported external CLI provider is available.',
    );
  }

  @override
  Future<SingleAgentRunResult> run(SingleAgentRunRequest request) async {
    final command = _resolveCommand(
      request.provider,
      configuredCodexCliPath: request.configuredCodexCliPath,
      model: request.model,
    );
    final args = _buildArgs(
      provider: request.provider,
      command: command,
      model: request.model,
      prompt: _augmentPrompt(request),
      cwd: request.workingDirectory,
    );
    final env = _buildEnvVars(
      provider: request.provider,
      aiGatewayBaseUrl: request.aiGatewayBaseUrl,
      aiGatewayApiKey: request.aiGatewayApiKey,
      config: request.config,
    );

    try {
      final process = await _processStarter(
        command,
        args,
        environment: env,
        workingDirectory: request.workingDirectory.trim().isEmpty
            ? null
            : request.workingDirectory,
      );
      await process.stdin.close();
      final timeout = Duration(seconds: request.config.timeoutSeconds);
      final stdout = await process.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(timeout, onTimeout: () => '');
      final stderr = await process.stderr
          .transform(utf8.decoder)
          .join()
          .timeout(timeout, onTimeout: () => '');
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () => -1,
      );

      final output = stdout.trim().isNotEmpty ? stdout.trim() : stderr.trim();
      if (exitCode == 0 && output.isNotEmpty) {
        return SingleAgentRunResult(
          provider: request.provider,
          output: output,
          success: true,
          errorMessage: '',
          shouldFallbackToAiChat: false,
        );
      }

      final fallbackReason = _isLaunchFailureExit(exitCode, stderr)
          ? '${request.provider.label} CLI could not be launched.'
          : null;
      return SingleAgentRunResult(
        provider: request.provider,
        output: output,
        success: false,
        errorMessage: stderr.trim().isNotEmpty
            ? stderr.trim()
            : 'CLI exited with code $exitCode',
        shouldFallbackToAiChat: fallbackReason != null,
        fallbackReason: fallbackReason,
      );
    } catch (error) {
      final fallbackReason = _isLaunchFailureError(error)
          ? '${request.provider.label} CLI could not be launched.'
          : null;
      return SingleAgentRunResult(
        provider: request.provider,
        output: '',
        success: false,
        errorMessage: error.toString(),
        shouldFallbackToAiChat: fallbackReason != null,
        fallbackReason: fallbackReason,
      );
    }
  }

  Future<bool> _isProviderAvailable(
    SingleAgentProvider provider, {
    required String configuredCodexCliPath,
  }) async {
    if (provider == SingleAgentProvider.auto) {
      return false;
    }
    if (provider == SingleAgentProvider.codex &&
        configuredCodexCliPath.trim().isNotEmpty) {
      return File(configuredCodexCliPath.trim()).existsSync();
    }
    return _binaryExists(_binaryName(provider));
  }

  Future<bool> _binaryExists(String command) async {
    if (_binaryExistsResolver != null) {
      return _binaryExistsResolver(command);
    }
    final check = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      <String>[command],
      runInShell: true,
    );
    return check.exitCode == 0 && '${check.stdout}'.trim().isNotEmpty;
  }

  String _binaryName(SingleAgentProvider provider) {
    return switch (provider) {
      SingleAgentProvider.auto => 'auto',
      SingleAgentProvider.codex => 'codex',
      SingleAgentProvider.opencode => 'opencode',
      SingleAgentProvider.claude => 'claude',
      SingleAgentProvider.gemini => 'gemini',
    };
  }

  String _resolveCommand(
    SingleAgentProvider provider, {
    required String configuredCodexCliPath,
    required String model,
  }) {
    final useOllamaLaunch = _prefersOllamaLaunch(
      provider: provider,
      model: model,
    );
    if (useOllamaLaunch) {
      return 'ollama';
    }
    if (provider == SingleAgentProvider.codex &&
        configuredCodexCliPath.trim().isNotEmpty) {
      return configuredCodexCliPath.trim();
    }
    return _binaryName(provider);
  }

  List<String> _buildArgs({
    required SingleAgentProvider provider,
    required String command,
    required String model,
    required String prompt,
    required String cwd,
  }) {
    final useOllamaLaunch = command == 'ollama';
    switch (provider) {
      case SingleAgentProvider.claude:
        if (useOllamaLaunch) {
          return _buildOllamaLaunchArgs(
            provider: provider,
            model: model,
            prompt: prompt,
            cwd: cwd,
          );
        }
        return model.trim().isEmpty
            ? <String>['-p', prompt]
            : <String>['--model', model.trim(), '-p', prompt];
      case SingleAgentProvider.codex:
        if (useOllamaLaunch) {
          return _buildOllamaLaunchArgs(
            provider: provider,
            model: model,
            prompt: prompt,
            cwd: cwd,
          );
        }
        return <String>[
          'exec',
          '--skip-git-repo-check',
          '--color',
          'never',
          if (cwd.trim().isNotEmpty) ...<String>['-C', cwd.trim()],
          if (model.trim().isNotEmpty) ...<String>['-m', model.trim()],
          prompt,
        ];
      case SingleAgentProvider.gemini:
        return model.trim().isEmpty
            ? <String>['-p', prompt]
            : <String>['--model', model.trim(), '-p', prompt];
      case SingleAgentProvider.opencode:
        if (useOllamaLaunch) {
          return _buildOllamaLaunchArgs(
            provider: provider,
            model: model,
            prompt: prompt,
            cwd: cwd,
          );
        }
        return <String>[
          'run',
          '--format',
          'default',
          if (cwd.trim().isNotEmpty) ...<String>['--dir', cwd.trim()],
          if (model.trim().isNotEmpty) ...<String>['-m', model.trim()],
          prompt,
        ];
      case SingleAgentProvider.auto:
        return const <String>[];
    }
  }

  bool _prefersOllamaLaunch({
    required SingleAgentProvider provider,
    required String model,
  }) {
    if (model.trim().isEmpty) {
      return false;
    }
    return provider == SingleAgentProvider.codex ||
        provider == SingleAgentProvider.opencode ||
        provider == SingleAgentProvider.claude;
  }

  List<String> _buildOllamaLaunchArgs({
    required SingleAgentProvider provider,
    required String model,
    required String prompt,
    required String cwd,
  }) {
    final tool = provider.providerId;
    final args = <String>['launch', tool, '--model', model.trim()];
    if (provider == SingleAgentProvider.claude) {
      args.add('--yes');
      args.addAll(<String>['--', '-p', prompt]);
      return args;
    }
    if (provider == SingleAgentProvider.codex) {
      args.addAll(<String>[
        '--',
        'exec',
        '--skip-git-repo-check',
        '--color',
        'never',
        if (cwd.trim().isNotEmpty) ...<String>['-C', cwd.trim()],
        prompt,
      ]);
      return args;
    }
    if (provider == SingleAgentProvider.opencode) {
      args.addAll(<String>[
        '--',
        'run',
        '--format',
        'default',
        if (cwd.trim().isNotEmpty) ...<String>['--dir', cwd.trim()],
        prompt,
      ]);
      return args;
    }
    args.addAll(<String>['--', '-p', prompt]);
    return args;
  }

  Map<String, String> _buildEnvVars({
    required SingleAgentProvider provider,
    required String aiGatewayBaseUrl,
    required String aiGatewayApiKey,
    required MultiAgentConfig config,
  }) {
    final baseEnv = <String, String>{...Platform.environment};
    if (config.aiGatewayInjectionPolicy != AiGatewayInjectionPolicy.disabled &&
        aiGatewayBaseUrl.trim().isNotEmpty &&
        aiGatewayApiKey.trim().isNotEmpty) {
      baseEnv['OPENAI_BASE_URL'] = aiGatewayBaseUrl.trim();
      baseEnv['OPENAI_API_KEY'] = aiGatewayApiKey.trim();
      baseEnv['OLLAMA_BASE_URL'] = aiGatewayBaseUrl.trim();
      baseEnv['OLLAMA_HOST'] = aiGatewayBaseUrl.trim();
      if (provider == SingleAgentProvider.claude) {
        baseEnv['ANTHROPIC_BASE_URL'] = aiGatewayBaseUrl.trim();
        baseEnv['ANTHROPIC_AUTH_TOKEN'] = aiGatewayApiKey.trim();
        baseEnv['ANTHROPIC_API_KEY'] = aiGatewayApiKey.trim();
      }
      return baseEnv;
    }
    final ollamaEndpoint = config.ollamaEndpoint.trim();
    if (ollamaEndpoint.isNotEmpty) {
      baseEnv['OLLAMA_BASE_URL'] = ollamaEndpoint;
      baseEnv['OLLAMA_HOST'] = ollamaEndpoint;
      baseEnv['OPENAI_API_KEY'] = 'ollama';
      baseEnv['OPENAI_BASE_URL'] = ollamaEndpoint.endsWith('/v1')
          ? ollamaEndpoint
          : '$ollamaEndpoint/v1';
    }
    if (provider == SingleAgentProvider.claude ||
        provider == SingleAgentProvider.codex) {
      baseEnv['ANTHROPIC_AUTH_TOKEN'] = 'ollama';
      baseEnv['ANTHROPIC_API_KEY'] = '';
      baseEnv['ANTHROPIC_BASE_URL'] = ollamaEndpoint;
    }
    return baseEnv;
  }

  String _augmentPrompt(SingleAgentRunRequest request) {
    if (request.attachments.isEmpty) {
      return request.prompt;
    }
    final attachmentLines = request.attachments
        .map((item) => '- ${item.name}: ${item.path}')
        .join('\n');
    return 'User-selected local attachments:\n$attachmentLines\n\n${request.prompt}';
  }

  bool _isLaunchFailureExit(int exitCode, String stderr) {
    if (exitCode == 127 || exitCode == 9009 || exitCode == -1) {
      return true;
    }
    final normalized = stderr.toLowerCase();
    return normalized.contains('not found') ||
        normalized.contains('no such file') ||
        normalized.contains('is not recognized');
  }

  bool _isLaunchFailureError(Object error) {
    if (error is ProcessException) {
      return true;
    }
    final normalized = error.toString().toLowerCase();
    return normalized.contains('not found') ||
        normalized.contains('no such file') ||
        normalized.contains('cannot find');
  }
}
