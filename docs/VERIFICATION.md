# 测试与验收

## 当前证据

- 本机只有 Command Line Tools，没有完整 Xcode 和 iOS SDK。本地没有编译、构建或运行会触发编译的测试；仅阅读代码，检查属性列表、资源、语法和差异。真机通过 iPhone Mirroring 操作，不是 USB 调试会话；本轮系统日志显示 iPhone OS 27.0（24A435）。
- [CI 43601356473](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43601356473) 是早期源码的通过结果，不能代表本轮源码。
- [CI 43609769276](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43609769276)：模拟器、iPhone Release、图标和 IPA 通过；21 项单元/集成有 1 项 MP3 歌词失败，2 项 UI 有 1 项因嵌套页面出现两个“完成”按钮失败。
- [诊断 CI 43611483223](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43611483223)：2 项 UI 全通过，21 项单元/集成仍有 1 项 MP3 歌词失败。真实文件日志确定 `id3/TXXX` 的 `.info` 为 `USLT`，文本值正常；读取器已补认该别名，临时诊断已删除。
- 修复提交 `55c0a10` 的 [CI 43612778897](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43612778897) 全通过；之后真机发现新的封面回调崩溃，不能据此宣称真机完成。
- 真机已通过 Chrome 下载 1.0.1，用户从心动签导入，沿用现有证书和 Bundle ID 覆盖安装成功。Spotlight 显示指定图标；原歌曲和 2:35 进度保留，启动时保持暂停。
- 真机搜索 Die For You / The Weeknd / Starboy / 4:20 成功，同步歌词保存并显示；点击首行跳到 0:28，播放时高亮与滚动跟随，偏移可设为延后 0.5 秒，测试后恢复为 0。
- 真机首次封面请求返回 400。直接请求确认：CAA 小写 UUID 返回 200、JPEG、89,288 字节，同一 UUID 大写返回 400。请求已改用小写；1.0.2 真机重试后发生退出，日志确认系统后台请求封面时，RemoteCommandManager 的回调触发 Swift actor 隔离断言。已在 1.0.3 / `5ab55d5` 把只读图片回调显式标为 `@Sendable`，并补系统后台读取回归；[CI 43614305475](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43614305475) 全通过：21 项单元/集成、2 项 UI，模拟器编译、iPhone Release、图标检查和 IPA 打包通过。
- 先前真机已检查退到主屏幕后时间继续推进、控制中心暂停与恢复。本轮 1.0.3 锁屏持续播放、封面、暂停和恢复，以及耳机断开暂停、来电中断和挂断恢复均由用户确认正常。

## 自动化覆盖

远端 CI 运行真实应用代码，音乐由仓库脚本生成，不依赖服务器或用户歌曲：

- 真实导入 MP3、FLAC、AAC、M4A、ALAC、WAV、AIFF；24-bit/96 kHz 双声道 FLAC 和 WAV。
- 解码、元数据、无标签回退、Unicode 文件名、重复内容、保留副本、损坏文件清理和取消。
- 磁盘数据库持久化、恢复进度和队列、恢复时保持静音。
- 播放列表排序、改名、收藏、元数据编辑后分组、删除记录与文件清理。
- AVPlayer 真实播放时间推进、暂停、Seek、结束事件。
- LRC 多时间戳、偏移、损坏时间戳；队列循环、插入、删除及随机后条目一致性。
- 空资料库、主 Tab、导入入口、真实音频导入后的 Mini Player、全屏、歌词与队列面板。

CI 的测试音频仅是有限样本，不代表所有目标格式组合都兼容。音频测试验证解码和播放状态，不能验证扬声器实际声音或听感。

## 真机验收清单

以下必须由有设备的测试者完成，未完成前不能认定 issue 任务书中的整体验收达标：

- [x] 用现有签名证书在 iPhone 安装、启动。
- [x] 从「文件」导入用户指定 MP3 并实际播放（用户确认）；批量和 iCloud 延迟下载另行验收。
- [ ] 从其他 App 使用系统打开方式导入，检查沙盒副本可长期使用。
- [ ] 用真实 MP3、FLAC、M4A、AAC、ALAC、WAV、AIFF 检查出声、完整播放和 Seek。
- [ ] 用大体积 FLAC 检查导入取消、内存、温度和滑动流畅度。
- [ ] 检查无封面、嵌入封面、超大封面、中文日文文件名和长标题。
- [ ] 模拟磁盘空间不足，确认报错与未完成文件清理。
- [x] 退到主屏幕继续播放，控制中心暂停和恢复。
- [x] 锁屏 30 秒持续播放，锁屏封面、暂停和恢复（用户确认）。
- [ ] 锁屏和耳机上一首/下一首；耳机暂停控制。
- [x] 耳机断开自动暂停，来电中断和挂断恢复（用户确认）。
- [ ] 蓝牙及 AirPlay 路由切换的完整真机检查。
- [ ] 强制退出和重新启动，音乐库、播放列表、队列与进度仍在，且不自动发声。
- [ ] 不同 iPhone 尺寸、横屏、深浅色、最大字体、Reduce Motion、VoiceOver。
- [x] Mini Player 展开、按钮收起、歌词点选跳转、高亮跟随和 0.5 秒校准。
- [ ] 下拉收起、底栏滚动收缩、手动滚动暂停跟随的完整真机验收。
- [x] 1.0.3 覆盖安装后正常启动，原歌曲、进度和歌词保留，已下载的 Starboy 封面在 Mini Player 和全屏播放器显示，背景取色更新，未再次退出。
- [ ] 真机断网、强制退出后确认歌词、封面和校准仍在。

