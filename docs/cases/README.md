# Multi-Agent Cases

这组案例用于手动验证 `XWorkmate` 当前的多 Agent 协作链路，覆盖：

- `仅 AI Gateway`
- `本地 OpenClaw Gateway`
- `远程 OpenClaw Gateway`
- `ARIS + 本地 Ollama`
- `Architect / Engineer / Tester`
- `Go bridge reviewer`
- `外部 Agent CLI / JSON-RPC session`

## 推荐验证顺序

1. [ARIS 本地 Ollama 功能交付](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/cases/aris_local_ollama_feature_delivery.md)
2. [ARIS 缺陷修复与审阅循环](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/cases/aris_bugfix_review_loop.md)
3. [外部 Agent CLI Bridge 会话](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/cases/external_agent_bridge_session.md)
4. [模式切换与线程连续追问](/Users/shenlan/workspaces/cloud-neutral-toolkit/XWorkmate.svc.plus/docs/cases/thread_mode_switch_followup.md)

## 你应该重点观察的点

- Assistant 仍复用现有输入框、附件、技能和当前线程
- `ARIS` 模式下会显示框架状态，但不会改变主布局
- 协作任务应按 `Architect -> Engineer -> Tester` 顺序推进
- 本地 Ollama 可用时，即便缺失部分云端 CLI，也应能退化运行
- 线程应可继续追问，不是一答即结束
- 任务列表仍保持极简，只显示名称、时间、归档
- `llm-chat` 和 `claude-review` 由 Go bridge 驱动，不依赖 `go run`

## 建议记录项

- 当前使用的框架：`原生` 或 `ARIS`
- 当前执行模式：`仅 AI Gateway` / `本地 OpenClaw Gateway` / `远程 OpenClaw Gateway`
- 参与角色的 CLI 组合
- 是否看到流式输出
- 是否发生自动回退
- 最终是否能继续在同一线程追问
