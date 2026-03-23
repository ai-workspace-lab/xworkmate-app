# ARIS 本地 Ollama 功能交付

## 目标

验证 `ARIS + 本地 Ollama` 在标准三角色链路下可以完成一条完整的小功能交付任务。

## 推荐配置

- 框架：`ARIS`
- 执行模式：`单机智能体` 或 `本地 OpenClaw Gateway`
- Ollama 端点：`http://127.0.0.1:11434`
- Architect：`gemini`
- Engineer：`opencode`
- Tester：`codex`

## 建议任务

把下面这段话直接粘到 Assistant：

```text
为当前 Flutter 工作区补一个「最近任务过滤器」：
1. 仅在现有任务列表顶部增加一个最近 24 小时过滤开关
2. 默认关闭，开启后只显示最近 24 小时更新过的任务
3. 不改变现有卡片布局
4. 补最小单测
5. 最后给出修改摘要和风险点
```

## 期望表现

- `Architect` 先给出拆解和约束
- `Engineer` 再进入实现
- `Tester` 最后做审阅和测试反馈
- 若 `Tester` 评分不足，会自动进入 review / fix 循环
- 线程保持 `open`，可以继续追问

## UI 观察点

- 顶部或会话状态中能看到当前是 `ARIS`
- 流程消息按阶段顺序出现
- 不会弹出独立 ARIS 页面
- 任务列表仍然是极简布局

## 通过标准

- 至少完成一轮 `Architect -> Engineer -> Tester`
- 会话能持续，不会一答即结束
- 最终结果里包含：
  - 改动摘要
  - 测试结果
  - 风险或后续建议
