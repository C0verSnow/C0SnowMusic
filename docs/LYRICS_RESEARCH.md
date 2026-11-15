# 歌词、封面下载与播放同步调研

核对日期：2026-11-14；Unix Timestamp：1794668330。通过 GitHub 检索并阅读实际源码、README、LICENSE 和 Issue；没有执行本地构建、编译、测试或 CMake。

## 结论

歌词模块采用原生 `URLSession`：歌词接 LRCLIB，封面接 MusicBrainz + Cover Art Archive。仅借鉴已有项目的查询顺序、版本匹配和保存方式，自行写 Swift；歌词查询本身不依赖 Python、Rust、FFmpeg 或服务器。现有 `LRCParser` 和 `LyricsView` 已有按播放时间高亮、滚动和点行跳转，下载的 LRC 可直接接入。Issue #9 的音频下载另使用手机内 Python，见 ONLINE_MUSIC.md。

## GitHub 候选与取舍

以下 star 和时间为本次核对快照；源码链接固定到 commit，便于复核。

| 项目 | 许可证与维护 | 实现、依赖与本项目取舍 |
| --- | --- | --- |
| [antongpopov/lyrics-downloader](https://github.com/antongpopov/lyrics-downloader/tree/bfc36deb39f7c5e206eddfe46fd8f141614bc540) | [MIT](https://github.com/antongpopov/lyrics-downloader/blob/bfc36deb39f7c5e206eddfe46fd8f141614bc540/LICENSE)；1 star；最后提交 2026-10-07；当前没有 Issue，无法证明社区响应情况。 | 用户指定参考。Python 3.8+，元数据依赖 tinytag 或 ffprobe，GUI 用 Tk。实际 [lyrics_downloader.py](https://github.com/antongpopov/lyrics-downloader/blob/bfc36deb39f7c5e206eddfe46fd8f141614bc540/lyrics_downloader.py) 先 LRCLIB `/get` 后 `/search`，默认搜索时长容差 3 秒；优先 LRC，其次纯文本；封面先 MusicBrainz release-group + CAA，iTunes 可选。借鉴流程，不作为运行时依赖。 |
| [tranxuanthang/lrclib](https://github.com/tranxuanthang/lrclib/tree/ffdfed4dd8288f9065f5562508c13705cbe0436c) | [MIT](https://github.com/tranxuanthang/lrclib/blob/ffdfed4dd8288f9065f5562508c13705cbe0436c/LICENSE)；2,263 stars；最后提交 2026-11-10；[Issue #138](https://github.com/tranxuanthang/lrclib/issues/138) 有作者回复和修复说明。 | Rust/Axum + SQLite 服务端。直接接官方 JSON API，无须把服务端或数据库嵌入应用。 |
| [J0R6IT0/navidrome-lyrics-plugin](https://github.com/J0R6IT0/navidrome-lyrics-plugin/tree/02701d51815c707897d56728b03ffe10e40c1417) | [MIT](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/02701d51815c707897d56728b03ffe10e40c1417/LICENSE)；468 stars；最后提交 2026-11-12；[Issue #43](https://github.com/J0R6IT0/navidrome-lyrics-plugin/issues/43) 有维护者跟进。 | Rust/WASM，依赖 Navidrome PDK、Extism、serde 等；[LRCLIB provider](https://github.com/J0R6IT0/navidrome-lyrics-plugin/blob/02701d51815c707897d56728b03ffe10e40c1417/src/providers/services/lrclib.rs) 展示纯文本回退、时长检查和同步优先。不引入插件框架。 |

活跃且许可证明确的对照来源选后两项。用户指定项目规模小，仍逐项核对，未把 star 少当作代码可靠性证明。另检索到 `moehmeni/syncedlyrics`，最后推送停留在 2024-07-28，不选作当前主要参考。

## LRCLIB 接口与约束

依据 [官方 API 文档](https://lrclib.net/docs.md) 及固定提交的 [get handler](https://github.com/tranxuanthang/lrclib/blob/ffdfed4dd8288f9065f5562508c13705cbe0436c/server/src/routes/get_lyrics_by_metadata.rs)、[时长匹配实现](https://github.com/tranxuanthang/lrclib/blob/ffdfed4dd8288f9065f5562508c13705cbe0436c/core/src/repositories/track_repository.rs)：

- `GET https://lrclib.net/api/get`：`track_name`、`artist_name` 必填；`album_name`、`duration` 可选，建议提供。`duration` 单位秒，允许 1…3600；服务端匹配容差为 ±2 秒。未知或超出范围的时长不要伪造。
- `GET /api/search`：可用 `track_name`、`artist_name`、`album_name` 结构化搜索；`q` 会优先于结构化字段。最多返回 20 项，无分页；返回顺序不能当作版本匹配证明。
- 读取 `syncedLyrics` 得到带行时间戳的 LRC；没有同步版本时读取 `plainLyrics`。两字段都可能为空；`instrumental` 为真表示纯音乐。新增 `lyricsfile` 和 `hasWordSync` 不影响本次行同步方案，无须支持其 YAML 格式。
- 不需要 API key。请求必须用应用名、版本、仓库地址设置 `User-Agent`。当前已识别客户端约 90 请求/分钟/IP，数值可能变化；官方建议串行并间隔 200–500ms。
- `429` 必须遵守 `Retry-After`，重试加少量随机延迟；`503` 也应遵守该头。错误体可能不是 JSON，先看 HTTP 状态。不要把网络失败缓存成“没有歌词”。
- 注册应用是可选项；客户端可用公开 `Lrclib-App-Id` 提高额度。不要把服务端 `Lrclib-Api-Key` 放进 iOS 应用。本次免 key 方案无需注册。

建议正常流程：先精确查询；无同步歌词时，可在保留同一首歌的纯文本结果后再搜索同步版本；候选同时核对歌名、歌手、可用的专辑信息和时长，找不到可靠同步版本则显示纯文本。具体规范化规则属于本项目设计，不是 API 保证。

真实限制：[插件 Issue #43](https://github.com/J0R6IT0/navidrome-lyrics-plugin/issues/43) 记录不同场次 live 版本只差两秒，去掉专辑约束后仍会错配。时长接近不能代替版本一致；不要自动删除 `Live`、`Remix` 等有意义的版本标签。LRCLIB 曾在迁移后短暂不可用，作者在 [Issue #138](https://github.com/tranxuanthang/lrclib/issues/138) 说明已修复；下载失败应允许重试，已保存的歌词仍离线可用。

## 封面来源

选用 [MusicBrainz + Cover Art Archive](https://musicbrainz.org/doc/Cover_Art_Archive)，与用户参考项目保持一致：按歌手、专辑查询 MusicBrainz release-group，核对候选后，调用 `https://coverartarchive.org/release-group/{mbid}/front-500` 或 `front-1200`。已有 release MBID 时也可用 `/release/{mbid}/front-500`。接口、缩略图规格、重定向和 404 语义见 [CAA 官方 API](https://musicbrainz.org/doc/Cover_Art_Archive/API)。

MusicBrainz 请求必须带有应用名、版本和联系链接的 `User-Agent`，同一 IP 平均最多每秒一条；查询应串行、按专辑复用结果。依据 [官方限流说明](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting)。封面缺失属于正常结果；CAA 会重定向到 Internet Archive，允许 `URLSession` 正常跟随重定向。

本次不采用 iTunes 作为回退。[Apple 官方条款](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/index.html) 限定 artwork 等推广素材的用途，要求关联商店推广及购买链接。免 key、能返回图片不等于可以任意用于本地播放器；参考项目的可选回退和改写图片尺寸 URL 也不能替代官方授权。

## 接入与验收建议

1. 下载入口由用户主动触发，说明会向服务发送歌名、歌手、专辑和时长。已有歌词、内嵌封面和手动导入内容默认保留。
2. 下载成功后通过现有库事务持久保存歌词和封面路径；按当前歌曲 ID 保存结果，避免等待下载时切歌后写到另一首歌。
3. 同步歌词沿用播放引擎真实 `currentTime`，暂停后高亮保持，拖动进度或点歌词后重新计算当前行；纯文本不编造时间戳。
4. 远端 CI 检查：同步、纯文本、纯音乐和无匹配；重启后离线保留；暂停、拖动、切歌、高亮和滚动；匹配与 HTTP 错误使用自造短文本及网络边界夹具，不把真实完整歌词提交到仓库。

## 授权边界

上述 MIT 许可证覆盖软件，不授予歌曲歌词或专辑图的版权。参考项目 [版权说明](https://github.com/antongpopov/lyrics-downloader/blob/bfc36deb39f7c5e206eddfe46fd8f141614bc540/README.md) 明确区分两者；CAA [官方政策](https://musicbrainz.org/doc/Cover_Art_Archive) 同样要求尊重作者和唱片公司的权利。应用按用户请求查询并本机保存，不将下载内容作为仓库素材、预装曲库或公开再分发；需要对外发行时，数据使用授权须单独评估。

## 补充：MP3 内嵌歌词读取

Unix Timestamp：1794668653。针对远端 CI 暴露的 MP3 歌词未读出问题，核对 ID3.org 规范、Apple 官方文档及 SDK 头文件、FFmpeg 源码；本地仍未编译或运行测试。

### 先检查 AVFoundation 的 TXXX 描述

`TXXX` 的 identifier 只说明它是用户文本帧，不能靠 identifier 中是否包含 `lyrics` 判断内容。Apple 的 [.id3MetadataUserText](https://developer.apple.com/documentation/avfoundation/avmetadataidentifier/id3metadatausertext) 对应该帧；[extraAttributes](https://developer.apple.com/documentation/avfoundation/avmetadataitem/extraattributes) 提供容器附加属性，[.info](https://developer.apple.com/documentation/avfoundation/avmetadataextraattributekey/info) 对应 `AVMetadataExtraAttributeInfoKey`。

本机 Apple 原厂 SDK `MacOSX26.5.sdk/.../AVFoundation.framework/Versions/A/Headers/AVMetadataFormat.h` 第 394–399 行明确说明：`TXXX`、`WXXX`、`APIC`、`GEOB` 的 `.info` 存放 Description。本次采用最小修复：在 TXXX 分支异步 `load(.extraAttributes)`，将 `.info` 字符串与 `lyrics` / `unsyncedlyrics` 作大小写无关比较，再读取 `load(.stringValue)`。不要把所有 TXXX 都当作歌词。本次不添加文件字节解析器；下列解析范围仅供将来确认 AVFoundation 根本未暴露帧时参考。

FFmpeg 版本也影响落盘格式：[8.0 固定源码](https://github.com/FFmpeg/FFmpeg/blob/140fd653aed8cad774f991ba083e2d01e86420c7/libavformat/id3v2enc.c) 把未知 metadata 键写成 `TXXX(description=键名, value=内容)`；该版本的 `lyrics` 没有专用写入分支。[2026-11-14 master 固定源码](https://github.com/FFmpeg/FFmpeg/blob/604ef3784d6fae44baf62fdbe9b3e4e5cfc3c681/libavformat/id3v2/writer.c) 则已将 `lyrics` 映射到 `USLT`。因此应检查 CI 实际 FFmpeg 版本及文件帧，不能只看 `ffprobe` 显示的逻辑键名推断帧类型。

### 必要的 ID3 格式事实

以下是规范事实的简述，来源：[ID3v2.3 §§3、4.2.2、4.9、5](https://id3.org/id3v2.3.0)、[ID3v2.4 结构 §§3、4、6](https://id3.org/id3v2.4.0-structure)、[ID3v2.4 帧 §§4.2.6、4.8](https://id3.org/id3v2.4.0-frames)。

| 项目 | ID3v2.3 | ID3v2.4 |
| --- | --- | --- |
| 文件头 | 10 字节；`ID3`、版本、标志、4 字节 synchsafe 标签长度 | 同左；可另有 10 字节 footer |
| 标签长度 | 不含 10 字节文件头；包含扩展头、帧、padding，按插入转义零后的长度计算 | 同左；也不含 footer |
| 帧头与长度 | 帧头 10 字节；帧体长度为普通 32 位大端整数 | 帧头 10 字节；帧体长度为 4 字节 synchsafe，按转义之后的帧体计算 |
| 扩展头 | 标签标志 `0x40` 表示存在；首 4 字节为普通大端长度，长度不包含这 4 字节 | 同一标志；首 4 字节为 synchsafe 长度，已包含这 4 字节，最小总长 6 |
| 文本编码字节 | `0` 为 ISO-8859-1；`1` 为带 BOM 的 Unicode 双字节编码 | `0` ISO-8859-1；`1` UTF-16+BOM；`2` UTF-16BE 无 BOM；`3` UTF-8 |
| Unsynchronisation | 标签标志 `0x80`；先对标签体撤销转义，再按帧长度遍历 | 帧格式标志 `0x02`；先按存储长度切帧，再对帧体撤销转义。标签 `0x80` 表示所有帧均转义，不能再对同一帧解两次 |

synchsafe 每字节只用低 7 位，四字节合成位移是 21、14、7、0。转义将 `FF 00` 改为 `FF 00 00`，将可能误认音频同步的 `FF E0…FF` 序列插入零；解码只在规范标志适用的范围移除 `FF` 后插入的那个零，不能对普通正文随意删零。

两版本的 `USLT` 帧体均为：编码字节、3 字节语言、以对应编码的 NUL 结尾的描述、剩余歌词文本。`TXXX` 则没有语言字段：编码字节、NUL 结尾描述、剩余值；仅选择描述为 `lyrics` 的帧。ISO-8859-1/UTF-8 的终止符为单字节零；UTF-16 为对齐的双字节零，不能从任意偏移搜索 `00 00`。带 BOM 的同帧字符串须沿用相同端序；正文自带 BOM 时正常去除。不要把描述或三字节语言拼进最终歌词。

### 未来确需独立 Swift 回退时的范围（本次不实现）

建议新建只读歌词解析器，仅在 AVFoundation 未返回歌词时读取文件头的 ID3v2.3/v2.4 标签；接受 `USLT` 和描述为 `lyrics` 的 `TXXX`，处理上述四种编码、版本对应的扩展头和转义。文本内容中若自带 LRC 时间戳，交给现有 `LRCParser`；不把 `USLT` 的名称理解为禁止保存 LRC 文本。

只按声明长度遍历帧，遇到 padding 或截断停止，不扫描音频去猜帧。压缩、加密帧跳过；分组帧和 v2.4 data-length indicator 帧可选择跳过，或按规范先移除它们的额外字段后再解释 payload。不要直接把这些额外字节当编码字节。本次不解析 `SYLT`、ID3v2.2、尾部或多标签合并，也不改写文件。这些是本次建议范围，不是宣称这些格式无效。

验收由远端 CI 覆盖真正文件：FFmpeg 写入的 TXXX、USLT、中文 UTF-8/UTF-16、v2.3 普通长度与 v2.4 synchsafe 长度；扩展头或转义处理若实现，也应有自造内容的字节夹具。先确认 `.info` 修复是否已经恢复现有 MP3 夹具，再决定是否需要字节回退。

## 真机与远端回归纠正

Unix Timestamp：1794671904。没有执行本地编译或测试。

- CI 43611483223 的真实 MP3 日志显示：identifier=`id3/TXXX`，commonKey 为空，stringValue 为自造歌词，`.info=USLT`，写入器为 `Lavf63.1.102`。之前仅比较 `lyrics` / `unsyncedlyrics` 仍会漏掉此文件；现增加 `uslt` 别名，保留原真实导入回归，不增加字节解析器。
- 真机 1.0.1 已搜索并保存同步歌词；封面实际失败为 CAA 返回 400。对 [Starboy release-group](https://musicbrainz.org/release-group/ceaa5c39-91c7-4c8a-886c-85b11fa8a1f6) 的封面地址实查：小写 ID 返回 200、JPEG、89288 字节；同一 ID 转大写返回 400。Swift `UUID.uuidString` 默认大写，因此在 CAA URL 生成处转小写；回归检查服务实际使用的 URL。该现象由实际请求证明，不是把 MusicBrainz 的间歇性 503 误判为客户端参数问题。
- 本轮另在 GitHub 搜索 `id3MetadataUserText` 的 Swift 实现，找到 Piwigo-Mobile、primuse、Cosmos-Music-Player 等代码位置；未复制代码，修复依据为 Apple 官方 API 与当前真实文件和 HTTP 诊断。
