# iOS 任务持久化 P1 结构收敛(TaskThreadStore)

> 日期:2026-07-20(Asia/Shanghai)
> 范围:`lib/runtime` 存储层;Desktop 任务工作流与持久化行为零变化
> 承接:[2026-07-20 持久化加固记录](2026-07-20-ios-session-persistence-hardening.md)之后的结构性收敛(P1),并落实「不向后兼容」决策
> 分支:`feature/ios-task-persistence-p1-convergence`

## 0. 决策记录

### D1 不向后兼容(2026-07-20 拍板)

移动端不再读取、迁移任何旧存储布局:沙盒 `tasks/` 分会话文件、单体
`threads.json`、`settings.yaml`/`audit.json` 沙盒回退、`secrets/*.secret`
升级探针全部删除。从 P1 之前版本覆盖升级 = 等同全新安装(会话清零、
需重新登录)。理由:

- 兼容层是三处已确认缺陷的直接来源:
  1. **双写失效**:移动 save 落到磁盘的分支被共享 dedup 缓存整体短路,
     磁盘侧永远 no-op,只留下假的灾备预期;
  2. **删除复活**:「prefs 为空 → 磁盘回捞」无法区分合法空状态,
     删光会话或诊断清理后重启,旧数据整批复活;
  3. **迁移反杀**:legacy `threads.json` 迁移的破坏性对账 + rename
     放最后,崩溃重入会删掉用户新产生的会话文件。
- 用户基数处于可接受一次性清零的阶段,兼容矩阵(4 代布局 × 崩溃
  重入)维护成本远超收益。

### D2 P1 只收敛结构,不引入数据库

sqflite/drift(WAL)评估后**暂不引入**:P1 的目标是把「换后端」的
成本压到一个 provider 的实现量;在消息体尚未拆出前引入 DB 收益有限。
P2(容量演进)已在接口层预留,触发条件见架构文档。

### D3 扩展 provider 插件位(为 iCloud / 云同步预留)

`TaskThreadStoreProvider` + `TaskThreadStoreRegistry`:新的后端
(iCloud key-value store、CloudKit、其他云存储)实现 provider 并注册
即可参与平台解析,`SettingsStore` 与上层零改动。

## 1. 交付内容

| 项 | 内容 |
|---|---|
| 新增 | `lib/runtime/task_thread_store.dart`:`TaskThreadStore` 接口、`FileTaskThreadStore`(桌面,行为与原实现逐条等价)、`PrefsTaskThreadStore`(移动)、provider registry |
| 重构 | `SettingsStore` 任务线程读写全部委托接口,平台分支收敛到 registry;删除全部 legacy 回退与迁移 |
| 加固 | 移动端坏记录先备份 `xworkmate.tasks.invalid.<id>-<ts>` 再移除(与桌面 `.invalid-*.bak` 对齐);新增 `xworkmate.storage.schemaVersion` 迁移锚点(当前=1,只打标) |
| 清理 | `SecretStore` 升级探针(#181)、`legacyLocalStateKey` / `loadLegacyLocalStateKeyBytes` 死代码;`SecureConfigStore.persistentWriteFailures` 的 settings 误映射到 audit 的笔误 |
| 测试 | 新增 `test/runtime/task_thread_store_test.dart`(Prefs/File/registry);重写 `settings_store_test.dart`(移除 legacy 用例,per-record 容错移植到分会话文件,新增注入式委托/失败包装用例) |
| 文档 | 重写 `secure-local-persistence-architecture.md`(移除 SQLite/durable mirror/sealed-state 失实描述);更新 chain-map S1-storage、手工用例 C4/C6 |

## 2. App Store 合规核对(本次变更视角)

- 数据存储位置:会话历史在 UserDefaults(随设备备份,符合「用户产生
  且不可再生数据应备份」);制品工作区 `Documents/.xworkmate` 维持
  `isExcludedFromBackup`(#170,App Review 2.23)——本次未触碰。
- 密钥:仍全部走 Keychain `first_unlock_this_device`,无明文密钥文件;
  「重装即登出」语义因探针删除而更严格、无例外分支。
- 隐私清单 `NSPrivacyCollectedDataTypes` 与 nutrition labels 对齐仍是
  上架前人工核对项(遗留,见加固记录 §2.4),与本次变更无关。

## 3. 验证

- `flutter analyze`:全仓干净。
- `flutter test test/runtime/task_thread_store_test.dart test/runtime/settings_store_test.dart`:27/27。
- `flutter test` 全量:见 PR 描述(注:main 基线原本即有 7 个
  legacy 迁移用例失败——#177 删实现未删测试;本次一并消除)。

## 4. 遗留

1. 真机手工回归(C1–C7,含 C6 新语义)待设备在线后执行。
2. 设置快照 / 审计 trail 尚未纳入 provider 模式(仍是 `SettingsStore`
   内的平台分支),后续如有第三种介质需求再收敛。
3. P2 容量演进的埋点(plist 尺寸)未实施;触发条件见架构文档。
