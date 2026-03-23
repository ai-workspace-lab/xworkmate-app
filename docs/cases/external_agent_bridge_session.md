# 外部 Agent CLI Bridge 会话

## 目标

验证 `Go core` 驱动的 reviewer / CLI 会话是持续的 session，而不是一次 prompt 一次退出。

## 推荐配置

- 框架：`ARIS`
- 本地 Ollama 可用
- `llm-chat` / `claude-review` 走 Go core
- Assistant 使用现有线程，不切新页面

## 建议任务

```text
请按 reviewer 方式审阅当前工作区的最近代码变更：
1. 先给出主要风险
2. 然后我会继续追问每一条风险
3. 不要只给结论，要保留后续会话上下文
```

## 手动验证步骤

1. 发送第一轮任务
2. 等 reviewer 返回第一轮风险列表
3. 在同一线程继续追问：
   - “展开第 1 条”
   - “如果不修会怎样”
   - “给最小修复建议”

## 期望表现

- 同一线程持续回答
- 能记住上一轮 reviewer 结果
- 不会退化成一次性 stateless 输出
- `abort/cancel` 后不会继续刷 delta

## 通过标准

- 第二轮、第三轮追问都能基于前文继续
- 没有出现会话上下文丢失
- 没有强制重新建任务
