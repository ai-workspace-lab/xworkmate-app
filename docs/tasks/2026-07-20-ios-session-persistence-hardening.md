# iOS 本地会话持久化加固记录(P0 / P1)

> 日期:2026-07-20(Asia/Shanghai)
> 范围:`lib/runtime` 存储层、`lib/app` 线程恢复、`ios/Runner` 工程
> 目标:历史任务会话在重启 / 升级 / 后台被杀场景下不丢;同时满足 iOS 上架规范(Data Storage Guidelines、密钥安全存储)。
> 状态:**P0 全部合并;P1 三项中 #170 / #171 已合并,#172(Keychain)待合并。真机端到端验收待设备重新连接后执行,清单见 [ios-session-persistence-manual-cases](../cases/ios-session-persistence-manual-cases.md)。**
> 前情:会话丢失第六轮排查(逐条容错加载)见 [2026-07-16-openclaw-ios-artifact-return-handoff](2026-07-16-openclaw-ios-artifact-return-handoff.md) §0.1;本文承接其后的结构性加固。

## 0. 任务进度总览

| 项 | 内容 | 结论 | 交付 |
|---|---|---|---|
| 评估 | 对照 iOS 规范盘点存储现状:位置 ✅、原子写 ✅、逐条恢复 ✅;绝对容器路径 ❌、密钥明文文件 ❌、备份策略未显式化 ⚠️ | 四个偏离点,两个构成丢失根因候选 | 评估记录(会话内),丢失场景矩阵 |
| P0-1 | 容器 UUID 随升级/重装漂移,持久化的 localFs 绝对路径全部悬空;激活中的会话有 ensure 自愈,**从不被激活的历史线程没有** | restore 时对托管形态路径(`…/.xworkmate/threads/<key>`)重定位到当次容器基准,迁移落盘一次 | [#168](https://github.com/ai-workspace-lab/xworkmate-app/pull/168) 已合并;chain map 新增 S1a |
| P0-2 | 生命周期 flush 疑似缺口 | **无需改码**:每条消息即时持久化(`replace` 默认 `persist:true`),`app.dart` 已在 inactive/paused/detached/hidden 触发 flush;极端场景由原子写兜底,`await` 救不了写一半被杀 | 证据记录,零代码变更 |
| 清理 | #168 误提交 8 张 golden 失败截图 | 删除 + `.gitignore` 收宽为 `test/**/failures/` | [#169](https://github.com/ai-workspace-lab/xworkmate-app/pull/169) 已合并 |
| P1-5 | 制品可从 bridge 重拉,不应计入 iCloud 备份(App Review 2.23 历史雷区) | AppDelegate 启动对 `Documents/.xworkmate` 打 `isExcludedFromBackup`,目录级覆盖子树;会话历史(App Support)保持默认备份 | [#170](https://github.com/ai-workspace-lab/xworkmate-app/pull/170) 已合并 |
| P1-3 | `threads.json` 单文件全量重写:O(全部历史)/次,一个坏字节威胁整表 | 每会话一文件 + `index.json` 排序;save 按脏会话 diff;坏一个文件只丢一个会话;孤儿文件恢复;legacy 单向迁移 `.migrated-*.bak` 退役 | [#171](https://github.com/ai-workspace-lab/xworkmate-app/pull/171) 已合并;chain map 新增 S1-storage |
| P1-4 | 密钥迁 Keychain,重装语义需拍板 | **重装即登出**(见 §1);`first_unlock_this_device` + 沙盒哨兵,升级路径单向迁移 `.secret` 文件 | [#172](https://github.com/ai-workspace-lab/xworkmate-app/pull/172) 待合并 |
| 遗留 | 见 §2 | — | — |

## 1. 决策记录:重装即登出(2026-07-20)

**背景**:iOS Keychain 数据跨卸载重装保留。若不处理,删 App 重装后 bridge token 仍在,可能自动恢复登录态——与"卸载=清数据"的用户直觉相悖,也与安全基线"signed-out 即断开"的精神需要额外对齐。

**决定**:重装即登出。实现锚点:

- 沙盒密钥目录内哨兵文件 `.keychain-bound` 随容器生灭;
- 启动绑定时哨兵缺失 → 先 `deleteAll()` 清 Keychain 残留,再做 `.secret` 文件迁移,最后写哨兵——**清残留先于迁移写入**,顺序有测试钉住;
- Accessibility `first_unlock_this_device`:不进 iCloud Keychain 同步、不随备份跨设备。

**被否方案**:利用 Keychain 跨重装特性保留登录态(体验好,但语义突变且需重新论证安全边界);维持明文文件(违反安全基线第 11 条)。

## 2. 遗留与跟进

1. **真机验收未做**(设备离线):重装登出、升级迁移、路径重基、备份排除四条链路需过一遍,清单见 [manual cases](../cases/ios-session-persistence-manual-cases.md)。#170 的 RunnerTests XCTest 同样待设备补跑(`build-for-testing` 已编译通过)。
2. **负载敏感 flaky 测试**:`app_controller_thread_workspace_binding_test.dart` › "records workspace files produced during an empty-artifact task run"——测试把旧文件写入与 `startedAtMs` 只隔几毫秒,机器忙时 mtime 过滤窗口吞掉间隔,全量跑必现、空载单跑 3/3 过,**与本工作流各 PR 无关**(main 基线同样复现)。已立独立跟进任务:修测试(旧文件 mtime 显式回拨)或收窄实现容差。
3. **`make ios-pods` 目标失效**:工程已迁 SPM,`ios/` 下无 Podfile,`ios-pods` / `ios-pods-check` / 依赖它们的 `build-ios-release-no-codesign` / `verify-ios-release` 本地全部跑不通,待修 Makefile。
4. 隐私清单 `NSPrivacyCollectedDataTypes` 目前为空,而 App 登录会向 svc.plus 传账号邮箱;App Store Connect 的 nutrition labels 与 manifest 是否对齐,上架前需人工核对。

## 3. 验证汇总

- #168:绑定测试新增未激活线程重定位用例;全量绿。
- #171:16 条存储测试(8 legacy 容错保持 + 8 新布局);全量 423/423。
- #172:7 条绑定/迁移单测;analyze 全仓干净;`flutter build ios --release` 成功(SPM 插件集成验证);全量 429/430(唯一失败即 §2.2 的既有 flaky)。
