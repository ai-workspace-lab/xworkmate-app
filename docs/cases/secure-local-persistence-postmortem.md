# Secure Local Persistence Postmortem

## 问题摘要

用户现场反馈很直接：

- 当前会话里 Gateway 可以正常连接
- App 一重启，本地配置和已保存凭证丢失
- `Gateway 访问` 页重新出现 `gateway token missing`

这不是单点 bug，而是持久层设计里连续几处降级路径叠加后的结果。

## 用户可见症状

### 1. 重启后网关凭证丢失

表现：

- token / password 在当前会话内可用
- 退出再打开后不可用
- 首次连接提示重新输入 shared token

### 2. 本地配置或任务会话恢复不稳定

表现：

- settings snapshot 或 assistant threads 在某些路径下恢复失败
- backup 虽然存在，但仍可能是明文旧格式

### 3. 明文本地状态残留

表现：

- 旧版 `SharedPreferences` 和 SQLite 中存在明文 settings / threads
- backup 文件也可能保留明文副本

## 根因

## 根因 1：对 `FlutterSecureStorage` 强制套了 400ms 超时

旧逻辑：

- secure storage 读写只要超过 `400ms`，就视为失败
- 一旦失败，直接退化成“仅内存”

结果：

- 当前进程内看起来一切正常
- 因为值实际上没持久化，进程退出后凭证全部丢失

这是这次“重启后 token 消失”的直接根因。

## 根因 2：secure storage 失败时降级策略设计错了

旧策略把“可恢复 secret”误当成“会话临时缓存”处理：

- token / password / API key 没写进 durable fallback
- 只保存在进程内存

这个策略对调试场景看似友好，但对桌面 App 的真实使用是灾难性的，因为用户天然预期“已经保存”的 secret 会跨重启存在。

## 根因 3：legacy prefs 迁移把明文直接写回了主存储

迁移链路里存在一个关键缺口：

- 从 `SharedPreferences` 读取到旧版明文 settings / threads
- 直接调用数据库写入
- 没有经过 sealed local state

结果：

- 用户完成升级后，本地状态仍可能继续以明文形式存在 SQLite
- 旧的 pref key 也没有被及时清理

这让“升级到新版本后自动变安全”的承诺失效了。

## 根因 4：本地状态密钥也被允许走普通 fallback

旧版把 `xworkmate.local_state.key` 当成普通 secret 处理。

结果：

- 一旦它掉进 fallback 文件，secure storage 就不再是本地状态加密的真正前提
- 架构上变成“有 secure storage 更好，没有也能常态运行”

这违背了本次补丁要建立的安全模型。

## 根因 5：线程状态异步保存存在覆盖竞态

Assistant 线程会话是异步落盘的。旧逻辑没有串行 flush：

- 线程 A 的旧快照可能在稍后写入
- 覆盖线程 B 或更新后的新状态

在加密封装增加写入成本后，这个竞态更容易暴露。

## 修复策略

### 1. secure storage 不再 400ms 即判死刑

- 超时提高到 `5s`
- 对真实 `FlutterSecureStorage` 保留超时保护
- 对测试注入 client 不套这层超时

### 2. secure storage 失败时改为 durable fallback，而不是仅内存

- Gateway token
- Gateway password
- AI Gateway API key
- Vault token

这些 secret 在 secure storage 异常时会写入持久化 fallback，保证跨实例恢复。

### 3. 本地配置和任务会话统一 sealed

对以下状态统一改为 AES-GCM sealed payload：

- `SettingsSnapshot`
- Assistant thread records
- `assistant-state-backup.json`

目标是消除明文 SQLite / 明文 JSON backup。

### 4. legacy 明文状态迁移时立即重写并清理旧 pref

新逻辑：

- 读旧 pref
- 若目标存储不存在，则按 sealed 路径写入
- 写入成功后删除旧 pref key

这样升级后不会继续遗留明文主副本。

### 5. 本地状态密钥升级为 primary secure storage only

`xworkmate.local_state.key` 现在的规则是：

- 必须优先保存在主 secure storage
- 不再纳入普通 secure fallback 白名单
- 对旧版 `local-state-key.txt` 仅做一次迁移，随后删除

### 6. Assistant 线程持久化改为串行队列

新增线程持久化 queue 和 flush 机制，保证：

- 新状态不会被晚到的旧写入覆盖
- clear / send / view-mode 切换前可以先 flush

### 7. dispose 后的异步通知保护

`SettingsController` 新增 dispose guard，避免恢复链路异步完成后向已销毁对象 `notifyListeners()`。

## 为什么旧方案会失效

旧方案的问题不在“没加密”，而在于它把三件不同的事混在了一起：

- 当前请求是否可用
- 是否已经持久化
- 是否已经安全持久化

一旦 secure storage 稍慢，系统就会把“当前连接可继续”错误地当成“数据已经保存”，这正是桌面应用里最危险的误导。

## 回归防线

这次新增的回归覆盖重点包括：

- secure storage 超时后 secret 仍能跨实例恢复
- SQLite 不可用时，sealed 的 settings / threads 仍能恢复
- plaintext local state 能迁移为 sealed storage
- legacy `local-state-key.txt` 能迁移到主 secure storage 并被清理
- backup 文件不再泄露明文 settings / threads

## 后续约束

后续所有涉及本地状态持久化的修改，都必须继续满足：

- `.env` 仍是预填，不是持久化真值
- 当前用户发起连接时可直接用表单值握手，不依赖 secure-store 回读
- local state 不得重新落回 `SharedPreferences` 明文
- backup 不得重新变成明文副本
- 不能再让 `xworkmate.local_state.key` 走常态文件 fallback
