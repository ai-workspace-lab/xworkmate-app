#   

> **Date**: 2026-07-15 (UTC+8)
> **Scope**: 现场调试 `iOS APP -> xworkmate-bridge -> OpenClaw`
> **Related Session**: `agent:main:draft:1784107717459614-1`
> **Related Repos**:
> - `openclaw-multi-session-plugins`
> - `xworkmate-app`
> - `xworkmate-bridge`
> - `xworkspace-console`
> - `xworkspace-core-skills`

---

## 问题描述

当前现象是：

- 远端 OpenClaw 任务已经执行完毕
- 但 iOS 真机上的 APP 仍然停留在 `running / 执行中`
- 这说明任务终态没有从 OpenClaw / bridge / app 链路正确回传到前端状态机

用户给出的现场入口：

`https://openclaw.svc.plus/chat?session=agent%3Amain%3Adraft%3A1784107717459614-1`

---

## 目前已确认的事实

1. `openclaw-multi-session-plugins` 中，任务状态识别已经修复。
2. `completed` 已被纳入终态，插件侧不再把已完成任务当成非终态。
3. `xworkmate-app` 的真机更新已完成，最新版本已经安装到 iPhone。
4. 真机侧当前仍然显示任务执行中，说明问题不在“有没有把新包装到手机上”，而在“终态是否被正确消费”。

---

## 已完成的修复

### OpenClaw 侧

- 已修复任务终态识别
- `completed` 现在会被当成终态处理
- 相关修复已经合并并验证通过

### iOS App 侧

- 已完成最新版本构建与真机安装
- 已把任务工作区入口补到移动端 UI
- 已处理 iOS 上的一批已知 UI / 文件监听 / artifact 展示问题

---

## 当前怀疑点

已解决！在深入追踪 `OpenClaw -> bridge -> APP` 链路后发现，终态确实验证无误地送到了前端，问题出在 `xworkmate-app` 的应用层状态维护。

---

## 根本原因 (Root Cause)

1. `pollOpenClawTaskAssociationInternal` 在轮询 `goTaskServiceClientInternal.getTask` 收到终态 (`status == 'completed'`) 后，会跳出轮询并进入 `applyGatewayChatResultInternal` 收尾流程。
2. 在 `applyGatewayChatResultInternal` 中，会调用 `upsertTaskThreadInternal` 将状态标为 `ready`，并判断是否需要清除 `openClawTaskAssociation` 任务描述符。
3. 为了能够正常拉取远端 Artifacts，该处有逻辑 `clearOpenClawTaskAssociation: !hasCurrentRunArtifacts`，即如果存在产物，则保留 `openClawTaskAssociation` 不予清理。
4. **致命遗漏**：尽管 `clearOpenClawTaskAssociation` 置为 `false` 以保留 Association，但代码却忘记了将**最新的含有终态状态的 Association** 传给 `upsertTaskThreadInternal`。这导致存在内存中的 Association 永远保持着轮询前最后的 `running` 状态。
5. APP 界面判断是否显示 "Executing..." 卡片依赖 `hasAssistantPendingRun` 属性，而该属性会检查 `!association.isTerminal`。因为内存中的 Association 停滞在 `running` (非 Terminal)，UI 被永远卡在了“执行中”界面！

---

## 修复方案

在 `applyGatewayChatResultInternal` 中的 `upsertTaskThreadInternal` 调用里，补充传递包含了最新状态的 `openClawTaskAssociation` 参数：

```dart
      openClawTaskAssociation: hasCurrentRunArtifacts && openClawAssociation != null
          ? openClawAssociation
          : null,
```
这样不仅保留了包含 Artifacts 等重要信息的任务体，同时也使得 `association.status` 成功更迭为 `completed`。`hasAssistantPendingRun` 在检查 `!association.isTerminal` 时会得出 `false`，从而自动隐去卡片，任务完美收尾。


---

## 现场信息

- 远端会话页面已打开
- 真机 APP 仍在 `running`
- 需要继续沿着 `OpenClaw -> bridge -> APP` 逐层对照日志和状态迁移

---

## 下一步

- 已修复代码 `lib/app/app_controller_desktop_thread_actions.dart`。
- 随后按照项目规范提交 PR，将这两个分支的代码进行合并，关闭任务。

