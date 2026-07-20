# 制品 mtime 过滤 flaky 测试:根因分析(未落地修复)

> 日期:2026-07-20(Asia/Shanghai)
> 范围:`test/runtime/app_controller_thread_workspace_binding_test.dart`、`lib/app/app_controller_desktop_runtime_helpers.dart`
> 状态:**分析已完成、结论已定;代码修复未落地**(见 §4 说明)。
> 首次记录:[2026-07-16 handoff](2026-07-16-openclaw-ios-artifact-return-handoff.md#L122)、[2026-07-20 加固记录 §2.2](2026-07-20-ios-session-persistence-hardening.md)均只标注"存量 flake、与本修复无关",未展开根因。本文补齐。

## 0. 复现现象

- 触发测试:`app_controller_thread_workspace_binding_test.dart` › `"records workspace files produced during an empty-artifact task run"`(约 2387 行起);同类抖动也见于 `"assistant history survives an iOS-style background flush"`。
- 复现方式:空载下单跑该测试 3/3 通过;机器忙时(如并行跑 `flutter build ios`)整文件跑必现失败。
- 失败表现:期望产物列表 `['prompts/DELIVERY.md', 'renders/identity-security-evolution.mp4']`,实际混入了 `startedAtMs` 之前写入的 `old-task-report.md`。

## 1. 根因:测试自己制造了一个"同毫秒"竞态,而实现按设计含入该边界

生产代码 `_workspaceArtifactPathsModifiedSinceInternal`(`lib/app/app_controller_desktop_runtime_helpers.dart:1688-1730`)按 mtime 过滤"任务期间产生的文件":

```dart
final thresholdMs = sinceMs ?? 0;
...
final stat = await file.stat();
// Files written in the run's first millisecond are current artifacts,
// not stale workspace content.
if (stat.modified.millisecondsSinceEpoch.toDouble() < thresholdMs) {
  continue;
}
```

**没有额外容差值**——过滤窗口就是 `[lastRunAtMs, ∞)`,且边界是**刻意含入**的(注释明确:run 起始那一毫秒内写入的文件算当前产物,不算旧内容)。这是唯一一处 mtime 过滤实现,全库无其他地方复现该模式。

测试(`test/runtime/app_controller_thread_workspace_binding_test.dart:2402-2406`)的时序:

```dart
await File('${localWorkspace.path}/old-task-report.md')
    .writeAsString('stale task output');
final startedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
await Future<void>.delayed(const Duration(milliseconds: 20));
```

写旧文件与取 `startedAtMs` 之间只隔一次 `writeAsString` 的返回耗时。空载下这个间隔通常跨过一次系统时钟毫秒边界,`old-task-report.md` 的 mtime 落在 `startedAtMs` 之前,测试稳定通过。**机器高负载时,调度延迟压缩了这个间隔**,写入完成和 `DateTime.now()` 取值有一定概率落在同一毫秒——此时 `stat.modified == thresholdMs`,按"含入"语义被算作当前产物,断言失败。

用一段探针脚本验证了这个机制本身成立(mtime 可被精确 pin 到任意毫秒且回读一致;高频写入下同毫秒命中确实随负载概率上升),但探针脚本随本次调查所在的临时 worktree 一并被清理,未保留在仓库中——它只是验证工具,不是交付物。

`"assistant history survives an iOS-style background flush"` 不经过这条 mtime 过滤路径;它的负载敏感点是另一处——`_waitForControllerInitialization` 的 5 秒硬 deadline(`test/runtime/app_controller_thread_workspace_binding_test.dart:2917`),机器忙时控制器初始化可能跨过该 deadline。两者外在表现相似(全量跑抖动、空载单跑稳定),根因不同,不能用同一个修复方案。

## 2. 结论:修测试,不修实现

- **不应收窄实现的边界语义**:`stat.modified == lastRunAtMs` 含入是有意设计,收紧为"同毫秒排除"会在生产环境丢失 run 第一毫秒内写出的真实产物——这是更差的权衡,真实场景里"旧文件恰好写在 run 开始的同一毫秒"概率远低于测试环境的人为压缩时序。
- **应修测试**:把 `old-task-report.md` 的 mtime 显式钉到严格早于 `startedAtMs`(例如 `File.setLastModified` 回拨若干秒),消除测试自身制造的时序竞态,而不是依赖"写入 + 取时间戳"这两步操作之间的调度间隙。
- 扫过全仓,`test/runtime/app_controller_thread_workspace_binding_test.dart` 中另外两处相同模式(约 2110、2203 行,skill-artifact-policy 相关测试)结构相同但写的都是 `artifact-ignore.md`——该文件按 basename 被 policy 自忽略(`ignores()` 见同文件 2024 行),不参与 mtime 过滤,因此不受影响,无需同样处理。

## 3. 建议修复(TDD,未执行)

```dart
await File('${localWorkspace.path}/old-task-report.md')
    .writeAsString('stale task output');
final startedAtMs = DateTime.now().millisecondsSinceEpoch.toDouble();
await File('${localWorkspace.path}/old-task-report.md').setLastModified(
  DateTime.fromMillisecondsSinceEpoch(startedAtMs.toInt() - 10000),
);
await Future<void>.delayed(const Duration(milliseconds: 20));
```

验证方式:`flutter analyze` + 在并发负载下(如后台跑 `flutter build ios`)多次全量跑该测试文件,确认不再抖动。`"assistant history survives an iOS-style background flush"` 需单独处理 `_waitForControllerInitialization` 的 deadline 收紧或轮询策略,不在本文范围。

## 4. 为何未落地

本次调查在临时 worktree(`jolly-shannon-495832`)中完成到 RED 复现阶段(把旧文件 mtime 显式钉到 `startedAtMs` 后,确认测试仍能稳定通过——即该改法不破坏既有断言,具备落地条件)。该 worktree 随后被清理,改动未合并回主仓,后续工作转向 [P1 存储层结构收敛](2026-07-20-ios-task-persistence-p1-refactor.md)。截至本文记录时,`test/runtime/app_controller_thread_workspace_binding_test.dart` 仍是原始状态,§3 的修复**尚未应用**——留作独立跟进任务,按 §3 方案直接实施即可,无需重新分析。
