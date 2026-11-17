# Telegram 音乐仓库和 YouTube Music 功能调研

核对日期：2026-11-16 UTC（美国东部仍为 11 月 15 日）；Unix Timestamp：1794797528。范围对应 [Issue #11](https://github.com/C0verSnow/c0versnowmusic/issues/11)。本次读取 GitHub 仓库、实际源码、许可证和 Issue 回复，以及 Telegram、Cloudflare 官方文档。没有本地编译、构建或运行测试，也没有执行 Telegram 账号操作。

## 建议采用的路线

保留现有 SwiftUI 设计和手机内 yt-dlp 下载链路。YouTube Music 用于搜索、首页和账户音乐库；Telegram 保存音频；Worker 管理索引、收藏和交付入口；D1 保存关系。收藏状态与实际音频分别保存，取消收藏不调用 Telegram 删除文件。这是结合本仓库现状和 Issue 提出的设计选择，不是上游项目已经提供的现成功能。

现有下载产物是原生 M4A。Telegram `sendAudio` 接受 MP3 和 M4A，因此无需为“存入 Telegram”增加 MP3 转码器；保存真实 MIME、扩展名和文件哈希。[Telegram sendAudio](https://core.telegram.org/bots/api#sendaudio)

## GitHub 候选比较与许可边界

下列 star 和提交时间是查询时的快照；star 数不代表接口稳定。MetroList 和 TeleMusic 是用户指定的设计参考；本 MIT 项目不复制其 GPL 实现。实现细节优先交叉核对 MIT 的 ytmusicapi 和 YouTube.js。

| 项目 | 规模、近期活动、许可证 | 实现、依赖、问题及采用方式 |
| --- | --- | --- |
| [MetrolistGroup/Metrolist](https://github.com/MetrolistGroup/Metrolist) | 14,446 stars；2026-11-16 推送；[GPL-3.0](https://github.com/MetrolistGroup/Metrolist/blob/main/LICENSE)；读取版本 `5b2fc2b88748ef0aec94320a8d853bba5dc125ef`。 | Kotlin 多平台，当前网络层依赖独立 InnerTubeX；业务层解析搜索卡片、首页 shelf、账户与分页。仅参考交互和数据职责。近期 [Issue #4796](https://github.com/MetrolistGroup/Metrolist/issues/4796) 有回复，但抽样实际是机器人；不能将其作为维护者已答复的证据。[#4779](https://github.com/MetrolistGroup/Metrolist/issues/4779) 的抽样也没有维护者人工答复。不能只凭提交活跃就宣称问题响应全部通过筛选。 |
| [abn3li/TeleMusic](https://github.com/abn3li/TeleMusic) | 50 stars；2026-11-15 推送；[GPL-3.0-only](https://github.com/abn3li/TeleMusic/blob/master/README.md#license)；读取版本 `40f2ee4c263adc9a2c6c13ac63817098efbbd74d`。 | Android Compose、TDLib、Media3、Room；用户登录 Telegram 后读取频道文件。作者在 [Issue #2](https://github.com/abn3li/TeleMusic/issues/2#issuecomment-5703173345) 回复升级版本，但用户随后仍报告失败，不能称为已验收修复。规模较小，仅保留为用户指定的专项参考。 |
| [sigma67/ytmusicapi](https://github.com/sigma67/ytmusicapi) | 3,119 stars；2026-11-12 推送；[MIT](https://github.com/sigma67/ytmusicapi/blob/main/LICENSE)；读取版本 `86fcd17ee3ff0d19bc807558d4e1a637df395143`。 | Python HTTP 客户端，具备搜索、首页、音乐库、点赞和账户解析；作为 Swift 自行实现的协议交叉依据，不新增一套 Python 网络服务。作者在 [Issue #1030](https://github.com/sigma67/ytmusicapi/issues/1030#issuecomment-6818691556) 明确表示其 OAuth 路径已不再支持。[PR #1032](https://github.com/sigma67/ytmusicapi/pull/1032) 最近合并了艺人页面缺失 header 的修复，说明 renderer 结构会变化。 |
| [LuanRT/YouTube.js](https://github.com/LuanRT/YouTube.js) | 5,423 stars；2026-11-11 推送；[MIT](https://github.com/LuanRT/YouTube.js/blob/main/LICENSE)；读取版本 `d6bcf97531e638fbb2505e3dace83139f834468e`。 | TypeScript InnerTube 客户端及 renderer 类型，支持多种 JS 运行时。可以核对协议，不必把整套 JS 客户端加入 Swift。作者在 [Issue #1165](https://github.com/LuanRT/YouTube.js/issues/1165#issuecomment-4413435886) 解释点赞操作可能受 BotGuard 和账户信任影响；请求成功不证明点赞永久保留。 |

## 搜索、首页和账户接口

以下是非公开 InnerTube 接口在上游源码里的实际使用方式，不是 Google 承诺兼容的公共 API。基础地址为 `https://music.youtube.com/youtubei/v1/`，POST JSON 携带现有 `context.client`，使用 `WEB_REMIX` 客户端。应复用仓库已保存的 YouTube 网页会话；不把 Google OAuth 的身份登录状态当成 YouTube 网页会话验证成功。[InnerTubeX 请求与认证源码](https://github.com/MetrolistGroup/innertubex/blob/main/src/commonMain/kotlin/com/metrolist/innertubex/InnerTube.kt)、[ytmusicapi 登录问题维护者回复](https://github.com/sigma67/ytmusicapi/issues/1030#issuecomment-6818691556)

| 功能 | Endpoint 和业务字段 | 应用处理 |
| --- | --- | --- |
| 综合搜索 | `POST search`，`{query}` | 保留 Top result、Tracks、Videos、Artist、Album 的类型区别；不把歌手和歌单当音频播放。 |
| 分类搜索 | `POST search`，`{query, params}` | 使用类别参数或服务端返回的搜索 endpoint 参数，不能靠英文分区标题推测类型。 |
| 搜索建议 | `POST music/get_search_suggestions`，`{input}` | 输入去抖；清空、提交或新查询后忽略旧响应。 |
| 首页 | `POST browse`，`{browseId: "FEmusic_home"}` | 登录时返回个人推荐；保留 shelf 顺序、标题、子项和 continuation。 |
| 探索 | `POST browse`，`{browseId: "FEmusic_explore"}` | 可作为无登录的发现来源；不把探索列表标为个性化推荐。 |
| 账户资料 | `POST account/account_menu`，`{}` | 请求成功后读取真实名称、头像、handle；保存 Cookie 本身不能证明会话有效。 |
| 音乐库首页 | `POST browse`，`{browseId: "FEmusic_library_landing"}` | 账户资料与音乐库分别展示加载、失败和空状态。 |
| 音乐库歌曲 | `POST browse`，`{browseId: "FEmusic_liked_videos"}` | 与全部点赞播放列表的职责不同；不要把当前页结果当成完整收藏快照。 |
| 点赞歌曲 | `POST browse`，`{browseId: "VLLM"}` | `LM` 是播放列表标识，`VLLM` 是 browse 标识；分页完成后才能用于全量取消收藏差集。 |
| 专辑 / 歌单 / 歌手 | `FEmusic_liked_albums` / `FEmusic_liked_playlists` / `FEmusic_library_corpus_artists` | 保留 browseId；专辑和歌手页面沿用服务端 navigationEndpoint。 |
| 听歌记录 | `POST browse`，`{browseId: "FEmusic_history"}` | 可用于 Listen Again；无会话时使用本机播放记录，并明确来源。 |
| 点赞 / 取消点赞 | `POST like/like` / `POST like/removelike`，`{target:{videoId}}` | 远端写入成功后再同步 D1；远端拒绝或会话失效时保留待同步状态。 |

协议交叉来源：[MIT 搜索实现](https://github.com/sigma67/ytmusicapi/blob/86fcd17ee3ff0d19bc807558d4e1a637df395143/ytmusicapi/mixins/search.py)、[MIT 首页实现](https://github.com/sigma67/ytmusicapi/blob/86fcd17ee3ff0d19bc807558d4e1a637df395143/ytmusicapi/mixins/browsing.py)、[MIT 音乐库、账户及点赞实现](https://github.com/sigma67/ytmusicapi/blob/86fcd17ee3ff0d19bc807558d4e1a637df395143/ytmusicapi/mixins/library.py)、[MetroList 业务操作](https://github.com/MetrolistGroup/Metrolist/blob/5b2fc2b88748ef0aec94320a8d853bba5dc125ef/shared/src/commonMain/kotlin/com/metrolist/shared/api/YouTubeRepository.kt)。

探索与点赞播放列表另见 [MIT Explore 实现](https://github.com/sigma67/ytmusicapi/blob/86fcd17ee3ff0d19bc807558d4e1a637df395143/ytmusicapi/mixins/explore.py)、[MIT `get_liked_songs`](https://github.com/sigma67/ytmusicapi/blob/86fcd17ee3ff0d19bc807558d4e1a637df395143/ytmusicapi/mixins/playlists.py#L236)。

MIT 搜索参数源码当前生成的普通分类参数如下，属于协议数据；仍需远端真实请求验收，未来可能变化：

| 分类 | `params` |
| --- | --- |
| songs | `EgWKAQIIAWoMEA4QChADEAQQCRAF` |
| videos | `EgWKAQIQAWoMEA4QChADEAQQCRAF` |
| albums | `EgWKAQIYAWoMEA4QChADEAQQCRAF` |
| artists | `EgWKAQIgAWoMEA4QChADEAQQCRAF` |

来源：[ytmusicapi `get_search_params`](https://github.com/sigma67/ytmusicapi/blob/86fcd17ee3ff0d19bc807558d4e1a637df395143/ytmusicapi/parsers/search.py#L234)。

### 应支持的数据结构

搜索主路径为 `contents.tabbedSearchResultsRenderer.tabs[].tabRenderer.content.sectionListRenderer.contents[]`；部分响应直接返回 `contents.sectionListRenderer`。Top result 来自 `musicCardShelfRenderer`，歌曲行来自 `musicResponsiveListItemRenderer`，双行卡片来自 `musicTwoRowItemRenderer`，分区可能使用 `musicShelfRenderer` 或 `musicCarouselShelfRenderer`。这是应该覆盖的已知数据形状，不应无边界递归把页面任意 `videoId` 全部收入结果。[MetroList 搜索结构参考](https://github.com/MetrolistGroup/Metrolist/blob/5b2fc2b88748ef0aec94320a8d853bba5dc125ef/shared/src/commonMain/kotlin/com/metrolist/shared/api/YouTubeSearchOperations.kt)、[MIT 搜索解析](https://github.com/sigma67/ytmusicapi/blob/86fcd17ee3ff0d19bc807558d4e1a637df395143/ytmusicapi/parsers/search.py)

首页和浏览页兼容 `singleColumnBrowseResultsRenderer`、`twoColumnBrowseResultsRenderer` 和直接的 `sectionListRenderer`。顶部 chip 携带自己的 browseId 和 params；每个 shelf 的 continuation 属于该 shelf，不能与外层页面 continuation 混用。参考设计：[MetroList browse 操作](https://github.com/MetrolistGroup/Metrolist/blob/5b2fc2b88748ef0aec94320a8d853bba5dc125ef/shared/src/commonMain/kotlin/com/metrolist/shared/api/YouTubeBrowseOperations.kt)、[其 InnerTube 集成约束](https://github.com/MetrolistGroup/Metrolist/blob/5b2fc2b88748ef0aec94320a8d853bba5dc125ef/docs/innertube.md)。

账户常见完整路径：`actions[0].openPopupAction.popup.multiPageMenuRenderer.header.activeAccountHeaderRenderer`。在该对象读取 `accountName.runs[].text`、`channelHandle.runs[].text` 和 `accountPhoto.thumbnails[].url`。字段位置存在包装差异时，可以仅在账户响应中定位 `activeAccountHeaderRenderer`；头像不能误读为歌曲 thumbnail。来源：[MIT `get_account_info`](https://github.com/sigma67/ytmusicapi/blob/86fcd17ee3ff0d19bc807558d4e1a637df395143/ytmusicapi/mixins/library.py#L460)、[MetroList 账户解析参考](https://github.com/MetrolistGroup/Metrolist/blob/5b2fc2b88748ef0aec94320a8d853bba5dc125ef/shared/src/commonMain/kotlin/com/metrolist/shared/api/YouTubeAccountParser.kt)。

认证请求使用 Cookie、`Origin: https://music.youtube.com`、`X-Goog-AuthUser` 和从会话 SAPISID 计算的 `Authorization: SAPISIDHASH <seconds>_<sha1>`；哈希原文是时间、SAPISID 和 origin，以空格连接。保留现有账户身份，不盲目写死所有用户索引为 0。只记录状态和错误类型，不记录 Cookie、Authorization 或完整原始响应。[上游认证协议实现](https://github.com/MetrolistGroup/innertubex/blob/main/src/commonMain/kotlin/com/metrolist/innertubex/InnerTube.kt#L407)、[MIT 浏览器会话校验](https://github.com/sigma67/ytmusicapi/blob/86fcd17ee3ff0d19bc807558d4e1a637df395143/ytmusicapi/auth/browser.py)

### 收藏同步的边界

点赞列表必须取完全部 continuation。中途失败时，只能增补已读到的歌曲，不能据此删除没读到的收藏。应把“分页完整成功”作为替换账户收藏快照的前提。MetroList 也明确禁止用不完整离线快照覆盖账户点赞。[分页约束](https://github.com/MetrolistGroup/Metrolist/blob/5b2fc2b88748ef0aec94320a8d853bba5dc125ef/docs/innertube.md#pagination)

HTTP 200 不能证明点赞已永久生效。YouTube.js 维护者说明 engagement 操作可能需要 BotGuard 挑战；本项目应保留失败状态，允许刷新真实收藏验证，不宣称所有账户都能稳定双向写入。[维护者说明](https://github.com/LuanRT/YouTube.js/issues/1165#issuecomment-4413435886)

## TeleMusic 的交付方式与本方案差异

TeleMusic 通过用户输入 `api_id` / `api_hash` 登录 TDLib；`SearchChatMessages` 读取音频消息，`DownloadFile` 在本地逐步下载。Media3 自定义 `TdlibDataSource` 使用本地文件随机读取，等待真实已下载的连续字节后供播放器使用。它没有提供可以直接部署到 Worker 的 Bot HTTP Range 服务。[TeleMusic 技术栈与设置](https://github.com/abn3li/TeleMusic/blob/40f2ee4c263adc9a2c6c13ac63817098efbbd74d/README.md)、[TDLib 管理器](https://github.com/abn3li/TeleMusic/blob/40f2ee4c263adc9a2c6c13ac63817098efbbd74d/app/src/main/java/com/abn3li/telemusic/data/telegram/TdlibManager.kt)、[本地音频 DataSource](https://github.com/abn3li/TeleMusic/blob/40f2ee4c263adc9a2c6c13ac63817098efbbd74d/app/src/main/java/com/abn3li/telemusic/playback/TdlibDataSource.kt)

TDLib 官方下载接口支持 offset、limit 和异步进度通知。这与云 Bot API 的 `getFile` 是不同接口，不能套用相同文件限制，也不能把 TDLib 数字 file ID 当作 Bot API 的字符串 file_id。[TDLib downloadFile](https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1download_file.html)

## Telegram 官方限制与落地约束

| 事项 | 本次核对结论 |
| --- | --- |
| 云 Bot API 上传 | multipart 音频通常最多 50 MB；URL 上传其他类型通常最多 20 MB。 |
| 云 `getFile` | 最大下载 20 MB；下载地址有效期至少 1 小时，过期重新 getFile。 |
| 已有文件复用 | 使用 `file_id` 重新发送；`file_unique_id` 不能下载或重新发送，也不是 SHA-256。 |
| 自建 Local Bot API | 下载无大小限制，上传最多 2000 MB；这是独立常驻服务，不是 Worker 里切换一个参数。 |
| Webhook | 校验 `X-Telegram-Bot-Api-Secret-Token`；按 update_id 去重；Bot 主动上传后直接保存 API 返回的 Message，不能只等 webhook。 |
| HTTP Range | 官方 getFile 文档没有保证 Range。是否可拖动必须真实验收，不能把未知能力写成已支持。 |

来源：[Telegram 文件类型与 getFile](https://core.telegram.org/bots/api#file)、[发送文件](https://core.telegram.org/bots/api#sending-files)、[自建 Bot API](https://core.telegram.org/bots/api#using-a-local-bot-api-server)、[Webhook](https://core.telegram.org/bots/api#setwebhook)。

第一版建议把云交付上限设为不超过 20,000,000 字节。超过时明确告知需要配置大文件交付服务；不得悄悄回退到“上传成功即一定可播放”。客户端通过自有 Worker 域名读取音频，Worker 内部调用 getFile；不把含 Bot Token 的下载 URL 返回给客户端。Worker 发送上游 Range 请求时，仅透传真实上游状态和长度；上游返回 200 时不能假装 206，也不能凭空添加 `Accept-Ranges: bytes`。这是根据官方能力边界作出的实现建议。

对本项目已经下载到手机的完整 M4A，优先本地直接播放；后台仓库存储独立进行。Telegram 已存文件的云播放仍需要实测首播和 seek。这样第一版不用为初次播放建立新的音频转码或常驻提取服务器。

## D1 入库、去重与 Worker 流式传输

`env.DB.batch([...preparedStatements])` 保证按顺序执行；整批属于事务，任一语句失败会回滚整批。适合一次提交 `tracks`、`audio_files`、`track_files`、`telegram_objects`、`upload_jobs` 和用户收藏关系。SQL 值使用 prepare/bind。不要分别 await 多次 INSERT 后假设它们天然构成同一事务。[Cloudflare D1 batch 官方文档](https://developers.cloudflare.com/d1/worker-api/d1-database/#batch)

建议先按 YouTube video ID 查曲目，再按客户端对完整文件计算的 SHA-256 查文件。文件内容哈希负责字节去重，video ID 负责来源歌曲查重；同曲不同编码不能混为同一文件。`telegram_objects` 保存 Bot 身份、chat ID、message ID、file_id、file_unique_id，客户端 API 仅返回公开业务字段。Webhook 没有内容哈希时先保存未归并记录，不把 file_unique_id 填进 sha256 字段。这些是针对 Issue 的数据模型建议，不是 Telegram 自动提供的哈希能力。

任务状态建议 `pending → ready / failed`；文件另外支持 `missing`。上传失败要保留实际错误与可重试状态，遇到 429 尊重 `retry_after`。同一 SHA-256 的成功结果允许重复请求复用。取消收藏只删除用户与曲目的关系，音频和 Telegram 对象继续保留。上传过程中已收到的 Message 是成功入库依据；后续 D1 写入失败要能用同一请求标识恢复，不能把可能成功的上传直接自动重传。这是常见网络失败路径，应在实际任务实现中以最少状态处理。

Worker 直接转发 `upstream.body` 可以保持流式传输；不要先 `arrayBuffer()` 或 `text()` 把整段音频读入内存。[Cloudflare Streams](https://developers.cloudflare.com/workers/runtime-apis/streams/)

免费 Worker 当前为 100,000 请求/日、10 ms CPU/请求、128 MB 内存。等待网络不计 CPU；响应体无强制大小限制，入站请求上限还依赖域名套餐。第一版不要把大文件转码和完整文件重复哈希放进免费 Worker。[Cloudflare Workers 限制](https://developers.cloudflare.com/workers/platform/limits/)

## 远端验收清单与本次证据范围

- 真实搜索覆盖综合 Top result、歌曲、视频、歌手和专辑；未知 renderer 与真正无结果分开显示。
- 真实账户会话验证覆盖头像、名字、过期 Cookie 和退出；仅保存会话不能显示为已完成资料同步。
- 收藏完整分页后更新 D1；取消收藏不删除 Telegram 文件；中途失败不误删未读到的收藏。
- 自造小型 M4A 上传、重复 SHA-256、失败重试、webhook 重放、D1 整批失败回滚与 getFile 过期刷新。
- 小文件经过 Worker 首播和拖动；核对上游实际 200/206、Content-Length 和 Content-Range。
- 超过 20 MB 的文件显示明确交付限制；没有大文件服务时不得标为云播放就绪。

上述是待执行的远端 CI / 真机验收。本文只完成主源研究和静态阅读；没有发起真实 YouTube 点赞、Telegram 发消息、上传音频或部署服务。

## 2026-11-16 自动补齐补充

用户要求点歌后自动加载封面、歌词和专辑，准确匹配自动应用，有歧义再选择。GitHub 继续检索 MetroList 的 `LrcLibLyricsProvider`、`LyricsClient` 与回归位置，仅核对功能职责，没有复制 GPL 实现；本项目复用自己的 MusicLookupClient、LRCLIB 匹配规则和 CAA 下载链路。

参考：[LRCLIB 官方接口文档](https://lrclib.net/docs)、[MetroList 歌词提供器职责](https://github.com/MetrolistGroup/Metrolist/blob/5b2fc2b88748ef0aec94320a8d853bba5dc125ef/shared/src/commonMain/kotlin/com/metrolist/shared/api/lyrics/LrcLibLyricsProvider.kt)。自动选择的“歌名、艺术家、时长相差不超过 2 秒，专辑唯一”是本项目的保守应用策略。播放器先播放，网络补齐后台执行；仍由本项目 Swift 实现落地，不新增服务或重复部署。

### 来源封面尺寸复验

真机全屏放大 YouTube Music 的 120px 列表封面会模糊。GitHub 在 ytmusicapi 中检索 resize 没有命中通用辅助函数，未复制代码；直接对当前实际返回的 Google 图片地址验证尺寸参数：原图 HTTP 200、9,999 字节、120×120；同一图片改为 `=w544-h544` 后 HTTP 200、133,795 字节、544×544，已核对仍是正确 Starboy 封面。应用只为 yt3/lh3.googleusercontent.com 的原生尺寸参数请求播放器大小，列表仍用小图，其他域名地址保持原样。这是对实际图片服务的验证，不承诺所有外部图片都支持同样参数。

## 缓存播放收尾核对

Unix Timestamp：1794827855。本轮 GitHub 检索 `cache playback`，读取 MetroList 固定提交 [36bb564b4a148c6b415dc3c1c74faf790ae76bc6 的缓存说明](https://github.com/MetrolistGroup/Metrolist/blob/36bb564b4a148c6b415dc3c1c74faf790ae76bc6/docs/audio-cache.md)。该文档区分完整缓存、播放读取和网络预取，失败后保留已有文件。本项目结合真实手机的云端等待问题，自行把仓库核对/补传及播放统计移到本地缓存播放之后的后台任务；保留现有文件校验和缓存逻辑，不复制 GPL 代码，不引入上游缓存实现。真实音频、Keychain 和 AVPlayer 的 503 回归交由远端 CI 执行，本地仅静态核对。
