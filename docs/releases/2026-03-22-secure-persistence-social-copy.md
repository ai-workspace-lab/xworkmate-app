# 2026-03-22 Secure Persistence Social Copy

## X

```text
XWorkmate 刚发了一个很关键的稳定性补丁：

修复了 macOS App 在重启 / 覆盖安装后，本地 Gateway 配置、已保存凭证和任务会话可能丢失的问题。

这次没有改 UI，重点是把本地 settings、assistant threads 和 recovery backup 全部切到 secure-storage 前提下的 sealed persistence。

结果很直接：
- 重启后状态不再丢
- 覆盖安装后状态继续保留
- 本地 snapshot / backup 不再明文落盘

#Flutter #macOS #AIGateway #SecurityEngineering
```

## 领英

```text
我们刚完成了 XWorkmate 一次很典型、也很值得发出来的桌面应用可靠性修复。

问题表面上看是“App 重启后本地配置丢失”，但根因并不只是一个保存 bug。我们最终定位到几层叠加问题：

1. Secure storage 读写被硬性套了 400ms 超时，超时后直接退化成“只存内存”
2. 本地 settings / task session 的恢复链路里还残留 plaintext migration 路径
3. Assistant thread 的异步持久化存在晚到覆盖新状态的竞态

这次修复后，我们把本地持久层重构为：

- FlutterSecureStorage 作为 secret 和 local-state key 的主信任根
- SettingsSnapshot、assistant thread records、recovery backup 统一做 AES-GCM sealed persistence
- SQLite 不可用时，仍通过 sealed durable files 保证可恢复
- secure storage 失败时，长期 secret 进入 durable fallback，而不是消失在会话内存里

对用户来说，变化是简单的：

- 重启后，Gateway 配置和任务会话不再丢
- 覆盖安装后，本地状态继续保留
- 本地 snapshot / backup 不再明文落盘

这类修复的价值，不在于“加了加密”四个字，而在于把“当前请求可用”“已经持久化”“已经安全持久化”这三件事重新分层，并让产品行为和用户预期重新对齐。

#SoftwareArchitecture #SecurityEngineering #Flutter #DesktopApp #Reliability
```

## 小红书

```text
最近把 XWorkmate 修了一个很真实的坑，值得单独记一笔。

用户反馈是：
“这次明明连上了，为什么重启以后本地配置又没了？”

一开始看像保存没写进去，继续往下查才发现问题更深：

1. secure storage 只要慢一点，旧逻辑 400ms 就判失败
2. 失败后不是写持久化兜底，而是直接退成“只存内存”
3. 所以当前会话看起来正常，App 一退出，token / password 就跟着没了
4. 更糟的是，本地 settings 和任务会话的旧迁移链路里还残留明文落盘

这次补丁做了几件事：

- secure storage 超时从 400ms 提到 5s
- secret 异常时走 durable fallback，不再只活在内存里
- 本地 settings、assistant threads、backup 全部改成 sealed persistence
- 修掉旧版 plaintext migration
- 补上 assistant thread 持久化竞态保护

结果就是：

- 重启后本地 Gateway 配置不再丢
- 覆盖安装后任务会话还能回来
- 本地 snapshot / backup 不再是明文

这类问题最难的点，不是修一行代码，而是把“能连上”和“真的保存了”分开看。

桌面 App 做到最后，用户要的不是一个当下能跑的 demo，而是一个重启以后还记得自己的工具。

#独立开发 #Flutter #桌面应用 #AI工具 #产品修复复盘
```
