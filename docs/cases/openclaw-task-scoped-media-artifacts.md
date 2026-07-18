# OpenClaw 全局媒体制品与任务作用域归档 Case

适用范围：iOS App、Desktop App、XWorkmate Bridge、`openclaw-multi-session-plugins` 与 OpenClaw 控制台。

## 问题摘要

2026-07-18 的任务 `agent:main:draft:1784352568972373-1` 请求「采集 AI 资讯，制作图片」。OpenClaw 成功生成新闻卡片，但控制台对多个图片显示：

```text
Unavailable
Outside allowed folders
```

例如：

- `ai-news-02-copilot---a4ca36c6-8218-4e2e-8230-69326a51cb0a.png`
- `ai-news-03-browser---7c1a40b9-95ee-4229-86c1-23dc78bef187.png`
- `ai-news-04-china---539887c4-3554-4a49-aa4d-377f3476a70f.png`
- `ai-news-05-tesla---11d5bf29-02a8-43b8-a2ff-bcfcd7be848b.png`

这不是生成失败，也不是 iOS 的渲染问题；是生成路径、网页回显路径和 XWorkmate 制品作用域不一致。

## 最新复现状态（2026-07-18）

复现会话：`agent:main:draft:1784354131167918-3`，Bridge run：`turn-1784354150350392849`。

- 6 张 PNG 已完成生成，均只存在于 `/home/ubuntu/.openclaw/media/tool-image-generation/`，单张约 2.1–2.5 MB；控制台对每张均显示 `Unavailable / Outside allowed folders`。
- 当前任务 scope 已由 Bridge 成功创建：`tasks/agent_main_draft_1784354131167918-3/turn-1784354150350392849/assets/images/`；检查时 scope 内尚无普通文件，说明图片生成工具没有直接遵循该目录。
- 已上线 Bridge 在 13:55:50 记录 `artifact_sync stage=prepare`，13:55:51 `chat.send` 成功；随后客户端持续调用 `xworkmate.tasks.get`。日志中的 `notification_dropped` 是 Bridge 主动过滤未经规范化的原始 gateway push/log 通知，不能单独等同于 RPC 调用失败。
- 截止检查时尚未观察到该 run 的终态 `artifacts.export → collect-and-snapshot → export` 日志。因此当前需分两条线继续验证：任务终态是否被插件正确投影；一旦首次 export 为空，Bridge 是否真正执行已部署的补偿分支。

联合调试应优先收集以下关联证据：

1. `xworkmate.tasks.get` 的规范化终态 payload（`status/runId/artifacts`）；
2. Bridge 的 `artifact_sync` 日志是否出现 `collect` 与 `export-retry`；
3. task scope 内的 `artifacts/media/...` 是否出现与全局 PNG 同 hash 的副本；
4. OpenClaw 最终回复 payload 中的 `MEDIA:` 是否仍为全局媒体路径。

## 现场证据

服务端以 `ubuntu` 身份运行 OpenClaw 与 Bridge。四个 PNG 均存在，时间为 2026-07-18 13:34，大小约 1.5–1.8 MB：

```text
/home/ubuntu/.openclaw/media/tool-image-generation/<file>.png
```

对应会话的最终回复直接包含：

```text
MEDIA:/home/ubuntu/.openclaw/media/tool-image-generation/<file>.png
```

OpenClaw 控制台把本地媒体路径交给安全读取器；路径不满足该进程实际生效的允许根目录时，错误被分类为 `path-not-allowed`，UI 显示 `Outside allowed folders`。线上 OpenClaw 版本为 `2026.6.1`。

同时，Bridge 日志显示本回合执行了 `xworkmate.session.prepare`，但旧 Bridge 未在制品导出为空后执行 `xworkmate.artifacts.collect-and-snapshot`。

## 正确的制品边界

全局媒体目录只能是工具运行时缓存，不能成为 XWorkmate 最终交付路径。每个任务的最终制品必须归档至：

```text
/home/ubuntu/.openclaw/workspace/
  tasks/<sanitize(sessionKey)>/<runId>/
    artifacts/<source>/<relative-file>
```

例如本任务的目标作用域为：

```text
tasks/agent_main_draft_1784352568972373-1/turn-1784352687172064585/
```

不变量：

