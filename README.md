# c0versnow music

[下载 v1.1.0-beta.1 IPA](https://github.com/C0verSnow/c0versnowmusic/releases/download/v1.1.0-beta.1/C0SnowMusic-unsigned.ipa) · [Release 与验收记录](https://github.com/C0verSnow/c0versnowmusic/releases/tag/v1.1.0-beta.1)

IPA 未签名，须用自己的 Apple 证书签名安装。

iPhone 上的原生音乐播放器，最低 iOS 26.0。使用 Swift 6、SwiftUI、SwiftData、AVFoundation 和系统 Liquid Glass。本地资料库离线使用，不自动上传本地音乐；可选 Google 登录、YouTube Music 搜索和 Telegram 音乐仓库。

本分支按 [issue #7](https://github.com/C0verSnow/c0versnowmusic/issues/7) 整体替换旧 Electron/Vue/Android 代码。桌面端、Bilibili、在线解析及旧下载脚本已移除；旧实现仍可从 Git 历史获取。

Issue #15 的对象职责、播放链路与恢复规则见 [面向对象架构核对](docs/OBJECT_ARCHITECTURE.md)。缓存优先；YouTube 曲目遇到云端缺失或故障时尝试手机重新获取，完成后后台补传。

仓库地址现为 `C0verSnow/c0versnowmusic`，应用显示名为 `c0versnow music`。存储升级接入固定版本的 [gps949/tg-s3](https://github.com/gps949/tg-s3)，音乐 API、旧 Telegram 音频和手机缓存继续兼容；接入、部署和回退见 [TG-S3 升级说明](docs/TG_S3_UPGRADE.md)。Xcode 工程、Bundle ID 和已发布 IPA 文件名保留原标识，支持覆盖安装。

## 当前界面

应用显示名为 c0versnow music。Issue #13 按提供的 Apple Music 截图整理原生界面，统一英文、搜索和资料库；YouTube 歌单、专辑、艺人直接进入对应分类，不再另设 Online Library。歌词页只保留右下角设置入口，旧缓存缺封面会独立恢复。行为、来源与验证范围见 [产品界面说明](docs/PRODUCT_UI.md)。

音频准备卡住时，可从账户 → Music Settings → Debug 查看实时阶段、耗时、网络状态和脱敏日志，并检查连接、复制或分享诊断。功能和隐私范围见 [应用内 Debug](docs/APP_DEBUG.md)。

## 打开与运行

1. 安装含 iOS 26 SDK 的 Xcode 26 或更新版本。
2. 打开 `C0SnowMusic.xcodeproj`，选择共享 Scheme `C0SnowMusic`。
3. 在 Signing & Capabilities 中选择自己的 Team；必要时把 Bundle Identifier 改成自己的唯一标识。
4. 选择 iOS 26 iPhone 或模拟器，运行。
5. 点击账户 → Music Settings →「从文件导入」，从「文件」选择音频；也可从其他 App 的「打开方式」交给 c0versnow music。

在线下载内置 BeeWare Python 3.13、yt-dlp、EJS 和 Apple WebKit 插件，Google/YouTube 网页登录使用系统 WKWebView 与 Keychain。无需服务器、Node、CMake、XcodeGen 或 CocoaPods。首次打开工程前运行 `python3 scripts/prepare_online_runtime.py` 下载固定校验值的预编译运行时和纯 Python 包；该脚本不会编译。项目文件直接纳入版本管理，新增源码由 Xcode 的同步目录管理。

仓库约定禁止本地编译验证。自动编译与测试使用原有 `build-player.yml` 改造的 GitHub Actions；以上 Xcode 步骤供用户安装真机使用。CI 上传的 iPhone `.app` 未签名，不能直接安装；必须用自己的开发者签名构建或导出。

## 功能

- Home、Radio、Library、Search 四个原生 Tab；滚动收起的系统底栏和浮动 Mini Player。Radio 使用真实 YouTube 电台歌单，空队列显示 Not Playing。
- 右上角 c0versnow music Account 包含 YouTube 网页登录和 Music Settings；界面统一英文，含导入和缓存管理，旧语言偏好不再影响显示。
- 搜索采用 c0versnow music / Library 两档，直接读取 YouTube Music 和已连接仓库；只显示封面、标题、作者卡片，不展示网页；综合结果按最佳结果、歌曲、视频等分组，可筛选、翻页和管理搜索历史；点歌后才获取音频。
- 真正的手机本机 yt-dlp 下载完整 M4A 纯音频；500 MB 缓存按完成时间从新到旧显示，容量不足删除最旧缓存。手动下载到资料库的副本单独保存，不参与自动淘汰。
- 全屏播放器、系统缩放转场、顶部下拉收起、进度预览和跳转、系统音量、AirPlay、收藏和分享。
- 单个或批量导入、取消、失败明细、流式 SHA-256 重复检测、跳过或保留副本。
- 应用沙盒保存音频、元数据与封面；封面降采样、内存和磁盘缓存。
- 歌曲、专辑、艺术家、流派、最近添加、最近播放、收藏；排序与防抖搜索。
- 播放列表创建、重命名、添加、移除、排序、删除及照片封面。
- 一个共享 PlaybackStore / AVPlayer；队列编辑、随机、单曲循环、列表循环和自动下一首。
- 后台播放、锁屏/控制中心/耳机控制、中断与拔耳机处理；恢复队列和进度时不自动发声。
- 内嵌歌词、LRC 导入、逐行高亮、滚动跟随和点词跳转；手动滚动后暂停跟随六秒。
- 编辑音乐库中的歌曲信息；不改写音频文件。
- 支持系统深浅外观、Dynamic Type、VoiceOver 和 Reduce Motion。全屏播放器始终使用暗色以保证对比度。

## 音频兼容性

目标容器和编码：MP3、FLAC、M4A/AAC、ALAC、WAV、AIFF。扩展名只用于系统文件选择过滤。导入会检查 AVURLAsset 可播放性、音轨、时长和首段 PCM 解码；完整播放错误通过播放器显示。

首段解码通过不代表整份文件无损坏。不同容器、编码、位深、采样率和设备组合必须实际播放验证。系统无法解码的文件会明确报错，处理办法是转换为 ALAC、M4A 或 WAV；当前没有引入额外解码器。FLAC 另有独立 Vorbis Comment / Picture 读取器，补充系统未暴露的标签。缺少元数据时使用原始文件名、「未知艺术家」「未知专辑」和中性封面。

远端测试生成三秒合成音，验证真实导入和 AVPlayer 播放推进、暂停、Seek、结束事件，包含 MP3、FLAC、AAC、ALAC、WAV、AIFF 和 24-bit/96 kHz 双声道 FLAC。完整结果及尚未验收项见 [测试与验收](docs/VERIFICATION.md)。未经过真机测试的格式不能据此声称已在所有 iPhone 完整支持。

## 下载歌词、封面和校准时间

全屏播放器打开 Lyrics，点击右下角 Lyrics Settings，在菜单选择 Find Lyrics and Artwork。导入 LRC 和时间校准也在同一菜单。歌名和艺术家可编辑；缺少标签但文件名形如 `艺术家 – 歌名` 时会预填这两个字段。

1. 点击「搜索歌词」。优先按歌名、歌手、专辑和音频真实时长精确查询 LRCLIB，找不到合适同步版本再列出搜索候选。
2. 核对专辑和录音版本，选择「使用此版本」。匹配结果中的标准歌名和艺术家会自动写回资料库，更新艺人分组和系统播放信息，无须逐项手改；其他标签保留。同步歌词保存为带时间戳的 LRC；没有时间戳时显示纯文本，不伪造同步。
3. 默认同时下载缺失的封面，来源为 MusicBrainz / Cover Art Archive。已有封面保留；封面服务失败不会撤销已经保存的歌词。
4. 在「歌词时间校准」里，可按 0.5 秒调整提前或延后，范围 ±30 秒。高亮和点行跳转使用同一个偏移量，并按歌曲保存。LRC 自带 offset 同样生效。

下载后歌词和封面留在本地，关闭、重启或断网仍可使用。只有主动搜索/下载时才向服务发送歌名、艺术家、专辑和时长；不会上传音频。429/503 的 Retry-After 会阻止过早请求，网络失败可以重试。

歌词查询参考用户指定的 [lyrics-downloader](https://github.com/antongpopov/lyrics-downloader)，仍使用原生 Swift URLSession，不经过音频下载用的 Python。[来源、许可证和匹配细节](docs/LYRICS_RESEARCH.md)。

## YouTube Music 与 Telegram 音乐仓库

Issue #11 新流程、D1 数据模型、专用 Bot 配置、收藏同步、20 MB 交付范围和故障恢复见 [音乐仓库说明](docs/TELEGRAM_MUSIC.md) 与 [接口调研](docs/TELEGRAM_MUSIC_RESEARCH.md)。首页使用 YouTube Music 真实分区，账户显示真实头像和验证状态；连接仓库后先查索引，缺失时手机获取 M4A 并上传 Telegram，取消收藏保留音频。

## 在线搜索、下载和 Google 登录

见 [在线功能配置与验收](docs/ONLINE_MUSIC.md)、[开源方案比较](docs/ONLINE_MUSIC_RESEARCH.md)。音源获取在手机完成；连接仓库后，存储和取回音频经过独立 Worker/D1 与 Telegram。只选择 YouTube 提供的原生 AAC/M4A 音轨，不下载视频，不伪造 MP3/FLAC 或无损音质；不支持的格式、地区限制、验证页面和网络错误会提示。缓存可被系统清理，长期保留请点「下载到资料库」。

Google 登录按 [NeriPlayer](https://github.com/cwuom/NeriPlayer) 的网页会话思路独立实现：通过 Google 网页登录 YouTube，确认已登录后把 Cookie 存入本机 Keychain，供搜索和 yt-dlp 使用。不需要 Google Client ID 或服务器。Google 可能拒绝内嵌浏览器登录；以真机结果为准，不会把失败显示成成功。

## 应用图标

按用户提供的 `Apple Music-iOS-512x512.png` 生成图标。源文件位于 `Design/AppIconSource.png`；1024px 无透明图片位于 AppIcon.appiconset，并在工程中指定 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。修改源图后，在 macOS 用 `osascript -l JavaScript scripts/make_app_icon.js <仓库绝对路径>` 重新生成，不手改生成文件。

## 文件与隐私

音频位于 `Application Support/MusicLibrary/Audio/`，数据库只存相对路径。导入使用 Security-Scoped URL；分块复制到 `Staging/`，检查后同卷移动；保存数据库失败会清理新文件。完全相同文件在复制前通过内容哈希识别。

音频和数据库默认参与系统设备备份。设置中可排除音频备份；封面有播放器版和列表缩略图。删除时可选择：

- **仅移除记录**：移除歌曲和播放列表引用，文件留在 `Removed/`，可在设置里重新导入。
- **同时删除音频文件**：移除记录并删除应用沙盒中的副本；「文件」中的原始文件不变。

允许打开其他 App 提供的音频，使用标准文档打开流程，没有 Share Extension，因此不需要 App Group。只配置 `UIBackgroundModes = audio`，不请求 Apple Music、麦克风或整个照片库权限。照片封面通过系统照片选择器提供单个已选择项目。

## 工程与验证

- [架构、阶段与参考来源](docs/ARCHITECTURE.md)
- [测试、真机验收和已知限制](docs/VERIFICATION.md)
- [第三方来源与许可证](docs/THIRD_PARTY.md)
- [在线功能、打包与已知限制](docs/ONLINE_MUSIC.md)
- [任务过程](tasklist.md)

CI 在 iOS 26 模拟器运行 XCTest 集成测试和 XCUITest，再编译未签名 iPhone Release。测试音频由 `scripts/make_audio_fixtures.py` 在远端生成，无真实用户音乐、无下载音源，Release 不包含这些测试资源。检查日志和 `.xcresult` 从 Actions 的 `iOS-test-evidence` 下载。
