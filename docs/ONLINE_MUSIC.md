# 在线音乐与账号

按 NeriPlayer 的网页会话用途实现登录，不需要 Google Client ID。Issue #9 在 `feature/issue-9-online-music` 实现。PR 等待用户 review，不自动合并。

## 操作

1. 右上角头像打开 c0versnow music Account，点 Music Settings 进入设置。应用界面统一英文，不再提供语言切换；当前行为与验证范围见 [PRODUCT_UI.md](PRODUCT_UI.md)。
2. 账户页可选 YouTube 网页登录、恢复和退出。本地音乐和公开在线功能不强制登录。
3. 搜索 Tab 选择 c0versnow music，输入歌名/歌手自动搜索。使用 YouTube Music 综合/分类搜索，按最佳结果、歌曲、视频等分组；歌手、专辑、歌单进入对应内容页。已连接仓库的匹配结果合入同一搜索。实际接口结构与许可见 [调研](TELEGRAM_MUSIC_RESEARCH.md)。
4. 点卡片后才准备音频；菜单可预下载或下载到资料库，同一时间一个下载，可取消。连接音乐仓库后的查重、上传与 Telegram 取回流程见 [音乐仓库](TELEGRAM_MUSIC.md)。
5. 在线缓存复用现有 AVPlayer、锁屏控制、后台播放和队列。缓存歌曲先完整下载并验证纯音频，再开始播放。缓存歌曲支持自动歌词、专辑和封面补齐，也可从 Lyrics Settings 手动查找或导入歌词；本地播放列表和元数据编辑使用保存到资料库的副本。临时缓存播放队列不在重启后自动恢复，可从缓存列表重新播放。

## 缓存

完整音频位于 `Library/Caches/OnlineAudio`，按完成时间从新到旧排列。上限严格按 500,000,000 字节计；添加新文件前删除最旧缓存。清单原子写入；启动时排除已被系统清掉的文件。失败、取消的临时下载会清理，单文件超过上限会报错。

`OnlineStaging` 只存进行中的下载，不出现在可播放清单中；下载过程也限制为 500 MB。用户点「下载到资料库」后，现有导入事务将副本存入 `Application Support/MusicLibrary/Audio`；缓存清理永远不遍历该目录。手动歌曲不计入 500 MB。

## 无服务器打包

首次准备依赖：`python3 scripts/prepare_online_runtime.py`。只下载和解包，无本地编译。推荐使用 Python 3.12 以上运行准备脚本。

- 固定 BeeWare `3.13-b18` iOS device/simulator XCFramework，校验官方 SHA-256。
- `scripts/online-requirements.txt` 固定四个纯 Python wheel 的版本和 SHA-256。没有手机运行 pip、动态下载脚本或远程执行服务。
- Xcode 中 `Package on-device Python runtime` 使用发行包附带的官方 `install_python` helper，将标准库和扩展打为 iOS frameworks；unsigned CI 采用 ad-hoc 签扩展，正式应用按自己的签名配置处理。
- 使用 Swift Python C API，在串行后台队列管理初始化、GIL 和调用。WebKit 操作通过上游插件回到主线程；Swift 添加自己的导航/弹窗限制，避免上游已知的跳转 YouTube 问题。
- 只选 `bestaudio[ext=m4a][vcodec=none]`，无需 FFmpeg。文件仍通过 AVFoundation 的可播放性、音轨与无视频检查，才进入缓存。

二进制与 wheel 位于被 Git 忽略的 `Vendor/`；GitHub Actions 在编译前运行同一准备脚本。请保留发行包和 wheel 内的全部第三方许可。设计参考、候选取舍见 [调研](ONLINE_MUSIC_RESEARCH.md)，不复制 Palladium 的 GPL 实现。

## IPA 发布

推送以 `v` 开头的版本标签会运行已有完整 iOS CI，全部通过后自动将 `C0SnowMusic-unsigned.ipa` 上传到同名 GitHub Release。带连字符的标签（例如 `v1.1.0-beta.1`）标为预发布；常规 `v1.1.0` 为正式发布。Release 的 IPA 与该标签源码、测试提交一致。未签名 IPA 仍须用自己的 Apple 证书签名安装，不能把 ZIP 包直接当成已签名应用。

## Google / YouTube 网页登录

参考 NeriPlayer 的网页会话设计，自行使用系统 WKWebView 实现，不复制其 GPL 代码，也不接入独立的 Google OAuth 身份登录 SDK。网页直接打开 Google 的 YouTube ServiceLogin，用户在 Google 页面完成认证，然后返回 YouTube 并点击「保存登录」。

只有真实 YouTube 页面返回 `ytcfg.LOGGED_IN`，且浏览器 CookieStore 中存在 YouTube 身份 Cookie 时才保存。Cookie 加密保存在本机 Keychain，不同步 iCloud，不写入仓库或测试日志；登录 WebView 使用独立内存数据存储，与 EJS 挑战 WebView 隔离。重启从 Keychain 恢复；会话失效仍需重新登录，保存过不代表服务器永远接受。

搜索将 YouTube 域 Cookie 附在 m.youtube.com 请求；下载把同一批 Cookie 转成 Python 原生 cookiejar，交给 yt-dlp。退出会清除 Keychain 与登录 WebView Cookie，并取消进行中的在线请求。已下载的本地音频不依赖账号。

iPhone 的 WKNavigationDelegate 不具有 Android WebView 的所有请求拦截能力，因此不照搬 NeriPlayer 的 youtubei 请求头拦截和复杂回退。Google 可能拒绝内嵌浏览器，不能承诺所有账户可登录；拒绝时保留真实页面和提示，不伪造登录成功。系统 Safari 与 OAuth 会话不能直接导出网站 Cookie，因此不把「在 Safari 登录」当作本 App 已有会话。

## 验证与限制

本地只做源码阅读、Python AST、shell 语法、plist 与差异检查，禁止本地编译或运行会触发编译的测试。远端已有 `build-player.yml` 负责模拟器/真机 Release 编译、XCTest 和 XCUITest。

新增测试覆盖手机页面解析与去重、错误页识别、真实 M4A 缓存淘汰、重启清单恢复、手动导入副本保留、拒绝 HTML、Python/SSL/WebKit 执行、设置入口与语言切换。CI 的通过状态须以 PR checks 为准；测试不使用用户音乐。

真实 Google/YouTube 网页登录需要在设备上完成认证后验收。真实 YouTube 下载会受平台页面/签名变化、地区、PO Token 和机器人验证影响；不声称支持所有视频，也不把合成文件测试当作真实网站下载成功。Search and library collections support continuation pagination.WebKit 插件使用 yt-dlp 私有 provider 接口，升级时须一起验证固定版本组合。

### DASH 音频容器

YouTube 的 M4A DASH 文件在 iPhone 验收中出现双倍时长和空尾。参考 [yt-dlp FixupM4a](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/postprocessor/ffmpeg.py)，手机用 AVAssetExportSession 的 Passthrough 将下载文件重新封装成标准 M4A，并使用 yt-dlp 返回的源时长限定范围。此过程不重新压缩音频，不需要 ffmpeg 或服务器。远端 CI 使用 FFmpeg 生成的合成 DASH 音频验证实际时长、解码和跳转。
