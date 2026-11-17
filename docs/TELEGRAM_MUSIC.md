# YouTube Music、Telegram 音乐仓库与 D1

对应 [Issue #11](https://github.com/C0verSnow/C0SnowMusic/issues/11)。保留现有 SwiftUI、资料库和播放器设计；接口参考及许可见 [调研](TELEGRAM_MUSIC_RESEARCH.md)。

## 用户流程

- 搜索分为 c0vermusic 与 Library；已连接仓库的匹配结果合入 c0vermusic 搜索。YouTube Music 的综合/歌曲/视频/专辑/艺术家/歌单结果按服务返回分组，支持下一页与历史。艺人和专辑进入内容页，不当作音频下载。
- 首页读取 YouTube Music 实际首页分区；登录时使用当前账户 Cookie。再次聆听来自本设备真实播放记录，仓库社区热门来自 D1 真实播放次数；没有数据就不展示，不伪造推荐。
- 顶栏只保留账户入口，使用已读取的真实头像。账户展示名字、handle、已验证/待验证状态，可刷新、重登或注销。原文件导入移到账户 → Music Settings → 从文件导入。
- Music Settings → 音乐仓库输入 HTTPS 地址及设备密钥。密钥保存在本机 Keychain，不写入 IPA、UserDefaults 或公开文档。首次连接会请求真实 API；断开只清除本机连接，不删除云端资源。
- 连接仓库后，点播放先按 YouTube video ID 查询 D1；已有音频从 Worker 取得并验证后缓存。缺失时由手机现有 yt-dlp 获取原生 M4A，先播放本机缓存，再独立保存到 Telegram。原有缓存也会在首次使用时补入仓库。未连接时继续本机下载模式。
- 音频先完整下载到设备，沿用 AVPlayer 的本地播放、拖动进度和 500 MB 淘汰。Worker 另提供正确的 HTTP Range/HEAD 接口；当前 iOS 不把远程流交给 AVPlayer，因此不承诺首字节即播。Telegram 没有承诺 Range；Worker 在流中跳过区间外字节并截取所需字节，不伪装上游的 Range 支持。
- 登录后自动同步完整 YouTube 收藏，Library 可下拉刷新；在线专辑、艺人、歌单直接进入对应资料库分类。在 YouTube 收藏/取消收藏后重新读取完整列表确认，成功才提交 D1。YouTube BotGuard 可能拒绝操作，此时用易懂提示说明操作未完成，不伪造成功。
- 同步只替换当前设备密钥对应用户的 YouTube 收藏关系。App 自己的收藏、其他用户、Telegram 音频都保留。每批最多 20 首暂存，完整数量核对后用 D1 事务切换，任一页或批次失败不清空旧收藏。
- 本地导入文件不自动上传。本地 SwiftData 收藏与在线 YouTube 收藏在 Favorite Songs 统一展示，仍各自保存在原有来源。没有后台定时同步、上传视频或伪装无损音频。

## 自动补齐与少点几次

- 输入搜索词后停顿 350 毫秒自动搜索，不需要再按搜索。切换分类仍按实际接口搜索；清空输入会清空旧结果。
- 打开账户页时，尚未验证的会话自动刷新资料；登录后自动加载资料库并同步收藏。仓库首次连接成功就加载收藏与热门，不需要再点刷新。主动操作失败显示易懂提示，后台失败不在首页显示诊断。
- 在线音频准备完成后立即交给播放器；封面、歌词、专辑在后台补齐，不让歌词或封面请求拖住音频播放。优先使用歌曲来源封面，缺失时使用准确匹配专辑的 MusicBrainz/CAA 封面。
- 歌词与专辑沿用 LRCLIB。只有歌名、非空艺术家、时长（相差不超过 2 秒）一致，并且精确候选的专辑唯一时自动应用。不同专辑版本或未知艺术家不会猜测；保留 Lyrics Settings 中的手动版本选择入口。
- 自动取得的歌词、专辑和封面在本机缓存旁保存，重新点同一首歌直接恢复；不覆盖已经手选或导入的歌词，不把用户音频发送给歌词或封面服务。播放器显示已知专辑，系统媒体信息同步更新。
- 当前缓存被主动清空后，相关本机补齐资料也随之移除。重新从仓库取音频会再次自动补齐；D1 保存歌曲索引和原有封面 URL，本期不把完整第三方歌词写入 D1。

## 部署与配置

本服务使用专用 Bot、私有存储频道、新 D1 和独立 Worker，初期不使用 R2、Queues 或常驻服务器。不要复用或覆盖旁边 TGMusic 的 Worker/Webhook。

1. 复用现有 Wrangler 登录，运行 `wrangler d1 create c0snow-music --config worker/wrangler.toml`，将返回 UUID 填入该配置。已有数据库不得重复创建。
2. 使用已登录 `tg` 与 BotFather 创建专用 Bot，用 `tg create-channel` 创建私有存储频道；把 Bot 加为可发音频的管理员。`tg` 的子命令对数字私有聊天支持不完全一致，先核对帮助；不能因为 `send` 支持 `id:` 就假设 `invite` 也支持。必要时在本人已登录的 Telegram 界面完成管理员配置。
3. 按 `worker/.dev.vars.example` 在仓库根目录保存 mode 0600 的 `.env`。`API_KEYS` 为 JSON `设备随机密钥 → 稳定用户ID`；`SEND_CHAT_IDS` 为 JSON `稳定用户ID → 授权接收聊天ID`。同一用户多设备使用同一个稳定用户ID。不得让客户端提供任意发送目标。
4. 运行 `python3 scripts/configure_music_backend.py deploy`。脚本先核对 Bot/频道，再应用远端迁移，用 `wrangler deploy --no-bundle` 直接上传原生 JS，通过 stdin 写 Workers Secrets，最后注册与核对 Webhook。不触发本地编译。
5. 运行 `python3 scripts/configure_music_backend.py check --url https://你的Worker.workers.dev`，核对真实受保护目录、Bot 和 Webhook。脚本不会输出 Token。
6. 在 iPhone 的音乐仓库设置中填地址和设备密钥。配置文件只留本地，不上传或作为 CI Artifact。设备密钥可单独轮换，不需要把 Bot Token 发给手机。

`TELEGRAM_BOT_TOKEN`、`TELEGRAM_STORAGE_CHAT_ID`、`TELEGRAM_WEBHOOK_SECRET`、`API_KEYS`、`SEND_CHAT_IDS`、`ADMIN_KEY` 全部为 Workers Secrets。D1 迁移文件入库；已应用的迁移不再修改，新结构另写新迁移。

## API

所有 `/api/*` 除 Webhook 都需要 `Authorization: Bearer <设备密钥>`；Webhook 用 Telegram 的 Secret 请求头并核对存储频道。API 不返回 Bot Token、频道位置、Telegram 文件下载 URL。

| 接口 | 用途 |
| --- | --- |
| `GET /api/tracks?search=&limit=30&offset=0` | 搜索仓库、分页，单页最多 100 |
| `GET /api/tracks?source_id=<videoID>` | 点击歌曲前查是否已有资源 |
| `GET /api/tracks/:id` | 元数据和音频状态 |
| `POST /api/tracks` | multipart `track` JSON、`sha256`、真实 `audio`；支持 MP3/M4A |
| `GET /api/files/:sha256` | 按内容哈希查文件状态 |
| `GET/HEAD /api/tracks/:id/content` | 受保护音频；单段 Range、后缀、416、准确长度 |
| `POST /api/tracks/:id/send` | 复用 file_id，向管理员配置的授权聊天发音频 |
| `POST /api/telegram/webhook` | 存储频道原生上传入库，按消息幂等处理 |
| `GET /api/jobs/:id` | 上传状态、次数、下次重试时间 |
| `POST /api/jobs/:id/reconcile` | 加 `X-Admin-Key`；人工核对发送结果，实际回执或 `not_sent: true` |
| `GET /api/favorites` | 当前用户的在线收藏 |
| `PUT/DELETE /api/tracks/:id/favorite` | App 收藏关系，不删除资源 |
| `POST /api/favorites/snapshots` | 开始本次完整 YouTube 收藏快照 |
| `PUT /api/favorites/snapshots/:id` | 每批 1–20 首 `tracks` 元数据 |
| `POST /api/favorites/snapshots/:id/commit` | `{complete:true,count:完整去重数量}`；事务替换 |
| `POST /api/favorites/sync` | 不超过 20 首时的单请求完整同步 |
| `POST /api/tracks/:id/play`、`GET /api/home` | 真实播放记录与社区热门 |

`tracks` 与 `audio_files` 用内部 ID，`track_files` 多对多关联；文件按实际字节 SHA-256 去重。`telegram_objects` 保存 Bot/消息/文件定位，`upload_jobs` 保存上传状态。相同音频可关联多个视频/歌曲而不重复上传。

## 限制与恢复

标准云 Bot API 的 getFile 最大 20 MB。当前从 App 上传也限制为 20,000,000 字节，避免“上传成功但永远无法下载”。原生 Telegram 上传的大文件记录为 `hash_pending`，SHA-256 保持 null，可通过 Bot 发送，App 交付明确返回 413。`file_unique_id` 仅作为 Telegram 快速索引，不冒充哈希。更大文件/真正即播需要另行部署 Local Bot API 或专用媒体交付适配器，本期没有假装实现。

上传先落任务再发送；相同哈希只领取一次。Telegram 明确拒绝可重试，429 持久保存完整 retry_after 截止时间，不在一个请求里无限等待。网络断开、5xx 或回执写入失败可能已经发送，任务保持 pending/uncertain，禁止自动重发。管理员先通过 Telegram 核对，再提交真实 message_id/file_id/file_unique_id，或者明确确认未发送后解锁。Worker 日志只记录错误类别，不打印含 Token 的上游异常。

Telegram 下载文件失效时标记 missing；目录中的 available 随之为 false。应用显示错误，不伪造可用。旧 Cookie 数据和旧音频缓存 JSON 兼容读取。

Worker 对完整音频做一次 WebCrypto SHA-256；免费套餐 CPU 预算是否适合实际文件大小必须实测，不承诺所有 20 MB 文件都能在免费 CPU 配额完成。播放流不缓冲完整文件；手机仍保留音频缓存。

备份只保存 D1 元数据，不等于独立音频备份。使用现有 Wrangler：

```sh
wrangler d1 export c0snow-music --remote --output /安全的备份目录/c0snow-music.sql --config worker/wrangler.toml
```

导出后核对文件大小，在独立空 D1 验证恢复再改生产绑定。不要清空生产数据库或以 Markdown 反向覆盖 D1。

## 验证

本地只做源码、JS 语法、plist/JSON 和差异检查。已有 build-player.yml 增加 Worker 远端 job，使用真实 SQLite 执行正式迁移、真实合成 MP3 及 HTTP Telegram 边界服务，检查去重、哈希、Range、429、发送不明、人工核对、失效、大文件、完整收藏事务和用户隔离。原 iOS 模拟器集成/UI、设备 Release 和 IPA 仍走原流程；Release 依赖两个 job 都通过。

真实网站接口、真机账户头像、YouTube 登录/收藏授权、用户实际音乐播放与大文件性能要单独记录，不把合成测试当作全部真机验收。

## Issue #15：职责与失败恢复

对象对应表和完整链路见 [架构核对](OBJECT_ARCHITECTURE.md)。AudioRepository 统一本地缓存、Worker 与手机提取；云端索引存在但文件不可用时，YouTube 曲目仍可尝试本机重新获取。云端错误保留在后台错误状态，取消不会触发重新下载。Telegram-only 曲目无法借 YouTube 重建文件，也不会再误走 YouTube 上传接口。自动缓存淘汰后同步清理失效播放引用，永久资料库副本独立保留。
