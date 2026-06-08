import '../../i18n/app_language.dart';

class WorkspaceManagementText {
  const WorkspaceManagementText._();

  static String get button =>
      appText('工作空间管理', 'Workspace management');
  static String get title =>
      appText('创建 / 升级 AI 工作空间', 'Create / Upgrade AI Workspace');
  static String get detect => appText('检测服务器', 'Detect server');
  static String get create => appText('创建工作空间', 'Create workspace');
  static String get upgrade => appText('升级工作空间', 'Upgrade workspace');
  static String get upgradeUnavailable => appText(
    '等待 playbooks 仓库提供 upgrade-ai-workspace.yml 后启用',
    'Enabled after playbooks provides upgrade-ai-workspace.yml',
  );
  static String get logs => appText('查看日志', 'View logs');
  static String get copyLogs => appText('复制日志', 'Copy logs');
  static String get ready =>
      appText('工作空间已就绪', 'Workspace is ready');
  static String get failed => appText('执行失败', 'Provisioning failed');
  static String get connectToWorkspace =>
      appText('连接到该工作空间', 'Connect to this workspace');
  static String get copyAddress => appText('复制地址', 'Copy address');
  static String get requiredFields => appText(
    '请填写服务器地址、Workspace 域名和认证信息。',
    'Enter server address, workspace domain, and authentication.',
  );
}
