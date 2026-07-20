# iOS 会话持久化手工回归用例

> 关联:[2026-07-20 持久化加固记录](../tasks/2026-07-20-ios-session-persistence-hardening.md)
> 覆盖 PR:#168(路径重定位)、#170(备份排除)、#171(每会话文件)、#172(Keychain + 重装即登出)
> 前置:真机(iOS 15.6+),已登录 svc.plus 账号,至少两个历史任务会话(其中一个含制品),其中至少一个会话自安装后从未再次打开过。

## C1 冷重启保留

1. 发一条新消息,等助手回复完成。
2. 上滑彻底杀掉 App,重新打开。

**预期**:会话列表完整,刚才的往返消息都在;启动无「跳过无效会话」告警。

## C2 后台被杀保留

1. 发一条消息,在助手回复流式输出中途按 Home 键切后台。
2. 等约 10 秒,上滑杀进程,重开。

**预期**:最多丢失被杀瞬间正在写入的最后一条;此前的历史完整,不出现整表清空。

## C3 升级(容器迁移)保留 + 路径重基

1. 用 `flutter install`(先卸载)以外的方式覆盖安装新 build(Xcode 直接 Run 到真机,或 TestFlight 升级)。
2. 打开 App,不点进任何会话,先拉取沙盒验证:

```bash
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier plus.svc.xworkmate \
  --source Library/Application\ Support/xworkmate/tasks --destination /tmp/xw-tasks
cat /tmp/xw-tasks/index.json
```

**预期**:每会话 `<base64url>.json` 文件与 `index.json` 存在(#171);任一会话文件里 `workspacePath` 指向**当前**容器 UUID,不残留旧容器路径(#168);从未打开过的历史会话同样已重基。

## C4 每会话文件坏损隔离

1. 在 C3 拉取的目录里任选一个会话文件,记下 threadId。
2. 用 `devicectl device copy to` 把该文件覆盖为非法 JSON,重启 App。

**预期**:仅该会话从列表消失,其余会话完好;启动出现跳过告警;沙盒里出现 `*.invalid-<ts>.bak` 备份,坏文件被移除(下次启动不再重复告警)。

## C5 重装即登出(#172)

1. 确认已登录(设置页显示账号邮箱)。
2. 删除 App,重新安装同一 build,打开。

**预期**:处于**未登录**状态,设置页显示登录表单;不出现自动恢复的账号会话;助手页为断开态(无残留 bridge token 发起的请求)。

## C6 升级密钥迁移(#172)

1. 装一个 #172 之前的 build 并登录(产生 `secrets/*.secret` 文件)。
2. 覆盖升级到含 #172 的 build(不卸载),打开。

**预期**:登录态保留、功能正常;拉取沙盒确认 `secrets/` 下不再有 `*.secret` 文件,只有 `.keychain-bound` 哨兵。

## C7 备份排除(#170)

设置 → Apple ID → iCloud → 管理账户储存空间 → 备份 → 本机,查看 XWorkmate 条目大小;或用 Xcode Devices 窗口检查。

**预期**:含大制品的工作区不计入备份体积(`Documents/.xworkmate` 已排除);会话历史仍随备份——iCloud 恢复到新机后,历史在、制品缺、制品可从任务详情重新拉取。

## 已知限制

- C2 的「写入进行中被杀」窗口内,最后一条消息可能回退到上一状态——原子写保证不损坏,不保证不丢最后一笔。
- C5 后 Keychain 的清理发生在**下次启动**时(绑定流程),不是卸载瞬间;卸载后不再安装则残留由 iOS 自身的 Keychain 生命周期管理。
