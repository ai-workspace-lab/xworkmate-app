# 核心功能集成测试自动化规划

## 1. 文档目标

这份文档用于把当前项目主线整理成一套可直接落到现有测试 harness 的自动化规划，服务于后续增量实现，而不是重新设计新的测试框架。

覆盖范围只保留两大模块：

- 设置页面配置功能
- 任务线程场景测试

本文默认当前真实拓扑如下：

- 在线用户同步会向本地设置注入远程默认值
- ACP 支持 selfhost 远程服务端
- ACP 支持 local / loopback 模式
- 线程执行同时覆盖本地执行型任务与在线执行任务

## 2. 现有可复用测试基础

后续实现优先扩展现有测试，而不是新增平行体系。

### 2.1 runtime 层

- `test/runtime/settings_controller_account_sync_suite.dart`
- `test/runtime/external_acp_endpoint_settings_suite.dart`
- `test/runtime/acp_endpoint_paths_suite.dart`
- `test/runtime/gateway_endpoint_normalization_suite.dart`
- `test/runtime/app_controller_thread_skills_suite.dart`
- `test/runtime/app_controller_execution_target_switch_suite.dart`
- `test/runtime/desktop_thread_artifact_service_test.dart`

### 2.2 feature 层

- `test/features/settings_page_gateway_acp_messages_suite.dart`
- `test/features/settings_page_suite.dart`
- `test/features/web_settings_page_external_acp_suite.dart`
- `test/features/assistant_page_installed_skill_e2e_suite.dart`

### 2.3 integration 层

- `integration_test/desktop_settings_flow_test.dart`
- `integration_test/desktop_navigation_flow_test.dart`

### 2.4 已有 harness 结论

已存在的 installed-skill E2E harness 已验证：

- `pptx`
- `docx`
- `xlsx`
- `pdf`

参考：

- `docs/reports/2026-03-30-installed-skill-e2e-harness.md`

后续新增覆盖优先把这套 harness 扩展到：

- `image-resizer`
- 本地浏览器自动化
- `image-cog`
- `image-video-generation-editting`
- `video-translator`
- 资讯采集
- 搜索

## 3. 分层约束

### 3.1 runtime

用于验证：

- endpoint 规范化
- 账户同步与 settings snapshot
- 线程身份、技能绑定、artifact 写回、线程隔离
- local / remote 模式切换与 provider 选择

### 3.2 feature

用于验证：

- 设置页输入、提示语、错误分类
- assistant 页技能选择、提交、结果表面
- 已安装技能对 UI 壳层的最小可见性

### 3.3 integration

用于验证：

- 桌面端设置入口与关键 happy path 冒烟
- 页面切换后配置可见性
- 线程入口与设置入口的真实联通

## 4. 通用断言基线

所有首批自动化用例默认都要尽量覆盖以下断言：

- 线程 ID 连续且不会串线程
- 技能绑定到当前线程，不串 provider
- 结果写入当前线程 workspace 或 artifact snapshot
- 本地执行型与在线执行型都通过同一结果表面暴露产物
- secret 不进入普通 settings snapshot
- local 模式允许明确的非 TLS 边界，remote 模式不允许静默降级
- 错误信息按配置错误、连接失败、鉴权失败、任务失败分层呈现

## 5. 设置页面配置功能

### `ACP-CONFIG-001` 在线用户同步成功且 secret 不落 settings snapshot

- 测试目标
  - 验证在线用户同步会注入远程默认配置，但 secret 只留在 secure storage 或运行时态，不进入普通 snapshot。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - 复用 `SettingsController` 账户同步假服务
  - 提供远程配置 payload，包含 endpoint、provider、secret 引用位
- 关键断言
  - 同步后 endpoint 与 provider 被注入本地设置
  - settings snapshot 不包含 token/password/API key 明文
  - 本地 override 仍可覆盖远程默认值
- 失败分类
  - 同步失败
  - snapshot 泄露 secret
  - 远程默认值覆盖用户 override
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/settings_controller_account_sync_suite.dart`
  - UI 显示补充到 `test/features/settings_page_suite.dart`

### `ACP-CONFIG-002` selfhost ACP 基址输入后正确派生 `/acp` 与 `/acp/rpc`

- 测试目标
  - 验证设置页输入 selfhost 基址后，内部派生出的 websocket / RPC 路径符合当前 ACP 规则。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - 复用 endpoint normalization 与 external endpoint settings 相关 fixture
  - 基址样例覆盖：
    - `https://host.example.com/opencode`
    - `https://host.example.com/codex`
- 关键断言
  - 基址派生 `.../acp`
  - RPC 派生 `.../acp/rpc`
  - 不重复拼接已存在的 `/acp`
  - UI 回显与内部值一致
