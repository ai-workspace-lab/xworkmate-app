# OpenClaw Gateway 5 并发 E2E 回归场景

这个 case 固化 5 个真实 OpenClaw Gateway 提示词，用于验证 XWorkmate App -> XWorkmate Bridge -> OpenClaw Gateway 的 5 并发稳定性、任务隔离和 artifact 同步。

Related key-mapping regression:

- App thread: `~/.xworkmate/threads/draft-1780658097668838-1`
- `appThreadKey`: `draft:1780658097668838-1`
- `openclawSessionKey`: `agent:main:draft:1780658097668838-1`
- OpenClaw URL: `https://openclaw.svc.plus/chat?session=agent%3Amain%3Adraft%3A1780658097668838-1`

The durable source of truth is
`SessionEntry.pluginExtensions["openclaw-multi-session-plugins"]["xworkmate.sessionMapping"]`.
Bridge/App must not recover this mapping by replacing `agent:main:` or by using a
legacy `sessionKey` compatibility field.

## 覆盖目标

- 连续出图：7 张连续风格 PNG。
- 模板出图：参考附件模板生成 7 张连续 PNG。
- PDF：拆章节、逐章生成图、汇总排版并输出 PDF。
- 视频：围绕同一安全演进主线制作测试视频。
- 视频流水线：拆章节、逐章调用 Codex/GPT Images、汇总排版并制作视频。

## 自动化落点

| 仓库 | 文件 | 覆盖点 |
| --- | --- | --- |
| `xworkmate-bridge` | `internal/acp/web_contract_test.go` | `TestHTTPHandlerGatewayOpenClawHandlesFiveConcurrentE2ECases` 通过 HTTP SSE 同时提交 5 个 OpenClaw Gateway 请求，断言不出现 queued、invalid handshake、socket closed、ACP_HTTP_CONNECTION_CLOSED、GATEWAY_CONNECT_FAILED。 |
| `xworkmate-app` | `test/runtime/assistant_execution_target_test.dart` | `OpenClaw gateway admits five representative E2E tasks without queueing` 断言 App 侧 5 个代表任务同时进入 running，复用各自 session/thread，不进入 queued，并且 artifact contract 使用 `schemaVersion/appThreadKey/expectedArtifactDirs`，不再写 `sessionKey` 兼容字段。 |
| `openclaw-multi-session-plugins` | `src/taskState.test.ts` | `appThreadKey -> openclawSessionKey` 写入 `pluginExtensions`，`xworkmate.tasks.get` 通过 mapping 查询 OpenClaw native task-registry，查不到时返回 `no_native_task_record`。 |
| `openclaw-multi-session-plugins` | `src/exportArtifacts.test.ts` | 同线程 `assets/images/**/*.png`、manifest、视频/PDF 交付物能被 export 到当前 task artifact scope，不串到旧线程或旧 run，`expectedArtifactDirs` 不存在也保留字段，路径 traversal 被拒绝。 |

## 5 个提示词

以下提示词按原始 E2E 输入记录，作为长期回归 case 的 canonical prompt。

### `OPENCLAW-E2E-001` 连续出图

```text
从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进
制作 使用codex 制作连续制作 7张的一些列图片
```

期望结果：

- 任务进入 running，不因为 5 并发停在 pending/queued。
- 输出 7 张独立 PNG，不合并成一张总览图。
- artifact 区显示当前任务本轮导出的 PNG 和 manifest。

### `OPENCLAW-E2E-002` 模板出图

```text
参考附件模版制作 ,围绕
从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进
连续制作 7张的一些列图片
```

期望结果：

- 任务复用当前线程 workspace 和附件上下文。
- 7 张图片保持模板风格一致。
- 当前任务 artifact 不展示旧线程文件。

### `OPENCLAW-E2E-003` PDF

```text
拆章节 -> 每章调用 Codex -> 每章 GPT images2 生成图 -> 汇总排版 -> 输出 PDF

右侧 artifact栏 显示的陈旧文件
```

期望结果：

- 每章图片素材和最终 PDF 归属当前 task scope。
- PDF 或相关素材出现在当前任务 artifact 区。
- 回归缺陷点：右侧 artifact 栏不能显示其他 run 或历史 workspace 的陈旧文件。
- 如果 OpenClaw 没有实际导出文件，App 显示 no exported artifacts，而不是旧文件。

### `OPENCLAW-E2E-004` 视频

```text
围绕
从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进 右侧是当下
测试制作视频
```

期望结果：

- 视频任务在 5 并发下不触发 `GATEWAY_CONNECT_FAILED: SOCKET_CLOSED`。
- 输出视频帧、配置或 MP4 时，artifact 只属于当前任务。
- 失败时释放 active slot 并继续 drain 后续任务。

### `OPENCLAW-E2E-005` 视频流水线

```text
围绕

从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进

拆章节 -> 每章调用 Codex -> 每章 GPT images2 生成图 -> 汇总排版 -> 制作视频
```

期望结果：

- 图片、manifest、视频配置、MP4/ffprobe 等产物按当前 run 隔离。
- Bridge 和 OpenClaw Gateway 只建立稳定连接，不重复并发握手。
- 不出现 `invalid handshake: first request must be connect`、`SOCKET_CLOSED`、`ACP_HTTP_CONNECTION_CLOSED`。

## 手动验收步骤

前置条件：

- `/Applications/XWorkmate.app` 已安装当前 release。
- 已登录并同步 managed bridge。
- 任务模式选择 `Gateway`，provider 选择 `OpenClaw`。
- `xworkmate-bridge.svc.plus` 和远端 OpenClaw Gateway 可用。

操作步骤：

1. 新建 5 个任务线程，分别输入上面的 5 个提示词。
2. 在短时间内连续提交，保持 `maxActive = 5`、`maxQueued = 20`。
3. 观察左侧任务列表，5 个任务应进入 running 或完成态，不应全部 pending。
4. 逐个打开任务，检查中心消息和右侧 artifact 区。
5. 对任意 running 任务继续提交一句补充要求，确认续聊仍落在当前任务而不是新 draft。

验收标准：

- 5 个任务不出现全等待不运行。
- 不出现 `invalid handshake: first request must be connect`。
- 不出现 `GATEWAY_CONNECT_FAILED: SOCKET_CLOSED: socket closed`。
- 不出现 `ACP_HTTP_CONNECTION_CLOSED`。
- 当前任务没有 artifact 时显示明确空态，不显示旧 run 文件。
- 当前任务生成 PNG/PDF/视频文件时，右侧 artifact 自动同步并只显示当前任务本轮文件。
- `xworkmate.session.prepare` 写入的 mapping 同时包含 `appThreadKey` 和 `openclawSessionKey`。
- `xworkmate.tasks.get` 使用 `appThreadKey/openclawSessionKey/runId`，不发送旧 `sessionKey` lookup 参数。
- `expectedArtifactDirs` 从 App metadata 到 Bridge prepare/export/snapshot 到 Plugin artifact resolver 全链路保留。

## 回归命令

```bash
# xworkmate-bridge
go test ./...

# openclaw-multi-session-plugins
pnpm test
pnpm typecheck
pnpm pack:check

# xworkmate-app
flutter analyze
flutter test test/runtime/assistant_execution_target_test.dart
flutter test test/runtime/gateway_acp_client_auth_test.dart
flutter test test/runtime/desktop_thread_artifact_service_test.dart
flutter test
```
