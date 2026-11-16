# 测试与验收

## Issue #11 搜索、账户与 Telegram 音乐仓库证据

### 恢复时已通过的 CI 与 IPA（自动补齐改动前）

- 产品提交 `caa95d0c4febdb3c252bf6c6ecd998c6656bb000` 的 [CI 43797997679](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43797997679) 已通过：36 项单元/集成测试、3 项 UI 测试零失败；模拟器编译、未签名 iPhone Release 编译、图标检查和 IPA 打包全部通过；Worker 的 10 项真实 SQLite、HTTP 与音频测试通过。`release` job 因本次不是发布标签而跳过，不影响 Release 编译或 IPA 产物。
- [IPA 产物 14195840405](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43797997679/artifacts/14195840405) 的 ZIP 已完整下载并通过 CRC 检查。归档 SHA-256 为 `2efe5f91dd246507e35345e9b806b295e9461cd5f6058ca44f9cf953d7f84c67`，与 GitHub 产物摘要和 CI 上传日志一致。
- 提取后的 `C0SnowMusic-unsigned.ipa` 为 24,994,905 字节，SHA-256 为 `9a71d5f9f7aa17ec6a2867a6185666016503a0f943f2eca194cb47f92c59df2f`；版本为 1.1.0/build 6，Bundle ID 为 `org.c0versnow.C0SnowMusic`，最低系统 26.0。`Info.plist` 的 AppIcon 与 `Assets.car` 均已静态核对。此构建沿用旧版版本号，必须靠上述产物哈希区分，不能只凭手机显示 1.1.0 就判定安装正确。
- [iOS 测试证据](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43797997679/artifacts/14195234761) 包含构建/测试日志、xcresult 与 UI 截图；[Worker 测试证据](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43797997679/artifacts/14194699823) 包含测试日志与合成 MP3。
- 本地没有编译、构建、配置 CMake 或执行会触发编译的测试。本轮只读取 CI、核对 ZIP/IPA、plist 与差异。前轮已在 GitHub 比较 MetroList、TeleMusic、ytmusicapi 和 YouTube.js，来源与许可证见 [调研文档](TELEGRAM_MUSIC_RESEARCH.md)，没有复制 GPL 代码；本轮恢复阶段没有新增功能方案检索。

### 已部署服务的 14 项真实检查

以下为暂停前 2026-11-16 UTC（纽约 11 月 15 日晚）保存的实际结果，任务记录时间为 Unix Timestamp 1794799701。本轮从原始脱敏 JSON 与验收脚本核对补入，没有重跑上传、向用户发送音频或重新部署。服务为 `https://c0snow-music-api.f1515xcn.workers.dev`，部署版本为 `4a5d0351-4cba-4970-8734-46b176d53770`，两份 D1 迁移已应用。

样本来自远端 CI 的合成 MP3，共 24,641 字节，SHA-256 为 `916ae9bd40370fe6403f1763935d084d1f86cee42fa97275f8d280a6d00d16c0`。两条歌曲为 `yt_c0snowtest1`、`yt_c0snowtest2`，均标明合成测试音；它们复用一份 Telegram 文件。没有使用用户音乐。

| 编号 | 实际检查 | 结果与判定 |
| --- | --- | --- |
| 1 | 使用无效设备密钥请求目录 | 通过，HTTP 401 |
| 2 | 第一条歌曲上传真实 MP3 | 通过，HTTP 200/201 |
| 3 | 第二条歌曲上传相同 MP3 | 通过，HTTP 200/201 |
| 4 | 两条歌曲按内容去重 | 通过，文件内部 ID 相同，SHA-256 与原文件一致 |
| 5 | 下载完整音频 | 通过，HTTP 200，完整 SHA-256 与原文件一致 |
| 6 | Range `bytes=10-99` | 通过，HTTP 206、90 字节及 Content-Range 与原文件相符 |
| 7 | 后缀 Range `bytes=-32` | 通过，HTTP 206、末尾 32 字节及 Content-Range 相符 |
| 8 | HEAD 音频请求 | 通过，HTTP 200、Content-Length 为 24641、无响应体 |
| 9 | 超出文件的 Range | 通过，HTTP 416 |
| 10 | 增加 App 云端收藏关系 | 通过，HTTP 200 |
| 11 | 取消 App 云端收藏关系 | 通过，HTTP 200 |
| 12 | 取消收藏后保留可下载音频 | 通过，音频 HEAD 仍为 HTTP 200 |
| 13 | 使用保存的 Telegram file_id 向授权用户发送 | 通过，HTTP 200，前轮验收已产生一份私聊测试音 |
| 14 | 核对真实 Bot Webhook | 通过，URL 正确且 pending_update_count 为 0 |

