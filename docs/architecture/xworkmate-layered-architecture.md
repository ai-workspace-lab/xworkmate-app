# XWorkmate 整体分层架构

Last Updated: 2026-04-08

## 目的

本文件只保留整体分层总览与目录作用，不再把当前兼容旁路写成长期规范。

统一口径如下：

- `TaskThread` 是线程控制面
- `GoTaskService.executeTask` 是唯一公开执行入口
- ACP 是统一控制面
- `bridge` 是 app 客户端侧的发现 / 配置 / 连接 / 对话枢纽
- 账户同步只同步 bridge 相关配置属性与安全引用，不负责自动连接
- 历史旁路与旧的直连叙述不再作为目标架构

## 总览图

```mermaid
flowchart TB
    subgraph L1["访问与归属层"]
        A1["Local user / device"]
        A2["Web user / browser session"]
        A3["Remote owner realm"]
    end

    subgraph L2["多端 UI 层"]
        B1["Desktop / Mobile / Web UI"]
        B2["AssistantPage / Settings / Tasks"]
    end

    subgraph L3["线程控制面"]
        C1["TaskThread"]
        C2["ownerScope"]
        C3["workspaceBinding"]
        C4["executionBinding"]
        C5["contextState"]
        C6["lifecycleState"]
    end

    subgraph L4["统一任务入口"]
        D1["AppController*"]
        D2["GoTaskService.executeTask"]
    end

    subgraph L5["ACP Control Plane"]
        E1["session.start / session.message"]
        E2["Router.Resolve"]
        E3["Skills.Resolve"]
        E4["Memory.Inject / Record"]
        E5["buildResolvedExecutionParams"]
    end

    subgraph L6["Bridge / Executors / Adapters"]
        F1["single-agent ACP request"]
        F2["multi-agent ACP request"]
        F3["bridge hub<br/>discovery / config / connect / dialogue"]
        F4["gateway / provider adapters"]
    end

    A1 --> B1
    A2 --> B1
    A3 --> B1
    B1 --> B2
    B2 --> C1
    C1 --> C2
    C1 --> C3
    C1 --> C4
    C1 --> C5
    C1 --> C6
    C1 --> D1
    D1 --> D2
    D2 --> E1
    E1 --> E2
    E2 --> E3
    E3 --> E4
    E4 --> E5
    E5 --> F1
    E5 --> F2
    F1 --> F3
    F2 --> F3
    F3 --> F4
```

## 核心规则

1. UI 不直接决定执行 lane。
2. `TaskThread` 承载线程级事实，不由页面局部状态拼装。
3. `GoTaskService.executeTask` 是唯一公开任务入口。
4. ACP 是统一控制面，负责 routing / skills / memory / resolved execution。
5. `bridge` 是 app 侧统一枢纽；gateway/provider 适配能力挂在 bridge 后面，不再把历史直连路径写成长期主链。

## 文档目录

### 目标规范

- [任务执行链路统一收敛](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/task-control-plane-unification.md)
- [ACP Forwarding Topology](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-bridge/docs/architecture/acp-forwarding-topology.md)

### 当前实现观察

- 当前实现观察不再保留独立主设计文档
- 如需判断规范，以 [任务执行链路统一收敛](/Users/shenlan/workspaces/cloud-neutral-toolkit/xworkmate-app/docs/architecture/task-control-plane-unification.md) 为准

### 边界与适配器说明

- 适配器边界统一收敛到本文件与主文档，不再保留旧的并列设计稿

## Removed From Target

- 旧的 `openClawTask` 公开语义不再是目标架构的一部分
- 不再把“客户端直接围绕旧 gateway 默认值运转”写成长期主设计
