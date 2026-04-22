# XWorkmate 测试 Case 覆盖矩阵

## 1. 目的

这份文档把当前仓库里已经定义的测试 case 按“主题场景”重新整理为一张更适合日常维护的总表，方便回答以下问题：

- 目前都设计了哪些典型场景
- 哪些场景已经有自动化基础
- 哪些场景目前仍主要依赖手动验证
- 每类 case 的主要落点在什么测试层
- 当前最明显的缺口在哪里

本文是索引与盘点，不替代原始 case 文档。

配套原始文档：

- [核心功能集成测试手动 Case](../cases/core-integration-manual-cases.md)
- [核心功能集成测试自动化规划](./core-integration-auto-test-plan.md)
- [APP 对接外部服务 API 接口测试详细清单](./app-external-service-api-test-matrix.md)
- [Testing Guide](../README_TESTING.md)

## 2. 状态口径

| 状态 | 含义 |
| --- | --- |
| 已设计 | 已在手动 case 或自动化规划中被明确命名和描述 |
| 已自动化 | 已有明确测试文件或 harness 落点，且仓库中存在对应测试基础 |
| 仅手动/待补自动化 | 手动 case 已定义，但自动化仍未完整落地 |
| 部分自动化 | 有底层 suite / fixture / harness，但场景还没有完整闭环 |

## 3. 典型场景总表

| 场景组 | 典型场景 | 当前状态 | 主要测试层 | 主要落点 | 备注 / 当前缺口 |
| --- | --- | --- | --- | --- | --- |
| 设置配置 | 在线账户同步后，远端默认值注入且本地 override 保留 | 已设计 + 已自动化 | runtime / feature | `test/runtime/settings_controller_account_sync_suite.dart` `test/features/settings_page_suite.dart` | 重点检查 secret 不进入普通 snapshot |
| 设置配置 | selfhost ACP 基址派生 `/acp` 与 `/acp/rpc` | 已设计 + 已自动化 | runtime / feature | `test/runtime/acp_endpoint_paths_suite.dart` `test/runtime/external_acp_endpoint_settings_suite.dart` | 需要持续防止路径重复拼接 |
| 设置配置 | local / loopback 允许非 TLS，remote 不允许静默降级 | 已设计 + 已自动化 | runtime / feature | `test/runtime/gateway_endpoint_normalization_suite.dart` `test/runtime/external_acp_endpoint_settings_suite.dart` | 属于安全边界关键 case |
| 设置配置 | 设置页“测试连接”对 hosted / selfhost / local / auth / 失败提示分类正确 | 已设计 + 部分自动化 | feature / integration | `test/features/settings_page_gateway_acp_messages_suite.dart` `integration_test/desktop_settings_flow_test.dart` | 冒烟链路存在，但错误分类覆盖仍应持续补齐 |
| 安全存储 | secret 只进 secure storage，不进普通 settings snapshot | 已设计 + 已自动化 | runtime / feature | `test/runtime/secure_config_store_suite_*.dart` `test/runtime/acp_bridge_server_self_hosted_secret_suite.dart` | 安全敏感，后续改动都应复用这组断言 |
| 本地线程执行 | `pptx` 文档生成并回写当前线程 artifact | 已设计 + 已自动化 | feature / runtime | `test/features/assistant_page_installed_skill_e2e_suite.dart` `test/runtime/app_controller_thread_skills_suite.dart` | 已由 installed-skill harness 验证 |
| 本地线程执行 | `docx` 文档生成并回写当前线程 artifact | 已设计 + 已自动化 | feature / runtime | `test/features/assistant_page_installed_skill_e2e_suite.dart` `test/runtime/app_controller_thread_skills_suite.dart` | 已由 installed-skill harness 验证 |
| 本地线程执行 | `xlsx` 表格生成并回写当前线程 artifact | 已设计 + 已自动化 | feature / runtime | `test/features/assistant_page_installed_skill_e2e_suite.dart` `test/runtime/desktop_thread_artifact_service_test.dart` | 已由 installed-skill harness 验证 |
| 本地线程执行 | `pdf` 生成/合并结果文件并回写当前线程 artifact | 已设计 + 已自动化 | feature / runtime | `test/features/assistant_page_installed_skill_e2e_suite.dart` `test/runtime/app_controller_thread_skills_suite_workspace_fallback.dart` | 已由 installed-skill harness 验证 |
| 本地线程执行 | `image-resizer` 图片处理结果回写当前线程 | 已设计 + 仅手动/待补自动化 | feature / runtime | 规划落点：`test/features/assistant_page_installed_skill_e2e_suite.dart` | 目前在规划文档中明确，但报告里仍属 deferred media |
| 本地线程执行 | 本地浏览器自动化结果回到当前线程，且切线程不串上下文 | 已设计 + 部分自动化 | runtime / feature | `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart` | 有线程隔离基础，浏览器技能闭环仍待补 |
| 在线线程执行 | `image-cog` 在线图像生成任务提交、轮询、产物回传 | 已设计 + 部分自动化 | runtime / feature | `test/runtime/app_controller_thread_skills_suite_acp.dart` | 已有 ACP thread suite 基础，完整 media 闭环待补 |
| 在线线程执行 | `image-video-generation-editting` 长任务轮询并回传图片/视频 | 已设计 + 仅手动/待补自动化 | runtime / feature | 规划落点：`test/runtime/app_controller_thread_skills_suite_acp.dart` | 当前仍以规划和手动 case 为主 |
| 在线线程执行 | `video-translator` 在线翻译/配音并回传结果 | 已设计 + 仅手动/待补自动化 | runtime / feature | 规划落点：`test/runtime/app_controller_thread_skills_suite_acp.dart` | 当前仍以规划和手动 case 为主 |
| 在线线程执行 | 资讯采集返回结构化资讯结果，保留线程归属 | 已设计 + 仅手动/待补自动化 | runtime / feature | 规划落点：`test/runtime/app_controller_thread_skills_suite_thread_isolation.dart` | 当前主要靠手动 case 覆盖 |
| 在线线程执行 | 搜索返回结构化结果，并支持同线程继续追问摘要 | 已设计 + 部分自动化 | runtime / feature | `test/runtime/app_controller_execution_target_switch_suite_thread.dart` `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart` | 线程连续性基础已在，搜索业务闭环仍应补强 |
| 线程连续性 | 同线程连续追问不丢上下文 | 已设计 + 已自动化 | runtime / feature | `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart` `test/runtime/app_controller_assistant_flow_test.dart` | 主线关键 case，已是当前测试重心之一 |
| 线程隔离 | A/B 线程切换后，技能、provider、artifact 不串线 | 已设计 + 已自动化 | runtime | `test/runtime/app_controller_thread_skills_suite_thread_isolation.dart` `test/runtime/app_controller_execution_target_switch_suite_thread.dart` | 当前已有明确 suite |
| 失败恢复 | 错误 endpoint / 失败任务在原线程展示清晰错误，允许原线程重试 | 已设计 + 部分自动化 | runtime / feature | `test/runtime/gateway_acp_client_suite.dart` `test/features/settings_page_gateway_acp_messages_suite.dart` | 线程级失败回退还可继续加强 |
| 结果表面一致性 | 本地执行型与在线执行型都通过统一 result surface 暴露结果 | 已设计 + 部分自动化 | runtime / feature | `test/runtime/desktop_thread_artifact_service_test.dart` | 统一 artifact surface 已有基础，但在线媒体任务仍是缺口 |
| UI 冒烟 | 登录流程、首页流程、桌面导航流程、桌面设置流程 | 已自动化 | integration | `integration_test/login_flow_test.dart` `integration_test/home_flow_test.dart` `integration_test/desktop_navigation_flow_test.dart` `integration_test/desktop_settings_flow_test.dart` | 更偏入口联通验证，不替代业务细场景 |

