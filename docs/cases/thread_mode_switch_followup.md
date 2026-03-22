# 模式切换与线程连续追问

## 目标

验证三种模式切换后，线程归属正确、模型随模式变化，并且现有线程还能继续追问。

相关设计说明：

- [Assistant 任务线程信息架构](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate.svc.plus/docs/architecture/assistant-thread-information-architecture.md)

## 需要覆盖的三种模式

- `仅 AI Gateway`
- `本地 OpenClaw Gateway`
- `远程 OpenClaw Gateway`

## 建议步骤

### 场景 A：仅 AI Gateway

发送：

```text
用一句话介绍你当前的执行上下文。
```

确认：

- 顶部状态显示 `仅 AI Gateway`
- 不显示 `已连接 openclaw ...`
- 模型标签来自 AI Gateway 当前模型

然后继续追问：

```text
继续基于刚才的上下文，再展开说 3 点。
```

确认线程连续。

### 场景 B：切到本地 OpenClaw Gateway

切模式后在新任务里发送：

```text
检查当前本地 Gateway 可用性，并说明你现在通过哪条链路工作。
```

确认：

- 顶部状态变成 `本地 OpenClaw Gateway`
- 模型标签跟随当前模式变化

### 场景 C：切到远程 OpenClaw Gateway

在可连接远程网关时发送：

```text
说明当前远程链路状态，并等待我继续追问。
```

然后继续追问一轮，确认线程不丢上下文。

## 通过标准

- 切换模式后，模型显示会跟着变
- `仅 AI Gateway` 不会错误显示 OpenClaw 已连接
- 三种模式下线程都能继续追问
- 任务列表分组归属与实际提交模式一致
- 右上角状态只反映当前线程，不沿用别的线程连接结果
