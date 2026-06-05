# Refactor Notes — 重构建议与架构审核

> 生成日期: 2026-06-05 | 基于 chain-map 和 module-boundary 的架构分析

---

## 总体评估

三个仓库形成了一个**清晰的 3 层架构**：App → Bridge → (Providers + Gateway + Plugins)。架构在职责拆分上是合理的，但在以下几个方面存在可改进的空间：

1. **循环依赖**: Plugin → Bridge (HTTP) + Bridge → Plugin (Gateway RPC) 形成调用环
2. **协议层过多**: Chain 2 经过 4 层跳转 (App → Bridge → Gateway → Plugin)
3. **容错不足**: 多处依赖未处理的状态丢失场景
4. **配置分散**: App/Bridge/Plugin 各自维护连接配置，缺乏统一管理

---

## 问题 1: Plugin ↔ Bridge 循环依赖

### 现状

```
Bridge → (Gateway RPC) → Plugin (xworkmate.artifacts.*)
Plugin → (HTTP JSON-RPC) → Bridge (session.start, multiAgent)
```

### 问题

- 两个方向使用不同协议 (Gateway RPC vs HTTP JSON-RPC)，增加调试难度
- 循环引用导致: Bridge 故障 → Plugin 不可用 → Bridge 的 agent 调用失败 → Plugin 的 bridgeAgents 也无法工作
- 版本升级需要同步两个方向

### 建议

**方案 A (推荐): 统一为单向调用**

将 Plugin 中的 `bridgeAgents.ts` 功能移到 Bridge 内部:

```
Bridge
  internal/
    acp/
      orchestrator.go      ← 集成当前 bridgeAgents 逻辑
      gateway.go            ← 保留 xworkmate.artifacts.* 调用
```

Plugin 变为纯工件管理 (只被调，不反向调用):

```
Plugin (简化后)
  src/exportArtifacts.ts   ← 只保留 prepare/export/list/read
  删除 src/bridgeAgents.ts  ← 移到 Bridge
```

**方案 B: 统一协议方向**

Plugin ↔ Bridge 全部走 Gateway RPC (去掉 Plugin 中的 HTTP 调用):

- Bridge 新增 `xworkmate.bridge.*` 网关方法供 Plugin 调用
- Plugin 通过 `api.callGatewayMethod()` 而非 `fetch()` 调用 Bridge

### 影响范围

- 方案 A: 改动 Bridge 内部 + 删除 Plugin 的 bridgeAgents.ts
- 方案 B: 改动 Bridge (新增网关方法) + Plugin (改用网关调用)

---

## 问题 2: Chain 2 协议层过多

### 现状

```
App ──(ACP/WS)──► Bridge ──(GW RPC/WS)──► Gateway ──(Plugin API)──► Plugin
     跳数: 4          协议变换: 2 次
```

### 问题

- 每层增加延迟和故障点
- 错误信息层层包装，难以定位根因
- Gateway 层是性能瓶颈 (WebSocket 单连接复用)

### 建议

**短期优化**:

在 Bridge 中增加 Gateway 连接池（当前为单连接）:
```go
// gatewayruntime/pool.go (新增)
type GatewayPool struct {
    conns   []*GatewayRuntime
    maxSize int
    mu      sync.Mutex
}

func (p *GatewayPool) Acquire() *GatewayRuntime { ... }
func (p *GatewayPool) Release(rt *GatewayRuntime) { ... }
```

**中期优化**:

Bridge 缓存工件元数据，减少实时 Gateway 调用:

```go
// internal/acp/artifact_cache.go (新增)
type ArtifactCache struct {
    cache map[string]*CachedArtifact
    ttl   time.Duration
}

// 命中缓存时跳过 Gateway→Plugin 调用
func (c *ArtifactCache) GetOrFetch(sessionKey, runId string) { ... }
```

**长期考虑**:

如果 Plugin 始终与 Bridge 在同一主机，考虑内嵌 Plugin 为 Bridge 内部模块（避免 Gateway RPC 中转）。

---

## 问题 3: 容错与恢复

### 3.1 SSE 流中断降级为轮询

**现状** (`external_code_agent_acp_desktop_transport.dart`):
```
SSE 流中断 → 降级为 xworkmate.tasks.get 轮询 → 非实时
```

**建议**:
- 在 Bridge 中维护任务状态的增量日志，支持断点续传
- App 重连时发送 `session.resume` 而非重新 `session.start`

### 3.2 Gateway WebSocket 断连 → 任务状态丢失

**现状** (`gatewayruntime/runtime.go`): 断连后未持久化任务状态。

**建议**:
- Bridge 中维护 `tasks` map，断连时标记为 `STALE`
- 重连后自动查询任务最新状态
- 超过 TTL 的 STALE 任务发出 `session.cancel` 通知 App

### 3.3 Gemini/Hermes 子进程崩溃

**现状**: 子进程崩溃后无自动重启。

