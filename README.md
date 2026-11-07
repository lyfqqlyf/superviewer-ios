# SuperViewer for iOS

参考向日葵 controlclient（ios_formal/controlclient）的操作方式实现的 iOS 客户端，
**手势操作与向日葵完全一致**。

## 修复记录（v1.0.1）

| 问题 | 修复 |
|---|---|
| CI 报错 `The configuration 'macos-14-arm64-us-default' is not supported` | `runs-on: macos-14` 镜像已退役 → 改用 `macos-latest`（可固定为 macos-15） |
| `SWIFT_VERSION "5.9"` 不是合法语言模式（Xcode 只接受 4.0/4.2/5.0/6.0） | 改为 `5.0` |
| `appendingPathComponent` 把 `?` 编码成 `%3F`，带查询参数的接口全部 404 | URL 改为字符串拼接 |
| `UTType.item` 未导入 `UniformTypeIdentifiers` 编译失败 | 补充 import |
| 文件列表 `.default` 单元格没有 detailTextLabel | 改为 `.subtitle` |
| 文件浏览器无“上级/盘符”导航 | 增加返回上级按钮 |
| 首页 help 按钮布局时机错误 | 移入 viewDidLayoutSubviews |

## GitHub Actions 编译 IPA（无需 Mac）

1. 在 GitHub 新建仓库（如 `superviewer-ios`），把本目录全部内容推上去：
   ```bash
   cd E:\tools\superviewer\ios
   git init && git add . && git commit -m "SuperViewer iOS"
   git remote add origin https://github.com/<你的用户名>/superviewer-ios.git
   git push -u origin main
   ```
2. 打开仓库 → **Actions** → 工作流 `Build IPA` → **Run workflow**
3. 构建完成后在 Artifacts 下载 `SuperViewer-unsigned-ipa`（**未签名 IPA**）

## 签名安装（三选一）

| 方式 | 要求 | 说明 |
|---|---|---|
| **Sideloadly / AltStore**（推荐） | 免费 Apple ID | 数据线装到手机，7 天有效，到期重签 |
| **TrollStore** | iOS 14-16.6.1 等 | 永久签名，无需开发者账号 |
| **Xcode / 开发者账号** | $99/年 | 真机调试安装，长期有效 |

> 未签名 IPA 先用 Sideloadly 拖入即可自动完成签名。

## 使用

1. 被控端：托盘启动服务（默认**隧道关闭**，局域网模式监听 `0.0.0.0:9443`）
2. 手机与电脑同一 Wi-Fi，App 内输入 `电脑局域网IP:9443` + 托盘查看的验证码
3. 之后开隧道：托盘菜单 → 隧道开关 → App 里填 `https://xxx.trycloudflare.com`

## 操作手势（与向日葵 ControlClient 一致）

### 触摸模式（默认）
| 手势 | 功能 |
|---|---|
| 单指点按 | 左键（点到哪点到哪） |
| 单指长按 0.55s | 右键 |
| 单指按下拖动 | 左键拖动（窗口拖动/多选） |
| 双指点按 | 右键 |
| 双指上下滑动 | 滚轮 |
| 双指捏合 | 缩放画面（1x~6x） |

### 指针模式（触摸板，"🖱 指针模式"按钮切换）
| 手势 | 功能 |
|---|---|
| 单指滑动 | 移动虚拟指针（可调灵敏度） |
| 单指点按 | 左键 |
| 长按后拖动 | 左键按住拖动 |
| 双指点按 | 右键 |
| 双指滑动 | 滚轮 |
| 双指捏合 | 缩放 |

### 工具栏
`⌨ 键盘`（修饰键粘滞 Ctrl/Alt/Shift/Win + Esc/Tab/方向键/Home/End/PgUp/PgDn/CAD/任务管理器）
`🖥 显示器` `🎚 画质/灵敏度` `⇅ 剪贴板` `⌨ 终端(PowerShell/CMD)` `📁 文件(下载/上传/删除/新建)` `⏻ 电源` `✕ 断开`

## 工程说明

- **project.yml**: XcodeGen 工程定义（CI 里自动生成 .xcodeproj）
- **.github/workflows/build-ipa.yml**: macOS runner 上 xcodebuild 归档并打包未签名 IPA
- **Sources/**: UIKit 实现
  - `ScreenCanvasView.swift` 手势状态机（对齐 RDGestureEventDelegate 语义）
  - `RemoteViewController.swift` 手势 → `{t:"mouse"/"key"/"combo"/"wheel"}` 协议
  - 协议与 Web 客户端共用同一服务端，无需额外配置

## 安全说明

- 登录会话用 HttpOnly Cookie（iOS HTTPCookieStorage），验证码不落盘
- 建议开启隧道后用 `https://` 地址（iOS ATS 强制 TLS）
- 局域网 http 依赖 `NSAllowsLocalNetworking` 白名单，仅允许本地网络明文
