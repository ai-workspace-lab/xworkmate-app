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

## 0.1 起因分析:立项前的现状评估

本节是 D1 的证据附录,记录立项时(P1 重构前)对现状的完整评估。**评估对象是当时 `lib/runtime/settings_store.dart` 上一次未提交的改动**(#181 之后、P1 之前;引入"任务会话搬家"回捞逻辑但从未合并),该版本已被本次 P1 重构整体替换,下述文件:行号引用的是评估当时的文件版本,不适用于现状——现状见 [secure-local-persistence-architecture.md](../architecture/secure-local-persistence-architecture.md)。

### 现状对比(#177 之后、P1 之前)

| 维度 | macOS Desktop | iOS(#177 后、P1 前) |
|---|---|---|
| 真值源 | `~/Library/Application Support/xworkmate/tasks/` 分会话文件 + index.json | SharedPreferences(UserDefaults 单 plist) |
| 写粒度 | 逐会话原子写,O(dirty) | 逐键 setString,但 OS 层是整 plist 重序列化 |
| 坏数据容错 | 先 `.invalid-<ts>.bak` 字节备份,再隔离删除 | 直接 `prefs.remove(k)`,无备份 |
| 抗后台被杀 | 进程内写,依赖原子写兜底 | cfprefsd 进程外落盘,天然更强 |
| 路径漂移 | 无此问题 | 免疫(弃用沙盒文件的根因,P0-1) |
| 卸载语义 | 数据保留 | 沙盒+prefs 清空、Keychain 残留 → "重装即登出" |

### Keychain 智能探针评估(#181,已合并;P1 中已删除)

`secret_store.dart` 原实现:`keychain_bound_uuid` 缺失时,探测旧 `secrets/`
目录非空 → 判定为升级、免除 `deleteAll()`。

方向正确但是**启发式而非版本化迁移**,有明确 cohort 缺口:#172~#177
之间的中间版本(secret 已入 Keychain、哨兵是沙盒 `.keychain-bound`
文件)升级到当时版本时,prefs 无 UUID 且 `secrets/` 目录为空 →
仍会误触发 `deleteAll()` 登出。P1 按 D1 决策整体删除该探针,恢复无
例外的"重装即登出",消灭这个缺口而非修补它。

### "任务会话搬家"回捞逻辑的三个实质缺陷(未提交 diff,已废弃)

1. **双写实际上没有写磁盘**:diff 意图让 iOS 同时写 prefs 和沙盒文件,
   但 `_saveTaskThreadsMobile` 结尾把共享的 dedup 缓存
   `_lastWrittenThreadJsonByThreadId` 更新为本轮期望值(原
   `settings_store.dart:657-660`),紧接着磁盘路径的 diff 用同一缓存
   判断(原 `398-401`)——全部命中"未变化"而跳过,index 的
   `listEquals` 同理。磁盘侧永远是 no-op,双写只是幻觉。
2. **已删数据会"复活"**:外层回退(原 `136-150`)以
   `mobileThreads.isEmpty` 触发磁盘回捞,但"prefs 为空"与"用户合法
   地删光了所有会话"不可区分。迁移从不退役磁盘源,`clearAssistantLocalState`
   移动端也只清 prefs(原 `440-451`)不碰沙盒。组合结果:用户删除
   全部会话或执行"诊断→清理本地配置"后,下次启动旧沙盒数据整批
   复活并回写 prefs。
3. **legacy 迁移的破坏性对账 + 崩溃窗口**:
   `_migrateLegacyThreadsFileIfNeeded` 会删除不在 legacy 清单里的
   分会话文件(原 `213-219`),而 legacy 文件退役 rename 放在最后一步
   (原 `234`)。若迁移完成后、rename 前进程被杀:用户新建会话写入
   分会话文件;下次启动 legacy 文件仍在 → 重新迁移 →
   用户的新会话文件被当作"多余文件"删掉,真实数据丢失。

三个缺陷共同指向同一个结构性问题:**"合并两个存储介质"这件事本身
不该由分散在各方法里的启发式判断承担**——这正是 D1(不向后兼容,
消灭合并面)与 D3(provider 抽象,新介质只能新增不能合并)的直接
动因。

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
