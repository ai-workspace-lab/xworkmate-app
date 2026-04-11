# 核心功能集成测试手动 Case

## 1. 使用说明

这份文档只保留当前项目主线的核心手动用例：

- 设置页面配置功能
- 任务线程场景测试

每个 case 都要求记录统一证据，最少包含：

- 当前模式
- 当前 provider / endpoint
- 输入提示词或操作
- 结果摘要
- 产物路径或截图点
- 是否需要外部服务人工确认

## 2. 设置页面配置功能

### `MANUAL-ACP-001` 在线用户同步后默认值与本地 override 共存

- 前置条件
  - 已登录在线账户
  - 账户侧存在可同步的 Gateway / ACP 默认配置
  - 本地有一项可区分的 override 值
- 操作步骤
  1. 打开 `Settings -> Integrations -> Gateway`
  2. 触发账户同步或重进设置页等待同步完成
  3. 观察远程默认 endpoint 与本地 override 的展示
  4. 返回主页面，再次进入设置页确认状态稳定
- 期望结果
  - 远程默认配置被注入
  - 本地 override 没有被覆盖
  - 页面不显示 secret 明文
- 建议记录项
  - 当前登录账户
  - 同步前后 endpoint 对比
  - 是否看到 secret 明文
  - 截图点：同步完成后的设置页

### `MANUAL-ACP-002` selfhost ACP 远程接入

- 前置条件
  - 有可访问的 selfhost ACP 基址
  - 若服务需要 auth，准备好 auth 值
- 操作步骤
  1. 进入 `Settings -> Integrations -> Gateway`
  2. 输入 selfhost 基址，例如 `https://host.example.com/opencode`
  3. 如有需要，填写 auth
  4. 点击 `测试连接`
  5. 保存并生效，返回页面再次确认
- 期望结果
  - 连接测试成功或失败信息明确
  - 内部派生路径符合 `/acp` 与 `/acp/rpc`
  - 保存后页面状态稳定，重新进入不会丢失 endpoint
- 建议记录项
  - provider / endpoint
  - auth 是否为空
  - 测试连接结果摘要
  - 截图点：测试连接结果

### `MANUAL-ACP-003` local ACP / local 模式接入

- 前置条件
  - 本机已有 local / loopback ACP 服务
  - 确认监听地址与端口
- 操作步骤
  1. 输入 loopback endpoint，例如 `http://127.0.0.1:9001/opencode`
  2. 点击 `测试连接`
  3. 保存并生效
  4. 关闭设置页后重新进入确认仍然显示 local endpoint
- 期望结果
  - local / loopback 非 TLS 允许通过
  - 页面明确显示当前为本地配置
  - 不会把 local endpoint 错误识别为 remote insecure endpoint
- 建议记录项
  - 当前模式
  - loopback endpoint
  - 测试连接结果
  - 是否需要本机服务日志人工对照

## 3. 本地执行型任务线程

### `MANUAL-LOCAL-001` `powerpoint-pptx`

- 前置条件
  - `pptx` 技能可用
  - 当前线程为空白或新建线程
- 操作步骤
  1. 在 assistant 线程中选择 `powerpoint-pptx`
  2. 输入“生成一个三页产品介绍演示稿”
  3. 等待任务完成
  4. 在同一线程继续追问“把第二页改成对比页”
- 期望结果
  - 当前线程生成 `.pptx` 产物
  - 产物显示在当前线程 artifact 区域
  - 第二次追问延续同一线程上下文
- 建议记录项
  - 线程 ID 或线程标题
  - 输入提示词
  - 产物路径
  - 截图点：artifact 列表与连续追问结果

### `MANUAL-LOCAL-002` `word-docx`

- 前置条件
  - `word-docx` 技能可用
- 操作步骤
  1. 选择 `word-docx`
  2. 输入“生成一份包含标题、目录和表格的周报文档”
  3. 等待结果生成
- 期望结果
  - 当前线程返回 `.docx` 产物
  - 结果归属当前线程
  - 不会跳到其他 provider 或其他线程
- 建议记录项
  - 当前模式
  - provider
  - 文档产物路径
  - 结果摘要

### `MANUAL-LOCAL-003` `excel-xlsx`

