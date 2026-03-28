part of 'settings_page.dart';

extension _SettingsPageMultiAgentMixin on _SettingsPageState {
  List<Widget> _buildAgents(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
  ) {
    final orchestrator = controller.multiAgentOrchestrator;
    final config = settings.multiAgent;
    final theme = Theme.of(context);
    final mountTargets = List<ManagedMountTargetState>.from(config.mountTargets)
      ..sort(
        (left, right) =>
            left.label.toLowerCase().compareTo(right.label.toLowerCase()),
      );
    final managedSkillCount = config.managedSkills
        .where((item) => item.selected)
        .length;
    final managedMcpCount = config.managedMcpServers
        .where((item) => item.enabled)
        .length;

    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final info = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText('多 Agent 协作', 'Multi-Agent Collaboration'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appText(
                        '限定在多 Agent 协作：Architect 负责调度/文档，Lead Engineer 负责主程，Worker/Review 负责并行 worker 与复审；第一批外部桥接走 ollama launch。',
                        'Multi-agent only: Architect handles orchestration/docs, Lead Engineer owns the critical path, Worker/Review handles parallel workers and review; first-batch external bridges run through ollama launch.',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                );
                final toggle = _InlineSwitchField(
                  label: appText('启用协作模式', 'Enable Collaboration'),
                  value: config.enabled,
                  onChanged: (value) => _saveMultiAgentConfig(
                    controller,
                    config.copyWith(enabled: value),
                  ),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [info, const SizedBox(height: 16), toggle],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 20),
                    Flexible(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: toggle,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('multi-agent-framework-${config.framework.name}'),
              initialValue: config.framework.name,
              decoration: InputDecoration(
                labelText: appText('协作框架', 'Framework'),
              ),
              items: MultiAgentFramework.values
                  .map(
                    (framework) => DropdownMenuItem<String>(
                      value: framework.name,
                      child: Text(framework.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                final framework = MultiAgentFrameworkCopy.fromJsonValue(value);
                _saveMultiAgentConfig(
                  controller,
                  config.copyWith(
                    framework: framework,
                    arisEnabled: framework == MultiAgentFramework.aris,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Ollama', value: config.ollamaEndpoint),
            _InfoRow(
              label: appText('文档 Lane', 'Doc Lane'),
              value:
                  '${config.architect.cliTool} · ${config.architect.model.isEmpty ? '—' : config.architect.model}',
            ),
            _InfoRow(
              label: appText('主程 Lane', 'Lead Lane'),
              value:
                  '${config.engineer.cliTool} · ${config.engineer.model.isEmpty ? '—' : config.engineer.model}',
            ),
            _InfoRow(
              label: appText('Worker Lane', 'Worker Lane'),
              value:
                  '${config.tester.cliTool} · ${config.tester.model.isEmpty ? '—' : config.tester.model}',
            ),
            _InfoRow(
              label: appText('超时时间', 'Timeout'),
              value: '${config.timeoutSeconds}s',
            ),
            _InfoRow(
              label: 'ARIS',
              value: config.usesAris
                  ? [
                      config.arisCompatStatus,
                      if (config.arisBundleVersion.trim().isNotEmpty)
                        config.arisBundleVersion.trim(),
                    ].join(' · ')
                  : appText('未启用', 'Disabled'),
            ),
            _InfoRow(
              label: appText('运行状态', 'Runtime'),
              value: orchestrator.isRunning
                  ? appText('协作执行中', 'Collaboration running')
                  : config.enabled
                  ? appText('已启用', 'Enabled')
                  : appText('已停用', 'Disabled'),
            ),
          ],
        ),
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('角色配置', 'Role Configuration'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _AgentRoleCard(
              title:
                  '🧭 ${appText('Architect（调度/文档）', 'Architect (Docs / Scheduler)')}',
              description: appText(
                '负责 requirements -> acceptance evidence、架构选项排序、文档与调度。',
                'Owns requirements -> acceptance evidence, option ranking, docs, and orchestration.',
              ),
              cliTool: config.architect.cliTool,
              model: config.architect.model,
              enabled: config.architect.enabled,
              cliOptions: _mergeOptions(config.architect.cliTool, const [
                'claude',
                'codex',
                'opencode',
                'gemini',
              ]),
              modelOptions: _getArchitectModelOptions(settings, config),
              onCliChanged: (tool) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  architect: config.architect.copyWith(cliTool: tool),
                ),
              ),
              onModelChanged: (model) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  architect: config.architect.copyWith(model: model),
                ),
              ),
              onEnabledChanged: (enabled) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  architect: config.architect.copyWith(enabled: enabled),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AgentRoleCard(
              title: '🔧 ${appText('Lead Engineer（主程）', 'Lead Engineer')}',
              description: appText(
                '负责关键实现、重构、集成收口，默认走 codex + minimax-m2.7:cloud。',
                'Owns critical implementation, refactors, and integration. Defaults to codex + minimax-m2.7:cloud.',
              ),
              cliTool: config.engineer.cliTool,
              model: config.engineer.model,
              enabled: config.engineer.enabled,
              cliOptions: _mergeOptions(config.engineer.cliTool, const [
                'codex',
                'claude',
                'opencode',
                'gemini',
              ]),
              modelOptions: _getLeadModelOptions(settings, config),
              onCliChanged: (tool) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  engineer: config.engineer.copyWith(cliTool: tool),
                ),
              ),
              onModelChanged: (model) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  engineer: config.engineer.copyWith(model: model),
                ),
              ),
              onEnabledChanged: (enabled) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  engineer: config.engineer.copyWith(enabled: enabled),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _AgentRoleCard(
              title:
                  '🧪 ${appText('Worker/Review（Worker 池）', 'Worker/Review Pool')}',
              description: appText(
                '负责 glm/qwen worker lane、回归审阅和补充建议。',
                'Owns glm/qwen worker lanes, review, regression checks, and follow-up notes.',
              ),
              cliTool: config.tester.cliTool,
              model: config.tester.model,
              enabled: config.tester.enabled,
              cliOptions: _mergeOptions(config.tester.cliTool, const [
                'opencode',
                'codex',
                'claude',
                'gemini',
              ]),
              modelOptions: _getWorkerModelOptions(settings, config),
              onCliChanged: (tool) => _saveMultiAgentConfig(
                controller,
                config.copyWith(tester: config.tester.copyWith(cliTool: tool)),
              ),
              onModelChanged: (model) => _saveMultiAgentConfig(
                controller,
                config.copyWith(tester: config.tester.copyWith(model: model)),
              ),
              onEnabledChanged: (enabled) => _saveMultiAgentConfig(
                controller,
                config.copyWith(
                  tester: config.tester.copyWith(enabled: enabled),
                ),
              ),
            ),
          ],
        ),
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('审阅策略', 'Review Strategy'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _EditableField(
                    label: appText('最大迭代次数', 'Max Iterations'),
                    value: config.maxIterations.toString(),
                    onSubmitted: (value) {
                      final parsed = int.tryParse(value.trim());
                      if (parsed != null && parsed > 0) {
                        _saveMultiAgentConfig(
                          controller,
                          config.copyWith(maxIterations: parsed),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _EditableField(
                    label: appText('最低达标分数', 'Min Acceptable Score'),
                    value: config.minAcceptableScore.toString(),
                    onSubmitted: (value) {
                      final parsed = int.tryParse(value.trim());
                      if (parsed != null && parsed >= 1 && parsed <= 10) {
                        _saveMultiAgentConfig(
                          controller,
                          config.copyWith(minAcceptableScore: parsed),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '当 Worker/Review 评分低于最低分数时，将进入迭代审阅循环。最多迭代指定次数。',
                'When the Worker/Review score is below minimum, the iteration loop runs until max iterations or the score passes.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final info = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText('发现与分发', 'Discovery & Distribution'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appText(
                        'App 作为统一发现与分发中心，维护托管 skills、MCP server list 和 LLM API 默认注入，但不会覆盖用户原有 CLI 配置。',
                        'The app acts as the discovery and distribution center for managed skills, MCP server lists, and LLM API defaults without overwriting existing CLI config.',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                );
                final refreshButton = OutlinedButton(
                  onPressed: () =>
                      controller.refreshMultiAgentMounts(sync: config.autoSync),
                  child: Text(appText('刷新挂载', 'Refresh Mounts')),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [info, const SizedBox(height: 12), refreshButton],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 16),
                    refreshButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _SwitchRow(
              label: appText('自动同步托管配置', 'Auto-sync managed config'),
              value: config.autoSync,
              onChanged: (value) => _saveMultiAgentConfig(
                controller,
                config.copyWith(autoSync: value),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'multi-agent-injection-${config.aiGatewayInjectionPolicy.name}',
              ),
              initialValue: config.aiGatewayInjectionPolicy.name,
              decoration: InputDecoration(
                labelText: appText('LLM API 注入策略', 'LLM API Injection'),
              ),
              items: AiGatewayInjectionPolicy.values
                  .map(
                    (policy) => DropdownMenuItem<String>(
                      value: policy.name,
                      child: Text(policy.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                _saveMultiAgentConfig(
                  controller,
                  config.copyWith(
                    aiGatewayInjectionPolicy:
                        AiGatewayInjectionPolicyCopy.fromJsonValue(value),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: appText('托管 Skills', 'Managed Skills'),
              value: '$managedSkillCount',
            ),
            _InfoRow(
              label: appText('托管 MCP', 'Managed MCP'),
              value: '$managedMcpCount',
            ),
            if (config.usesAris) ...[
              const SizedBox(height: 4),
              Text(
                appText(
                  'ARIS 模式会把内嵌 skills 与 Go core reviewer 作为本地 Ollama 协作增强层，不会覆盖你原有的 CLI 全局配置。',
                  'ARIS mode injects embedded skills and the Go core reviewer for local Ollama collaboration without overwriting your existing CLI global config.',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            ...mountTargets.map(
              (target) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MountTargetCard(target: target),
              ),
            ),
          ],
        ),
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('协作流程概览', 'Workflow Overview'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _WorkflowStep(
              label: '1',
              emoji: '🧭',
              title: appText(
                'Architect（调度/文档）',
                'Architect (Docs / Scheduler)',
              ),
              desc: appText(
                '收敛 requirements -> acceptance evidence，并冻结里程碑。',
                'Freeze requirements -> acceptance evidence and milestones.',
              ),
            ),
            _WorkflowStep(
              label: '2',
              emoji: '🔧',
              title: appText('Lead Engineer（主程）', 'Lead Engineer'),
              desc: appText(
                '主程执行关键路径与集成收口。',
                'Lead engineer executes the critical path and integration.',
              ),
            ),
            _WorkflowStep(
              label: '3',
              emoji: '🧪',
              title: appText('Worker/Review（Worker 池）', 'Worker/Review Pool'),
              desc: appText(
                '并行 worker 补切片，review lane 给出复审与回归建议。',
                'Parallel workers handle bounded slices while the review lane returns critique and regression guidance.',
              ),
            ),
            _WorkflowStep(
              label: '↻',
              emoji: '🔄',
              title: appText('迭代（如需要）', 'Iterate (if needed)'),
              desc: appText(
                '主程修复 -> Worker/Review 重新审阅',
                'Lead engineer fixes -> Worker/Review re-reviews',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '首批支持的外部启动模式：`ollama launch claude --model kimi-k2.5:cloud --yes -- -p ...`、`ollama launch codex --model minimax-m2.7:cloud -- exec ...`、`ollama launch opencode --model glm-5:cloud -- run ...`。',
                'First-batch launch bridges: `ollama launch claude --model kimi-k2.5:cloud --yes -- -p ...`, `ollama launch codex --model minimax-m2.7:cloud -- exec ...`, and `ollama launch opencode --model glm-5:cloud -- run ...`.',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ];
  }

  List<String> _getLocalModelOptions(SettingsSnapshot settings) {
    return <String>[
          settings.ollamaLocal.defaultModel,
          'qwen3.5',
          'glm-4.7-flash',
        ]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<String> _mergeOptions(String current, List<String> defaults) {
    return <String>[current.trim(), ...defaults]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<String> _getArchitectModelOptions(
    SettingsSnapshot settings,
    MultiAgentConfig config,
  ) {
    return _mergeOptions(config.architect.model, <String>[
      'kimi-k2.5:cloud',
      'qwen3.5:cloud',
      'glm-5:cloud',
      ..._getLocalModelOptions(settings),
    ]);
  }

  List<String> _getLeadModelOptions(
    SettingsSnapshot settings,
    MultiAgentConfig config,
  ) {
    return _mergeOptions(config.engineer.model, <String>[
      'minimax-m2.7:cloud',
      'qwen3.5:cloud',
      'glm-5:cloud',
      ..._getLocalModelOptions(settings),
    ]);
  }

  List<String> _getWorkerModelOptions(
    SettingsSnapshot settings,
    MultiAgentConfig config,
  ) {
    return _mergeOptions(config.tester.model, <String>[
      'glm-5:cloud',
      'qwen3.5:cloud',
      'glm-4.7-flash',
      'qwen3.5',
      ..._getLocalModelOptions(settings),
    ]);
  }

  List<Widget> _buildExperimental(
    BuildContext context,
    AppController controller,
    SettingsSnapshot settings,
    UiFeatureAccess uiFeatures,
  ) {
    final toggles = <Widget>[
      if (uiFeatures.allowsExperimentalSetting(
        UiFeatureKeys.settingsExperimentalCanvas,
      ))
        _SwitchRow(
          label: appText('Canvas 宿主', 'Canvas host'),
          value: settings.experimentalCanvas,
          onChanged: (value) => _saveSettings(
            controller,
            settings.copyWith(experimentalCanvas: value),
          ),
        ),
      if (uiFeatures.allowsExperimentalSetting(
        UiFeatureKeys.settingsExperimentalBridge,
      ))
        _SwitchRow(
          label: appText('桥接模式', 'Bridge mode'),
          value: settings.experimentalBridge,
          onChanged: (value) => _saveSettings(
            controller,
            settings.copyWith(experimentalBridge: value),
          ),
        ),
      if (uiFeatures.allowsExperimentalSetting(
        UiFeatureKeys.settingsExperimentalDebug,
      ))
        _SwitchRow(
          label: appText('调试运行时', 'Debug runtime'),
          value: settings.experimentalDebug,
          onChanged: (value) => _saveSettings(
            controller,
            settings.copyWith(experimentalDebug: value),
          ),
        ),
    ];

    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('实验特性', 'Experimental'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (toggles.isEmpty)
              Text(
                appText(
                  '当前发布配置未开放额外实验开关。',
                  'This build does not expose additional experimental toggles.',
                ),
              ),
            ...toggles,
          ],
        ),
      ),
    ];
  }
}