- 失败分类
  - path 重复拼接
  - RPC 路径丢失
  - 基址与回显不一致
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/acp_endpoint_paths_suite.dart`
  - 兼并到 `test/runtime/external_acp_endpoint_settings_suite.dart`
  - 设置页提示补充到 `test/features/settings_page_gateway_acp_messages_suite.dart`

### `ACP-CONFIG-003` local ACP loopback 模式允许非 TLS，remote 模式不允许静默降级

- 测试目标
  - 明确 local / loopback 与 remote transport trust boundary。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - endpoint normalization fixtures
  - loopback host 样例：
    - `http://127.0.0.1:9001/opencode`
    - `ws://127.0.0.1:9001/codex`
  - remote host 样例：
    - `http://example.com/opencode`
- 关键断言
  - loopback/local 模式可接受非 TLS
  - remote 模式遇到非 TLS 时给出明确错误或阻止提交
  - remote 模式不会 silently rewrite 成 insecure transport
- 失败分类
  - loopback 被误拦截
  - remote 静默降级
  - 错误分类不清晰
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/gateway_endpoint_normalization_suite.dart`
  - 连接策略落到 `test/runtime/external_acp_endpoint_settings_suite.dart`
  - 表单提示补充到 `test/features/settings_page_gateway_acp_messages_suite.dart`

### `ACP-CONFIG-004` 设置页测试连接对 hosted base URL、自定义 auth、失败提示语分类正确

- 测试目标
  - 验证设置页“测试连接”在 hosted、自定义 auth、空 auth、连接失败等路径下给出稳定反馈。
- 推荐测试层级
  - `feature`
  - `integration`
- 前置依赖与假服务
  - fake gateway client
  - hosted / selfhost / local 三类 endpoint fixture
  - fake failure 分类：
    - 鉴权失败
    - 空响应
    - 网络失败
- 关键断言
  - 按配置类型显示正确提示文案
  - 成功时状态更新为已连接或已验证
  - 失败时文案可区分空响应、认证失败、网络失败
- 失败分类
  - 所有失败收敛成同一文案
  - 成功失败状态混乱
  - UI 不回显当前配置来源
- 后续实现建议文件落点
  - 首选扩展 `test/features/settings_page_gateway_acp_messages_suite.dart`
  - Web 设置页差异补充到 `test/features/web_settings_page_external_acp_suite.dart`
  - 桌面 happy path 冒烟补充到 `integration_test/desktop_settings_flow_test.dart`

## 6. 任务线程场景测试

### 6.1 通用 harness 规则

线程类测试优先复用 installed-skill E2E harness 与 thread skill runtime suite，统一要求：

- 当前线程内技能绑定正确
- prompt 进入真实 controller 提交路径
- 结果写入 thread workspace / artifact snapshot
- provider / mode / thread 三个维度相互隔离

首选落点：

- `test/features/assistant_page_installed_skill_e2e_suite.dart`
- `test/runtime/app_controller_thread_skills_suite.dart`
- `test/runtime/app_controller_execution_target_switch_suite.dart`
- `test/runtime/desktop_thread_artifact_service_test.dart`

### 6.2 本地执行型

#### `THREAD-LOCAL-001` `pptx` 在当前线程绑定、提交、产物回写

- 测试目标
  - 验证 `pptx` 技能从当前线程选中、提交到结果产物落盘的完整链路。
- 推荐测试层级
  - `feature`
  - `runtime`
- 前置依赖与假服务
  - 已安装技能共享根目录 fixture
  - 确定性 artifact writer
- 关键断言
  - 当前线程记录绑定 `pptx`
  - 产物进入当前线程 workspace
  - artifact snapshot 可见 `.pptx` 结果
- 失败分类
  - 技能未绑定
  - 结果写到错误线程
  - artifact snapshot 不刷新
- 后续实现建议文件落点
  - 扩展 `test/features/assistant_page_installed_skill_e2e_suite.dart`
  - 必要时补到 `test/runtime/app_controller_thread_skills_suite_shared_roots.dart`

#### `THREAD-LOCAL-002` `docx`

- 测试目标
  - 验证 `docx` 本地文档生成链路与线程绑定一致。
- 推荐测试层级
  - `feature`
  - `runtime`
- 前置依赖与假服务
  - 同 `pptx` harness
- 关键断言
  - 当前线程技能为 `docx`
  - 产物后缀与 artifact metadata 正确
  - 二次追问仍引用同一线程上下文
- 失败分类
  - 技能/产物元信息不一致
  - 连续追问丢线程
- 后续实现建议文件落点
  - 扩展 `test/features/assistant_page_installed_skill_e2e_suite.dart`
  - 线程连续性扩展 `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart`

#### `THREAD-LOCAL-003` `xlsx`

- 测试目标
  - 验证表格任务在当前线程生成并回写结果。
- 推荐测试层级
  - `feature`
  - `runtime`
- 前置依赖与假服务
  - 同 installed-skill harness
- 关键断言
  - 产物路径进入当前线程 workspace
  - artifact snapshot 里能看到 `.xlsx`
  - 不会误落到共享根目录或其他线程目录
- 失败分类
  - 产物路径越界
  - artifact snapshot 漏刷新
- 后续实现建议文件落点
  - 扩展 `test/features/assistant_page_installed_skill_e2e_suite.dart`
  - 产物归属补到 `test/runtime/desktop_thread_artifact_service_test.dart`

#### `THREAD-LOCAL-004` `pdf`

- 测试目标
  - 验证 PDF 工具链在当前线程中以本地执行型方式完成。
- 推荐测试层级
  - `feature`
  - `runtime`
- 前置依赖与假服务
  - 同 installed-skill harness
- 关键断言
  - 当前线程与 `pdf` 技能绑定
  - 结果作为 artifact 返回，而不是只停留在流式文本
  - 失败时保留线程内错误摘要
- 失败分类
  - 只返回文本不回写 artifact
  - 失败状态丢失
- 后续实现建议文件落点
  - 扩展 `test/features/assistant_page_installed_skill_e2e_suite.dart`
  - 失败回写补到 `test/runtime/app_controller_thread_skills_suite_workspace_fallback.dart`

#### `THREAD-LOCAL-005` `image-resizer`

- 测试目标
  - 把媒体类中的本地图片处理纳入已安装技能 harness。
- 推荐测试层级
  - `feature`
  - `runtime`
- 前置依赖与假服务
  - 新增本地图片处理 skill fixture
  - 确定性输出文件名
- 关键断言
  - `image-resizer` 被识别为本地执行型
  - 输出图片进入当前线程 artifact snapshot
  - 输出 metadata 标识批处理或尺寸变化摘要
- 失败分类
  - 媒体技能被误分到在线执行
  - 结果文件未进入线程产物面
- 后续实现建议文件落点
  - 首选扩展 `test/features/assistant_page_installed_skill_e2e_suite.dart`
  - provider / mode 归类补到 `test/runtime/app_controller_execution_target_switch_suite_thread.dart`

#### `THREAD-LOCAL-006` 本地浏览器自动化

- 测试目标
  - 验证本地浏览器自动化技能走本地执行路径，且结果仍回到线程 artifact / 文本摘要表面。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - browser automation skill fixture
  - fake browser result payload
- 关键断言
  - 当前线程内 mode 为本地执行
  - 执行结果包含摘要与可选产物记录
  - 切换线程后不会复用上一线程浏览器上下文
- 失败分类
  - 浏览器自动化被归到远程 provider
  - 线程切换后结果串线
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart`
  - 壳层可见性补到 `test/features/assistant_page_installed_skill_e2e_suite.dart`