## 4. 按层看当前测试重点

| 测试层 | 当前主要承担的场景 |
| --- | --- |
| runtime | endpoint 规范化、账户同步、secret 边界、线程归属、provider 切换、artifact 回写、线程隔离 |
| feature | 设置页提示语与输入行为、assistant 页技能选择与提交、installed-skill E2E 壳层闭环 |
| integration | 桌面端导航、设置入口联通、登录与首页 happy path 冒烟 |
| manual | 在线媒体任务、外部服务依赖场景、需要真实服务/真实账号/真实产物确认的 case |

## 5. 当前最值得关注的缺口

### 5.1 媒体类 case 自动化不足

当前文档设计最完整、但自动化落地最薄弱的一组是媒体类能力：

- `image-resizer`
- `image-cog`
- `image-video-generation-editting`
- `video-translator`

现状：

- 手动 case 已定义
- 自动化规划已给出首选落点
- 但已落地的 installed-skill E2E harness 目前只稳定覆盖 `pptx / docx / xlsx / pdf`

参考：

- [2026-03-30 Installed-Skill E2E Harness](../reports/2026-03-30-installed-skill-e2e-harness.md)

### 5.2 在线任务结果面一致性仍需补齐

当前线程、artifact、provider 切换的基础 suite 已经比较完整，但“在线长任务的轮询状态 + 统一 artifact result surface”仍有补强空间，尤其是：

- 长任务中间态是否稳定可见
- 失败是否稳定回写线程消息
- 在线结果是否与本地结果保持统一展示模型

## 6. 建议维护方式

后续新增 case 时，建议同时更新三处：

1. 原始 case 文档
   - 手动验证更新到 [core-integration-manual-cases.md](../cases/core-integration-manual-cases.md)
   - 自动化规划更新到 [core-integration-auto-test-plan.md](./core-integration-auto-test-plan.md)
2. 本总表
   - 更新“当前状态 / 主要落点 / 缺口”
3. 验证记录
   - 如果场景首次自动化落地或完成专项验收，补一份 `docs/reports/` 报告

## 7. 快速结论

如果只看“目前设计的典型测试场景”，当前主线已经比较清晰地覆盖了四个核心面：

- 设置与连接配置
- 本地执行型线程任务
- 在线执行型线程任务
- 线程连续性、隔离与结果面一致性

其中最成熟的是：

- 设置配置与 endpoint/security 边界
- 文档类本地技能线程链路
- 线程隔离与连续追问

其中最需要继续补的是：

- 媒体类技能自动化
- 在线长任务闭环
- 更贴近真实交互的桌面集成回归
