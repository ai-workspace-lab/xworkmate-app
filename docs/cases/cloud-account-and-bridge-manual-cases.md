# 云端账号与 XWorkmate Bridge 连接手动 Case

本文档整理 Apple 审核专用只读账号、svc.plus 云端同步、以及公网 / 本地 `xworkmate-bridge` 接入的手动验证用例。

## 1. 测试账号与连接参数

### 1.1 云端账号

| 项目 | 内容 |
|------|------|
| 账号类型 | 只读评审账号（Apple 审核专用） |
| 服务地址 | `https://accounts.svc.plus` |
| 邮箱 / 账号 | `review@svc.plus` |
| 密码 | `***REMOVED-CREDENTIAL***` |

### 1.2 公网 xworkmate-bridge 组合 1

| 环境变量 | 值 |
|----------|----|
| `BRIDGE_SERVER_URL` | `https://xworkmate-bridge.svc.plus` |
| `BRIDGE_AUTH_TOKEN` | `***REMOVED-CREDENTIAL***` |

### 1.3 公网 xworkmate-bridge 组合 2

| 环境变量 | 值 |
|----------|----|
| `BRIDGE_SERVER_URL` | `https://xworkmate-bridge.svc.plus` |
| `BRIDGE_REVIEW_AUTH_TOKEN` | `***REMOVED-CREDENTIAL***` |

### 1.4 本地 xworkmate-bridge

| 环境变量 | 值 |
|----------|----|
| `BRIDGE_SERVER_URL` | `http://127.0.0.1:8787` |
| `BRIDGE_AUTH_TOKEN` | `***REMOVED-CREDENTIAL***` |

---

## 2. 通用证据记录要求

每个 case 执行后建议记录：

- 当前 App 版本 / 构建号
- 当前平台与网络环境
- 当前入口：`Settings -> Integrations`
- 当前页签：`svc.plus 云端同步` 或 `AI 智能体工作空间`
- 服务地址 / Bridge 地址
- token 类型：`BRIDGE_AUTH_TOKEN` 或 `BRIDGE_REVIEW_AUTH_TOKEN`
- 连接测试结果摘要
- 是否出现 secret 明文
- 截图点：保存前、保存后、重新进入设置页

---

## 3. 五类典型任务

以下五类任务用于验证 App 登录后能否通过当前连接方式稳定创建任务、执行技能、生成文件产物并回写到当前线程。

| 任务编号 | 类型 | 验收产物 |
|----------|------|----------|
| CASE-001 | 采集最新 AI 资讯 | `.md` 文件 |
| CASE-002 | 附件图片制作视频 | 视频文件，附件图片被使用 |
| CASE-003 | 安全身份演进连续图片 | 7 张连续风格图片 |
| CASE-004 | 多平台软文矩阵 | 多个 `.md` 文件 |
| CASE-005 | 章节拆解 + Codex + GPT images2 + PDF | 汇总排版后的 PDF |

### `TASK-CASE-001` 采集最新 AI 资讯并保存 Markdown

- 输入提示词

```text
采集最新AI资讯，保存在md文件
```

- 期望结果
  - 任务能联网采集最新 AI 资讯
  - 结果保存为 Markdown 文件
  - 线程结果区展示文件产物
  - Markdown 内包含标题、来源、摘要和时间信息
- 建议记录项
  - 任务线程 ID
  - 输出 `.md` 文件路径
  - 资讯来源数量
  - 截图点：任务完成后的 artifact 区域

### `TASK-CASE-002` 附件图片制作视频

- 前置条件
  - 当前线程上传至少 1 张图片附件
- 输入提示词

```text
制作视频，附件带有图片
```

- 期望结果
  - 任务识别并使用用户上传的图片附件
  - 输出视频文件
  - 失败时错误信息明确说明缺少图片、视频生成失败或依赖不可用
  - 产物归属当前线程 workspace
- 建议记录项
  - 附件图片文件名
  - 输出视频路径
  - 视频时长和分辨率
  - 截图点：附件与视频产物

### `TASK-CASE-003` 安全身份演进连续 7 张图片

- 输入提示词

```text
从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进，连续制作 7 张一系列图片
```