这些线上检查证明已部署 Worker/D1/Telegram 链路可用。第 10、11 项是仓库收藏接口，不能代替 YouTube 账户实际收藏写入验收。429、回执不明、人工核对、失效音频、大文件限制、完整收藏事务和用户隔离由远端自动化覆盖，不算作上述 14 项线上检查。

### 自动补齐补充（1.1.1/build 7）

- 最新产品提交 `4c69d895d513d4e7403bde0778a82a2b5b86143d` 的 [CI 43819839808](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43819839808) 与同提交项目静态验证已全通过：39 项单元/集成、3 项 UI、10 项 Worker 零失败；模拟器、iPhone Release、图标检查与 IPA 打包均通过，标签发布 job 按条件跳过。
- 新增自动补齐、旧缓存空专辑、版本歧义和第三列专辑回归已执行。自动补齐回归使用远端生成的无标签合成 M4A，实际解码、图片处理和缓存存储均走真实实现，只有外部 HTTP 响应用合成数据；重开后歌词、专辑和封面保留，音频 SHA-256 不变。
- [新版 IPA 产物](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43819839808/artifacts/14203888195) 已完整下载，ZIP CRC 和 SHA-256 通过；归档 SHA-256 为 `9ed569fae03253b26d293f3463c716b2cf31a36385c3e1a743f32ecb3efd15df`，与 GitHub 和 CI 日志一致。IPA 为 25,013,551 字节，SHA-256 为 `13a30a15f2e1d010f40336eb65f36a24f952f771f5ea770defdda68187bb7df3`，已核对 1.1.1/build 7、原 Bundle ID、AppIcon 和 Assets.car。
- 用户追加要求点歌后自动加载封面、歌词和专辑，并减少同类手动步骤。此版新增后台精确补齐、专辑保存与显示、第三列专辑解析、输入自动搜索、进入资料库自动同步、待验证账户自动刷新、仓库连接后自动刷新，以及仓库下载的状态/错误显示。
- 1.1.1/build 7 已通过心动签覆盖安装，原 2 首本地歌曲和封面、账户头像/会话、仓库连接保留。点“再次聆听”后，旧缓存自动补齐 Starboy 专辑，无须进入匹配页。
- 随后在缓存页确认只有本次 Die For You，清除至 Zero KB，再点歌曲从仓库重新下载。自动出现 Starboy 专辑与同步歌词，未点击查找或选用版本；歌词高亮和滚动随真实时间推进，4:20 自然结束后回零暂停。进入在线资料库自动启动收藏同步，没有手点同步按钮。
- 真机发现来源封面只有 120×120，放大偏糊。已直接请求同一来源的 544×544 版本，返回 HTTP 200、133,795 字节，实际尺寸与画面均核对，新增原生 URL 尺寸选择回归。1.1.1/build 8 只补这一封面清晰度问题，仍待新一轮远端 CI 和新版真机复验。
- 服务没有重新部署，本地没有编译或运行会触发编译的测试。

### 本次真机验收（先前 caa95d0 IPA）

- [x] 用上述哈希的 IPA 经 Chrome 下载、心动签沿用现有证书和 Bundle ID 覆盖安装，原 2 首歌与封面保留。
- [ ] 覆盖安装后会话已保留；刷新账户取得真实头像、名字、handle 和已连接状态。强退重启的持久化仍待复验。
- [x] 原有 4 首 YouTube 收藏已同步到 D1；在 App 为 Die For You（源 ID `QLCpqdqeoII`）增加 YouTube 收藏后，回读 D1 得到 5 首。随后从 App 取消收藏，D1 恢复原 4 首，原收藏 ID 集合完全一致；音频仍 ready/available，HEAD 200、4,207,300 字节，哈希未变。脱敏证据见 `docs/evidence/issue-11-favorites-roundtrip.json`。
- [ ] Music Settings 已用既有 `.env` 设备密钥成功连接音乐仓库。同一来源复试成功，手机取得 4,207,300 字节 M4A 并上传 Telegram，D1 显示 ready/available。随后经 Worker 完整下载返回 HTTP 200，实际字节数与 SHA-256 `4240d9013a3c5a1fae35c6eb3c5476c7f5bce271a6820b36ab5c288e7c281481` 均与 D1 一致；用户清空缓存后，手机从仓库重新下载并出现已缓存标记，开始播放；旧版完整播放已通过。
- [x] 按 Issue 最新评论，从归零缓存重新取 Die For You / The Weeknd（QLCpqdqeoII），连续播放到自然结束，界面回零并暂停，时长 4:20。用户确认正常出声、无卡顿；滑条跳转仍需新版复验。