1. 同一任务的网页回显、Desktop 右侧制品栏和 iOS 制品卡引用同一个 task scope。
2. 不能通过放宽全局 `/home/ubuntu/.openclaw/media` 白名单解决问题；这会绕过任务线程隔离。
3. `artifactScope`、`sessionKey`、`runId` 必须保持一致；插件会拒绝不匹配的三元组。
4. 复制时必须拒绝符号链接、路径逃逸和不在 OpenClaw 受控媒体/临时目录中的源文件。

## 部署环境（2026-07-18 已核验）

| 项 | 当前值 | 说明 |
| --- | --- | --- |
| 主机 | `openclaw.svc.plus` | 通过 `root` 仅作运维诊断；服务进程不以 root 运行 |
| 服务用户 | `ubuntu` | OpenClaw、Bridge、任务工作区及媒体目录的唯一运行身份 |
| OpenClaw gateway | `OpenClaw 2026.6.1 (2e08f0f)`，`127.0.0.1:18789` | `node /home/ubuntu/.local/bin/openclaw gateway run --port 18789 --force` |
| XWorkmate Bridge | `v1.0-beta2`，commit `2e5c5b6`，`127.0.0.1:8787` | `ubuntu` 的 systemd user service；工作目录 `/opt/cloud-neutral/xworkmate-bridge` |
| Bridge 旧 system service | inactive | `/usr/local/bin/xworkmate-go-core` 已停用；不可误判为当前运行版本 |
| 多会话插件 | `openclaw-multi-session-plugins 2026.6.2`，enabled | 安装源 `global:openclaw-multi-session-plugins/dist/index.js` |
| OpenClaw workspace | `/home/ubuntu/.openclaw/workspace` | task scope 根目录 |
| 全局生成媒体缓存 | `/home/ubuntu/.openclaw/media/tool-image-generation` | 仅作为运行时输入，不能作为最终 XWorkmate 制品引用 |
| 临时输出补偿源 | `/tmp/openclaw` | 与全局媒体目录一起由插件收集器扫描 |

认证信息只保留在 systemd 服务环境中；日志、case、截图和提交不得记录 token 值。

## 相关仓库与所有权

| 仓库 | 本地位置 | 负责内容 |
| --- | --- | --- |
| `xworkmate-app` | `/Users/shenlan/workspaces/ai-workspace-lab/xworkmate-app` | iOS/Desktop 会话持久化、任务轮询、制品卡、下载、分享、Desktop 右侧制品栏 |
| `xworkmate-bridge` | `/Users/shenlan/workspaces/ai-workspace-lab/xworkmate-bridge` | App ACP 协议、`session.prepare/chat.send/tasks.get` 编排、终态空制品的 collect/export 重试 |
| `openclaw-multi-session-plugins` | `/Users/shenlan/workspaces/ai-workspace-lab/openclaw-multi-session-plugins` | `xworkmate.*` gateway 方法、`tasks/<session>/<run>` 作用域、制品安全导出和全局媒体/临时目录快照 |
| `openclaw`（运行时上游） | `/Users/shenlan/workspaces/ai-workspace-lab/openclaw` | `image_generate` 输出、`MEDIA:` 解析、Control UI 本地媒体安全读取，以及发送前 payload hook 能力 |

## 当前部署链路

```text
iOS / Desktop App
  │  HTTPS + SSE: /acp/rpc
  ▼
XWorkmate Bridge (ubuntu, 127.0.0.1:8787)
  │  WebSocket gateway RPC
  ├─ xworkmate.session.prepare
  ├─ chat.send
  ├─ xworkmate.tasks.get
  └─ artifacts.export → (empty) collect-and-snapshot → artifacts.export
  ▼
OpenClaw Gateway (ubuntu, 127.0.0.1:18789)
  │
  ├─ openclaw-multi-session-plugins
  │    └─ tasks/<sanitize(sessionKey)>/<runId>/artifacts/  ← 最终交付根
  │
  └─ image_generate / media tools
       └─ ~/.openclaw/media/tool-image-generation/         ← 临时全局缓存
```

最终媒体的正确数据流应为：

```text
工具全局缓存
  → 当前任务 artifacts/ 内的受控副本
  → 改写后的网页 MEDIA 引用
  → Bridge export manifest
  → iOS 制品卡 / Desktop 右侧制品栏
```