### 6.3 在线执行型

#### `THREAD-ONLINE-001` `image-cog`

- 测试目标
  - 验证图像生成在线任务的提交、轮询、产物回传与线程归属。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - fake remote provider / ACP task status poller
  - 远程图片 artifact fixture
- 关键断言
  - 线程内 provider 标识为在线执行
  - 任务状态从提交进入完成
  - 图片产物进入当前线程 artifact snapshot
- 失败分类
  - 状态轮询中断
  - 产物回传到错误线程
  - provider 标识错误
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/app_controller_thread_skills_suite_acp.dart`
  - UI 壳层补到 `test/features/assistant_page_installed_skill_e2e_suite.dart`

#### `THREAD-ONLINE-002` `image-video-generation-editting`

- 测试目标
  - 验证图片/视频在线生成编辑链路的长任务管理。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - fake long-running remote task
  - image-to-video / text-to-video 结果 fixture
- 关键断言
  - 长任务状态可轮询
  - 最终视频或图片产物进入当前线程
  - 失败状态会回写线程消息而不是静默结束
- 失败分类
  - 长任务无状态
  - 结束但无产物
  - 失败静默
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/app_controller_thread_skills_suite_acp.dart`
  - 必要时新增 sibling suite：`test/runtime/app_controller_thread_skills_suite_media_remote.dart`

#### `THREAD-ONLINE-003` `video-translator`

- 测试目标
  - 验证视频翻译/配音任务的在线提交与出片产物回传。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - fake remote translation job
  - 带字幕/带配音结果 fixture
- 关键断言
  - 线程内保留任务状态摘要
  - 成功时回传视频或字幕产物
  - 失败时线程中可见错误摘要与重试入口状态
