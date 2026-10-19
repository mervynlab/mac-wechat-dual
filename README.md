# mac-wechat-dual

macOS 微信双开 / 多开的一键脚本与原理说明。

- 不修改原版 `WeChat.app`，不改动微信任何代码，不注入、不 Hook
- 每个副本拥有**独立的数据目录**，账号、聊天记录互不干扰
- 基于 APFS 克隆复制，副本**几乎不占额外磁盘空间**
- 微信更新后重跑一条命令即可同步，聊天数据保留

> 已验证环境：macOS 15 (Apple Silicon)，微信 4.1.13。其它版本原理相同，欢迎反馈。

---

## 快速开始

```bash
git clone https://github.com/<your-name>/mac-wechat-dual.git
cd mac-wechat-dual
chmod +x wechat-dual.sh
./wechat-dual.sh install        # 生成并启动 /Applications/WeChat2.app
```

稍等几秒，会弹出第二个微信的登录窗口，扫码登录第二个账号即可。之后直接在启动台 / 应用程序里打开 **WeChat2**。

可选：放进 PATH，随处可用

```bash
cp wechat-dual.sh /usr/local/bin/wechat-dual   # 或 ~/.local/bin/wechat-dual
```

## 用法

| 命令 | 说明 |
|---|---|
| `wechat-dual.sh install [N]` | 创建并启动第 N 个微信（默认 2）。`install 3` 生成 WeChat3，以此类推 |
| `wechat-dual.sh open [N]` | 启动已创建的副本 |
| `wechat-dual.sh list` | 列出所有副本和版本，提示哪些落后于原版 |
| `wechat-dual.sh remove N` | 删除副本，**保留**该账号聊天数据 |
| `wechat-dual.sh remove N --purge` | 删除副本**并删除**该账号本地数据（需输入 `yes` 确认，不可恢复） |

环境变量：

- `WECHAT_APP`：原版微信路径，默认 `/Applications/WeChat.app`
- `WECHAT_DUAL_DIR`：副本存放目录，默认 `/Applications`（非管理员账户可设为 `~/Applications`）

## 微信更新后

副本不会跟着原版更新。原版更新后：

1. 退出 WeChat2
2. 执行 `./wechat-dual.sh install 2`

副本会按新版本重建，第二个账号的聊天记录仍在原处，无需重新同步。

---

## 原理

### 为什么微信只能开一个？

macOS 用 **Bundle ID** 识别一个 App，微信的 Bundle ID 是 `com.tencent.xinWeChat`。它在两处起作用：

1. **单实例**：同一个 Bundle ID 已在运行时，再次打开只会激活已有窗口。
2. **数据目录**：微信是沙盒应用（签名权限中 `com.apple.security.app-sandbox = true`），数据固定在 `~/Library/Containers/<Bundle ID>/`。同一个 ID 只有一个数据目录，也就只能登录一个账号。

### 脚本做了什么

| 步骤 | 操作 | 作用 |
|---|---|---|
| 1. 复制 | `cp -Rc WeChat.app WeChat2.app` | `-c` 使用 APFS 克隆（copy-on-write），1.4 GB 的 App 秒级复制，几乎不占空间 |
| 2. 改 ID | 将副本 `Info.plist` 的 `CFBundleIdentifier` 改为 `com.tencent.xinWeChat2` | 系统视为另一个 App：允许同时运行，并分配独立数据目录 `~/Library/Containers/com.tencent.xinWeChat2` |
| 3. 移除扩展 | 删除副本的 `Contents/PlugIns` | 分享扩展与文件提供扩展的 ID 仍与原版相同，双份注册可能干扰原版 |
| 4. 重签名 | `codesign --force --deep --sign -` | 修改 Info.plist 后原签名失效，系统会拒绝启动；`-` 表示本地临时签名（ad-hoc），在本机运行没有问题 |

一句话：**Bundle ID 是身份证号，沙盒是按身份证号分配的房间，签名是防伪章**——复制一份、改号、盖自己的章，系统就再分一个房间。

### 微信 4.x 的结构（供参考）

用静态分析工具查看 `WeChat.app`（只读，不运行、不反编译保护逻辑）可以看到：

- `Contents/MacOS/WeChat`：很小的启动壳
- `Contents/Resources/wechat.dylib`：业务核心（约 350 MB，C++ / Objective-C）
- `Contents/MacOS/WeChatAppEx.app`：基于 Chromium 的小程序 / 网页容器
- `Contents/PlugIns/*.appex`：分享扩展、文件提供扩展（本工具在副本中移除它们的原因）
- `Contents/Frameworks/Sparkle.framework`：自动更新

副本方案只涉及 Bundle ID 与签名，与以上内部结构无关，因此对版本变化不敏感。

---

## 常见问题

**Q：副本缺少哪些功能？**
系统「分享」菜单里没有微信 2；访达侧边栏没有微信 2 的文件入口。其余聊天、文件、音视频通话、小程序正常。首次使用摄像头、麦克风、通知时系统会重新请求授权。

**Q：副本提示有新版本？**
副本内置的 Sparkle 更新器可能提示升级。副本内升级可能因签名不匹配失败，建议忽略，以「原版更新 → 重跑 install」为准。

**Q：提示 `/Applications 不可写`？**
当前账户不是管理员。使用 `WECHAT_DUAL_DIR=~/Applications ./wechat-dual.sh install`。

**Q：打开副本提示"已损坏"或无法验证开发者？**
脚本已清除隔离属性。如仍提示，在「系统设置 → 隐私与安全性」中点击"仍要打开"，或重跑 `install`。

**Q：第二个账号的数据在哪？怎么备份？**
`~/Library/Containers/com.tencent.xinWeChat2`。备份该目录即可，也可以用微信自带的聊天记录迁移。

**Q：能开三个、四个吗？**
可以：`install 3`、`install 4`……每个副本独立。注意内存占用会线性增加。

**Q：怎么彻底恢复原状？**
`./wechat-dual.sh remove 2 --purge`。原版微信从未被修改，无需恢复。

---

## 风险与免责声明

- 本项目与腾讯公司无任何关联，"微信 / WeChat" 为其各自权利人的商标。
- 本工具仅利用 macOS 的应用标识与沙盒机制，不修改、不破解、不逆向微信的任何保护机制，也不提供自动收发消息等功能。
- 多开不是微信官方支持的功能，理论上存在被风控的可能，请自行评估重要账号的风险。使用本工具产生的一切后果由使用者自行承担。
- 请遵守《腾讯微信软件许可及服务协议》及所在地法律法规。

## License

[MIT](LICENSE)
