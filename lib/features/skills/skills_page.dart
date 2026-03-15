 import 'package:flutter/material.dart';
 
 import '../../app/app_controller.dart';
 import '../../i18n/app_language.dart';
 import '../../models/app_models.dart';
 import '../../runtime/runtime_models.dart';
 import '../../widgets/status_badge.dart';
 import '../../widgets/surface_card.dart';
 import '../../widgets/top_bar.dart';

class SkillsPage extends StatelessWidget {
  const SkillsPage({
    super.key,
    required this.controller,
    required this.onOpenDetail,
  });

  final AppController controller;
  final ValueChanged<DetailPanelData> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final items = controller.skills;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                breadcrumbs: [
                  AppBreadcrumbItem(
                    label: appText('主页', 'Home'),
                    icon: Icons.home_rounded,
                    onTap: controller.navigateHome,
                  ),
                  AppBreadcrumbItem(label: appText('技能', 'Skills')),
                ],
                title: appText('技能', 'Skills'),
                subtitle: appText(
                  '管理已安装的技能包，查看技能状态与依赖。',
                  'Manage installed skill packages, view status and dependencies.',
                ),
                trailing: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: appText('搜索技能', 'Search skills'),
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await controller.skillsController.refresh(
                          agentId: controller.selectedAgentId.isEmpty
                              ? null
                              : controller.selectedAgentId,
                        );
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (items.isEmpty)
                SurfaceCard(
                  child: Text(
                    controller.connection.status ==
                            RuntimeConnectionStatus.connected
                        ? appText(
                            '当前网关或代理没有加载技能。',
                            'No skills loaded for the active gateway / agent.',
                          )
                        : appText(
                            '连接 Gateway 后可加载技能。',
                            'Connect a gateway to load skills.',
                          ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items
                      .map(
                        (skill) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SurfaceCard(
                            onTap: () => onOpenDetail(
                              DetailPanelData(
                                title: skill.name,
                                subtitle: appText('技能', 'Skill'),
                                icon: Icons.extension_rounded,
                                status: skill.disabled
                                    ? StatusInfo(
                                        appText('已禁用', 'Disabled'),
                                        StatusTone.warning,
                                      )
                                    : StatusInfo(
                                        appText('已启用', 'Enabled'),
                                        StatusTone.success,
                                      ),
                                description: skill.description,
                                meta: [skill.source, skill.skillKey],
                                actions: [appText('刷新', 'Refresh')],
                                sections: [
                                  DetailSection(
                                    title: appText('依赖要求', 'Requirements'),
                                    items: [
                                      DetailItem(
                                        label: appText(
                                            '缺失二进制', 'Missing bins'),
                                        value: skill.missingBins.isEmpty
                                            ? appText('无', 'None')
                                            : skill.missingBins.join(', '),
                                      ),
                                      DetailItem(
                                        label: appText(
                                            '缺失环境变量', 'Missing env'),
                                        value: skill.missingEnv.isEmpty
                                            ? appText('无', 'None')
                                            : skill.missingEnv.join(', '),
                                      ),
                                      DetailItem(
                                        label: appText('缺失配置', 'Missing config'),
                                        value: skill.missingConfig.isEmpty
                                            ? appText('无', 'None')
                                            : skill.missingConfig.join(', '),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        skill.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        skill.description,
                                        style:
                                            Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: StatusBadge(
                                    status: skill.disabled
                                        ? StatusInfo(
                                            appText('已禁用', 'Disabled'),
                                            StatusTone.warning,
                                          )
                                        : StatusInfo(
                                            appText('已启用', 'Enabled'),
                                            StatusTone.success,
                                          ),
                                  ),
                                ),
                                Expanded(flex: 2, child: Text(skill.source)),
                                Expanded(
                                  flex: 2,
                                  child: Text(skill.primaryEnv ?? 'workspace'),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}
