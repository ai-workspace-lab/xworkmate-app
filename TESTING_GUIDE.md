# Testing Guide - XWorkmate

## 测试架构

本项目集成了三种自动化测试能力，验证五层架构：

1. **Golden Test** - UI视觉回归测试 (Layer 2, 3, 4, 5)
2. **integration_test** - 功能流程测试 (全架构层)
3. **Patrol** - 增强E2E + 原生交互测试 (全架构层)

### 架构对应关系

| 架构层 | 组件 | 测试覆盖 |
|--------|------|----------|
| Layer 1 | Access & Attribution | Patrol |
| Layer 2 | Multi-end UI Shell | Golden, Integration |
| Layer 3 | TaskThread Control Plane | Golden, Integration |
| Layer 4 | GoTaskService Dispatch | Golden, Integration |
| Layer 5 | Service Integration | Golden, Integration |
| Cross-cutting | Security & Persistence | Integration |

## 目录结构

```
test/
├── golden/
│   ├── golden_test.dart           # 基础Golden测试
│   ├── architecture_golden_test.dart # 架构层Golden测试
│   └── goldens/                   # Golden截图文件
├── integration_test/
│   ├── test_support.dart          # 集成测试支持
│   ├── architecture_layers_test.dart  # 架构层测试
│   ├── architecture_integration_test.dart # 架构流程测试
│   ├── desktop_navigation_flow_test.dart
│   └── desktop_settings_flow_test.dart
├── patrol_test/
│   ├── app_test.dart              # Patrol基础测试
│   └── architecture_patrol_test.dart # 架构Patrol测试
└── features/                      # Feature测试
    ├── assistant_page_suite*.dart
    ├── settings_page_suite*.dart
    └── ...
```

## 运行测试

### Golden 测试

```bash
# 运行所有Golden测试
flutter test test/golden/

# 更新Golden文件（UI变更后）
flutter test test/golden/ --update-goldens

# 仅更新特定文件
flutter test test/golden/golden_test.dart --update-goldens
```

### Widget 测试

```bash
# 运行所有widget测试
flutter test

# 运行特定测试文件
flutter test test/widget_test.dart

# 运行features测试
flutter test test/features/settings_page_test.dart
flutter test test/features/assistant_page_test.dart
```

### Integration 测试

```bash
# 运行integration测试
flutter test integration_test/

# 使用指定设备
flutter test integration_test/ -d macOS

# 运行架构层测试
flutter test integration_test/architecture_layers_test.dart
flutter test integration_test/architecture_integration_test.dart
```

### Patrol 测试

```bash
# 安装Patrol CLI
dart pub global activate patrol

# 运行Patrol测试
flutter pub run patrol test

# 运行特定测试
flutter pub run patrol test patrol_test/app_test.dart

# 运行架构测试
flutter pub run patrol test patrol_test/architecture_patrol_test.dart
```

## CI/CD 流程

### PR 阶段
```yaml
- flutter test test/golden/           # Golden UI测试
- flutter test integration_test/      # 集成测试
- flutter test test/features/         # Feature测试
- flutter test test/runtime/          # Runtime测试
```

### Release 阶段
```yaml
- flutter pub run patrol test         # 真机E2E
```

## 添加新测试

### Golden 测试示例
```dart
testGoldens('page should match golden', (tester) async {
  await tester.pumpWidgetBuilder(MyPage());
  await tester.pumpAndSettle();
  await screenMatchesGolden(tester, 'page_name');
});
```

### Integration 测试示例
```dart
testWidgets('flow test', (tester) async {
  await pumpDesktopApp(tester);
  await tester.tap(find.byKey(Key('my_button')));
  await tester.pumpAndSettle();
});
```

### Patrol 测试示例
```dart
patrolTest('native interaction', ($) async {
  await $.pumpWidgetAndSettle(MyApp());
  await $.tap(find.byKey(Key('my_button')));
});
```

## Key 使用规范

所有测试使用 `Key` 定位元素：

```dart
// 正确
find.byKey(const Key('my_element'))

// 避免flaky
find.text('Submit')      // 可能本地化变化
find.byType(TextField)  // 可能多个实例
```

## 已知问题

- widget_test.dart 需要AppController完整初始化，当前被跳过
- integration_test需要macOS设备运行
- Patrol测试需要真实设备或模拟器

## Architecture Tests 覆盖

### Layer 2: 多端UI层
- AppShellDesktop加载
- 导航Tab切换
- 页面渲染

### Layer 3: TaskThread控制面
- 主线程存在性验证
- 新线程创建
- 线程切换
- ContextState管理

### Layer 4: GoTaskService调度
- ExecutionBinding分发
- Settings默认继承

### Layer 5: 服务集成
- Gateway配置持久化
- Provider绑定

### Cross-cutting: 安全与持久化
- 线程记录跨重载持久化
