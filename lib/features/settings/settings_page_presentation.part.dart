part of 'settings_page.dart';

extension _SettingsPagePresentationMixin on _SettingsPageState {
  List<Widget> _buildAppearance(
    BuildContext context,
    AppController controller,
  ) {
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('主题', 'Theme'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ChoiceChip(
                  label: Text(appText('浅色', 'Light')),
                  selected: controller.themeMode == ThemeMode.light,
                  onSelected: (_) => controller.setThemeMode(ThemeMode.light),
                ),
                ChoiceChip(
                  label: Text(appText('深色', 'Dark')),
                  selected: controller.themeMode == ThemeMode.dark,
                  onSelected: (_) => controller.setThemeMode(ThemeMode.dark),
                ),
                ChoiceChip(
                  label: Text(appText('跟随系统', 'System')),
                  selected: controller.themeMode == ThemeMode.system,
                  onSelected: (_) => controller.setThemeMode(ThemeMode.system),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildDiagnostics(
    BuildContext context,
    AppController controller,
  ) {
    final runtimeLogs = controller.runtimeLogs
        .where(_matchesRuntimeLogFilter)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('网关诊断', 'Gateway Diagnostics'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: appText('连接', 'Connection'),
              value: controller.connection.status.label,
            ),
            _InfoRow(
              label: appText('地址', 'Address'),
              value:
                  controller.connection.remoteAddress ??
                  appText('离线', 'Offline'),
            ),
            _InfoRow(
              label: appText('代理', 'Agent'),
              value: controller.activeAgentName,
            ),
            _InfoRow(
              label: appText('认证模式', 'Auth Mode'),
              value:
                  controller.connection.connectAuthMode ??
                  appText('未发起', 'Not attempted'),
            ),
            _InfoRow(
              label: appText('认证诊断', 'Auth Diagnostics'),
              value: controller.connection.connectAuthSummary,
            ),
            _InfoRow(
              label: appText('健康负载', 'Health Payload'),
              value: controller.connection.healthPayload == null
                  ? appText('不可用', 'Unavailable')
                  : encodePrettyJson(controller.connection.healthPayload!),
            ),
            _InfoRow(
              label: appText('状态负载', 'Status Payload'),
              value: controller.connection.statusPayload == null
                  ? appText('不可用', 'Unavailable')
                  : encodePrettyJson(controller.connection.statusPayload!),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        key: const ValueKey('runtime-log-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appText('运行日志', 'Runtime Logs'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        appText(
                          '只记录本机运行期的连接、鉴权、配对和 socket 诊断，不写入密钥明文。',
                          'Shows local runtime diagnostics for connection, auth, pairing, and socket events without logging secret values.',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: runtimeLogs.isEmpty
                      ? null
                      : () => controller.clearRuntimeLogs(),
                  child: Text(appText('清空', 'Clear')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('runtime-log-filter'),
              controller: _runtimeLogFilterController,
              decoration: InputDecoration(
                labelText: appText('筛选日志', 'Filter Logs'),
                hintText: appText(
                  '按级别、分类或关键字过滤',
                  'Filter by level, category, or keyword',
                ),
                prefixIcon: const Icon(Icons.manage_search_rounded),
              ),
              onChanged: (_) => _setState(() {}),
            ),
            const SizedBox(height: 16),
            if (runtimeLogs.isEmpty)
              Text(
                appText('当前没有运行日志。', 'No runtime logs yet.'),
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SelectionArea(
                  child: ListView.separated(
                    itemCount: runtimeLogs.length,
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final entry = runtimeLogs[index];
                      return SelectableText(
                        entry.line,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        key: const ValueKey('assistant-local-state-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('本地数据清理', 'Local Data Cleanup'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              appText(
                '删除本机保存的 Assistant 任务线程会话、本地设置快照和恢复备份，不会删除已保存密钥，也不会触碰外部 Codex 全局目录。',
                'Deletes locally saved Assistant threads, settings snapshots, and recovery backups. Stored secrets and the external Codex home stay untouched.',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('assistant-local-state-clear-button'),
                onPressed: () =>
                    _showClearAssistantLocalStateDialog(context, controller),
                icon: const Icon(Icons.delete_forever_rounded),
                label: Text(
                  appText('清理任务线程与本地配置', 'Clear threads and local config'),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText('设备', 'Device'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: appText('平台', 'Platform'),
              value: controller.runtime.deviceInfo.platformLabel,
            ),
            _InfoRow(
              label: appText('设备类型', 'Device Family'),
              value: controller.runtime.deviceInfo.deviceFamily,
            ),
            _InfoRow(
              label: appText('型号标识', 'Model Identifier'),
              value: controller.runtime.deviceInfo.modelIdentifier,
            ),
          ],
        ),
      ),
    ];
  }
}
