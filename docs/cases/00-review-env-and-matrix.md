# XWorkmate App Review Test Cases｜环境与覆盖矩阵

> 适用目录：`xworkmate-app/docs/cases/`
>
> 目标：为 Apple 审核、公网 Bridge、自建 Bridge、本地 Bridge、典型 AI 工作流提供稳定、可复现、可回归的测试用例。

## 1. 测试账号与环境变量

### 1.1 云端账号

| 项目 | 值 |
|---|---|
| 账号类型 | 只读评审账号（Apple 审核专用） |
| 服务地址 | `https://accounts.svc.plus` |
| 邮箱 / 账号 | `review@svc.plus` |
| 密码 | 从安全变量读取：`XWORKMATE_REVIEW_PASSWORD` |

> 不建议将真实密码提交到仓库。Apple 审核备注、CI Secret、本地 `.env.local` 可保存真实值。

### 1.2 公网 xworkmate-bridge｜正式 Token 组合

```bash
BRIDGE_SERVER_URL=https://xworkmate-bridge.svc.plus
BRIDGE_AUTH_TOKEN=${BRIDGE_AUTH_TOKEN}
```

### 1.3 公网 xworkmate-bridge｜Review Token 组合

```bash
BRIDGE_SERVER_URL=https://xworkmate-bridge.svc.plus
BRIDGE_REVIEW_AUTH_TOKEN=${BRIDGE_REVIEW_AUTH_TOKEN}
```

### 1.4 本地 xworkmate-bridge｜开发组合

```bash
BRIDGE_SERVER_URL=http://127.0.0.1:8787
BRIDGE_AUTH_TOKEN=${BRIDGE_AUTH_TOKEN}
```

## 2. 通用验收标准

- App 能完成账号登录、Bridge 连接、Token 校验、会话初始化。
- 网络异常、Token 失效、Bridge 不可达时，App 不崩溃，并给出明确错误提示。
- 长任务执行期间，状态流、日志流、任务结果、取消重试行为保持稳定。
- 同一任务重复执行 3 次，产物结构和关键字段稳定，不出现空白页、卡死、重复提交、状态错乱。
- App 从前台切后台再恢复，任务状态可以继续读取或明确提示已中断。

## 3. 五类典型任务覆盖矩阵

| 用例 | 核心链路 | 主要覆盖点 | 稳定性关注 |
|---|---|---|---|
| AI 资讯 Markdown | 搜索 / 摘要 / Markdown 生成 | 长文本、引用、结构化输出 | 流式输出中断、重复标题、空结果兜底 |
| 图片制作视频 | 图片输入 / 脚本 / 分镜 / 视频指令 | 多模态任务、素材引用、步骤编排 | 附件丢失、任务超时、进度状态错乱 |
| 7 张连续图片 | 连续图文 / 风格一致 / 批量生成 | 多步骤连续产物 | 序号错乱、风格漂移、单张失败重试 |
| 多平台软文矩阵 | 公众号 / 小红书 / 视频号 / 推文 | 同主题多平台改写 | 语气失控、长度失控、平台字段缺失 |
| 章节拆解生成图文 PDF | 长文拆解 / 图文页 / PDF 导出 | 长链路 Artifact | 内存占用、导出失败、页面丢失 |

## 4. 回归优先级

P0：登录、Bridge 连接、Token 校验、会话创建、任务状态流。

P1：长任务恢复、取消、重试、错误提示、Artifact 列表刷新。

P2：多平台文本质量、图片风格一致性、PDF 排版一致性。
