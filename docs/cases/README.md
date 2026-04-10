# 核心集成测试 Cases

`docs/cases/` 只保留当前项目主线需要长期维护的手动集成用例，不再承载旧的多 Agent / ARIS / 外部桥接历史 case。

## 当前入口

- [核心功能集成测试手动 Case](./core-integration-manual-cases.md)

## 配套文档

- [核心功能集成测试自动化规划](../testing/core-integration-auto-test-plan.md)
- [测试 Case 覆盖矩阵](../testing/test-case-coverage-matrix.md)
- [XWorkmate 测试规范模板与指南](../testing/xworkmate-test-spec.md)
- [XWorkmate 测试规范](../quality/xworkmate-test-spec.md)

## 使用建议

推荐顺序：

1. 先看自动化规划，确认当前能力树与测试落点
2. 再按手动 Case 执行设置页与任务线程验证
3. 执行后把证据记录回具体测试单或验收报告

## 维护边界

- 这里不再新增历史回溯型 postmortem 或旧架构演示 case
- 与当前主线不匹配的多 Agent / ARIS / 外部 CLI bridge 案例已移除
- 如果新增长期手动用例，必须挂到当前“设置页配置”或“任务线程”能力树下