- 前置条件
  - `excel-xlsx` 技能可用
- 操作步骤
  1. 选择 `excel-xlsx`
  2. 输入“生成一个带汇总公式的销售表”
  3. 等待结果完成
- 期望结果
  - 当前线程中出现 `.xlsx` 产物
  - 线程 workspace 有对应文件
  - 结果摘要说明生成成功
- 建议记录项
  - 提示词
  - 文件名
  - artifact 区域截图

### `MANUAL-LOCAL-004` `pdf`

- 前置条件
  - `pdf` 技能可用
- 操作步骤
  1. 选择 `pdf`
  2. 输入“合并两个 PDF 并输出新文件”
  3. 等待任务完成
- 期望结果
  - 当前线程生成 PDF 结果
  - 失败时线程中能看到错误摘要
  - 不会只显示文本而没有产物
- 建议记录项
  - 输入操作
  - 产物路径
  - 成功或失败摘要

### `MANUAL-LOCAL-005` `image-resizer`

- 前置条件
  - `image-resizer` 技能可用
  - 有可处理的本地图片
- 操作步骤
  1. 选择 `image-resizer`
  2. 输入“将图片缩放到 1200x800 并压缩”
  3. 等待任务完成
- 期望结果
  - 当前线程出现处理后的图片产物
  - 结果归属当前线程 workspace
  - 结果摘要包含尺寸或压缩信息
- 建议记录项
  - 原图与结果图路径
  - 输出尺寸
  - 截图点：线程结果区

### `MANUAL-LOCAL-006` 本地浏览器自动化

- 前置条件
  - 本地浏览器自动化技能可用
  - 有可访问网页
- 操作步骤
  1. 在当前线程选择浏览器自动化技能
  2. 输入“打开示例页面并提取标题”
  3. 等待结果返回
- 期望结果
  - 线程内返回网页操作摘要
  - 如有截图或日志产物，进入当前线程 artifact
  - 切换到其他线程后不复用本线程结果
- 建议记录项
  - 访问网址
  - 返回摘要
  - 是否生成截图或日志

## 4. 在线执行任务线程

### `MANUAL-ONLINE-001` `image-cog`

- 前置条件
  - 在线 provider 可用
  - `image-cog` 技能可用
- 操作步骤
  1. 在 assistant 线程选择 `image-cog`
  2. 输入“生成一张极简产品海报”
  3. 等待任务状态完成
- 期望结果
  - 线程中显示在线任务结果
  - 产物图片回到当前线程 artifact
  - provider 显示为在线执行
- 建议记录项
  - 当前 provider / endpoint
  - 任务状态变化
  - 图片产物路径或截图

### `MANUAL-ONLINE-002` `image-video-generation-editting`

- 前置条件
  - 在线视频/图片生成服务可用
- 操作步骤
  1. 选择 `image-video-generation-editting`
  2. 输入“基于这张图生成 5 秒镜头推近视频”
  3. 等待任务轮询完成
- 期望结果
  - 线程内可见任务处理中间状态或最终状态
  - 最终产物回传到当前线程
  - 失败时有明确错误摘要
- 建议记录项
  - 任务开始与结束时间
  - 视频或图片结果路径
  - 是否需要外部服务后台确认

### `MANUAL-ONLINE-003` `video-translator`

- 前置条件
  - 在线翻译/配音服务可用
  - 准备一个待翻译视频
- 操作步骤
  1. 选择 `video-translator`
  2. 输入“将视频翻译成英文并输出字幕版”
  3. 等待任务完成
- 期望结果
  - 当前线程返回翻译后的视频或字幕产物
  - 线程中可见任务成功或失败摘要
  - 不会丢失当前线程上下文
- 建议记录项
  - 输入视频来源
  - 结果产物路径
  - 错误信息或成功摘要

### `MANUAL-ONLINE-004` 资讯采集

- 前置条件
  - 在线采集能力可用
- 操作步骤
  1. 选择资讯采集能力
  2. 输入“采集今天关于 AI Agent 的 5 条资讯”
  3. 查看结果
- 期望结果
  - 线程返回结构化资讯结果
  - 标题、来源、摘要等字段完整
  - 结果留在当前线程内
