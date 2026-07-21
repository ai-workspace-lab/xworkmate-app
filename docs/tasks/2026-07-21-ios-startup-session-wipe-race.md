# iOS 启动竞态导致历史任务会话被清空(P0)

> 日期:2026-07-21(Asia/Shanghai)
> 范围:`lib/features/mobile` 首帧引导、`lib/app` 启动恢复、`lib/runtime` 存储层写对账
> 分支:`bugfix/ios-startup-session-wipe-race`
> 关联:[2026-07-20 持久化加固记录](2026-07-20-ios-session-persistence-hardening.md)、[2026-07-20 P1 结构收敛](2026-07-20-ios-task-persistence-p1-refactor.md)

## 0. 现象

真机(iOS 27.0,v1.1.8+2,含 P1 收敛的 main)复现:

1. App 内正常产生若干历史任务会话,杀进程重开。
2. 侧边栏「最近」区只剩一条「新对话」。
3. 顶部「切换任务会话」抽屉同样只有「新对话」。

**关键**:此现象在 P1 收敛(#182)之前就存在,收敛之后依旧存在。前几轮
排查(#168 路径重基、#177 迁 SharedPreferences、#181 升级探针)每次都
"改对了一个真问题"但现象不消失,原因是根因根本不在存储介质与路径上。

## 1. 根因:首帧引导抢跑异步初始化,把「部分快照」当成全量写回

链路(时间序):

```
AppController 构造
  └─ unawaited(initializeInternal())        ← 异步,未 await
        ① settingsController.initialize()
        ② loadAppUiState()
        ③ loadTaskThreads()                  ← 读到历史会话
        ④ RuntimeBootstrapConfig.load()      ← 含网络/文件探测,慢
        ⑤ restoreAccountSession()            ← 含网络,慢
        ⑥ restoreAssistantThreadsInternal()  ← 才把记录灌进 repository
        ⑦ ensureActiveAssistantThreadInternal()

MobileAssistantDetailPage.initState
  └─ addPostFrameCallback(prepareMobileAssistantSession)
        └─ ensureActiveAssistantThreadInternal()   ← 首帧就跑,通常早于 ⑥
```

首帧回调进入 `ensureActiveAssistantThreadInternal`
(`lib/app/app_controller_desktop_thread_storage.dart:87`)时,`repository`
仍是空的(⑥ 未执行),于是:

1. `assistantSessionSummariesInternal()` 返回空 → `firstWhere` 落到
   `orElse` 分支,`createAssistantDraftSessionKeyInternal()` 铸出一个新
   draft key;
2. `hasAssistantTaskStateInternal(fallback.key)` 为 false →
   `initializeAssistantThreadContext(...)` 把这条新 draft 写进 repository;
3. repository 的 `replace(persist: true)` 触发
   `saveTaskThreads([仅这一条 draft])`;
4. `PrefsTaskThreadStore.save` 在 `_cachePrimed == false` 的冷缓存分支里,
   先把 prefs 中**现存的全部** `xworkmate.tasks.thread.*` 键读进
   `_lastWrittenThreadJsonByThreadId`(值记 null),随后按
   "在缓存里但不在本次期望集合中 ⇒ 已删除"的对账逻辑,把所有历史键
   `prefs.remove(...)` 掉,并把 index 重写为只含新 draft。

**历史会话在这一步被一次性清空**。等 ⑥ 真正执行时,`sanitizedAssistantThreads`
早已是空列表(③ 读到的内容还在内存里,但 ⑦ 之后的持久化已经把磁盘覆盖),
UI 自然只剩「新对话」。

设备侧证据(`plutil` 导出真机 UserDefaults):

```
flutter.xworkmate.tasks.index
  {"version":1,"threadIds":["draft:1784549818922984-1"]}
flutter.xworkmate.tasks.thread.draft:1784549818922984-1
  {... "title":"新对话" ... "messages":[] ...}
```

只剩一条空的「新对话」,且其 `createdAtMs`/`updatedAtMs` 相差约 3.4 秒
——正是「首帧铸 draft → 初始化后续步骤」的时间跨度,与推断吻合。

### 为什么桌面端不复现

桌面端 `initializeInternal` 的 ④⑤ 步几乎瞬时完成(本地配置、无移动网络
栈冷启动开销),⑥ 通常早于首帧回调;且桌面首帧路径不走
`prepareMobileAssistantSession`。竞态窗口在桌面上基本不存在。

### 为什么 P1 收敛没有修复它

P1 把 `FileTaskThreadStore` / `PrefsTaskThreadStore` 从
`SettingsStore` 中抽出,**逐条保持了原有语义**,其中就包括这段
"冷缓存 prime → 按缺席即删除对账"的写逻辑。P1 既没有引入该缺陷,
也没有触碰它——所以现象原样保留。

## 2. 修复(两层,TDD)

单点修复不够:只挡住首帧这一个调用点,任何其他"初始化完成前触发保存"
的路径(设置页、深链、通知唤起)都会再次清库。因此分两层。

### 层 1 — 恢复完成前不落盘,且恢复不吞掉启动期会话

**先否掉的两个做法**(都实测失败,记下来免得重走):

1. *`ensureActiveAssistantThreadInternal` 入口 `await` 恢复信号*。
   等于把「激活会话」绑死在「初始化全部完成」上。widget 测试里
   `pumpAndSettle` 不等真实 I/O,首帧后拿不到线程上下文,顶栏直接不
   渲染(`mobile_assistant_page_test` 变红);生产环境若初始化卡在网络
   步骤,首屏同样空等。**UI 不该等初始化。**
2. *把 await 挪到移动端首帧调用点*。同样的空等问题,只是换了位置。

**实际落地**:草稿照常在首帧建出来(UI 不阻塞),但把「部分视图写盘」
这件事本身堵死。

- `DesktopTaskThreadRepository` 新增 `suspendPersistence()` /
  `resumePersistence()`:挂起期间 `_schedulePersist()` 只记待办、不落盘;
- `AppController` **构造函数体内**显式挂起。不能依赖
  `late final` 字段初始化器里的 `..suspendPersistence()`——那是惰性的,
  挂起时机取决于仓库何时被首次访问,若首次访问发生在 resume 之后就会
  被永久挂起;
- `completeAssistantThreadsRestoredInternal()` 里 resume 并冲一次盘;
  它在 ⑥ 之后调用,`finally` 与 `dispose()` 兜底,初始化异常也不会让
  持久化永久失能。

**配套:恢复改为合并而非覆盖。** `restoreAssistantThreadsInternal` 原本
上来就 `clear()`,会把启动期间已经产生的会话连同用户输入一起丢掉——
移动端首帧必然创建一个会话,用户也可能在初始化跑完前就开始输入。现在
先留存 `preRestoreRecords` / `preRestoreMessages`,填完磁盘记录后把磁盘
上没有的启动期会话补回去(**磁盘记录优先**)。

这一条是被测试逼出来的:`assistant_execution_target_test` 里多个用例
就是「构造 controller → 立刻 ensure → 设置执行目标」,不等初始化。
挂起持久化后它们的早期写入不再落盘,随后被 `clear()` 抹掉,执行目标
退回 `agent`。合并式恢复同时修好了它们和真机竞态——说明这不是为了迁就
测试,而是恢复语义本来就该如此。

### 层 2 — 存储安全网:删除对账只针对本实例观察过的会话

即便未来又出现"初始化完成前拿到部分快照就保存",也不该演变成数据丢失。

问题出在 `save` 的冷缓存分支:它会先扫描介质,把**当前存在的所有会话**
填进 `_lastWrittenThreadJsonByThreadId`(值记 null),再按"在缓存里但不在
本次期望集合中 ⇒ 已删除"对账。于是一次部分快照保存就能删光全库。

修正后的不变量:**该缓存只记录本实例确实 `load()` 过或 `save()` 过的会话**。

- 删除那段"扫描介质填 null"的冷缓存 prime;
- 对账逻辑本身保持无条件执行——因为缓存里现在只会有已知条目,
  未被本实例观察过的会话天然不在对账范围内;
- 同实例内的正常删除(`save([a,b])` 后 `save([a])`)行为不变,
  因为 `b` 是本实例写过的、属于已知条目。

曾经考虑过"未 `load()` 过就禁止一切删除"的门槛式做法,但它会连带
挡掉同实例内合法的删除(三条既有用例因此变红),而且没有触及真正的
病灶。上面这个不变量更小、更准:病灶就是"把没读过的东西当成读过的"。

语义代价:冷启动 save 后 index 可能暂时不含尚未加载的历史会话——但两个
store 的 load 都有"孤儿记录按 threadId 排序追加"的兜底,历史依旧可见,
下一次正常 load→save 循环会自然收敛。

**注意层 2 单独不足以修复本 bug。** 真实时序里 `loadTaskThreads`(③)
在首帧之前就跑完了,store 的缓存**已经**被历史会话填充,所以那次部分
快照保存照样会触发删除——层 2 只挡得住"从未 load 过就 save"。它是纵深
防御的第二道,不是主修复。主修复是层 1。

## 3. 测试

RED 先行,三条:

| 用例 | 文件 | 覆盖 |
|---|---|---|
| `first-frame ensureActiveAssistantThread does not wipe persisted history` | `test/runtime/app_controller_startup_thread_restore_race_test.dart` | 层 1:初始化未完成时调用 ensure,历史会话必须仍在 |
| `ensureActiveAssistantThread after restore reuses the persisted session` | 同上 | 层 1:恢复后应复用历史会话而非另铸 draft |
| `a save before any load never deletes unknown keys` / `... unknown files` | `test/runtime/task_thread_store_test.dart` | 层 2:未观察过的会话不被删除(Prefs / File 各一条) |

原 `a fresh store instance prunes stale files/keys on save` 调整为
`... after loading`(显式先 `load()` 再 `save()`),因为"未 load 即删除"
正是被移除的危险行为——该用例原本固化的就是缺陷语义。

## 4. 验证

- `flutter analyze`:全仓干净。
- `flutter test`:全量通过。
- 真机:构建安装后杀进程重开,「最近」与「切换任务会话」应保留历史会话。

## 5. 遗留

1. 本次只修「不再丢」。**已被清空的历史数据不可恢复**——用户设备上
   P1 及之前版本已经发生的丢失是终局的。
2. `ensureActiveAssistantThreadInternal` 现在会 await 恢复信号,理论上
   会让首帧到可交互的时间略微后移(等于初始化 ④⑤ 的耗时)。若真机观感
   有回退,后续可考虑把 ④⑤ 移出关键路径(恢复线程只依赖 ①②③)。
