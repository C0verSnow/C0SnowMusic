# 在线音乐、Google 登录和手机本地 yt-dlp 调研

核对日期：2026-11-14；Unix Timestamp：1794713717。已在 GitHub 检索同类项目，读取许可证、实际源码、发布记录和 Issue 回复。本文不代表代码或真机验收通过；没有运行本地编译、构建或测试。

## 本次选择

用户已明确要求“全部在手机运行，不用服务器”。因此选择在 iOS 应用内嵌入 Python，调用真正的 yt-dlp；下载完整音频后，继续交给现有 AVPlayer。SwiftUI、缓存管理和搜索卡片仍自行实现。用户随后指定 NeriPlayer 作为登录参考；其实际功能是保存 YouTube 网页账户会话，不能用本应用的 Google OAuth 身份登录冒充。具体结论见下方补充章节。

这会新增有明确用途的第三方运行时。原先“完全没有第三方运行时”与“手机内运行 yt-dlp”无法同时满足：yt-dlp 是 Python 项目，YouTube 签名挑战还需要 JavaScript 执行能力。这是架构约束，不是需要用户部署服务器。依据 [yt-dlp 官方依赖说明](https://github.com/yt-dlp/yt-dlp#dependencies)、[CPython 官方 iOS 文档](https://docs.python.org/3.13/using/ios.html)。

## GitHub 候选比较

以下 star、最近推送均为本次 API 查询快照。star 不能证明实现正确；选型同时核对实际源码和维护者回复。

| 项目 | 维护、许可和规模 | 实现、依赖、已知问题与取舍 |
| --- | --- | --- |
| [yt-dlp/yt-dlp](https://github.com/yt-dlp/yt-dlp) | Unlicense；207,879 stars；2026-11-14 推送；稳定版 [2026.10.26](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26)。[Issue #18053](https://github.com/yt-dlp/yt-dlp/issues/18053) 有贡献者当天跟进。 | 真正下载引擎；当前主线要求 Python 3.11+。YouTube 完整支持需要 EJS 与 JS 引擎；FFmpeg 用于合并、转码等后处理，不是下载单条原生 m4a 必需。使用其 Python API，不把命令行二进制当 iOS 子进程启动。 |
| [beeware/Python-Apple-support](https://github.com/beeware/Python-Apple-support) | MIT 包装工程；1,373 stars；2026-11-12 推送。Python 本体还须附带 PSF 等原始许可。 | 官方 CPython iOS 嵌入路线的打包工具，有设备和模拟器 XCFramework。选维护中的 3.13 系列；[3.13-b18 资源](https://github.com/beeware/Python-Apple-support/releases/tag/3.13-b18) 可直接取得预编译包。不要盲跟 `/latest`，本次 `/latest` 已是 3.15，而主分支研究 3.16。 |
| [tfourj/Palladium](https://github.com/tfourj/Palladium) | GPLv3；161 stars；2026-11-12 推送；[Issue #100](https://github.com/tfourj/Palladium/issues/100) 有作者定位、后续版本修复说明。规模较小，作为直接相关的补充来源。 | 已有手机内 yt-dlp 应用：PythonKit、BeeWare Python、FFmpeg、curl-cffi、QuickJS-NG、WebKit JSI；[构建说明](https://github.com/tfourj/Palladium/blob/main/docs/BUILD.md) 列出本机二进制依赖。[源码目录](https://github.com/tfourj/Palladium/tree/main/Palladium/Services/Python) 展示串行后台执行和独立 Python 入口。只借鉴架构，不复制 GPL 实现，也不照搬整个下载器依赖。 |
| [net00-1/SW-DLT](https://github.com/net00-1/SW-DLT) | MIT；1,104 stars；2026-10-07 推送。 | iOS 18/26 快捷指令，把 yt-dlp 放在 a-Shell / a-Shell Mini 运行。说明手机本机下载可行，但要求另装应用，不能作为本项目内嵌库。 |
| [grqz/yt-dlp-apple-webkit-jsi](https://github.com/grqz/yt-dlp-apple-webkit-jsi) | Apache-2.0；167 stars；2026-04-25 推送；[v0.1.1](https://github.com/grqz/yt-dlp-apple-webkit-jsi/releases/tag/v0.1.1)。维护频率低于主项目，只作为可选 JS 适配来源。 | [pyproject.toml](https://github.com/grqz/yt-dlp-apple-webkit-jsi/blob/master/pyproject.toml) 没有额外 Python 依赖，通过 ctypes 和苹果 WebKit 解 EJS，不必带 Deno。使用 yt-dlp 私有 EJS 接口，必须固定兼容版本。真实 [Issue #5](https://github.com/grqz/yt-dlp-apple-webkit-jsi/issues/5) 记录意外跳转 YouTube，见下文。 |
| [alexeichhorn/YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) | MIT；424 stars；2026-10-31 推送；[0.4.10](https://github.com/alexeichhorn/YouTubeKit/releases/tag/0.4.10)。[Issue #139](https://github.com/alexeichhorn/YouTubeKit/issues/139) 有作者回复、修复与用户复测。 | 原生 Swift 本地解流，内含 JSCore 资源；Package.swift 无第三方包依赖。可参考音频格式选择和签名处理。但 `.local` 不是 yt-dlp；`.remote` 才通过 WebSocket 间接调用服务端 yt-dlp，因此不符合本次“全部在手机”选择。 |
| [google/GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) | Apache-2.0；759 stars；2026-11-13 推送；[10.1.0](https://github.com/google/GoogleSignIn-iOS/releases/tag/10.1.0)。[Issue #667](https://github.com/google/GoogleSignIn-iOS/issues/667) 有 Google 贡献者回复。 | 官方 Google 登录。当前 Package.swift 是 Swift tools 6.0、iOS 15+；正式 target 依赖 AppAuth、AppCheckCore、GTMAppAuth、GTMSessionFetcherCore。采用官方 SDK，不自行重写 OAuth。 |
| [openid/AppAuth-iOS](https://github.com/openid/AppAuth-iOS) | Apache-2.0；2,039 stars；2026-11-13 推送；[Issue #987](https://github.com/openid/AppAuth-iOS/issues/987) 有维护者修复说明。 | 标准 OAuth / OIDC、ASWebAuthenticationSession、PKCE；Google SDK 已经使用它。作为协议依据，不再直接加一套独立登录流程。 |
| [TeamNewPipe/NewPipeExtractor](https://github.com/TeamNewPipe/NewPipeExtractor) | GPLv3；2,062 stars；2026-11-11 推送。 | Java 提取器。其 [搜索源码](https://github.com/TeamNewPipe/NewPipeExtractor/blob/dev/extractor/src/main/java/org/schabi/newpipe/extractor/services/youtube/extractors/YoutubeSearchExtractor.java) 按 renderer 区分视频、频道、播放列表并处理 continuation。仅参考数据层设计，自行写 Swift，不搬 Java 依赖或 GPL 代码。 |

搜索还找到 `kewlbear/YoutubeDL`、`kewlbear/YoutubeDL-iOS`，分别停在 2023、2024 年，不作为当前主要方案；`yousif-toama/yt-dlp-ios` 没查到明确许可证，排除代码借用。

## 手机内嵌 Python 的最小路线

使用 [BeeWare 手动接入说明](https://github.com/beeware/Python-Apple-support/blob/3.13/USAGE.md)，从固定发布下载 `Python-3.13-iOS-support.b18.tar.gz`，不在本机自行编译 Python。项目应保留资源地址、版本、校验值和原始许可证；CI 下载预编译资源后完成应用编译。

1. Xcode 链接并嵌入 `Python.xcframework`，按 device / simulator 选择对应 slice。将对应标准库放到应用 `python/lib`。
2. Python 标准库扩展须按官方说明打包为独立 framework，同时保留 `.fwork` / `.origin` 关联。不能只复制 `.py` 后假定 `ssl`、`_ctypes` 可以工作。优先使用发行包附带的打包工具，签名行为需区分真机、模拟器和 unsigned CI。
3. 在 Python 第一次使用前配置 bundle 内 `PYTHONHOME`、`PYTHONPATH`，关闭写 bytecode，启用 UTF-8；使用 Python C API 初始化和调用。官方文档明确支持 Swift `import Python`；PythonKit 是可选包装，并非必须依赖。
4. 将 yt-dlp、EJS 和选定 JS provider 固定版本打进应用，不要求用户在手机输入 pip 命令。Python 官方包更新和应用代码更新都走项目 CI / 发布流程。
5. 在专属后台线程串行调用 Python。Swift actor 自身不保证总在同一 OS 线程，因此不能把 Python 的线程状态、GIL 和 UIKit 主线程要求混为一谈。向 UI 只返回 Swift 可传递的结果。

CPython 的 [iOS 嵌入文档](https://docs.python.org/3.13/using/ios.html#adding-python-to-an-ios-project) 和 [初始化 API](https://docs.python.org/3/c-api/init_config.html) 是打包与初始化的直接依据。上述步骤是接入建议，不是声称在本仓库已经验证成功。

### JavaScript 签名挑战

[yt-dlp 官方 EJS 文档](https://github.com/yt-dlp/yt-dlp/wiki/EJS) 和 [公告 #14404](https://github.com/yt-dlp/yt-dlp/issues/14404) 说明不能继续把旧的 Python 正则解密器当长期方案。手机内应调用苹果自带 JS 引擎，避免把桌面 Deno/Node 可执行文件塞进包里。

现成 Apache-2.0 WebKit 插件通过 [AppleWebKitJCP](https://github.com/grqz/yt-dlp-apple-webkit-jsi/blob/master/yt_dlp_plugins/extractor/ytjsc.py) 注册 provider，继承 `EJSBaseJCP`，用 WebKit 执行挑战，再把结果交还 yt-dlp。它的 `is_available()` 检查 Darwin；CPython iOS 的 `os.uname()` 仍返回 Darwin，因此这个检查不会因为 `sys.platform == 'ios'` 而直接失败。程序化调用时要确认插件实际被发现与加载，不能只把文件放进包就假定有效。

不能原样把当前插件当作已解决的完整接入：[Issue #5](https://github.com/grqz/yt-dlp-apple-webkit-jsi/issues/5) 已有最小复现，EJS 给真实 `window.location` 赋值后会触发导航，甚至切到 YouTube 应用。这是已发生的失败场景，需要限制挑战 WebView 的导航和弹窗，或自行实现不依赖浏览器导航的 JavaScriptCore provider。Palladium 的相关代码是 GPL，不复制其补丁；任何修正应从 Apache 插件和苹果接口独立实现并保留许可。

当前插件还缺 PO Token 完整支持，且接口属于 yt-dlp 私有实现。这意味着版本组合、真实签名挑战和设备行为都必须远端 CI / 真机验证。仅 `import yt_dlp` 成功不等于下载成功。

### 下载范围

仅支持能取得原生 AAC/m4a 音频的普通视频，优先 `bestaudio[ext=m4a]`，不合并视频，不转 MP3，不调用 FFmpeg 后处理。找不到兼容音频则提示原因，不偷偷下载视频或不兼容的 WebM。通过 yt-dlp 实际下载完成的文件接现有媒体校验与播放流程，禁止只解析地址后直接开始远程播放。

[官方 YouTube 提取器说明](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#youtube) 提醒 PO Token、账户和地区限制会影响可用格式。Google OAuth 登录不会自动解决这些限制；错误应保留可读原因，允许用户重试。

## Google 手机登录：官方 OAuth 备选

此前按本应用身份登录调研了 [Google 官方安装配置](https://developers.google.com/identity/sign-in/ios/start-integrating)、[登录接入](https://developers.google.com/identity/sign-in/ios/sign-in) 和 [迁移说明](https://developers.google.com/identity/sign-in/ios/quick-migration-guide)。这条路线只适合本应用 OAuth / 官方 API 授权，不是 NeriPlayer 的 YouTube 网页会话方案。当前稳定版是 10.1.0；部分入门页仍写 9.0.0，依赖版本以官方 GitHub release 和 Package.swift 为准。

- `Info.plist` 使用 `GIDClientID`，`CFBundleURLTypes` 注册该 iOS client ID 的 reversed scheme，如 `com.googleusercontent.apps.123-example`。Client ID 必须在 Google Cloud 按本应用 bundle ID 创建；它是应用身份标识，不是用户 Google 密码，也不能借其他开源项目的 ID。
- SwiftUI 在 `.onOpenURL` 里调用 `GIDSignIn.sharedInstance.handle(url)`；启动时调用 `restorePreviousSignIn` 恢复；点击登录时用当前 presenting controller 调 `signIn(withPresenting:)`。
- 不需要后端身份校验时无需创建 `GIDServerClientID`。缺少本应用 Client ID 时，登录按钮给出可读配置说明，不能填假值或把登录显示为成功。
- 登录通过系统认证会话处理。AppAuth 的 [官方说明](https://github.com/openid/AppAuth-iOS#specification) 支持 ASWebAuthenticationSession 和 PKCE；[RFC 8252](https://www.rfc-editor.org/rfc/rfc8252) 要求 native public client 使用 PKCE。不要用嵌入 WKWebView 收集 Google 密码。

Google OAuth 结果是身份、token 和获准的 API scope，不是任意 HTTP 客户端的 YouTube cookie 登录。不要把 SDK token 当作 m.youtube.com 的 cookie，也不要声称登录后就能下载所有受限音频。若以后需要登录后的网页账户态，应另行说明浏览器 cookie 会话的用途与边界。

## 补充：NeriPlayer 的实际登录与 iPhone 可移植范围

Unix Timestamp：1794715435。用户指定参考 [cwuom/NeriPlayer](https://github.com/cwuom/NeriPlayer)。本次读取固定提交 [bcc057a15ee6d8ff1f4c3c6de7115a177756b91c](https://github.com/cwuom/NeriPlayer/commit/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c)，避免后续重构改变文件含义。仓库 4,193 stars，GPL-3.0，最近推送 2026-11-13；[Issue #307](https://github.com/cwuom/NeriPlayer/issues/307) 有作者明确解释 Cookie 加密和内置浏览器登录，[Issue #448](https://github.com/cwuom/NeriPlayer/issues/448) 有作者回应网络风控问题。它符合活跃、许可证明确、有维护者回应的参考条件。以下只借鉴设计，不复制 GPL Kotlin 实现。

### 它登录的是 YouTube 网页，不是本应用 OAuth

入口是 [YouTubeWebLoginActivity.kt](https://github.com/cwuom/NeriPlayer/blob/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c/app/src/main/java/moe/ouom/neriplayer/activity/auth/YouTubeWebLoginActivity.kt)：

1. Android `WebView` 打开 `https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F`，开启 JS、DOM storage 和 Cookie。该入口没有本应用的 `client_id` / OAuth redirect，也不调用 GoogleSignIn SDK。
2. 使用移动 WebView UA，剥除 `; wv`、`Version/4.0` 标志。源码注释说明这是为缓解 Google 的“不安全浏览器”拒登；播放请求另用固定桌面 Web UA，登录和播放 UA 分开。这只是项目当前做法，不能据此承诺 iOS 改 UA 也能稳定登录。
3. `CookieManager` 读取 Google、YouTube 和 YouTube Music 域 Cookie；`shouldInterceptRequest` 观察 YouTube 请求的 `Cookie`、`Authorization`、`X-Goog-AuthUser`、origin、UA。`evaluateJavascript` 从 `ytcfg` 读取 `LOGGED_IN`、`SESSION_INDEX`、`DELEGATED_SESSION_ID`、`USER_SESSION_ID`。
4. 保存前先用原生 HTTP 携带候选 Cookie 请求 YouTube Music / YouTube 首页，再解析真实登录标记。仅有 Cookie 名称或成功打开登录页不算登录成功，见 [YouTubeWebLoginVerifier.kt](https://github.com/cwuom/NeriPlayer/blob/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c/modules/platform/src/main/java/moe/ouom/neriplayer/platform/youtube/auth/YouTubeWebLoginVerifier.kt)。
5. 账户包存到 `EncryptedSharedPreferences`，由 Android `MasterKey` 保护，见 [YouTubeAuthRepository.kt](https://github.com/cwuom/NeriPlayer/blob/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c/modules/platform/src/main/java/moe/ouom/neriplayer/platform/youtube/auth/YouTubeAuthRepository.kt)。这不是把密码写进播放器配置。

Cookie 读取、写回和域处理在 [YouTubeWebCookieStore.kt](https://github.com/cwuom/NeriPlayer/blob/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c/modules/platform/src/main/java/moe/ouom/neriplayer/platform/youtube/auth/web/YouTubeWebCookieStore.kt)；保留的会话 Cookie 名称在 [YouTubeCookieSupport.kt](https://github.com/cwuom/NeriPlayer/blob/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c/modules/platform/src/main/java/moe/ouom/neriplayer/platform/youtube/api/auth/YouTubeCookieSupport.kt)。其中包括 SAPISID / APISID、SID 家族和对应 `__Secure-*` Cookie。

### 会话如何用于 API 和下载

[YouTubeRequestSupport.kt](https://github.com/cwuom/NeriPlayer/blob/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c/modules/platform/src/main/java/moe/ouom/neriplayer/platform/youtube/api/transport/YouTubeRequestSupport.kt) 为页面请求加 Cookie、UA，为 Innertube 请求加 `X-Goog-AuthUser`，并按当前时间、origin 和 SID Cookie 重新计算 SHA-1 的 `SAPISIDHASH` / `SAPISID1PHASH` / `SAPISID3PHASH`。这是网页会话签名，不是 OAuth Bearer token。

媒体下载不是把登录 Cookie 无差别发送给所有地址：同一源码专门剥除 googlevideo 媒体请求中的登录 Cookie / Authorization 等头，改用对应媒体 UA、origin、referer。[AudioDownloadSourceResolver.kt](https://github.com/cwuom/NeriPlayer/blob/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c/modules/download/runtime/src/main/java/moe/ouom/neriplayer/core/player/download/source/AudioDownloadSourceResolver.kt) 从自己的 YouTube 播放仓库取得直链或 HLS，检查缺少 PO Token 的 WEB_REMIX 地址并尝试降级；[AudioDownloadFileTransfer.kt](https://github.com/cwuom/NeriPlayer/blob/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c/modules/download/runtime/src/main/java/moe/ouom/neriplayer/core/player/download/transfer/AudioDownloadFileTransfer.kt) 以 OkHttp 完成下载、范围读取和完整性检查。其 [Gradle 依赖](https://github.com/cwuom/NeriPlayer/blob/bcc057a15ee6d8ff1f4c3c6de7115a177756b91c/gradle/libs.versions.toml) 包含 NewPipeExtractor、AndroidX JavaScriptEngine、Media3 和 OkHttp；不能误称这个链路本身就是 Python yt-dlp。

作者在 [Issue #257](https://github.com/cwuom/NeriPlayer/issues/257) 明确反馈网络、账户和 IP 会影响结果，能播放不代表能完整下载；用户在后续版本曾复测恢复。因此这里只借鉴“真实会话验证”和“登录、解析、下载分层”，不照搬大规模回退体系。

### iPhone 能做哪些，哪些不能直接照搬

技术上能实现同类本机会话入口：`WKWebView` 展示网站，使用同一 `WKWebsiteDataStore` 的 [WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore) 获取和观察本 WebView 的 Cookie；允许用户保存后，把必要会话材料存入 Keychain，再供本机 URLSession / Python cookiejar 使用。`HttpOnly` 不应靠 `document.cookie` 抓取；使用 WebKit 原生 cookie store。iOS 26 用 `getAllCookies` / `allCookies` 后按域筛选；不能误用文档主线里才标 iOS 27 的按 URL 取 Cookie 新接口。

但 Android `shouldInterceptRequest` 不是 iOS `WKNavigationDelegate` 的等价功能。后者不能当作捕获全部 HTTPS 子资源 / XHR 请求头的网络代理；移植应从 CookieStore 和 YouTube 页面的少量登录标记入手，通过独立请求验证。现有 yt-dlp 负责 YouTube 自己的 API 会话签名，不需要为下载再重写 NeriPlayer 全套 Innertube 协议。

系统浏览器方案也有明确限制：[ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) 返回服务端重定向的 callback URL；没有把 Google / YouTube 全部 Cookie 导出给调用应用的接口。[SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller) 也隔离网页交互，不能拿来读取 Cookie。用户在 Safari 登录后，不应声称本机 yt-dlp 自动获得其 Safari 登录会话。

Google 对嵌入浏览器有实际限制：[OAuth 政策](https://developers.google.com/identity/protocols/oauth2/policies) 禁止把 OAuth 授权请求放在开发者可控制的 embedded user-agent；[错误说明](https://developers.google.com/identity/protocols/oauth2/javascript-implicit-flow#disallowed_useragent) 明确提到 WKWebView 可得到 `disallowed_useragent`。NeriPlayer 用的是 Google 自家 ServiceLogin 网页入口，不能将第三方 OAuth 的规则机械等同于“该入口必定无法打开”；同样不能把 Android 的 UA 技巧当作 iPhone 可稳定通过 Google 检查的证明。

建议本项目将用户入口命名为“YouTube 网页登录”，无需要求用户创建本应用 Client ID。先独立实现 WKWebView 会话、CookieStore、Keychain、注销清理和真实 YouTube 页面验证，并将被网站拒登的原因如实显示。若当前 iPhone / Google 账户拒绝内嵌登录，保留用户主动导入自己的 Netscape Cookie 文件这一可行回退；不要把打开 Safari 或 Google OAuth SDK 显示为网页会话已取得。是否能在目标 iPhone 真正登录，需要真机验证，本轮只完成源码与官方 API 核对。

## m.youtube.com 搜索卡片

手机页面不是受保证的公开 JSON API。建议请求 `https://m.youtube.com/results?search_query=...` 后，从页面中提取 `ytInitialData` 的完整 JSON，再转为自己的 Swift 类型。提取 JSON 边界要识别引号、转义和括号深度，不使用遇到第一个 `}` 就结束的正则。

只遍历有意义的视频 renderer，例如 `videoRenderer`、`compactVideoRenderer`；对当前移动页出现的 `videoWithContextRenderer` 等结构按实际夹具补充。读取 video ID、标题、作者、缩略图和时长；以 video ID 去重。频道、播放列表、广告和 Shorts shelf 不要伪装成普通音频结果。NewPipe 当前 [搜索器源码](https://github.com/TeamNewPipe/NewPipeExtractor/blob/dev/extractor/src/main/java/org/schabi/newpipe/extractor/services/youtube/extractors/YoutubeSearchExtractor.java) 和 yt-dlp [搜索入口](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_search.py) 可以作为区分结果类型与 continuation 的参考，二者并未保证所有移动页面字段不变。

`200` 加空卡片也可能是 consent、机器人校验或结构变化。把“没有结果”和“未能解析页面”分开显示。先做普通单页搜索，未实现 continuation 时不要声称支持完整分页。解析代码自行实现，只借鉴 renderer 思路。

## 500 MB 缓存规则

以下是本项目规则，不是第三方 API 行为：

- 固定容量按 500,000,000 字节计，UI 显示 500 MB。自动缓存和用户主动下载分开保存、分开计数。
- 仅完整且验证通过的文件进入缓存清单。临时下载不计为可播放缓存，失败和取消清理临时文件。
- 按缓存完成时间排序；容量超限时，先删最旧的自动缓存；展示顺序仍为从新到旧，读取缓存不改变完成时间。
- 正在播放的音频须有明确持有策略，避免清理后尚未打开文件；单文件超过上限时明确拒绝自动缓存或只保留为临时播放文件，不把永久超限写入清单。
- 手动下载永不参与这 500 MB 的淘汰。自动缓存转为手动下载时，先通过现有资料库导入事务保存独立副本；永久副本不参与缓存淘汰。
- 重启后按磁盘现状校正清单。系统可以清除 `Library/Caches`，记录存在不等于文件仍存在。

## 远端与真机验收重点

远端 CI 应验证设备和模拟器均能链接 Python、导入 ssl/ctypes/yt-dlp/EJS/provider，执行自造文件的下载落盘和缓存规则。真实 YouTube 验收还要覆盖一次实际签名挑战、下载完整 m4a 后再播放、切歌取消、断网重试、登录恢复、回调 scheme、缓存重启和手动下载保留。GitHub runner 可能被 YouTube 限流；这类限制不能用删除真实验收或改成假成功掩盖。

本次没有部署或选择服务器，也没有向 GitHub 发消息。上述研究只创建本文档。
