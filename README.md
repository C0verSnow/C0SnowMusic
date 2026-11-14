# C0SnowMusic

iPhone 上的原生本地音乐播放器，最低 iOS 26.0。使用 Swift 6、SwiftUI、SwiftData、AVFoundation 和系统 Liquid Glass。无需账号，不接入在线曲库，不上传音乐。播放和资料库离线使用；歌词和封面可由用户主动联网查询。

本分支按 [issue #7](https://github.com/C0verSnow/C0SnowMusic/issues/7) 整体替换旧 Electron/Vue/Android 代码。桌面端、Bilibili、在线解析及旧下载脚本已移除；旧实现仍可从 Git 历史获取。

## 打开与运行

1. 安装含 iOS 26 SDK 的 Xcode 26 或更新版本。
2. 打开 `C0SnowMusic.xcodeproj`，选择共享 Scheme `C0SnowMusic`。
3. 在 Signing & Capabilities 中选择自己的 Team；必要时把 Bundle Identifier 改成自己的唯一标识。
4. 选择 iOS 26 iPhone 或模拟器，运行。
5. 点击右上角「+」，从「文件」选择音频；也可从其他 App 的「打开方式」交给 C0SnowMusic。

本项目无第三方运行时依赖，无需 Node、CMake、XcodeGen、CocoaPods 或服务端。项目文件直接纳入版本管理，新增源码由 Xcode 的同步目录管理。

仓库约定禁止本地编译验证。自动编译与测试使用原有 `build-player.yml` 改造的 GitHub Actions；以上 Xcode 步骤供用户安装真机使用。CI 上传的 iPhone `.app` 未签名，不能直接安装；必须用自己的开发者签名构建或导出。

## 功能

- 首页、发现、资料库、搜索四个原生 Tab；滚动收起的系统底栏和浮动 Mini Player。
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

全屏播放器打开「歌词」，点击「在线查找歌词与封面」或底部搜索按钮。歌名和艺术家可编辑；缺少标签但文件名形如 `艺术家 – 歌名` 时会预填这两个字段。

1. 点击「搜索歌词」。优先按歌名、歌手、专辑和音频真实时长精确查询 LRCLIB，找不到合适同步版本再列出搜索候选。
2. 核对专辑和录音版本，选择「使用此版本」。匹配结果中的标准歌名和艺术家会自动写回资料库，更新艺人分组和系统播放信息，无须逐项手改；其他标签保留。同步歌词保存为带时间戳的 LRC；没有时间戳时显示纯文本，不伪造同步。
3. 默认同时下载缺失的封面，来源为 MusicBrainz / Cover Art Archive。已有封面保留；封面服务失败不会撤销已经保存的歌词。
4. 在「歌词时间校准」里，可按 0.5 秒调整提前或延后，范围 ±30 秒。高亮和点行跳转使用同一个偏移量，并按歌曲保存。LRC 自带 offset 同样生效。

下载后歌词和封面留在本地，关闭、重启或断网仍可使用。只有主动搜索/下载时才向服务发送歌名、艺术家、专辑和时长；不会上传音频。429/503 的 Retry-After 会阻止过早请求，网络失败可以重试。

本次参考用户指定的 [lyrics-downloader](https://github.com/antongpopov/lyrics-downloader)，实现为原生 Swift URLSession，没有引入 Python 运行时。[来源、许可证和匹配细节](docs/LYRICS_RESEARCH.md)。

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
- [任务过程](tasklist.md)

CI 在 iOS 26 模拟器运行 XCTest 集成测试和 XCUITest，再编译未签名 iPhone Release。测试音频由 `scripts/make_audio_fixtures.py` 在远端生成，无真实用户音乐、无下载音源，Release 不包含这些测试资源。检查日志和 `.xcresult` 从 Actions 的 `iOS-test-evidence` 下载。
