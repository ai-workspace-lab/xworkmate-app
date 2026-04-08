# Flutter + Go 分层测试体系实施模板（业务代码零侵入）

> 目标：在不修改 `lib/` 业务实现的前提下，补齐可落地、可持续演进的测试分层与 CI 模板。

## 1. 推荐目录分层

```text
project_root/
├── test/
│   ├── widget/
│   └── golden/
├── integration_test/
├── patrol_test/
├── go/go_core/
│   └── internal/**/*_test.go
└── .github/workflows/
    ├── pr-tests.yml
    └── release-e2e.yml
```

- `test/widget/`：组件行为与交互局部验证（快）。
- `test/golden/`：视觉基线与 UI 回归（中速）。
- `integration_test/`：关键业务流程主链路（慢）。
- `patrol_test/`：真机/模拟器系统级能力（最慢、最高真实性）。
- `go/go_core/internal/**/*_test.go`：后端 handler/service/repository 单测（快）。

## 2. 本仓库落地约束

1. **不改业务代码**：仅新增测试脚手架、测试文档、CI 编排。
2. **先快后慢**：PR 默认只跑 `widget + go unit (+ 可选 golden)`。
3. **重流程放夜间/发布前**：`integration + patrol` 放 `release-e2e.yml`。
4. **失败可定位**：每一层独立 Job，避免“大锅饭”日志。

## 3. 本地执行命令模板

```bash
# Flutter 依赖
flutter pub get

# 快速反馈层
flutter analyze
flutter test test/widgets test/features test/runtime

# Golden（有目录时）
flutter test test/golden

# Integration
flutter test integration_test

# Patrol（安装后）
patrol test patrol_test

# Go 单元测试
cd go/go_core && go test ./...
```

## 4. Golden 约定（模板）

- 黄金图建议集中在 `test/golden/goldens/`。
- 统一尺寸、字体、主题，降低跨平台漂移。
- 更新基线命令（示例）：

```bash
flutter test test/golden --update-goldens
```

## 5. Patrol 约定（模板）

- `patrol_test/` 覆盖系统权限弹窗、WebView、文件选择、原生交互。
- PR 不强制 Patrol，避免高成本阻塞。
- 发布前执行 `release-e2e.yml` 中 Patrol Job。

## 6. GitHub Actions 分层执行建议

### PR 层（`pr-tests.yml`）

- `analyze`：`flutter analyze`
- `flutter-unit-widget`：`flutter test`（核心 test 目录）
- `go-unit`：`go test ./...`
- `flutter-golden`（可选）：仅当 `test/golden/` 存在并有测试文件时执行

### 发布前层（`release-e2e.yml`）

- `flutter-integration`：关键流程回归
- `patrol`：真机/模拟器系统级流程
- 可选接入人工审批与制品归档

## 7. 增量演进路线

1. 先稳定 PR 快速层（分析 + Flutter 单测 + Go 单测）。
2. 再补 golden 基线（页面级视觉回归）。
3. 然后扩展 integration_test 核心路径。
4. 最后补 Patrol 的系统级场景，绑定发布前门禁。

## 8. 验收清单（模板）

- [ ] PR 在 10~15 分钟内完成快速反馈。
- [ ] Go 与 Flutter 测试失败可单层定位。
- [ ] Golden 回归有固定目录与更新机制。
- [ ] integration_test 覆盖关键业务主路径。
- [ ] Patrol 覆盖至少 1 条权限或系统弹窗关键流。