当前已上线的是 Bridge 末端的补偿复制；尚缺 OpenClaw 的“发送前复制并改写网页回显”步骤。

## 调用链与故障点

```text
image_generate
  → ~/.openclaw/media/tool-image-generation/*.png        (全局临时输出)
  → 最终回复 MEDIA:<全局路径>                              (控制台读取被拒绝)

Bridge xworkmate.session.prepare
  → workspace/tasks/<session>/<run>/                      (已建立但未被媒体工具使用)
  → artifacts.export                                      (scope 为空时无法返回给 App)
```

该断层同时造成两种用户可见问题：

| 表面 | 原因 | 正确修复 |
| --- | --- | --- |
| OpenClaw 控制台 `Outside allowed folders` | 回复引用全局媒体路径 | 在媒体发送前复制到 task scope 并改写 `MEDIA`/结构化附件路径 |
| iOS/Desktop 反复检测制品或制品为空 | export 仅扫描 task scope，工具输出仍在全局媒体/临时目录 | 任务完成后执行 collect-and-snapshot，再重试 export |

## 已上线补偿（Bridge）

已部署 Bridge 提交 `2e5c5b6`：`fix(acp): collect terminal artifacts before export retry`。

部署验证：

```text
服务：xworkmate-bridge.service（ubuntu 用户服务）
状态：active
版本 commit：2e5c5b6
```

行为：首次 `xworkmate.artifacts.export` 为空时，Bridge 调用：

```text
xworkmate.artifacts.collect-and-snapshot
→ xworkmate.artifacts.export（重试）
```

插件现有收集器扫描 `~/.openclaw/media/` 与 `/tmp/openclaw/`，仅把符合安全边界的文件复制到当前任务 scope。因此它能补齐 iOS 与 Desktop 的制品回传，但它发生在任务终态后，**不能修复已经发给 OpenClaw 网页的旧 `MEDIA:` 路径**。

## 尚未上线的根治项（OpenClaw）

需要在 OpenClaw 支持可改写最终回复媒体载荷的运行时版本上，使用 `reply_payload_sending` 这类发送前 hook：

1. 读取当前 `sessionKey/runId`；
2. 仅接受 OpenClaw 受控媒体/临时根目录中的真实普通文件；
3. 复制到 `tasks/<session>/<run>/artifacts/...`；
4. 用任务内绝对路径改写最终回复中的 `mediaUrl/mediaUrls` 及对应 `MEDIA:` 引用；
5. 失败时记录明确日志，不扩大本地文件读取权限。

当前线上 OpenClaw `2026.6.1` 所加载的插件 API 不提供可安全替换最终回显载荷的 hook；不能用提示词解析、修改会话 JSON，或放宽目录白名单替代。下一次 OpenClaw 运行时升级需先确认该 hook 的正式契约、准备回滚包，再部署相应插件版本。

## 回归验收

### OpenClaw 控制台

1. 新建会生成图片、PDF、音频或视频的任务。
2. 最终回复的每一项媒体均显示可用预览，不出现 `Outside allowed folders`。
3. 物理文件位于当前 `tasks/<session>/<run>/artifacts/`，不依赖全局媒体缓存长期保存。
4. 另一任务不能通过路径或引用读取本任务制品。

### iOS 与 Desktop

1. 等待任务完成，Bridge 日志应出现收集与 export 重试（仅首轮 export 为空时）。
2. iOS 历史任务中显示制品卡；点击图片/PDF/媒体文件会打开原始文件的系统分享面板。
3. Desktop 右侧制品栏仍显示同一任务 scope 的制品；二进制文件不被错误当作文本预览。
4. 普通纯文本任务正常完成，不触发无限制的制品轮询。

## 诊断命令（只读）

```bash
ssh root@openclaw.svc.plus
sudo -u ubuntu find /home/ubuntu/.openclaw/media /tmp/openclaw -type f -name '<artifact-name>'
sudo -u ubuntu systemctl --user status xworkmate-bridge.service
sudo -u ubuntu /home/ubuntu/.local/bin/xworkmate-go-core version
```

排查时不得输出服务认证令牌或将任务制品复制到任务 scope 之外。