- 期望结果
  - 输出 7 张图片
  - 7 张图片主题分别覆盖：单机权限、网络边界、Web 安全、云身份、Zero Trust、AI Agent 身份、AI 模型与知识保护
  - 图片风格、尺寸、命名方式保持连续一致
  - 线程结果区能看到完整图片系列
- 建议记录项
  - 7 张图片路径
  - 图片尺寸
  - 是否存在缺图或主题错位
  - 截图点：图片系列列表

### `TASK-CASE-004` 安全身份演进多平台软文矩阵

- 输入提示词

```text
围绕 从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进

1. 输出Markdown格式文件， 微信公众号短图文  400-600字 插入关键词的软文
2. 输出Markdown格式文件， 小红书风格        600-800字 插入钩子话题的软文
3. 输出Markdown格式文件， X文案串           小于144字的英语 鲜明的观点
4. 输出Markdown格式文件， 微信公众号文章    800-1200字左右
5. 输出Markdown格式文件， 头条号长文        800-1200字左右
```

- 期望结果
  - 输出 Markdown 格式文件
  - 至少包含微信公众号短图文、小红书风格、X 文案串、微信公众号文章、头条号长文五类内容
  - 字数、语言和平台风格符合输入要求
  - X 文案串为英语且单条小于 144 字符
  - 内容围绕同一条安全身份演进主线，不跑题
- 建议记录项
  - 输出文件路径
  - 每个平台内容字数
  - X 文案字符数
  - 截图点：Markdown 产物列表

### `TASK-CASE-005` 安全身份演进章节拆解生成图文 PDF

- 输入提示词

```text
从单机权限 → 网络边界 → Web安全 → 云身份 → Zero Trust → AI Agent 身份 → AI模型与知识保护 演进
拆章节 -> 每章调用 Codex -> 每章 GPT images2 生成图 -> 汇总排版 -> 输出 PDF
```

- 期望结果
  - 任务先拆分章节，再逐章生成内容
  - 每章调用 Codex 生成或整理章节文本
  - 每章调用 GPT images2 生成配图
  - 最终汇总排版为 PDF
  - PDF 中章节顺序与演进主线一致，图片与章节内容匹配
- 建议记录项
  - 章节清单
  - 每章图片路径
  - 输出 PDF 路径
  - PDF 页数
  - 截图点：PDF artifact 与预览页

---

## 4. 连接云端账号

### `MANUAL-CLOUD-001` 只读评审账号登录

- 前置条件
  - App 可访问 `https://accounts.svc.plus`
  - 当前未登录，或已退出其他账号
- 操作步骤
  1. 打开 `Settings -> Integrations`
  2. 切换到 `svc.plus 云端同步`
  3. 在 `服务地址` 输入 `https://accounts.svc.plus`
  4. 在 `邮箱或账号` 输入 `review@svc.plus`
  5. 在 `密码` 输入 `***REMOVED-CREDENTIAL***`
  6. 点击 `登录`
  7. 等待账号同步完成
- 期望结果
  - 登录成功，账号状态稳定显示为已登录或同步完成
  - App 不展示密码明文
  - 若账号侧托管 bridge 配置可用，设置页可同步到对应连接配置
  - 只读评审账号不能触发破坏性写入或管理动作
- 建议记录项
  - 登录账号
  - 服务地址
  - 登录结果摘要
  - 同步后的 bridge endpoint
  - 截图点：登录成功后的 `svc.plus 云端同步` 页

### `MANUAL-CLOUD-002` 退出后重新登录保持稳定

- 前置条件
  - 已完成 `MANUAL-CLOUD-001`
- 操作步骤
  1. 在设置页退出当前账号
  2. 关闭或返回设置页
  3. 再次进入 `Settings -> Integrations -> svc.plus 云端同步`
  4. 使用 `review@svc.plus` / `***REMOVED-CREDENTIAL***` 重新登录
  5. 观察同步状态与本地配置状态
- 期望结果
  - 退出后不会继续显示已登录状态
  - 重新登录成功
  - 重新登录后同步状态可恢复
  - 本地已保存的手动 bridge override 不应被异常覆盖
- 建议记录项
  - 退出前后账号状态
  - 重新登录结果
  - 同步前后 endpoint 对比

### `MANUAL-CLOUD-TASKS-001` 云端账号登录后执行五类典型任务