辅助功能权限与镜像解锁已完成。首次获取 Die For You 音频在手机报 `SSL: UNEXPECTED_EOF_WHILE_READING`，两次内置重试后失败，尚未上传音频；手动复试同一来源成功，没有为此修改代码或重新部署。初次失败仍保留，不宣称所有网络条件都可用。旧版 issue #9 的真机通过记录保留在下方，不能冒充本次结果。

手动匹配补充：旧版 LRCLIB 精确找到 Die For You / The Weeknd / Starboy / 4:20；选择后同步歌词与 CAA 封面保存成功，真机显示 Starboy 封面。专辑输入仍为空，已确认旧版没有保存匹配专辑，现由 1.1.1 补充修复并改成自动加载。

### 本期限制

标准云端交付上限为 20,000,000 字节。更大文件交付和真正远程边播边下尚未实现，继续作为后续功能。当前 App 先完整下载并验证音频，再用本地 AVPlayer 播放；Worker 的 Range 正确不等于 App 已远程即播。其他部署与恢复说明见 [音乐仓库设计](TELEGRAM_MUSIC.md)。

## Issue #9 在线功能证据

- 最终产品代码 `b8bf67887449c6f7bada48f17e147d174f19f6e4` 的 [CI 43680765143](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43680765143) 全通过：28 项单元/集成、3 项 UI，模拟器与 iPhone Release 编译、图标检查和 IPA 打包均通过。覆盖真实 Keychain 存取/注销、连续两次 Python/SSL/EJS/WebKit 执行、真实 yt-dlp 合成音频传输、移动页面转义解析、DASH 重新封装时长/解码/跳转、缓存淘汰与手动副本保留、设置/语言 UI。
- 本地没有编译、构建或运行编译型测试，只做源码、Python AST、shell 语法、plist、差异和 CI 产物静态检查。已在 GitHub 检索并比较 NeriPlayer、Palladium、BeeWare、yt-dlp 等项目，来源与许可见 ONLINE_MUSIC_RESEARCH.md 和 THIRD_PARTY.md。
- [v1.1.0-beta.1 Release](https://github.com/C0verSnow/C0SnowMusic/releases/tag/v1.1.0-beta.1) 已发布，标签指向上述产品提交，附带 24,696,065 字节的 `C0SnowMusic-unsigned.ipa`；GitHub 附件状态为 uploaded，服务器提供的 SHA-256 与本地核对一致。
- 最终 IPA 直接下载自上述 CI，SHA-256 为 `0a912f8d768cf007163a87c6603c9c0d7b9aa481bddffa2a42a40e1a48b03609`。1.1.0/build 6 已通过 iPhone Mirror、Chrome 和心动签覆盖安装，沿用现有证书与 Bundle ID；原来的 Die For You、封面和资料库保留。
- 真机确认账户页进入 Music Settings，系统英文、简体中文/English 切换正常，账户导航标题立即更新。用户亲自在 App 内 Google 页面认证并保存；强退重开和覆盖安装后均恢复 YouTube 会话，无须 Client ID，没有读取 Safari、Chrome 或 YouTube App 的私有 Cookie。
- 真实搜索 `BaW_jenozKc` 返回封面、标题和作者，自动预下载 162KB 纯 M4A 并播放。手动保存后清空缓存，永久副本仍可播放。随后复验清缓存时 Mini Player 同步消失，缓存归零；只移除了本次创建的测试视频及应用内副本，原歌曲保留。
- 按用户要求搜索 The Weeknd 的 One Of The Girls。最终版本在同一进程连续完成两个官方音源下载，第二首为 The Weeknd 官方频道的 Official Audio；真实播放器显示 4:04，时间推进正常。拖到末尾后结束并暂停回零，再跳至 1:58 后播放至 2:05，未出现旧版 8:08 空尾。验收结束已暂停。
- 本轮真机发现并修复了清缓存残留播放器引用、连续加载插件失败和 DASH 双倍时长；均补入真实实现的远端回归。先前失败或取消的 CI 不算作最终通过证据。
- 真实网站仍会受到网络、地区和 YouTube 验证限制，不代表全部账户、全部视频和全部地区都可用。用户音乐、登录 Cookie、证书与手机私人画面未上传到仓库。

- issue #9 已按原要求关闭；[PR #10](https://github.com/C0verSnow/C0SnowMusic/pull/10) 已转为待审核，未合并。后续仅更新文档，不改变标签对应的产品代码；临时下载服务已关闭。

## 本地播放器历史证据（issue #7）

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
- [x] 强制退出和重新启动，音乐库、当前歌曲与进度保留，启动保持暂停。
- [ ] 多首队列和播放列表的完整实机恢复矩阵。
- [ ] 不同 iPhone 尺寸、横屏、深浅色、最大字体、Reduce Motion、VoiceOver。
- [x] Mini Player 展开、按钮收起、歌词点选跳转、高亮跟随和 0.5 秒校准。
- [ ] 下拉收起、底栏滚动收缩、手动滚动暂停跟随的完整真机验收。
- [x] 1.0.3 覆盖安装后正常启动，原歌曲、进度和歌词保留，已下载的 Starboy 封面在 Mini Player 和全屏播放器显示，背景取色更新，未再次退出。
- [x] 真机把 App 无线数据设为 Off 后强制退出重开，歌词、封面和延后 0.5 秒保留；测完恢复 WLAN & Cellular Data 和 0 秒偏移。

## 已知限制与处理

- 没有外部解码器。无法通过系统解码检查的文件需转换为 ALAC、M4A 或 WAV；错误会显示给用户。
- 资料库快照和搜索索引在内存中；列表使用原生懒加载，首页限制展示数量。数万首歌曲的内存和首屏时间尚未实测。
- 没有逐字歌词、云同步、CarPlay、均衡器、无缝衔接或交叉淡化。在线搜索与 YouTube 网页会话从 issue #9 起提供，见本文上方记录。
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
- 用户确认耳机断开自动暂停、来电中断和挂断恢复均正常。其他格式因手机没有样本，由用户明确要求保留待办；离线强制重启也已完成。

## 真机封面崩溃的证据

2026-11-14 11:05（America/New_York），1.0.2 / build 3。用户确认 App 自己退出；通过手机「设置 → Analytics & Improvements → View Analytics Logs」读取对应记录。异常为 `EXC_BREAKPOINT / SIGTRAP`，触发线程 2；关键栈为 Swift actor 隔离检查、`RemoteCommandManager.update` 内图片闭包、`MPMediaItemArtwork jpegDataWithSize:`、系统 Now Playing 串行队列。

该回调由旧 Objective-C API 保存，在主线程上下文创建的普通 Swift 闭包继承了 MainActor 隔离；系统后台请求图片时触发运行时断言。修复仅让只读图片回调显式成为 `@Sendable`，没有关闭并发检查，也没有把同步系统请求阻塞到主线程。

现有下载持久化集成测试增加真实系统链路：保存自造封面，调用 PlaybackStore 刷新系统信息，再通过后台任务从 `MPNowPlayingInfoCenter` 取 `MPMediaItemArtwork.image(at:)`，确认能返回图片。没有用 mock 替代系统图片回调。原崩溃已经有真机日志；新回归与修复一起提交，未单独运行未修复版的新增测试，远端验证结果单独记录。

参考：[Apple MPMediaItemArtwork](https://developer.apple.com/documentation/mediaplayer/mpmediaitemartwork/init(boundssize:requesthandler:))、[Swift 6 跨隔离回调说明](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/incrementaladoption/)。真实崩溃日志中的设备标识、证书和完整歌词未提交。

## 1.0.4 在线匹配后自动修正

用户要求联网查歌词时自动修正歌名和艺术家。选用匹配版本后，标准歌名、艺术家和歌词在同一资料库事务中保存；艺人分组与系统媒体信息同步更新，搜索框采用标准参数供下次搜索使用。专辑和流派保留；专辑艺术家原本跟随歌曲艺术家时同步更新。不在仅浏览候选时改动歌曲。

真实导入与下载持久化回归增加标准歌名、艺术家、分组和重开数据库检查；保留原音频 SHA-256 不变的验证。代码 `e24fbb5` 的 [CI 43615814350](https://github.com/C0verSnow/C0SnowMusic/actions/runs/43615814350) 全通过：21 项单元/集成、2 项 UI，模拟器编译、iPhone Release、图标检查与 IPA 打包通过。真机已用 Chrome 下载、心动签覆盖安装 1.0.4 / build 5。

实际操作：搜索并选用 Die For You / The Weeknd / Starboy / 4:20，提示歌名和艺术家已更新。播放器、控制中心显示 Die For You / The Weeknd 和封面，艺人列表显示 The Weeknd。强制退出再打开后修正结果、封面和进度保留，启动保持暂停。

## 离线重启与校准保存

在 1.0.3 将歌词设为延后 0.5 秒。系统设置中只将 C0SnowMusic 的 Wireless Data 从 WLAN & Cellular Data 改为 Off，保留镜像连接；在多任务界面拖走应用卡片，确认退出后重新打开。歌曲、3:36 进度、封面、歌词和延后 0.5 秒全部保留，启动保持暂停。测完恢复 0 秒偏移和原来的 WLAN & Cellular Data。

1.0.4 又完成一次强制退出重开，标准歌名、艺术家、封面和进度保留，启动暂停。临时局域网下载服务已关闭。
