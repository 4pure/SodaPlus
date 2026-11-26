# SodaPlus

路径：`/Users/p/Workspace/Program/SwiftProjects/SodaPlus`

基于 [libresoda](https://github.com/sodahub-org/libresoda) 的 **Swift / macOS** 汽水客户端。交互与能力对齐开源 [SodaM](https://github.com/sodahub-org/sodam)：侧栏导航、推荐流、听歌模式、搜索、我喜欢、歌单、底栏播放条、队列、歌词页、扫码/Cookie 登录、系统媒体键。

## 功能

- 侧栏：推荐 / 听歌模式 / 搜索 / 我喜欢 / 我的歌单 / 设置
- 底栏：封面、曲信息、上一首/播放/下一首、进度、播放模式、音量、队列抽屉
- 播放页：封面 + 滚动歌词
- 队列：列表循环 / 单曲循环 / 随机；菜单栏控制；关窗后台继续播
- `AVPlayer` + `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`
- Rust CLI 桥 `sodaplus-bridge`（JSON）接通 libresoda
- 默认签名服务与 SodaM 一致（可在设置中替换）

## 构建

```bash
./scripts/fetch-libresoda.sh   # 若尚未 vendoring
./scripts/build-bridge.sh
swift run                      # 开发

make build-mac                 # Universal DMG → installers/
make build-mac-arm             # Apple Silicon DMG
make build-mac-intel           # Intel DMG
make build-mac-app             # Universal .app（不打 DMG）
make build-mac-arm-app         # Apple Silicon .app

脚本入口：`./scripts/package.sh [arm|intel|universal] [--app-only]`（Makefile 薄封装）。
open installers/SodaPlus.app   # 仅 :app / --app-only 后可用
```

版本唯一源：`Config/Version.xcconfig`。完整打包只出 DMG；`--app-only` / `build-mac-*-app` 才把 `.app` 发到 `installers/`。

## 登录

1. 设置 → 生成二维码（纯 HTTP 登录，不依赖本机 Chrome）
2. 用**汽水音乐 App**扫码并在手机上点确认（二维码内容是 `scan_url` 原样，对齐 SodaM）
3. 若需要二次验证，**在 App 登录弹层内**完成（内嵌 WebView 加载本机 `security_host`）；完成后继续等轮询成功
4. 或粘贴官方客户端 Cookie 到设置页

技术点：扫码登录走常驻 `sodaplus-bridge serve`，**create/check 必须同进程**，否则登录会话 cookie jar 对不上（见 libresoda `QR-LOGIN.md`）。轮询间隔 6 秒，避免 `error_code=7` 限流。

VIP 整曲依赖签名服务；默认已写入 SodaM 公共签名地址，也可自建 `libmssdk`。

## 合规

- 依赖 libresoda 时整体按 **AGPL-3.0-or-later**
- 非官方，与字节 / 汽水无关
- 仅供个人播放有权内容；勿用于抓取、公开代理或绕过付费