- 前置条件
  - 已完成 `MANUAL-CLOUD-001`
  - 云端同步状态稳定
  - 当前线程可创建新任务
- 操作步骤
  1. 使用 `review@svc.plus` 登录 `svc.plus 云端同步`
  2. 确认账号同步完成
  3. 新建或进入一个测试线程
  4. 依次执行 `TASK-CASE-001` 到 `TASK-CASE-005`
  5. 每个任务完成后记录产物路径和结果摘要
- 期望结果
  - 五类任务均能在云端账号连接上下文下启动
  - 任务产物均归属当前 App 线程
  - 云端账号只读属性不影响正常评审用任务执行
  - 执行过程中不暴露密码、session 或 bridge token 明文
- 建议记录项
  - 登录账号
  - 五类任务的线程 ID
  - 五类任务的产物路径
  - 失败任务的错误摘要

---

## 5. 连接公网 xworkmate-bridge

### `MANUAL-BRIDGE-REMOTE-001` 公网 bridge 使用 `BRIDGE_AUTH_TOKEN`

- 前置条件
  - 当前网络可访问 `https://xworkmate-bridge.svc.plus`
  - 准备公网组合 1 的 `BRIDGE_AUTH_TOKEN`
- 操作步骤
  1. 打开 `Settings -> Integrations`
  2. 切换到 `AI 智能体工作空间`
  3. 在 `Bridge 地址` 输入 `https://xworkmate-bridge.svc.plus`
  4. 在 `鉴权令牌 (TOKEN)` 输入 `***REMOVED-CREDENTIAL***`
  5. 点击 `保存配置`
  6. 重新进入设置页确认配置仍然存在
  7. 发起一次需要 AI 智能体工作空间的任务，确认可建立连接
- 期望结果
  - 配置保存成功
  - 重新进入设置页时 endpoint 保持为公网 bridge 地址
  - token 不以明文展示
  - 任务请求走公网 bridge，而不是本地 `127.0.0.1`
- 建议记录项
  - Bridge 地址
  - token 类型：`BRIDGE_AUTH_TOKEN`
  - 保存结果
  - 任务执行结果摘要
  - 截图点：`AI 智能体工作空间` 保存后的页面

### `MANUAL-BRIDGE-REMOTE-002` 公网 bridge 使用 `BRIDGE_REVIEW_AUTH_TOKEN`

- 前置条件
  - 当前网络可访问 `https://xworkmate-bridge.svc.plus`
  - 准备公网组合 2 的 `BRIDGE_REVIEW_AUTH_TOKEN`
- 操作步骤
  1. 打开 `Settings -> Integrations -> AI 智能体工作空间`
  2. 在 `Bridge 地址` 输入 `https://xworkmate-bridge.svc.plus`
  3. 在 `鉴权令牌 (TOKEN)` 输入 `***REMOVED-CREDENTIAL***`
  4. 点击 `保存配置`
  5. 重新进入设置页确认配置稳定
  6. 发起一次 AI 智能体工作空间任务
- 期望结果
  - 使用 review token 也能保存并建立连接
  - token 不以明文展示
  - 任务侧不会把 review token 写入日志明文
  - 失败时错误信息能区分网络不可达、鉴权失败和服务异常
- 建议记录项
  - Bridge 地址
  - token 类型：`BRIDGE_REVIEW_AUTH_TOKEN`
  - 保存结果
  - 连接或任务结果摘要
  - 是否在页面或日志看到 secret 明文

### `MANUAL-BRIDGE-REMOTE-TASKS-001` 公网 bridge 组合 1 执行五类典型任务

- 前置条件
  - 已完成 `MANUAL-BRIDGE-REMOTE-001`
  - 当前配置使用 `BRIDGE_AUTH_TOKEN`
- 操作步骤
  1. 确认 `Bridge 地址` 为 `https://xworkmate-bridge.svc.plus`
  2. 确认 token 类型为 `BRIDGE_AUTH_TOKEN`
  3. 新建或进入一个测试线程
  4. 依次执行 `TASK-CASE-001` 到 `TASK-CASE-005`
  5. 每个任务完成后重新进入设置页，确认公网 bridge 配置未丢失
- 期望结果
  - 五类任务均通过公网 bridge 组合 1 执行
  - 生成 Markdown、视频、图片系列和 PDF 产物
  - 任务不会回退到本地 `127.0.0.1`
  - bridge token 不出现在页面、任务摘要或普通日志明文中
