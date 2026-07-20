# iOS 会话持久化手工回归用例

> 关联:[2026-07-20 持久化加固记录](../tasks/2026-07-20-ios-session-persistence-hardening.md)、[2026-07-20 P1 结构收敛](../tasks/2026-07-20-ios-task-persistence-p1-refactor.md)
> 覆盖 PR:#168(路径重定位)、#170(备份排除)、#171(每会话文件)、#172(Keychain + 重装即登出)、#177(SharedPreferences重构原生存储)、P1 收敛(TaskThreadStore,不向后兼容)
> 前置:真机(iOS 15.6+),已登录 svc.plus 账号,至少两个历史任务会话(其中一个含制品),其中至少一个会话自安装后从未再次打开过。

## C1 冷重启保留

1. 发一条新消息,等助手回复完成。
2. 上滑彻底杀掉 App,重新打开。

**预期**:会话列表完整,刚才的往返消息都在;启动无「跳过无效会话」告警。

## C2 后台被杀保留

1. 发一条消息,在助手回复流式输出中途按 Home 键切后台。
2. 等约 10 秒,上滑杀进程,重开。

**预期**:最多丢失被杀瞬间正在写入的最后一条;此前的历史完整,不出现整表清空。

## C3 升级(容器迁移)保留 + 路径重基

1. 用 `flutter install`(先卸载)以外的方式覆盖安装新 build(Xcode 直接 Run 到真机,或 TestFlight 升级)。
2. 打开 App,不点进任何会话。由于移动端已全部迁移至 `SharedPreferences` 原生存储(#177)，不再依赖脆弱的文件沙盒路径，无需再从沙盒拉取文件验证。

**预期**:历史会话列表完整存在。由于存储方案变为 `UserDefaults`，会话数据已经对沙盒文件路径变化免疫；任一老会话打开加载正常。

## C4 每会话记录坏损隔离

1. (受限于 iOS UserDefaults 沙盒调试不便,可通过 Desktop 端模拟文件破坏,或用单测覆盖:`test/runtime/task_thread_store_test.dart`)
2. 构造一个包含非法 JSON 字符串的 `xworkmate.tasks.thread.<id>` 值。

**预期**:仅该会话从列表消失,其余会话完好;受损原文先备份到 `xworkmate.tasks.invalid.<id>-<ts>` 键,再从工作集移除,后续启动不重复报错。

## C5 重装即登出(#172)

1. 确认已登录(设置页显示账号邮箱)。
2. 删除 App,重新安装同一 build,打开。

**预期**:处于**未登录**状态,设置页显示登录表单;不出现自动恢复的账号会话;助手页为断开态(无残留 bridge token 发起的请求)。

## C6 从 P1 之前版本覆盖升级(不向后兼容决策)

1. 装一个 P1 收敛之前的旧版本 build 并登录、产生若干会话。
2. 覆盖升级到含 P1 收敛的 build(不卸载),打开。

**预期**:等同全新安装——旧版沙盒里的会话数据与文件型 secret 一律不读取、不迁移;`keychain_bound_uuid` 缺失会触发 Keychain 清理,需重新登录。此为 2026-07-20 的明确决策(见关联文档),不是缺陷。同版本(P1 后)之间覆盖升级,会话历史与登录态完整保留(C1/C3 语义不变)。

## C7 备份排除(#170)

设置 → Apple ID → iCloud → 管理账户储存空间 → 备份 → 本机,查看 XWorkmate 条目大小;或用 Xcode Devices 窗口检查。

**预期**:含大制品的工作区不计入备份体积(`Documents/.xworkmate` 已排除);会话历史仍随备份——iCloud 恢复到新机后,历史在、制品缺、制品可从任务详情重新拉取。

## C8(自动化)制品 mtime 过滤竞态 flaky 测试

不是真机手工用例,记录在此是因为它与本文件覆盖的同一能力树
(任务线程 / 制品持久化)共享代码路径,且已被反复标注为"存量 flake"
却从未展开根因——归档到这里避免下次又被当成新问题重新排查。

1. 单跑 `flutter test test/runtime/app_controller_thread_workspace_binding_test.dart --plain-name "records workspace files produced during an empty-artifact task run"`:空载 3/3 通过。
2. 后台起负载(如 `flutter build ios --release &`)后跑整个测试文件:必现失败,期望产物列表混入 run 开始前写入的 `old-task-report.md`。

**预期(当前实际,未修复)**:失败断言形如
`['prompts/DELIVERY.md', 'renders/identity-security-evolution.mp4']`
变成三元素列表,多出 `old-task-report.md`。根因是测试自身把"写旧文件"
与"取 `startedAtMs`"这两步时序压得太近,高负载下二者落入同一毫秒,
被生产代码"同毫秒含入"的边界语义判为当前产物——不是生产代码缺陷。
完整分析与待落地修复方案见
[2026-07-20 mtime 过滤 flaky 分析](../tasks/2026-07-20-artifact-mtime-filter-flaky-test-analysis.md)。
`"assistant history survives an iOS-style background flush"` 外在
表现相同但根因不同(`_waitForControllerInitialization` 的 5 秒硬
deadline),不要用同一个修复方案套用。

## 已知限制

- C2 的「写入进行中被杀」窗口内,最后一条消息可能回退到上一状态——原子写保证不损坏,不保证不丢最后一笔。
- C5 后 Keychain 的清理发生在**下次启动**时(绑定流程),不是卸载瞬间;卸载后不再安装则残留由 iOS 自身的 Keychain 生命周期管理。