**建议**:
```go
// internal/geminiadapter/process_manager.go (增强)
type ProcessManager struct {
    cmd        *exec.Cmd
    restartMax int           // 最大重启次数
    backoff    time.Duration  // 退避策略
}

func (pm *ProcessManager) Start() {
    for i := 0; i < pm.restartMax; i++ {
        if err := pm.run(); err != nil {
            time.Sleep(pm.backoff * time.Duration(1<<i))
            continue
        }
        break
    }
}
```

---

## 问题 4: 配置管理分散

### 现状

| 组件 | 配置位置 | 管理方式 |
|------|---------|---------|
| App | `config/settings.yaml` | 本地文件 |
| App | `config/feature_flags.yaml` | 本地文件 |
| Bridge | 环境变量 / `config.yaml` | Ansible 部署 |
| Plugin | `openclaw.plugin.json` / 环境变量 | 插件清单 |

### 问题

- `bridgeUrl` 和 `bridgeToken` 在 App/Bridge/Plugin 三处独立配置
- 配置不一致导致调试困难
- 无版本化配置管理

### 建议

**集中配置源**: 使用 accounts.svc.plus 作为配置中心。

```
accounts.svc.plus
  GET /api/config/bridge → { serverUrl, authToken, providers... }
  GET /api/config/plugin → { bridgeUrl, bridgeToken, workspaceDir... }
```

**本地配置缓存**:
- App 首次启动从 accounts 拉取配置
- Bridge 启动时从 accounts 拉取 providers 配置
- Plugin 从 OpenClaw 网关配置中继承 bridge 连接信息

---

## 问题 5: 无版本兼容性检查

### 现状

三个仓库独立发布，无版本契约:
- xworkmate-app: 1.1.4
- xworkmate-bridge: (无显式版本)
- openclaw-multi-session-plugins: 0.1.15

### 建议

**在 ACP 协议中增加版本协商**:

```json
// acp.capabilities 响应中增加
{
  "protocolVersion": "1.0.0",
  "minCompatibleVersion": "1.0.0",
  "componentVersions": {
    "app": "1.1.4",
    "bridge": "0.2.0",
    "gateway": "2026.5.28",
    "plugins": "0.1.15"
  }
}
```

**App 启动时校验**:
```dart
// gateway_runtime_core.dart
final caps = await gatewayRuntime.getCapabilities();
if (!isCompatible(caps.minCompatibleVersion)) {
  showUpdateDialog();
  return;
}
```

---

## 重构优先级矩阵

| 优先级 | 问题 | 改动量 | 影响 | 建议时序 |
|--------|------|--------|------|---------|
| **P0** | Plugin↔Bridge 循环依赖 | 中 (移动 bridgeAgents) | 消除循环 + 简化协议 | 本周 |
| **P0** | Gateway 断连任务丢失 | 小 (增加持久化) | 核心可靠性 | 本周 |
| **P1** | Gemini/Hermes 进程崩溃 | 小 (增加重启) | 提供商可用性 | 本周 |
| **P1** | 配置管理分散 | 大 (集中配置) | 运维效率 | 本月 |
| **P2** | Chain 2 协议层过多 | 大 (连接池+缓存) | 性能 + 延迟 | 本月 |
| **P2** | 版本兼容性检查 | 小 (协议扩展) | 升级安全 | 本月 |
| **P3** | SSE 降级轮询优化 | 中 (增量日志) | 用户体验 | 下月 |

---

## 各仓库具体改动清单

### xworkmate-app

- [ ] `lib/runtime/gateway_acp_client.dart`: 增加版本兼容性检查
- [ ] `lib/runtime/external_code_agent_acp_desktop_transport.dart`: 支持 session.resume
- [ ] `lib/runtime/runtime_models_account.dart`: 从 accounts 拉取集中配置
- [ ] `config/settings.yaml`: 减少硬编码 URL，改为从 accounts 获取

### xworkmate-bridge

- [ ] `internal/acp/orchestrator.go`: 集成 bridgeAgents 逻辑（方案A）
- [ ] `internal/gatewayruntime/runtime.go`: 增加连接池 + 任务状态持久化
- [ ] `internal/gatewayruntime/pool.go`: 新增连接池
- [ ] `internal/acp/artifact_cache.go`: 新增工件缓存
- [ ] `internal/geminiadapter/` + `internal/hermesadapter/`: 增加子进程自动重启
- [ ] `internal/acp/rpc_handler.go`: 支持 session.resume

### openclaw-multi-session-plugins

- [ ] `src/bridgeAgents.ts`: 删除或重构为单向网关调用（方案B）
- [ ] `openclaw.plugin.json`: 简化配置（从网关继承 bridge 信息）
- [ ] `src/exportArtifacts.ts`: 增加 artifactRef TTL 可配置

---

## 不做的事情

| 项目 | 原因 |
|------|------|
| 引入 gRPC 替代 JSON-RPC | 现有协议工作正常，切换成本高于收益 |
| 合并 App 和 Bridge 为单体 | 拆分有明确的价值 (独立部署、技术栈隔离) |
| 引入消息队列 | 当前规模不需要，会增加运维复杂度 |
| 统一为单一编程语言 | Dart/Go/TS 各有适用场景，不必强行统一 |