- 建议记录项
  - token 类型
  - 每类任务产物路径
  - bridge 连接结果
  - 是否出现 endpoint 回退

### `MANUAL-BRIDGE-REMOTE-TASKS-002` 公网 bridge 组合 2 执行五类典型任务

- 前置条件
  - 已完成 `MANUAL-BRIDGE-REMOTE-002`
  - 当前配置使用 `BRIDGE_REVIEW_AUTH_TOKEN`
- 操作步骤
  1. 确认 `Bridge 地址` 为 `https://xworkmate-bridge.svc.plus`
  2. 确认 token 类型为 `BRIDGE_REVIEW_AUTH_TOKEN`
  3. 新建或进入一个测试线程
  4. 依次执行 `TASK-CASE-001` 到 `TASK-CASE-005`
  5. 对比五类任务的启动、执行、产物回写是否与组合 1 一致
- 期望结果
  - review token 能支持五类典型评审任务
  - Markdown、视频、图片系列和 PDF 均能作为产物回写
  - 若某类任务受权限限制失败，错误信息应明确说明鉴权或能力限制
  - 不泄漏 `BRIDGE_REVIEW_AUTH_TOKEN` 明文
- 建议记录项
  - token 类型
  - 五类任务结果摘要
  - 失败任务错误码或错误文案
  - 截图点：最终产物列表

---

## 6. 连接本地 xworkmate-bridge

### `MANUAL-BRIDGE-LOCAL-001` 本地 bridge 使用 `BRIDGE_AUTH_TOKEN`

- 前置条件
  - 本机已启动 `xworkmate-bridge`
  - `http://127.0.0.1:8787` 可访问
  - 准备本地组合的 `BRIDGE_AUTH_TOKEN`
- 操作步骤
  1. 打开 `Settings -> Integrations -> AI 智能体工作空间`
  2. 在 `Bridge 地址` 输入 `http://127.0.0.1:8787`
  3. 在 `鉴权令牌 (TOKEN)` 输入 `***REMOVED-CREDENTIAL***`
  4. 点击 `保存配置`
  5. 发起一次 AI 智能体工作空间任务
  6. 对照本地 bridge 日志确认请求到达
- 期望结果
  - 配置保存成功
  - 任务请求命中本地 bridge
  - 页面不会把公网 bridge 与本地 bridge endpoint 混用
  - 重新进入设置页后仍显示本地 bridge 地址
- 建议记录项
  - 本地 bridge 监听地址
  - App 保存结果
  - 本地 bridge 日志摘要
  - 任务结果摘要

### `MANUAL-BRIDGE-LOCAL-002` 本地 bridge 未启动时的错误提示

- 前置条件
  - 本地 `xworkmate-bridge` 未启动
  - 设置页使用 `http://127.0.0.1:8787`
- 操作步骤
  1. 打开 `Settings -> Integrations -> AI 智能体工作空间`
  2. 保存本地 bridge 地址与 token
  3. 发起一次 AI 智能体工作空间任务
  4. 观察页面错误提示
- 期望结果
  - 保存配置可完成，或给出明确的连接失败提示
  - 任务失败信息明确指向本地 bridge 不可达
  - 不会自动回退到公网 bridge
  - 不会清空用户刚输入的本地配置
- 建议记录项
  - 错误提示文案
  - 任务失败摘要
  - 设置页配置是否保留

### `MANUAL-BRIDGE-LOCAL-TASKS-001` 本地 bridge 执行五类典型任务

- 前置条件
  - 已完成 `MANUAL-BRIDGE-LOCAL-001`
  - 本地 `xworkmate-bridge` 保持运行
- 操作步骤
  1. 确认 `Bridge 地址` 为 `http://127.0.0.1:8787`
  2. 新建或进入一个测试线程
  3. 依次执行 `TASK-CASE-001` 到 `TASK-CASE-005`
  4. 每个任务完成后对照本地 bridge 日志
  5. 重新进入设置页确认本地 bridge 地址仍然保留
- 期望结果
  - 五类任务请求均命中本地 bridge
  - 任务产物正常回写到当前线程
  - 断网或公网不可用时，本地 bridge 任务仍按本地能力给出明确结果
  - 不会自动切换到公网 bridge