- 建议记录项
  - 当前 provider / endpoint
  - 输入提示词
  - 结果中的标题 / 来源 / 摘要
  - 是否回到当前线程

## 5. XWorkmate App -> XWorkmate Bridge 远端单 Agent / Gateway 验收

这些 case 用于验证 `xworkmate-app` 通过当前 bridge / gateway ACP 链路调用
`xworkmate-bridge`，再转发到远端 `codex / opencode / gemini / openclaw`
时的真实线程行为，重点关注：

- provider 选择是否正确
- follow-up 是否保持同一 thread
- artifact 是否写回当前线程本地 workspace
- `lastRemoteWorkingDirectory` / `remoteWorkspaceRefKind` 是否只作为 metadata

统一新增记录项：

- 当前模式
- 当前 provider / endpoint
- 输入提示词
- 线程 ID
- 本地线程 workspace 路径
- 产物路径列表
- `lastRemoteWorkingDirectory`
- `remoteWorkspaceRefKind`
- 是否需要外部服务人工确认

### `MANUAL-REMOTE-001` Codex 对话 + `pptx`

- 前置条件
  - 已选择任务对话模式 `codex`
  - bridge/provider 连通
- 操作步骤
  1. 输入“生成一个两页产品介绍演示稿，输出为 `deck.pptx`”
  2. 等待任务完成并确认 artifact 区出现 `.pptx`
  3. 在同一线程继续追问“把第二页改成总结页”
- 期望结果
  - 对话可用
  - `.pptx` 写回当前线程本地 workspace
  - follow-up 复用同一线程，不漂移到其他 provider
  - `lastRemoteWorkingDirectory` 更新，但 `workspaceBinding` 仍是本地目录

### `MANUAL-REMOTE-002` Codex `docx/xlsx/pdf`

- 前置条件
  - 已选择任务对话模式 `codex`
- 操作步骤
  1. 执行 `docx`：生成一份周报文档
  2. 执行 `xlsx`：生成一个带汇总公式的销售表
  3. 执行 `pdf`：生成或转换出一个 PDF 摘要文件
- 期望结果
  - 三类任务均可执行
  - 产物分别出现在 artifact 区
  - 文件落回当前线程本地 workspace

### `MANUAL-REMOTE-003` Codex `image-resizer`

- 前置条件
  - 已选择任务对话模式 `codex`
  - 线程目录内有一张待处理图片
- 操作步骤
  1. 输入“将 `input.png` 缩放到 1200x800 并输出 `resized.png`”
  2. 等待结果完成
- 期望结果
  - 图片处理成功
  - 输出图片写回当前线程本地 workspace
  - 结果摘要含尺寸或压缩信息

### `MANUAL-REMOTE-004` OpenCode 对话 + `pptx`

- 前置条件
  - 已选择任务对话模式 `opencode`
- 操作步骤
  1. 输入“生成一个两页演示稿 `deck.pptx`”
  2. 等待完成
  3. 同线程继续追问修改第二页内容
- 期望结果
  - 对话可用
  - `.pptx` 落回当前线程本地 workspace
  - follow-up 继续复用同一线程上下文

### `MANUAL-REMOTE-005` OpenCode `docx/xlsx/pdf`

- 前置条件
  - 已选择任务对话模式 `opencode`
- 操作步骤
  1. 执行 `docx`
  2. 执行 `xlsx`
  3. 执行 `pdf`
- 期望结果
  - 三类任务可用
  - 产物可见且落回当前线程本地 workspace

### `MANUAL-REMOTE-006` OpenCode `image-resizer`

- 前置条件
  - 已选择任务对话模式 `opencode`
  - 已准备本地输入图片
- 操作步骤
  1. 输入图片缩放任务
  2. 等待结果
- 期望结果
  - 输出图片可见
  - 线程 artifact 和本地 workspace 均可确认结果

### `MANUAL-REMOTE-007` Gemini 基础对话

- 前置条件
  - 已选择任务对话模式 `gemini`
- 操作步骤
  1. 输入“回复 exactly pong”
  2. 在同一线程继续追问“回复 exactly round2”
- 期望结果
  - 基础对话可用
  - 两轮消息都停留在同一线程
  - provider 显示仍为 `gemini`

### `MANUAL-REMOTE-008` Gemini 文档 / 图片任务能力边界确认

