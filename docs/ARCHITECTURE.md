# 原生播放器架构

## 数据和状态

```text
MusicRootView（首页 / 发现 / 资料库 / 搜索）
  ├─ LibraryStore → SwiftData（LibrarySchemaV1 / LibraryMigrationPlan）
  │    └─ AudioImportService actor → SHA-256 / MetadataExtractor / ArtworkCache actor
  ├─ YouTubeAccountStore → WKWebView / CookieStore → Keychain
  ├─ OnlineMusicStore → m.youtube.com / OnDeviceDownloader（串行 Python C API）
  │    └─ OnlineAudioCache actor → 500MB M4A 文件；手动保存仍走资料库导入
  └─ PlaybackStore → PlayerEngine → AVPlayerEngine（唯一 AVPlayer）
       ├─ QueueManager
       ├─ AudioSessionManager
       └─ RemoteCommandManager → MediaPlayer
```

Song、Album、Artist、Playlist、PlaylistItem 和 PlaybackSession 为持久化模型。资料库写操作集中在主线程的 LibraryStore；导入、哈希和文件复制通过独立 actor 执行，元数据异步加载。UI 和系统遥控共用一个 PlaybackStore；播放器是否展开与是否播放各自独立。

歌曲通过 ID 关联专辑、艺术家和播放列表。更新歌曲信息时重新分组，移除歌曲时清理列表引用和空分组。队列条目另有独立 ID，允许同一歌曲重复加入；保存快照和当前条目下标，恢复时过滤已经移除的歌曲。

## 文件导入

1. 获取安全访问，读取文件属性，以 1 MiB 分块计算 SHA-256。
2. 按大小和哈希检查完全重复文件；提供跳过和保留副本策略。
3. 检查可用空间，分块复制到沙盒暂存目录。
4. AVFoundation 检查真实音轨并读取首段 PCM，异步读取系统元数据；FLAC 额外解析 Vorbis 和图片块。
5. ImageIO 在后台生成 1024px 封面与 160px 缩略图。
6. 原子移动音频文件，再保存数据库；数据库失败时清理这次新增文件。

数据库只保存 UUID 文件名和相对路径。取消在分块读取、复制及异步阶段检查。普通元数据失败不阻断有效音频导入；不支持的编码明确拒绝。数据库错误不会自动删除原有资料库。

## UI 和交互

原生 `TabView` 使用 `tabBarMinimizeBehavior(.onScrollDown)` 和 `tabViewBottomAccessory`，让系统协调安全区域和玻璃材质。`matchedTransitionSource` 与系统 zoom 转场承接 Mini Player 和全屏播放器；减少动态效果时使用普通系统呈现。主内容不铺玻璃材质。iOS 26.1 起使用 `tabViewBottomAccessory(isEnabled:content:)` 隐藏未加载歌曲时的附件，保留 Tab 和导航状态；iOS 26.0 使用原有条件内容。

全屏播放器使用封面缓存中的单次取色、静态渐变、原生系统音量和 AirPlay 选择器。滑块拖动仅预览，放手 Seek；头部拖动收起，避免与进度条争夺手势。歌词仅按文件时间戳逐行同步，不虚构逐字精度。

## 阶段交付

| 阶段 | 实现入口 | 验证方式 |
| --- | --- | --- |
| 1 工程 | Xcode 项目、AppRuntime、SwiftData 模型、Info.plist | 静态配置检查、远端编译 |
| 2 界面 | HomeView、LibraryView、SearchView、MiniPlayerView、NowPlayingView | 远端 XCUITest；真机视觉待验收 |
| 3 导入 | AudioImportService、MetadataExtractor、FLACMetadata、ArtworkCache | 远端真实合成音导入、重复、损坏、取消测试 |
| 4 播放 | PlayerEngine、AVPlayerEngine、PlaybackStore、系统集成 | 远端 AVPlayer 实际推进、暂停、Seek、结束；系统硬件控制待真机 |
| 5 资料库 | LibraryStore、PlaylistsView、MetadataEditor | 远端持久化、列表排序、收藏、分组和删除测试 |
| 6 歌词与细节 | LyricsView、LRCParser、系统辅助功能 | 解析测试、页面测试；完整辅助功能待真机 |

以上为代码覆盖范围，不能替代测试通过或真机验收。当前证据见 VERIFICATION.md。

## 在线会话与本机下载

账户页内的 Music Settings 承接原设置，语言保存在 UserDefaults；局部标题观察语言变化，不重建整棵 Tab 或播放状态。YouTube 网页会话参考 NeriPlayer 的设计独立实现，只有真实 YouTube 页面的登录信号和身份 Cookie 同时满足才写 Keychain。登录 WebView 的内存数据存储与 EJS 挑战 WebView 分开，搜索和 yt-dlp 只使用 YouTube 域会话。

搜索从手机页面提取对象或转义字符串形式的 ytInitialData，自行转为视频卡片。下载通过 BeeWare 预编译 Python、固定版本 yt-dlp/EJS/WebKit 完全在手机内运行；只有完整且可播放、没有视频轨的 M4A 才进入缓存。缓存按完成时间从新到旧显示，容量不足先删最旧项。手动下载通过原导入事务保存独立文件，永不参与缓存淘汰。

缓存播放仍使用唯一 PlaybackStore / AVPlayer；临时 Song 不写入 SwiftData。主动清缓存时同步移除对应播放队列和临时路径，避免按钮继续引用已删文件。永久资料库模型和数据库版本保持不变。详细配置与验收见 ONLINE_MUSIC.md。

## 官方 API 依据

- [SwiftUI 新设计与系统底栏](https://developer.apple.com/videos/play/wwdc2025/323/)
- [tabViewBottomAccessory](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:))
- [异步加载媒体信息](https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously)

参考源码的提交、依赖和许可核对见 THIRD_PARTY.md。在线功能使用系统 WebKit 和本机 Python 下载引擎，不依赖自建服务器；音频播放与解码仍交给系统 AVFoundation。