- 建议记录项
  - 本地 bridge 日志摘要
  - 五类任务产物路径
  - 是否发生公网 endpoint 混用
  - 截图点：设置页与任务产物

---

## 7. 云端同步与手动配置共存

### `MANUAL-BRIDGE-MIXED-001` 云端账号登录后切换公网 bridge 手动配置

- 前置条件
  - 已使用 `review@svc.plus` 登录
  - 云端同步状态稳定
- 操作步骤
  1. 登录 `svc.plus 云端同步`
  2. 切换到 `AI 智能体工作空间`
  3. 手动输入公网 bridge 组合 1
  4. 点击 `保存配置`
  5. 返回主页面后重新进入设置页
- 期望结果
  - 手动 bridge 配置保存成功
  - 云端账号登录状态不丢失
  - 本地手动配置不会被同一轮页面刷新异常覆盖
  - 页面能区分云端同步状态与 AI 智能体工作空间连接状态
- 建议记录项
  - 登录账号
  - 同步状态
  - 手动配置 endpoint
  - 重新进入设置页后的 endpoint

### `MANUAL-BRIDGE-MIXED-002` 公网 bridge 与本地 bridge 来回切换

- 前置条件
  - 公网 bridge 可访问
  - 本地 bridge 可按需启动
- 操作步骤
  1. 保存公网 bridge 组合 1
  2. 发起一次任务并记录结果
  3. 切换为本地 bridge 组合
  4. 发起一次任务并记录结果
  5. 再次切换回公网 bridge 组合 2
  6. 重新进入设置页确认最终配置
- 期望结果
  - 每次切换后 endpoint 与 token 类型都按用户最后一次保存生效
  - 任务请求不会继续使用旧 endpoint
  - 页面不会出现公网 / 本地配置交叉污染
  - 最终配置以最后一次保存为准
- 建议记录项
  - 三次保存的 endpoint
  - 三次任务结果摘要
  - 最终设置页截图

---

## 8. 回归覆盖矩阵

| 测试编号 | 云端账号 | 公网 Bridge | 本地 Bridge | Secret 隐藏 | 配置持久化 |
|----------|:--------:|:-----------:|:-----------:|:-----------:|:----------:|
| MANUAL-CLOUD-001 | ✅ | ✅ | - | ✅ | ✅ |
| MANUAL-CLOUD-002 | ✅ | ✅ | - | ✅ | ✅ |
| MANUAL-CLOUD-TASKS-001 | ✅ | ✅ | - | ✅ | ✅ |
| MANUAL-BRIDGE-REMOTE-001 | - | ✅ | - | ✅ | ✅ |
| MANUAL-BRIDGE-REMOTE-002 | - | ✅ | - | ✅ | ✅ |
| MANUAL-BRIDGE-REMOTE-TASKS-001 | - | ✅ | - | ✅ | ✅ |
| MANUAL-BRIDGE-REMOTE-TASKS-002 | - | ✅ | - | ✅ | ✅ |
| MANUAL-BRIDGE-LOCAL-001 | - | - | ✅ | ✅ | ✅ |
| MANUAL-BRIDGE-LOCAL-002 | - | - | ✅ | ✅ | ✅ |
| MANUAL-BRIDGE-LOCAL-TASKS-001 | - | - | ✅ | ✅ | ✅ |
| MANUAL-BRIDGE-MIXED-001 | ✅ | ✅ | - | ✅ | ✅ |
| MANUAL-BRIDGE-MIXED-002 | - | ✅ | ✅ | ✅ | ✅ |

## 9. 典型任务覆盖矩阵

| 连接方式 | CASE-001 AI 资讯 MD | CASE-002 图片视频 | CASE-003 7 图系列 | CASE-004 软文矩阵 | CASE-005 图文 PDF |
|----------|:-------------------:|:-----------------:|:-----------------:|:-----------------:|:-----------------:|
| 云端账号 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 公网 bridge 组合 1 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 公网 bridge 组合 2 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 本地 bridge | ✅ | ✅ | ✅ | ✅ | ✅ |

> 注意：以上 token 为评审 / 测试用途。执行测试时不得将 token 明文贴入公开 issue、公开日志或截图备注。