- 前置条件
  - 已选择任务对话模式 `gemini`
- 操作步骤
  1. 分别尝试 `docx / pptx / xlsx / pdf / image-resizer`
  2. 记录每项成功或失败
- 期望结果
  - 若成功：artifact 落回当前线程本地 workspace
  - 若失败：错误摘要明确，可区分是 provider 能力限制还是 bridge/app 落盘问题

### `MANUAL-GATEWAY-001` OpenClaw Gateway 基础对话

- 前置条件
  - 任务线程使用 remote gateway / `openclaw gateway`
  - `openclaw.svc.plus` 可连通
- 操作步骤
  1. 输入普通对话任务
  2. 等待 gateway 返回结果
- 期望结果
  - 可建立对话
  - 线程消息返回成功或明确失败摘要
  - provider / mode 显示为 gateway 路径

### `MANUAL-GATEWAY-002` OpenClaw Gateway 文档类任务

- 前置条件
  - Gateway 路径可用
- 操作步骤
  1. 执行 `docx` 或 `pptx`
  2. 执行 `xlsx` 或 `pdf`
- 期望结果
  - 至少 1-2 类文档任务成功
  - 若返回 artifact，应回写当前线程本地 workspace
  - 若只返回文本摘要，应记录为“对话成功但无 artifact”

### `MANUAL-GATEWAY-003` OpenClaw Gateway 浏览器自动化

- 前置条件
  - Gateway 浏览器能力可用
  - 有可访问网页
- 操作步骤
  1. 输入“打开示例页面并提取标题”
  2. 如支持截图，再追问“截图并保存结果”
- 期望结果
  - 可执行浏览器任务
  - 返回网页摘要
  - 若有截图 / 日志产物，应进入当前线程 artifact

### `MANUAL-GATEWAY-004` OpenClaw Gateway 在线资讯汇总

- 前置条件
  - Gateway 联网能力可用
- 操作步骤
  1. 输入“汇总今天关于 AI Agent 的 5 条资讯”
  2. 查看结构化结果
- 期望结果
  - 能返回标题、来源、摘要
  - 结果留在当前线程
  - 若生成文档或截图，写回当前线程本地 workspace
  - 查询词
  - 结果条数
  - 结果摘要截图

### `MANUAL-ONLINE-005` 搜索

- 前置条件
  - 在线搜索能力可用
- 操作步骤
  1. 选择搜索能力
  2. 输入“搜索 XWorkmate ACP 配置说明”
  3. 查看结果后继续追问“把前 3 条结果做摘要”
- 期望结果
  - 搜索结果结构完整
  - 连续追问复用同一线程
  - 不新建孤立线程
- 建议记录项
  - 初始查询词
  - 连续追问内容
  - 搜索结果摘要

## 5. 通用线程场景

### `MANUAL-THREAD-001` 同线程连续追问

- 前置条件
  - 任意一个本地执行或在线执行任务已经成功完成
- 操作步骤
  1. 在原线程继续提问“继续基于刚才结果展开 3 点”
  2. 观察回复
- 期望结果
  - 沿用原线程
  - 回答引用刚才的结果
- 建议记录项
  - 原线程标识
  - 连续追问内容
  - 是否保留上下文

### `MANUAL-THREAD-002` 切换线程后的状态隔离

- 前置条件
  - 至少准备两个不同线程
- 操作步骤
  1. 在线程 A 完成一个任务
  2. 切换到线程 B 执行不同任务
  3. 再切回线程 A
- 期望结果
  - A、B 两个线程的技能、provider、artifact 不串线
  - 当前线程状态只反映当前线程
- 建议记录项
  - 线程 A/B 标识
  - 各自技能与产物
  - 切换前后截图

### `MANUAL-THREAD-003` 失败回退观察

- 前置条件
  - 准备一个可稳定触发失败的配置或任务
- 操作步骤
  1. 使用错误 endpoint 或故意不可达的在线任务
  2. 提交任务并观察线程结果
- 期望结果
  - 线程中出现清晰失败信息
  - 不会把失败误报为成功
  - 保留当前线程，便于继续修正并重试
- 建议记录项
  - 失败输入
  - 错误摘要
  - 是否能在同线程重试
