# 测试验收报告 — Single Agent 重构

> 生成时间: `2026-03-23T10:51:00`
> 分支: `main` (未提交)
> 测试范围: `test/runtime/app_controller_ai_gateway_chat_suite.dart`, `test/runtime/secure_config_store_suite.dart`, `test/runtime/app_controller_execution_target_switch_suite.dart`, `test/features/assistant_page_suite.dart`

---

## 测试命令与结果

| # | 命令 | 结果 |
|---|------|------|
| 1 | `flutter analyze` | ✅ PASS — No issues found (2.6s) |
| 2 | `flutter test test/runtime/app_controller_ai_gateway_chat_suite.dart` | ✅ PASS — 5/5 |
| 3 | `flutter test test/runtime/secure_config_store_suite.dart` | ✅ PASS — 19/19 |
| 4 | `flutter test test/runtime/app_controller_execution_target_switch_suite.dart` | ✅ PASS — 10/10 |
| 5 | `flutter test test/features/assistant_page_suite.dart` | ✅ PASS — 13/13 (6 skip) |

---

## 重点验证点覆盖

> 注: 本报告形成于 ACP-only 收敛之前；下面的测试名已在后续版本中被 ACP-only 语义替换。

| 验证点 | 对应测试用例 | 状态 |
|--------|-------------|------|
| Single Agent 线程优先走外部 CLI | 历史用例，现已替换为 ACP-only provider 路由校验 | ✅ |
| 外部 CLI 不可用时返回明确错误 | 历史用例，现已替换为 ACP-only 不自动降级校验 | ✅ |
| singleAgentProvider 线程级持久化兼容旧值 | `SettingsSnapshot keeps compatibility with legacy target json values`<br>`AssistantThreadRecord keeps compatibility with legacy json payloads` | ✅ |
| Assistant 页面 provider chip 无回归 | `AssistantPage shows Single Agent chip and keeps task rows minimal`<br>`AssistantPage shows Single Agent provider selector on the right` | ✅ |
| 自动滚动无回归 | Suite 整体通过 | ✅ |

---

## 失败项

**无**

---

## 高风险回归点

**无高风险项。** 所有目标验证点均被测试套件覆盖且通过。

---

## 建议人工补测项

1. **端到端 Single Agent CLI 拉起**
   - 单元测试 mock 了外部进程调用
   - 需在真实环境验证 Claude CLI 安装/路径探测逻辑

2. **并发切换执行目标时的竞态**
   - 测试覆盖了顺序切换
   - 真实用户快速切换时的状态同步建议人工复现

3. **旧版持久化数据迁移路径**
   - 测试覆盖了 legacy json 兼容性
   - 建议在真实设备上从旧版本升级验证迁移

---

## 相关文件

- 测试套件: `test/runtime/app_controller_ai_gateway_chat_suite.dart`
- 测试套件: `test/runtime/secure_config_store_suite.dart`
- 测试套件: `test/runtime/app_controller_execution_target_switch_suite.dart`
- 测试套件: `test/features/assistant_page_suite.dart`
- 历史实现说明: 早期 single-agent shim 已在 ACP 控制面统一后删除
