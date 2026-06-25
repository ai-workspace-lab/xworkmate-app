# Codex /goal｜XWorkmate App 稳定性修复

```text
/goal
你在 /Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app 仓库中持续执行稳定性修复。

请参考：
- /Users/shenlan/workspaces/ai-workspace-lab/xworkspace-console/docs/case/
- /Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app/docs/cases/

目标不是重构 UI，而是围绕 Review 账号、公网 xworkmate-bridge、本地 xworkmate-bridge 和 5 类典型任务用例，修复 App 在登录、Bridge 连接、Token 校验、任务创建、状态流、长任务恢复、取消重试、Artifact 展示中的稳定性问题。

环境覆盖：
1. 云端只读评审账号：accounts.svc.plus / review@svc.plus，密码从 XWORKMATE_REVIEW_PASSWORD 读取。
2. 公网 Bridge：BRIDGE_SERVER_URL=https://xworkmate-bridge.svc.plus，支持 BRIDGE_AUTH_TOKEN。
3. 公网 Review Bridge：BRIDGE_SERVER_URL=https://xworkmate-bridge.svc.plus，支持 BRIDGE_REVIEW_AUTH_TOKEN。
4. 本地 Bridge：BRIDGE_SERVER_URL=http://127.0.0.1:8787，支持 BRIDGE_AUTH_TOKEN。

典型任务用例：
1. AI 资讯 Markdown。
2. 图片制作视频。
3. 7 张连续图片。
4. 多平台软文矩阵。
5. 章节拆解生成图文 PDF。

执行要求：
1. 先阅读 docs/cases 下的用例和覆盖矩阵，梳理当前 App 中对应链路。
2. 不改变现有主视觉和核心交互，优先修复崩溃、卡死、无限 Loading、状态丢失、错误提示不清晰、Token 分支混乱、长任务恢复失败等问题。
3. 优先补齐连接层、任务状态层、错误处理层、日志可观测性和最小回归测试。
4. 对每一处修复，说明触发场景、根因、修改文件、验证方式。
5. 每轮只做小步提交，避免大面积重构。
6. 禁止把真实密码或 Token 写入仓库；统一通过环境变量、Secret 或本地 .env.local 读取。
7. 如果发现用例与当前实现不一致，优先补充兼容层或清晰错误提示，不要直接删除功能入口。

验收标准：
- 三种 Bridge 连接模式均能给出明确成功或失败状态。
- Review 账号登录失败、Token 错误、Bridge 不可达时 App 不崩溃。
- 五类典型任务至少能完成任务创建、状态展示、失败提示和结果/Artifact 展示的主链路验证。
- 长任务切后台再恢复后，状态不会错乱。
- 连续执行 3 次同类任务，不出现任务串线、重复提交、空白结果页。
```