- 失败分类
  - 任务状态与线程消息脱节
  - 只有文本结果无实际产物
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/app_controller_thread_skills_suite_acp.dart`
  - 结果面一致性补到 `test/runtime/desktop_thread_artifact_service_test.dart`

#### `THREAD-ONLINE-004` 资讯采集

- 测试目标
  - 验证资讯采集在在线执行模式下返回结构化结果，且与线程上下文绑定。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - fake fetch/search provider
  - 结构化 article list fixture
- 关键断言
  - 线程中保留查询条件与结果摘要
  - article list 结构化字段完整
  - 结果不会串到其他线程的搜索结果中
- 失败分类
  - 结构化字段缺失
  - 采集结果串线
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart`
  - UI 结果面补到 `test/features/assistant_page_installed_skill_e2e_suite.dart`

#### `THREAD-ONLINE-005` 搜索

- 测试目标
  - 验证搜索任务在线执行时的结果结构和线程归属。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - fake search provider
  - top-N 搜索结果 fixture
- 关键断言
  - 当前线程消息记录本次查询
  - 搜索结果结构完整
  - 后续追问复用同一线程而不是新建孤立任务
- 失败分类
  - 查询记录缺失
  - 连续追问断链
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/app_controller_execution_target_switch_suite_thread.dart`
  - 连续追问行为补到 `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart`

## 7. 线程连续性与隔离

### `THREAD-CROSS-001` 同线程连续追问不丢上下文

- 测试目标
  - 验证本地执行型与在线执行型在完成一次任务后，都能继续在同一线程追问。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - 已有 thread skill fixtures
  - 至少一条本地执行与一条在线执行样例
- 关键断言
  - 第二次提问复用原线程 ID
  - 上下文引用到第一次任务结果
  - 不会因 provider 切换而新建错误线程
- 失败分类
  - 线程 ID 重置
  - 上下文丢失
  - provider 切换导致错绑
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart`
  - UI 壳层最小补充到 `test/features/assistant_page_suite_core.dart`

### `THREAD-CROSS-002` 切换线程后技能、产物、状态不串线

- 测试目标
  - 验证多线程场景下技能选择、artifact、provider 状态严格归属当前线程。
- 推荐测试层级
  - `runtime`
- 前置依赖与假服务
  - 多线程 fixture
  - 每线程不同技能与不同 artifact
- 关键断言
  - 线程 A 的 artifact 不出现在线程 B
  - 线程 B 的 provider 状态不污染线程 A
  - 当前线程右上角状态只反映当前线程
- 失败分类
  - artifact 串线
  - 状态面串线
  - 技能选择残留
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart`
  - 如需状态面验证，补到 `test/runtime/app_controller_execution_target_switch_suite_thread.dart`

### `THREAD-CROSS-003` 本地执行型与在线执行型在 artifact / result surface 上表现一致

- 测试目标
  - 保证用户无论走本地还是在线执行，结果面都遵循统一模型。
- 推荐测试层级
  - `runtime`
  - `feature`
- 前置依赖与假服务
  - 一组本地执行 fixture
  - 一组在线执行 fixture
- 关键断言
  - 两类任务都能回写 artifact snapshot
  - 消息摘要格式遵循统一 result surface
  - 不要求用户切换不同浏览入口查看结果
- 失败分类
  - 本地只有 artifact，在线只有文本
  - 结果面模型不一致
- 后续实现建议文件落点
  - 首选扩展 `test/runtime/desktop_thread_artifact_service_test.dart`
  - 壳层可见性补到 `test/features/assistant_page_installed_skill_e2e_suite.dart`

## 8. 实施顺序建议

### P0

- `ACP-CONFIG-001`
- `ACP-CONFIG-002`
- `ACP-CONFIG-003`
- `ACP-CONFIG-004`
- `THREAD-LOCAL-005`
- `THREAD-LOCAL-006`
- `THREAD-ONLINE-001`
- `THREAD-ONLINE-002`
- `THREAD-ONLINE-003`
- `THREAD-ONLINE-004`
- `THREAD-ONLINE-005`
- `THREAD-CROSS-001`
- `THREAD-CROSS-002`
- `THREAD-CROSS-003`

### 已有基础可复用项

以下能力优先在现有 harness 上扩断言，而不是重写：

- `THREAD-LOCAL-001`
- `THREAD-LOCAL-002`
- `THREAD-LOCAL-003`
- `THREAD-LOCAL-004`

## 9. 完成标准

这份自动化规划被视为可执行，需要满足：

- 每个首批 case 都有明确首选落点
- 不引入新的测试框架名词
- 能直接映射到 `runtime / feature / integration` 三层
- 每个 case 都有可实现的依赖与 fake service 提示
- 每个 case 都有可验证断言与失败分类
