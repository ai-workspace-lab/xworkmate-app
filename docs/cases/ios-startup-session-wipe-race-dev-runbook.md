# Dev Runbook: iOS Startup Session-Wipe Race

> PR: [#183 fix(mobile): stop startup race from wiping persisted task sessions on iOS](https://github.com/ai-workspace-lab/xworkmate-app/pull/183)
> Commit: `d9b26a8`
> Date: 2026-07-21 (Asia/Shanghai)
> 关联分析:[2026-07-21 根因记录](../tasks/2026-07-21-ios-startup-session-wipe-race.md)、[P1 结构收敛](../tasks/2026-07-20-ios-task-persistence-p1-refactor.md)
> 关联手工用例:[iOS 会话持久化手工回归用例](ios-session-persistence-manual-cases.md) C1–C8

## Scope

- 真机(iOS)助手页首帧启动路径与 `AppController` 异步初始化的时序竞态。
- 代码:`lib/app/app_controller_desktop_core.dart`、`lib/app/app_controller_desktop_settings_runtime.dart`、`lib/app/app_controller_desktop_thread_storage.dart`、`lib/app/task_thread_repositories.dart`、`lib/features/mobile/mobile_assistant_page_core.dart`。
- 不涉及桌面端行为(桌面初始化在首帧前就绪,不触发该竞态)。

## Symptom

真机(iOS 27.0,v1.1.8+2)复现:

1. App 内正常产生若干历史任务会话,杀进程重开。
2. 侧边栏「最近」区只剩一条「新对话」。
3. 顶部「切换任务会话」抽屉同样只有「新对话」。

该现象在 #177(迁 SharedPreferences)、#181(升级探针)、#182(P1 结构收敛)之前就存在,三次修复之后依旧复现——**根因不在存储介质或路径上**,前几轮修的都是别的真问题。

## Evidence Pattern

从真机拉取 UserDefaults 确诊(方法见下方「Runtime Debugging」):

```json
flutter.xworkmate.tasks.index
  {"version":1,"threadIds":["draft:1784549818922984-1"]}
flutter.xworkmate.tasks.thread.draft:1784549818922984-1
  {"title":"新对话", "contextState":{"messages":[]}, "createdAtMs":1784549818923.0, "updatedAtMs":1784549822295.0}
```

只剩一条空的「新对话」,且 `createdAtMs` 与 `updatedAtMs` 相差约 **3.4 秒**——这个跨度就是「首帧建出草稿」到「初始化把网络相关步骤走完」之间的时间窗。这个数字本身就是诊断线索:如果再次复现,先量一下这个 delta,量级对得上就基本锁定同一条竞态。

## Why This Happened

```
AppController 构造
  └─ unawaited(initializeInternal())        ← 异步,未 await
        ① settingsController.initialize()
        ② loadAppUiState()
        ③ loadTaskThreads()                  ← 读到历史会话(内存)
        ④ RuntimeBootstrapConfig.load()      ← 含网络/文件探测,慢
        ⑤ restoreAccountSession()            ← 含网络,慢
        ⑥ restoreAssistantThreadsInternal()  ← 才把记录灌进 repository
        ⑦ ensureActiveAssistantThreadInternal()

MobileAssistantDetailPage.initState
  └─ addPostFrameCallback(prepareMobileAssistantSession)
        └─ ensureActiveAssistantThreadInternal()   ← 首帧就跑,早于 ⑥
```

首帧回调进入 `ensureActiveAssistantThreadInternal` 时 repository 仍是空的:铸出新 draft → `initializeAssistantThreadContext` 把它写进 repository → `replace(persist: true)` 触发 `saveTaskThreads([仅这一条 draft])` → 存储层按「缺席即删除」对账,把 prefs 里全部历史键清空。⑥ 真正执行时,磁盘已经被覆盖成空表。

手机上 ④⑤ 步有网络开销,首帧必然赢得竞态;桌面端这两步近乎瞬时,踩不到。

完整推导过程(含两次被否的方案)见 [根因记录](../tasks/2026-07-21-ios-startup-session-wipe-race.md)。

## Fix Strategy

**两层修复,层 1 是主修复,层 2 是纵深防御:**

### 层 1 — 恢复完成前不落盘,恢复不吞掉启动期会话

- `DesktopTaskThreadRepository`(`lib/app/task_thread_repositories.dart:15-33`)新增 `suspendPersistence()` / `resumePersistence()`。挂起期间 `_schedulePersist()`(同文件 :95-97)只记待办、不落盘。
- `AppController` **构造函数体内**(`app_controller_desktop_core.dart:179`)显式调用 `suspendPersistence()`。**不能**放进 `late final` 字段初始化器——那是惰性求值,挂起时机取决于仓库何时被首次访问,若首次访问发生在 resume 之后就会被永久挂起(这个坑在实现时踩过一次,已记入代码注释)。
- `completeAssistantThreadsRestoredInternal()`(`app_controller_desktop_core.dart:304`)里 resume 并冲一次盘;调用点:`initializeInternal` 里 ⑥ 之后(`app_controller_desktop_settings_runtime.dart:474`)、`finally` 兜底(同文件 :549)、`dispose()`(`app_controller_desktop_core.dart:190`)——初始化异常不会让持久化永久失能。
- `restoreAssistantThreadsInternal`(`app_controller_desktop_thread_storage.dart:600`)不再上来就 `clear()`,改为合并式:先留存 `preRestoreRecords` / `preRestoreMessages`(:605-609),填完磁盘记录后把磁盘上没有的启动期会话补回(:744-751,磁盘记录优先)。

### 层 2 — 存储写缓存只记录本实例观察过的会话

`TaskThreadStore`(`lib/runtime/task_thread_store.dart`,File / Prefs 两实现)的写缓存不再在冷启动 save 时预扫描介质填充,只记录本实例确实 `load()` 过或 `save()` 过的会话;删除对账天然只针对已知条目。**单独不足以修复本 bug**——真实时序里 `loadTaskThreads`(上图 ③)在首帧前已跑完,缓存本就装着历史,层 2 只挡得住「从未 load 过就 save」的场景。

### 被否方案(实测失败,别再走这条路)

在 `ensureActiveAssistantThreadInternal` 入口或移动端调用点 `await` 恢复信号——等于把「激活会话」绑死在「初始化全部完成」上。`pumpAndSettle` 不等真实 I/O,widget 测试首帧后拿不到线程上下文,`mobile_assistant_page_test` 直接变红;生产环境若初始化卡在网络步骤,首屏同样空等。**UI 不该等初始化**,这是本次唯一被两次独立验证否掉的方向。

## Fix Validation

- `flutter analyze`:干净。
- `flutter test`:全量 **438/438** 通过(修复前 437/438,唯一失败是既有 mtime flaky,已随本次一并修掉,见下)。
- 新增回归:`test/runtime/app_controller_startup_thread_restore_race_test.dart`
  - `first-frame ensureActiveAssistantThread does not wipe persisted history`
  - `ensureActiveAssistantThread after restore reuses the persisted session`
- 顺带修复:`app_controller_thread_workspace_binding_test.dart` 的 mtime 过滤 flaky(旧文件 mtime 显式回拨 10 秒),并发 `flutter build ios` 负载下连续 3 次全绿。分析见 [mtime flaky 分析记录](../tasks/2026-07-20-artifact-mtime-filter-flaky-test-analysis.md)。

## Runtime Debugging

**从真机拉取 UserDefaults 逐条核对持久化状态**(需要真机已通过 Xcode 信任、`devicectl` 可用):

```bash
xcrun devicectl list devices
# 记下目标设备的 Identifier

xcrun devicectl device copy from \
  --device <DEVICE_IDENTIFIER> \
  --domain-type appDataContainer \
  --domain-identifier plus.svc.xworkmate \
  --source Library/Preferences/plus.svc.xworkmate.plist \
  --destination ./device-prefs.plist

plutil -convert xml1 -o - ./device-prefs.plist | grep -A2 'xworkmate.tasks'
```

关键键:

- `flutter.xworkmate.tasks.index` — 有序会话索引
- `flutter.xworkmate.tasks.thread.<threadId>` — 每会话 JSON,看 `title` / `contextState.messages` / `createdAtMs` / `updatedAtMs`
- `flutter.xworkmate.storage.schemaVersion` — 存储 schema 版本锚点

若只剩一条空「新对话」且 `updatedAtMs - createdAtMs` 在 2–5 秒量级,基本就是本 bug 复现,不必重新排查。

## Local Repro / Regression Guard

```bash
flutter test test/runtime/app_controller_startup_thread_restore_race_test.dart
```

两条用例都在**不 await 初始化完成**的前提下模拟首帧调用时序,任何回归(比如层 1 的挂起逻辑被误改、恢复重新变成覆盖式)都会在这里先炸,不用等真机复现。

## Manual Acceptance

装机后按 [ios-session-persistence-manual-cases.md](ios-session-persistence-manual-cases.md) 的 **C1(冷重启保留)** 与 **C2(后台被杀保留)** 执行;两条用例覆盖的正是本 bug 的现象面。额外补一条本 bug 专属检查:

**C1a 首帧竞态专项**

1. 建 2–3 个会话,各发一条消息,**不要等太久**,趁初始化可能还没完全跑完就立刻上滑杀进程(越快复现条件越接近真实竞态窗口)。
2. 重新打开,检查「最近」列表与「切换任务会话」抽屉。

预期:全部会话都在。若丢失,先用上面的 Runtime Debugging 步骤拉设备状态,看 `updatedAtMs - createdAtMs` delta,再决定是不是同一根因复发。

## Rollback

- 无 schema 变更,纯行为修复。`git revert d9b26a8` 即可回到修复前状态(会重新引入本文档描述的丢失,但不会产生新的数据损坏)。
- 回滚后如需临时缓解,可指导用户避免「刚发完消息立刻杀进程」,降低复现概率(不是修复,只是权宜)。

## Known Limitation

- 本次只保证「今后不再丢」。**已经被清空的历史数据不可恢复**——用户设备上 #182 及之前版本已经发生的丢失是终局的。
- `ensureActiveAssistantThreadInternal` 之前的语义没变(仍不 await 任何东西),真正的安全网在 repository 挂起——理解这一点,以后排查同类问题时别再往「加 await」的方向走。
