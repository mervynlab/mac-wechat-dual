# mac-wechat-dual

[![macOS](https://img.shields.io/badge/macOS-12%2B-black?logo=apple)](#已验证环境)
[![WeChat](https://img.shields.io/badge/WeChat-4.x-07C160)](#已验证环境)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**macOS 微信双开 / 多开**：一条命令生成第二个微信，独立登录、独立数据，原版微信一个字节都不改。

- 🧩 **零侵入**：不修改原版 `WeChat.app`，不改动微信代码，不注入、不 Hook
- 🗂 **数据隔离**：每个副本拥有独立的沙盒数据目录，账号、聊天记录互不干扰
- 💾 **几乎不占空间**：基于 APFS 克隆复制，1.4 GB 的微信秒级复制
- 🔄 **跟随更新**：原版升级后重跑一条命令即可同步，聊天数据保留
- 🧹 **随时还原**：一条命令删除副本，可选同时清理数据

---

## 快速开始

```bash
git clone https://github.com/mervynlab/mac-wechat-dual.git
cd mac-wechat-dual
./wechat-dual.sh install        # 生成并启动 /Applications/WeChat2.app
```

几秒后会弹出第二个微信的登录窗口，扫码登录第二个账号即可。之后在启动台 / 应用程序里直接打开 **WeChat2**。

不想 clone？只下载脚本也可以（建议先打开链接看一眼脚本内容再运行）：

```bash
curl -fsSLO https://raw.githubusercontent.com/mervynlab/mac-wechat-dual/main/wechat-dual.sh
chmod +x wechat-dual.sh && ./wechat-dual.sh install
```

可选：放进 PATH，随处可用：

```bash
cp wechat-dual.sh ~/.local/bin/wechat-dual   # 或 /usr/local/bin/wechat-dual
```

### 已验证环境

| macOS | 芯片 | 微信版本 | 结果 |
|---|---|---|---|
| 15.3 | Apple Silicon | 4.1.13 | ✅ 双开正常 |
| 15.3 | Apple Silicon | 4.1.15 | ✅ 原版升级后重跑 `install`，第二个账号数据保留 |

其它版本原理相同。遇到问题或在新版本上验证成功，欢迎提 [Issue](https://github.com/mervynlab/mac-wechat-dual/issues) 补充这张表。

## 用法

```bash
./wechat-dual.sh <命令> [参数]
```

| 命令 | 说明 |
|---|---|
| `install [N]` | 创建并启动第 N 个微信，默认 2；`install 3` 生成 WeChat3 |
| `open [N]` | 启动已创建的副本 |
| `list` | 列出所有副本及版本，标出落后于原版的 |
| `remove N` | 删除副本，**保留**该账号聊天数据 |
| `remove N --purge` | 删除副本**并删除**该账号本地数据（需输入 `yes` 确认，不可恢复） |

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

`install` 一共四步，原版 `WeChat.app` 全程只读：

**① 复制一份微信**

```bash
cp -Rc /Applications/WeChat.app /Applications/WeChat2.app
```

`-c` 使用 APFS 克隆（copy-on-write）：副本与原版共享磁盘块，只有被改动的文件才真正占空间，1.4 GB 的微信秒级复制完成。

**② 改 Bundle ID**

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.tencent.xinWeChat2" \
  /Applications/WeChat2.app/Contents/Info.plist
```

系统据此把副本当成另一个 App：允许和原版同时运行，并给它分配独立的数据目录 `~/Library/Containers/com.tencent.xinWeChat2`。同时把显示名改为「微信2」，方便在程序坞里区分。

**③ 移除副本里的扩展**

```bash
rm -rf /Applications/WeChat2.app/Contents/PlugIns
```

分享扩展、文件提供扩展的 ID 仍和原版一样，两份同时注册可能干扰原版的分享菜单和访达集成，所以副本不带它们。

**④ 本地重新签名**

```bash
codesign --force --deep --sign - /Applications/WeChat2.app
```

改过 `Info.plist` 后腾讯原签名失效，系统会拒绝启动；`--sign -` 表示本机临时签名（ad-hoc），在自己电脑上运行没有问题。最后清除隔离属性并启动副本。

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

## 作者

[@mervynlab](https://github.com/mervynlab) · 觉得有用就点个 ⭐ Star 吧