## 已知限制与处理

- 没有外部解码器。无法通过系统解码检查的文件需转换为 ALAC、M4A 或 WAV；错误会显示给用户。
- 资料库快照和搜索索引在内存中；列表使用原生懒加载，首页限制展示数量。数万首歌曲的内存和首屏时间尚未实测。
- 没有逐字歌词、在线曲库、账户、云同步、CarPlay、均衡器、无缝衔接或交叉淡化。这些不是本次基础播放链路的依赖。
- 自动化不制造设备真实磁盘耗尽、来电和耳机硬件事件，这些保留为真机验收项。
- 暂存/删除文件遇到系统强制杀进程时的崩溃恢复，以及封面孤立文件回收，尚未提供专门的修复界面。
- UI 的布局和系统转场已实现，但没有真机逐帧对照 Apple Music，不声称像素级复刻。

## 本轮补充验证

- MP3 TXXX 的 Description 必须从 AVMetadataItem.extraAttributes[.info] 读取，并识别 lyrics / unsyncedlyrics / USLT，不能只用 TXXX 标识猜内容；已保留触发失败的真实 MP3 回归测试。
- 新增同步/纯文本/纯音乐、未知时长、相似歌名不同版本、封面艺人专辑匹配、Retry-After 和校准后高亮/Seek 同时钟测试。
- 新增下载结果的磁盘持久化与原音频哈希不变验证；测试使用自造短文本、合成音和自造图片。
- 新增 iPhone Release 产物图标配置检查。用户歌曲、完整歌词与真实专辑封面不进入测试仓库。

## 1.0.3 真机复验

- Chrome 下载、心动签应用内导入、沿用原证书和 Bundle ID 签名覆盖安装。已核对 1.0.3 / build 4。
- 上一版已保存到本地的 Starboy 封面在新版本启动后显示；Mini Player、全屏封面和背景取色正常，系统封面链路没有再次触发原崩溃。原歌曲、进度和歌词仍在，启动保持暂停。
- 已关闭镜像，由用户在实机播放并锁屏等待 30 秒。用户确认持续出声、锁屏封面、锁屏暂停和恢复均正常。
- 用户确认耳机断开自动暂停、来电中断和挂断恢复均正常。其他格式因手机没有样本，由用户明确要求保留待办；离线强制重启另行记录。

## 真机封面崩溃的证据

2026-11-14 11:05（America/New_York），1.0.2 / build 3。用户确认 App 自己退出；通过手机「设置 → Analytics & Improvements → View Analytics Logs」读取对应记录。异常为 `EXC_BREAKPOINT / SIGTRAP`，触发线程 2；关键栈为 Swift actor 隔离检查、`RemoteCommandManager.update` 内图片闭包、`MPMediaItemArtwork jpegDataWithSize:`、系统 Now Playing 串行队列。

该回调由旧 Objective-C API 保存，在主线程上下文创建的普通 Swift 闭包继承了 MainActor 隔离；系统后台请求图片时触发运行时断言。修复仅让只读图片回调显式成为 `@Sendable`，没有关闭并发检查，也没有把同步系统请求阻塞到主线程。

现有下载持久化集成测试增加真实系统链路：保存自造封面，调用 PlaybackStore 刷新系统信息，再通过后台任务从 `MPNowPlayingInfoCenter` 取 `MPMediaItemArtwork.image(at:)`，确认能返回图片。没有用 mock 替代系统图片回调。原崩溃已经有真机日志；新回归与修复一起提交，未单独运行未修复版的新增测试，远端验证结果单独记录。

参考：[Apple MPMediaItemArtwork](https://developer.apple.com/documentation/mediaplayer/mpmediaitemartwork/init(boundssize:requesthandler:))、[Swift 6 跨隔离回调说明](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/incrementaladoption/)。真实崩溃日志中的设备标识、证书和完整歌词未提交。

## 1.0.4 在线匹配后自动修正

用户要求联网查歌词时自动修正歌名和艺术家。选用匹配版本后，标准歌名、艺术家和歌词在同一资料库事务中保存；艺人分组与系统媒体信息同步更新，搜索框采用标准参数供下次搜索使用。专辑和流派保留；专辑艺术家原本跟随歌曲艺术家时同步更新。不在仅浏览候选时改动歌曲。

真实导入与下载持久化回归增加标准歌名、艺术家、分组和重开数据库检查；保留原音频 SHA-256 不变的验证。代码 `e24fbb5` 的 [CI 43615814350](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43615814350) 正在运行，真机仍安装 1.0.3，待 1.0.4 产物覆盖安装后验收。
