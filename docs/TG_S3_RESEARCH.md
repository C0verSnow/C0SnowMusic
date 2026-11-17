# gps949/tg-s3 实际接入研究

核对时间：2026-11-17 UTC。上游固定为 `82bff102498658fd462ad478229fc49cb2f44c47`，查询时也是 `main` 的最新提交。音乐仓库按本次读取的 `75d213e2795d055c33655140c50b51285eced08e` 源码理解。本文只研究，不实现、不部署、不改密钥、不发送消息；没有本地编译、构建或编译型测试，也没有触发远端 CI。[上游提交][commit]、[音乐 Worker][music-worker]

## 1. 先说结论

**技术上可以让真实 tg-s3 承担新音频的对象存储，同时保留现有音乐 API 和旧 Telegram 文件读取。最小方案是保留音乐 Worker，在后面接一个独立 tg-s3 Worker；先保留 20,000,000 字节上传限制，不引入 VPS。** 这不是把现在的 Telegram 适配器改名：新音频的字节确实经过 tg-s3 的 PutObject，后续通过其 GetObject/HeadObject 交付；歌曲、收藏、播放记录仍归音乐 D1。[音乐客户端][music-client]、[音乐 Worker][music-worker]、[上游路由][index]、[PutObject][put]

接入时有六个必须讲清楚的边界：

1. **鉴权分两种 Bearer。** `/api/upload` 接受 D1 的 `access_key_id:secret_access_key`；普通 S3 GET/HEAD 的 Bearer 是 Telegram Mini App `initData`。网关可统一使用 SigV4，不能把普通固定 token 随便塞给所有路由。[上传专用鉴权][simple-auth]、[普通鉴权][auth]、[Mini App Bearer][bearer]
2. **既有 Bot 可以复用，现有 Webhook 可以保留。** S3 上传直接取得 `sendDocument` 回执并写 D1，不等 Webhook。但上游 `deploy.sh` 会调用 `setWebhook`；音乐仓库现有配置脚本的 deploy 分支也会调用它，不能直接照跑这两个完整部署流程。[上传写入][put]、[上游部署脚本][deploy-webhook]、[音乐配置脚本][music-config]
3. **旧文件先保留，按新后端、旧后端分别读取。** 不能把 tg-s3 的对象假装成现有 `telegram_objects`：上游 PUT 成功只回 ETag，普通 PUT 存的是 document；音乐 `/send` 目前用 `sendAudio(file_id)`，两者不能直接等同。[PutObject 返回][put]、[音乐 Worker][music-worker]、[Telegram 文件类型约束][sending-files]
4. **上游没有“恰好上传一次”的完整保证。** 同 key 普通 PUT 会再次发 Telegram 消息，并异步尝试删除旧消息。网关必须保留现有按哈希领取任务、`uncertain` 后先核对的做法。[条件写入][put-conditions]、[覆盖清理][put-cleanup]、[音乐上传任务][music-worker]
5. **R2 在运行时代码里可选，仓库默认配置和一键脚本却默认创建、绑定它。** 禁用要明确去掉 `CACHE` 绑定并避开脚本的创建步骤，不能仅仅不创建桶。[Env][types]、[Wrangler 配置][wrangler]、[缓存代码][get]、[脚本初始化][deploy-init]
6. **“2GB”不是这个固定版本已经打通的端到端承诺。** Local Bot API、可达 VPS、HTTP 上传入口限制只是前置条件；处理器鉴权还有明确的 ESM/`require` 冲突，定时清理也可能把有效大文件当失效文件删掉。见第 7 节。[处理器][processor-auth]、[处理器模块配置][processor-package]、[定时清理][cron]

此外，维护者已在 Issue #6 明确提醒 Telegram 的云存储用途条款问题。官方条款 5.2(e) 点名 `cloud storage sites`，6.3 不保证文件持续可用。对“外部 S3 音乐仓库”的适用判断属于基于这些条文的判断，不能把 README 的“无限免费”视为许可或耐久保证。[维护者回复][issue6-comment]、[官方用途条款][terms-operation]、[官方数据可用性条款][terms-data]

## 2. 项目规模、维护和许可证：如实记录

本次实际进行了 GitHub 仓库检索、固定提交源码读取、最近提交和全部 Issue/PR 列表及相关回复检查。`tg-s3` 搜索返回了用户指定的 `gps949/tg-s3`，也有其他项目；本次没有做出“已从所有候选里筛出最佳方案”的结论，研究对象由用户明确指定。[GitHub 搜索入口][repo-search]、[仓库 API][repo-api]

| 检查项 | 2026-11-17 查询结果 | 证据 |
| --- | --- | --- |
| 规模 | 123 stars、38 forks、2 watchers；创建于 2026-03-20，未归档 | [GitHub 仓库 API][repo-api]；这些数字会变化 |
| 最新代码 | 2026-07-10 的 `82bff10`，距研究日约四个月；前一次重要修复为 2026-05-31 的 `a4e660a` | [固定提交][commit]、[迁移修复提交][migration-fix] |
| Issue 响应 | #2 在 5 月 12 日提出，维护者 5 月 31 日回复并修复迁移；#4 在 6 月 18 日提出，维护者 7 月 10 日解释大文件前置条件；#6 在 9 月 23 日提出，维护者 10 月 30 日详细回复；#7 在 9 月 29 日提出，查询时无回复 | [#2][issue2]、[#2 回复][issue2-comment]、[#4][issue4]、[#4 回复][issue4-comment]、[#6 回复][issue6-comment]、[#7][issue7] |
| 未解决状态 | 查询时四个普通 Issue（#2、#4、#6、#7）仍 open；另有 open PR #1。仓库 API 的 `open_issues_count=5` 含 PR，不能写成五个普通 Issue | [全部 Issue/PR API][issues-api]、[PR #1][pr1] |
| 许可证声明 | 英文及中文 README 末尾写 MIT；固定提交完整文件树没有独立 `LICENSE`/`LICENSE.md`/`COPYING`，GitHub API 的 `license` 为 null | [英文 README][readme]、[中文 README][readme-zh]、[固定文件树 API][tree-api]、[仓库 API][repo-api] |

因此应称为“用户指定、有一定关注度、维护者仍有回复、代码更新不频繁的小项目”，**不能声称已经通过‘高 star、近期持续提交、许可证完整’的筛选**。README 的 MIT 是项目自己的声明，但没有完整独立许可证文本和版权声明；不能写成“已核实独立 MIT LICENSE”。[README][readme]、[文件树][tree-api]

依赖也要分开说：Worker 的 `package.json` 只有开发依赖，实际要求 Wrangler `^4.0.0`、TypeScript `^5.7.0`；README 的“wrangler v3”已落后于代码。VPS 处理器另依赖 Express、Sharp 和镜像里的 FFmpeg。PR #1 的订阅、多租户方案未在此固定提交合入，不属于当前接入能力。[Worker 包配置][package]、[处理器包配置][processor-package]、[处理器镜像][processor-docker]、[PR #1][pr1]

## 3. 音乐网关可直接调用的真实路径、鉴权、headers

### 3.1 路径与鉴权表

假定独立 tg-s3 地址为 `https://对象服务域名`，音乐桶名为 `music`。它按 URL 路径解析 bucket/key，bucket 转小写；不是按虚拟主机解析桶。建议 key 为 `audio/<实际音频 SHA-256>.mp3` 或 `.m4a`，各路径段编码后再签名。[路径解析][path]、[签名校验][sigv4]

| 用途 | 方法与路径 | 真正接受的鉴权 | 结果与限制 |
| --- | --- | --- | --- |
| 普通对象上传 | `PUT /music/audio/<hash>.m4a`，body 是音频原始字节 | AWS SigV4 header，或有效预签名参数 | 成功 `200`、空 body、`ETag`；不是 JSON Telegram 回执 |
| 简单上传扩展 | `PUT` 或 `POST /api/upload?bucket=music&key=audio%2F<hash>.m4a`，body 同上 | `Authorization: Bearer <access_key_id>:<secret_access_key>` | 只做上传；调用同一 PutObject；readonly 拒绝，bucket 权限受限 |
| 下载 | `GET /music/audio/<hash>.m4a` | SigV4 header，或 GET 的预签名参数 | 完整 GET `200`；可处理单段 Range，返回 `206`/`416` |
| 查元数据 | `HEAD /music/audio/<hash>.m4a` | SigV4 header，或 HEAD 的预签名参数 | `200` 与对象 headers、无 body；只查 D1，不证明 Telegram 字节仍可下载 |
| 创建桶 | `PUT /music` | admin 级 SigV4，或有效 Mini App initData | 会尝试创建 Forum Topic；失败后退回普通聊天发送，仍可落桶记录 |

上表依据：[上传扩展路由][simple-route]、[鉴权][auth]、[S3 授权][authorize]、[PutObject][put]、[GetObject][get]、[HeadObject][head]、[CreateBucket][bucket]。

**两个 Bearer 不通用。** 普通 `authenticate()` 的 Bearer 会校验 Telegram WebApp 的 HMAC、必填 `auth_date`，最多一小时旧、最多一分钟未来；校验成功作为 admin。`/api/upload` 则单独查 D1、按冒号拆 AK/SK、做恒时比较。不能用音乐设备 API key、Bot token、`VPS_SECRET` 或任意固定 Bearer 代替。不存在源码支持的 `X-API-Key` 对象鉴权。[普通鉴权][auth]、[Mini App Bearer][bearer]、[简单鉴权][simple-auth]

**建议网关统一 SigV4**，理由是 GET/HEAD 本来就需要它；简单上传只能省 PUT 的签名，不会省整套读签名。AK/SK 只放服务端，手机继续使用原来的音乐设备 key，不增加 S3 凭据输入。[音乐客户端][music-client]、[上游鉴权][auth]

### 3.2 SigV4 请求必须对应真实请求

普通 header 形式为：

```text
Authorization: AWS4-HMAC-SHA256 Credential=<AK>/<YYYYMMDD>/us-east-1/s3/aws4_request, SignedHeaders=<实际签名的小写有序头名>, Signature=<实际计算的十六进制签名>
x-amz-date: <YYYYMMDDTHHMMSSZ>
x-amz-content-sha256: <PUT 原始字节的 SHA-256；无正文读请求可用 UNSIGNED-PAYLOAD>
Content-Type: audio/mp4 或 audio/mpeg
```

这只是协议字段说明，不是可执行实现。应签真实 method、编码后的 pathname、排序并编码的 query、实际 host 与签名 headers。普通签名时间允许正负 15 分钟，Credential 日期必须与 `x-amz-date` 相同；服务为 `s3`，默认 region 为 `us-east-1`。不要把手机的 Authorization 原样传过去，也不要签一个域名后发到另一个域名。小文件 PUT 会比较真实 SHA-256；预签名校验本身使用 `UNSIGNED-PAYLOAD`。[签名实现][sigv4]、[PUT 摘要校验][put]、[默认 region][wrangler]

网关 PUT 可把实际发送的 `content-type;host;if-none-match;x-amz-content-sha256;x-amz-date;x-amz-meta-sha256` 作为签名头名单；GET/HEAD 可使用 `host;x-amz-content-sha256;x-amz-date`。有意签 Range 时，再按小写字典序加入 `range`，并使用请求中真实的值。没发送的 header 不列入名单；正文是原始音频，不是手机 multipart 表单原封不动转发。[签名实现][sigv4]、[PUT 读取正文][put]、[音乐表单入口][music-worker]

预签名 GET/HEAD 参数为 `X-Amz-Algorithm`、`X-Amz-Credential`、`X-Amz-Date`、`X-Amz-Expires`、`X-Amz-SignedHeaders`、`X-Amz-Signature`，有效期 1–604800 秒。method 参与签名，GET 链接不能直接充当 HEAD 链接。上游自带 URL 生成器读取第一条 active admin credential；网关自行按已有受限凭据签名则不必依赖这个生成器。[签名校验][sigv4]、[预签名生成器][presigned]、[凭据读取][metadata-credentials]

### 3.3 音乐需要保留的请求和响应语义

- PUT 发送正确 MIME、真实字节、准确长度；使用 `If-None-Match: *` 避免常规覆盖。可加 `x-amz-meta-sha256`，由 HEAD 取回比对；它是业务元数据，不能替代按字节验证。简单上传同样会把这些 headers 传入 PutObject。[简单上传路由][simple-route]、[PUT 条件与校验][put-conditions]、[元数据 headers][headers]
- GET 转发 `Range` 以及用到的条件 headers。上游 GET 支持条件 `304`/`412`；小文件先把 Telegram 完整内容放入内存，再切片返回，不等于 Telegram 源站有 Range。带 Range 请求不读写 CDN/R2 缓存。[GetObject][get]
- HEAD 返回 ETag、Content-Type、Content-Length、Last-Modified、Accept-Ranges 和用户元数据。它没有 getFile 检查；对未知回执的核对还需要 GET 并验证字节，不能只看 `HEAD 200`。[HeadObject][head]、[响应头构造][headers]
- 音乐网关继续返回现有 JSON 和 `private, no-store`；内容接口保留单段 Range、准确长度、HEAD、416 等约定。tg-s3 对普通音频默认给 `public, max-age=86400`，不应原样成为设备接口的缓存策略。[当前音乐交付][music-worker]、[上游响应头][headers]、[默认缓存值][constants]

## 4. D1、credential、bucket 怎样初始化

**音乐 D1 与 tg-s3 D1 应分开。** 前者保存 `tracks/audio_files/track_files/favorites/plays/upload_jobs/telegram_objects`，后者保存 `buckets/objects/credentials` 等。虽然没有必要合并这两套表，也不能直接用音乐 schema 冒充对象 schema。[音乐迁移][music-schema]、[tg-s3 schema][schema]

### 4.1 数据库起步

上游 `wrangler.toml` 的 `DB` 必填，默认 database name 是 `tg-s3-db`，`database_id` 为空占位。新库走固定提交的 `migrations/0001` 至 `0004`；后续部署继续沿用 migration 历史。[Wrangler][wrangler]、[基线 migration][migration1]、[0002][migration2]、[0003][migration3]、[0004][migration4]

`src/storage/schema.sql` 是当前完整表结构；`npm run db:init:remote` 直接执行它。**不要在同一个新库先执行完整 schema，再无条件重跑 0001–0004**：完整 schema 已含 `is_public/optimize_config/default_encryption`，后续 ALTER 会重复。Issue #2 已发生过基线与 ALTER 冲突，固定提交包含修复；不是今天还没修的同一个 bug。[包脚本][package]、[schema][schema]、[migration 注释][migration1]、[#2 回复][issue2-comment]

### 4.2 凭据从哪里来

真实 AK/SK 在 D1 `credentials`，没有读取 `S3_ACCESS_KEY`/`S3_SECRET_KEY` 环境变量的兜底。至少需要这些字段：

| 字段 | 音乐网关建议值/含义 |
| --- | --- |
| `access_key_id` / `secret_access_key` | 专门给音乐服务的随机 AK/SK；不写进文档、代码或手机 |
| `name` | 能认出的用途名 |
| `buckets` | `music`；多个桶用逗号分开，`*` 表示全部 |
| `permission` | `readwrite`；可读写对象，不能创建/删除桶 |
| `is_active` | `1` 才会被正常鉴权读取 |
| `created_at` / `last_used_at` | schema 默认值/使用记录 |

字段与权限依据：[schema][schema]、[credential 查询和创建][metadata-credentials]、[授权函数][authorize]。

创建有两条真实路：已有 admin 通过 `/api/miniapp/credential` 创建，或在受控初始化时写入 D1。Mini App 管理 API 要 admin；在“不改 Webhook”的起步方案里，可以使用一次性的受控 D1 初始化，避免依赖 Telegram 管理界面。**这是未来初始化建议，本次没有生成、读取或写入任何真实密钥。**[Mini App credential API][credential-api]、[D1 写入函数][metadata-credentials]

需要特别纠正文档矛盾：`docs/deployment.md` 部分段落仍说脚本自动创建并显示初始 admin AK/SK，但本次固定的 `deploy.sh` 没有 credential INSERT/生成步骤，结尾让用户去 Keys 页创建；迁移也只建空表。因此不能等部署脚本自动给音乐网关生成可用凭据。[旧部署描述][deployment-doc]、[脚本实际初始化][deploy-init]、[脚本结尾][deploy-summary]、[migration1][migration1]

### 4.3 桶与 Telegram 聊天的关系

`buckets` 至少要有 `name`、`created_at`、`tg_chat_id`；可选 `tg_topic_id`。音乐桶保持 `is_public=0`、`default_encryption=0`，不启用媒体优化和对象过期规则；计数初始为零。`DEFAULT_CHAT_ID` 是 CreateBucket 使用的默认聊天，实际 PUT 使用 D1 桶行里的 `tg_chat_id/tg_topic_id`。[schema][schema]、[桶写入函数][metadata]、[CreateBucket][bucket]、[PutObject][put]

初始化桶也有两种办法：

- admin 签名 `PUT /music`，上游尝试在默认超级群创建 Topic；失败会记录 warning，再以无 Topic 的方式创建桶。因此“建桶成功”不能证明 Bot 有发送文件的权限。[CreateBucket][bucket]、[#2 回复][issue2-comment]
- 对已知聊天做受控 D1 初始化，明确 `tg_chat_id`，无 Topic 时设 null。这样起步不需要发送创建 Topic 请求。已有存储频道在 Bot 有发帖权限时可用 `sendDocument`；这一点仍要在未来获准的实际验证中核对，不能拿建表成功代替。[桶写入函数][metadata]、[上传客户端][telegram-client]、[Telegram sendDocument][send-document]

## 5. R2 可选，但缓存不是完整备份

| 实际路径 | 固定提交的行为 |
| --- | --- |
| L1 Cache API | 非 SSE-C、非 Range、非空且不超过 `20*1024*1024` 字节的完整 GET，先读 `caches.default`；命中前核对 D1 ETag |
| L2 R2 | 有 `env.CACHE`、非 SSE-C、非 Range、大小在 `64*1024` 至 `20*1024*1024` 字节之间才尝试读取；核对 R2 custom metadata 的 ETag |
| L3 Telegram | 缓存没命中后下载；小文件完整缓冲；完整 GET 可异步回填缓存。大于阈值转 VPS，不进 R2 |
| Range / HEAD | Range GET 不走这些缓存读取/回填分支；HEAD 只查对象元数据 |
| 缓存失败 | R2 读写失败被捕获或记日志，继续读 Telegram/返回已读字节；PUT 本身不把文件写 R2 |
| 清理 | 覆盖/删除尝试清 CDN 和 R2；cron 每次清最多 20 条 R2 里的失配/孤儿记录，没有实现按“热度”淘汰或自动容量上限 |

依据：[完整缓存逻辑][get]、[阈值][constants]、[HEAD][head]、[PUT 写入][put]。

因此，不启用 R2 的正确含义是部署配置不绑定 `CACHE`，并跳过 `deploy.sh` 的 R2 创建和 lifecycle 设置。仅把账户里桶删掉而保留绑定，不是可用配置。Worker 代码本来允许没有 CACHE；README 和默认 `wrangler.toml` 并未提供一个现成的“无 R2 一键部署”开关。[可选 Env][types]、[默认绑定][wrangler]、[脚本 R2 步骤][deploy-init]

R2 在一次符合条件的完整读取后就可能入缓存，不是达到某个访问次数才算“热”。没有 10GB 自动环形淘汰逻辑；脚本配置的是 90 天对象到期。没有单独实现“满了就停传 Telegram”的容量门槛；R2 写失败不会反向撤销已成功的对象上传。不能把免费额度当作程序内硬容量。[GET 回填与错误处理][get]、[90 天策略][deploy-init]。#7 正在询问关闭 R2 和满额行为，查询时无维护者回复，本文结论来自源码而非已获上游答复。[Issue #7][issue7]

注释说“加密文件跳过缓存”，实际条件主要只排除 SSE-C；SSE-S3 自动解密后的明文也能进上述 CDN/R2 分支。这是代码阅读结论，不能泛称“两种加密都不缓存”。音乐最小方案先不用新加密，避免无意引入另一套密钥管理。[GetObject][get]

`caches.default` 的内容和 `cache.delete()` 都局限于当前数据中心，不是全网同步缓存/全局 purge。上游读取时还会对照 D1 ETag，所以不能只凭 purge 函数名推断全球强一致。[上游缓存核对][get]、[Cloudflare Cache API][cf-cache]

## 6. 复用既有 Bot、保留 Webhook，以及旧文件不删的迁移

### 6.1 不动 Webhook 的可行范围

**小文件 S3 路径可行。** `sendDocument` 是 Worker 主动请求 Telegram，得到同步消息回执后写 tg-s3 D1；`getFile` 也主动调用。Bot 当前更新回调地址属于另一条链路，不是这两个动作的前置条件。[上传顺序][put]、[TelegramClient][telegram-client]

保留现有 `/api/telegram/webhook` 和其 secret，tg-s3 不接收更新即可；不要执行上游 `/bot/webhook` 注册，不要执行 `getUpdates` 抢更新。tg-s3 的 Bot 命令、聊天自动入库、Mini App 入口管理不因此自动可用。其 webhook 主要处理 private chat，本来也不是现有音乐存储频道 webhook 的替代品。[上游 webhook 路由][index]、[上游消息处理][bot-webhook]、[音乐 webhook][music-worker]、[Telegram 更新机制][telegram-updates]

未来部署需把“部署 Worker/配置 DB”与“注册 Webhook”分开执行。上游 `deploy.sh` 无条件随有效 URL 尝试 setWebhook；音乐 `configure_music_backend.py deploy` 也会部署、覆盖 secrets、setWebhook。两个脚本都不能直接作为本次无副作用接入的现成入口。[上游脚本][deploy-webhook]、[音乐脚本][music-config]

Bot 可共用，但音乐原生频道入库与 tg-s3 对象入库应明确职责。建议新对象使用明确的专用桶/聊天位置，既有频道旧消息保持原样；同聊天使用时，未来实际验证要核对更新是否会造成音乐侧重复索引，不假定 Bot 自己的发送一定会以预期形式回到旧 webhook。[音乐 webhook 去重][music-worker]、[tg-s3 直接回执落库][put]

### 6.2 推荐迁移：先让新写入走 tg-s3，旧读取保持可用

1. 保留全部 `telegram_objects`、`audio_files`、歌曲关联和旧消息；增加明确的对象后端定位，区分旧 Telegram 与新 tg-s3 的 bucket/key。旧行不改成假 S3 行。客户端下载接口不变。[音乐 schema][music-schema]、[客户端接口][music-client]、[上游对象 schema][schema]
2. 新上传按实际 SHA-256 领取现有 upload job，发到真实 tg-s3，收到成功或核对成功后才把新对象标成 ready。用哈希组成不可变 key，避免用歌名作为覆盖键。[音乐任务领取][music-worker]、[PutObject][put]
3. 下载优先使用已验证的新定位，没有新定位则走旧 `tg_file_id` 读取。迁移期间保留旧定位作回退；网络 `503` 不等于对象不存在，不能见到后端短暂故障就把旧文件标 missing。[当前旧读取][music-worker]、[上游错误返回][index]
4. 如需搬旧文件，读取旧音频原始字节，核对真实 SHA-256，再 PUT 到新的不可变 S3 key。通过 HEAD 核对大小/元数据，并 GET 校验字节后，才登记新定位。**整个步骤不执行 Telegram 删除、S3 DELETE、旧行 DELETE 或替换旧消息引用。** 失败留旧路径继续读。[当前哈希与读接口][music-worker]、[PUT/GET/HEAD][put]、[对象读取][get]、[元数据读取][head]
5. 未算出哈希的旧大文件仍留 `hash_pending` 和旧定位；不能用 `file_unique_id` 充当 SHA-256，也不能承诺接入 tg-s3 后立刻跨过当前 App 的 20,000,000 字节上限。[音乐 schema 与可用状态][music-schema]、[音乐可播放对象选择][music-worker]、[客户端限制][music-client]

这是“保留旧副本、逐个确认新副本”的建议。新对象最后可能仍落在同一个 Telegram 平台，但由真实 tg-s3 管理 bucket/key、回执和交付。不能在同 key 上反复 PUT 作为迁移核对，因为普通覆盖会触发旧消息清理。[覆盖清理][put-cleanup]

### 6.3 零拷贝 D1 导入能否做

**表结构允许，当前没有供音乐迁移直接调用的现成导入接口。** 使用同一 Bot 时，可把旧消息的 `tg_chat_id/tg_message_id/tg_file_id/tg_file_unique_id` 加上 key、真实大小、MIME、时间、正确 ETag 写成对象记录，并更新桶统计；get-object 不强制要求源消息类型是 document，因此旧 audio 的 file_id 可用于 getFile。[对象 schema][schema]、[对象写入与统计][metadata]、[GET][get]、[Telegram getFile][telegram-getfile]

但这会让两个系统共同引用同一消息；tg-s3 的覆盖、删除、生命周期或一致性清理会尝试删除该消息。要保证“不删旧文件”，不能在未隔离这些删除路径时直接把旧消息纳入 tg-s3 管理。最小方案优先保留旧读路径，搬字节到新 key；零拷贝属于后续单独的迁移设计。[覆盖清理][put-cleanup]、[删除清理][delete]、[cron][cron]

旧音乐哈希是 SHA-256，上游单次 PUT ETag 是带引号的明文 MD5，不能把 SHA-256 随手塞成“与正常 PUT 相同的 ETag”。导入前应从真实字节算出对应摘要；保留 `x-amz-meta-sha256` 作为音乐的校验信息。换 Bot 时不能直接复用原 Bot 的 file_id，需另取新 Bot 可用的回执或重新传字节。[PUT ETag][put]、[音乐哈希][music-worker]、[Telegram file_id 约束][sending-files]

### 6.4 `/send` 是一个真实兼容点

现有 `/api/tracks/:id/send` 将旧 `tg_file_id` 传给 `sendAudio`。上游 PUT 使用 `sendDocument`，成功响应又不直接提供 Telegram file_id；把 bucket/key 或 document file_id 塞回这条旧逻辑会失败。Telegram 官方也不允许通过重发 file_id 改变文件类型。最小接入应保留旧 audio 的发送定位，新对象另行定义“获取字节后发音频”等行为；不能声称不用适配就保留完整发送能力。本次未发送任何消息。[音乐 send 路由][music-worker]、[上游文档上传][telegram-upload]、[PUT 返回][put]、[官方重发约束][sending-files]

## 7. 上传幂等、回执不明和大文件的真实约束

### 7.1 已发生的问题与源码推断分开说

**已有公开报告：** #2 是新库 migration 冲突及上传 500；维护者修复 migration，并指出“能建文件夹”不代表 Bot 能发真实文件。#4 是配置了 API_ID/HASH 仍传不了 20MB 以上；维护者补充必须让 Worker 通过 VPS_URL 访问 processor。它们已在当前固定提交中有相应修复/说明，但不是端到端音乐接入验收。[#2 回复][issue2-comment]、[#4 回复][issue4-comment]、[修复提交][commit]

**以下来自真实控制流程，未冒充已经线上复现的故障：**

- PutObject 先检查 key，之后发 Telegram，最后写 D1；不存在与 Telegram 一起提交的事务、持久化发送 intent 或“发送中”任务。若消息已发送，但回执丢失或 D1 写失败，HEAD 仍可能 404。**404 无法证明没发过。**[PUT 顺序][put]、[D1 upsert][metadata]
- `If-None-Match: *` 对已落 D1 的顺序重试返回 412，但它是读取后判断，再异步发消息，再 upsert，最终写入没有原子 `INSERT IF ABSENT` 条件。因此它不提供并发恰好一次；网关已有哈希任务领取仍有实际作用，不需要为此另起一套庞大并发系统。[条件检查][put-conditions]、[最终 upsert][metadata]、[音乐任务领取][music-worker]
- 普通同 key PUT 会发送新消息，保存新定位后在 `waitUntil` 里调用旧消息删除。S3 层“同 key 仍有相同内容”不等于 Telegram 消息没有重复、没有删除。[PUT 写入][put]、[旧消息清理][put-cleanup]
- TelegramClient 最多尝试三次；短 429 等待后重试，超过 10 秒的 FloodWait 直接抛出；它只对特定 `AbortError` 分支重试，并非对所有网络错误都重试。发送调用被取消时，远端是否已接受无法单靠本地异常确认。[TelegramClient][telegram-client]
- VPS 的 buffered `proxyPut` 可对网络/AbortError 重试；`proxyPutFull` 明确因为正文 stream 只能消费一次而不重试。不要把“VPS 有 retry 函数”泛化成全部上传都安全重试。[VPS client][vps-client]
- 大文件 put-full 分支在小文件 SHA-256 校验之前返回；传给处理器的是可选 Content-MD5，没有把 `x-amz-content-sha256` 传过去做字节摘要比较。因此不能把大文件“SigV4 验签成功”写成“服务端已经核对文件 SHA-256”。[PUT 大文件分支][put]、[VPS 参数][vps-client]、[处理器摘要校验][processor]

网关应沿用当前任务语义：已领取后只发送一次；成功回执丢失先 HEAD，再必要时 GET 校验哈希；确认对象存在且字节一致才能登记 ready。若对象不在 D1 但可能已发到 Telegram，继续 `uncertain`，由受控核对处理，不能自动重新 PUT。若上游内部已经因 AbortError 重发，网关本身也无法保证 Telegram 仅有一个消息；这个固定版本无法给出完整恰好一次保证。[音乐上传与 reconcile][music-worker]、[PUT 顺序][put]、[TelegramClient][telegram-client]

另外，音乐旧 reconcile 入口收的是 Telegram 音频回执；不能把上游 ETag 当作该回执，更不能把所有 tg-s3 HTTP 500 都标为“明确未发送”。上游普通 S3 错误会被统一成 XML InternalError，简单上传还处于该普通 S3 try/catch 之外，网关应兼容错误 body 不一定是音乐 JSON。[音乐 reconcile][music-worker]、[上游路由与错误处理][index]

### 7.2 Local Bot API + VPS 的必要条件

| 条件 | 实际要求与结论 |
| --- | --- |
| Telegram API 身份 | VPS 运行 Local Bot API，需自己的 `TELEGRAM_API_ID` 与 `TELEGRAM_API_HASH` 并启用 `--local`；不是仅填 Bot token。上游 compose 用 `TELEGRAM_LOCAL=1` 启动对应镜像 |
| Worker 到处理器 | `VPS_URL` 必须是真正可访问的处理器地址，配套 `VPS_SECRET` 与处理器 `AUTH_SECRET` 相同；Tunnel 是可达方法，不能代替 VPS_URL |
| 处理器到 Telegram | `TG_LOCAL_API` 必须指向 Local Bot API；默认云端地址仍受 getFile 大小约束 |
| 请求路由 | PUT 估算大小超过 `20*1024*1024`、存在 VPS_URL、不是 AWS STREAMING 编码、且有正文，才直接流向 put-full；没有长度不能据此保证进入流式路径 |
| 文件上限 | 上游常量写 `2*1024*1024*1024`，官方写上传最大 2000 MB；二者不能不加说明地视为同一已验证字节边界 |
| 入口与分片 | Worker 前面的域名计划仍限制请求体；Free/Pro 100MB、Business 200MB。2GB 单请求不能靠流式代码绕过；大对象需符合入口上限的 multipart 等已实现路径，且还要核对合并与临时文件空间 |
| 内存与磁盘 | 小文件路径整块缓冲；AWS STREAMING 编码有 100MiB 内存限制。VPS put-full 先写临时文件、可选加密再上传，需要足够磁盘和传输时间 |

依据：[官方 Local API 说明][local-api]、[官方服务器说明][local-server]、[compose][compose]、[VPS client][vps-client]、[PUT 大文件分支][put]、[constants][constants]、[处理器 put-full][processor]、[Cloudflare 请求/内存限制][cf-limits]。当前 Cloudflare 官方 HTTP 请求时长并非代码注释所称的固定“30 秒”；上游仍主动设置了 25 秒短超时与 10 分钟长超时，所以必须按实际代码和所在平台共同判断。[常量][constants]、[官方 limits][cf-limits]

现有音乐 App 的上传、音乐 Worker 校验及 available 判定都限制为 `20_000_000` 字节，比上游的 20MiB 更小。只增加 VPS_URL 不会改变这些客户端与接口限制；最小对象接入没有必要一起扩展大文件。[客户端][music-client]、[音乐 Worker][music-worker]

### 7.3 固定提交的大文件明显阻碍

1. **处理器鉴权会碰到 ESM/require 冲突。** `processor/package.json` 是 `type: module`，Docker 用 `node server.js`；鉴权中却调用未定义的 `require('crypto').timingSafeEqual`。正常有效 Authorization 长度相同时会执行该表达式，按 Node ESM 规则抛 `ReferenceError`；这不是“还缺 API_ID”能解决的配置问题。结论来自静态源码和官方模块规则，本次没有启动容器复现。[处理器第 32–46 行][processor-auth]、[包配置][processor-package]、[镜像入口][processor-docker]、[Node ESM 规则][node-esm]
2. **cron 没按大小切到 Local API。** 它用硬编码云端 TelegramClient 对抽样对象 getFile，任何 HTTP 400 都删 D1 行并尝试完整清理。有效大文件触及云 API getFile 大小限制也可能得到 400，不能因此判为文件丢失。这直接违反“保留旧文件”的接入要求；若把旧消息零拷贝导入，更可能影响原副本。上线前应先停用相关破坏性定时清理，再单独修正判断，不能把它作为普通无害缓存清理。[cron][cron]、[云端客户端][telegram-client]、[官方 getFile][telegram-getfile]、[删除清理][delete]
3. **Local API 的文件路径与 Range 仍需核实。** 官方 Local 模式 getFile 可返回绝对路径；处理器所有下载路径仍拼 `/file/bot<TOKEN>/<file_path>`，没有区分本地绝对路径。compose 又没有把 Bot API 数据卷共享给 processor。不能因此直接保证“Local 模式所有下载已通”。Range 路径则把上游响应透传，Worker 只检查 `res.ok` 就可能按请求范围重写为 206；如果实际下载服务忽略 Range 回 200，状态和正文长度会不一致。这里是具体待验证条件，不宣称已经实测失败。[官方本地路径要求][local-server]、[处理器 get/range/getFilePath][processor]、[compose][compose]、[VPS range client][vps-client]、[Worker 大文件 Range][get]
4. **云端与 Local API 不能当成无迁移成本的双实例。** 官方要求从云端迁往本地前 `logOut`，否则更新投递无保证；上游的小文件调用及 cron 却仍硬编码云端 API。保留既有音乐 Webhook、复用同 Bot、再增加 Local API，必须专门设计 API 实例与更新交接；不能沿用第 6.1 节的小文件结论，宣称大文件也可以无感接入。[官方服务器迁移][local-server]、[云端客户端][telegram-client]、[compose][compose]

上述都是现有代码路径带来的约束，不是建议预先增加大量低概率防御。最小接入绕开 VPS，并不要求现在修完全部大文件功能。[PUT 分流][put]、[现有客户端限额][music-client]

## 8. 远端构建上游 bundle，本地 `--no-bundle` 部署能否做

**可以设计成这个流程，尚未执行验证。** tg-s3 入口是 TypeScript 且有跨文件与动态 import，不能把原始 `src/index.ts` 用音乐现有的 `--no-bundle` 命令直接上传。应先在远端把固定提交打成可部署的 JavaScript，再由本地只上传产物。Cloudflare 官方明确支持预处理产物配合 `--no-bundle`。[上游入口][wrangler]、[包配置][package]、[Cloudflare bundling][cf-bundling]

建议在未来获得实施授权后，沿用音乐仓库现有 GitHub Actions 流程增加对应步骤，而不是另外引入本地构建工具：

1. CI 拉取固定 SHA，使用上游 `package-lock.json` 固定依赖，通过 `npm ci` 安装。远端运行 Wrangler 的 `deploy --dry-run --outdir <产物目录>` 生成 bundle；这是编译动作，**只能在远端**。此阶段不需要向生产部署，也不应执行 deploy.sh。[包与锁文件][package]、[锁文件][lock]、[Wrangler dry-run][cf-deploy]
2. 产物包含打好的 JS、实际需要的额外模块、上游 SHA、依赖锁文件摘要、构建工具版本、完整性摘要和适用的部署配置。若动态 import 被打成额外文件，应保留对应模块规则；不要假设永远只需复制一个入口文件。[上游动态 import][put]、[Wrangler 模块配置][cf-config]
3. 本地下载并核对产物及摘要，配置 `main` 指向产物而非 TS；保留正确 D1 binding、region、兼容日期，明确选用无 R2 和无破坏性 cron 的配置。配置不得另挂本地 custom build 命令，也不手工修改生成的 bundle。[上游 bindings][wrangler]、[Cloudflare bundling][cf-bundling]、[模块与 build 配置][cf-config]
4. 将来本地部署只使用 `wrangler deploy --no-bundle --config <已审阅配置>` 上传已构建产物；D1 初始化和 secret 配置是独立操作，**该参数不会顺便帮忙初始化数据库、生成 credential、保留 Webhook 或修复源码问题**。不要再用会直接执行普通 `wrangler deploy` 和 setWebhook 的上游 deploy.sh。[官方 deploy][cf-deploy]、[上游脚本][deploy-init]、[Webhook 注册][deploy-webhook]

固定上游文件树没有 `.github/workflows`，所以没有现成上游 bundle workflow 可直接声称“已经通过”。音乐现有 `build-player.yml` 有 music-api 和 iOS 远端检查，但没有 tg-s3 bundle 步骤，Markdown/doc 改动又被 paths-ignore 跳过。因此本研究未触发 CI，也没有产生远端构建通过的结论。[上游文件树][tree-api]、[音乐远端 CI][music-ci]

## 9. 最小接入建议与后续验收范围

建议第一步只做这些：

- 独立部署固定版本 tg-s3 Worker 与专用 D1；不用 R2、不用 VPS，关闭包含删除动作的 cron；保留现有 Bot 和音乐 Webhook。受控初始化一个私有 music 桶和限桶 readwrite credential。以上是部署配置建议，本报告未执行。[配置][wrangler]、[鉴权授权][authorize]、[cron][cron]
- 音乐 Worker 保留全部现有 API，增加真实 tg-s3 对象定位与调用。新字节走真实 PutObject，GET/HEAD 由对象服务提供；音乐 D1 继续负责歌曲、哈希去重、任务和播放数据。手机继续本机 yt-dlp 和原接口，不把 tg-s3 误当 YouTube 提取服务。[音乐客户端][music-client]、[音乐 Worker][music-worker]、[上游对象 handlers][put]
- 统一用 SigV4，key 按内容哈希固定；顺序重试使用条件写入，发送结果不明继续 uncertain。旧对象保持读取，旧消息、旧表记录不删；迁移一个确认一个。[签名][sigv4]、[条件写入][put-conditions]、[音乐恢复语义][music-worker]
- 单独处理 `/send` 的 audio/document 差异和 S3 错误到音乐 JSON 的转换；别把“对象上传成功”当作所有音乐功能已经兼容。[文件类型约束][sending-files]、[音乐接口][music-worker]、[上游路由][index]
- 将来在既有远端 CI 核对：原设备鉴权和音乐 JSON、真实 S3 签名 PUT/HEAD/GET、完整字节与 SHA-256、重复上传、上游 412、回执不明、旧文件回退、Range/HEAD/416、收藏/播放以及新旧 `/send` 行为。CI 边界测试通过后，另行获准做实际云端服务验证；不能把源码阅读写成已部署成功。[现有 CI][music-ci]、[音乐与对象源码][music-worker]、[PUT][put]、[GET][get]

当前最明显的阻碍是：没有现成音乐后端定位与协议适配；上游部署脚本有 Webhook 副作用；未知回执不能安全自动重传；默认 cron 有删文件行为；VPS 固定代码存在上述实际缺口；README MIT 没有独立 LICENSE；官方用途条款与外部云存储目标存在明确冲突。前四项决定最小技术接入怎样做，VPS 不必混进第一步；许可和用途结论不能被“能上传”覆盖。[脚本][deploy-webhook]、[PUT 顺序][put]、[cron][cron]、[处理器][processor-auth]、[README][readme]、[文件树][tree-api]、[官方条款][terms-operation]

本报告只修改本文件。没有改 `tasklist.md` 或其他代码，没有部署、改密钥、发消息、开子代理或运行本地构建。核对方法为源码阅读、GitHub 主来源查询、官方文档和文档差异检查；所有运行效果仍以未来获准的远端验证为准。

## 来源索引

上游源码链接全部固定到本次指定提交；Issue、仓库计数与官方文档是研究日读取的动态来源，不能伪装成固定提交内容。

[commit]: https://github.com/gps949/tg-s3/commit/82bff102498658fd462ad478229fc49cb2f44c47
[readme]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/README.md
[readme-zh]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/README.zh.md
[index]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/index.ts
[simple-route]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/index.ts#L72-L98
[simple-auth]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/index.ts#L391-L407
[auth]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/index.ts#L409-L437
[authorize]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/index.ts#L443-L463
[credential-api]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/index.ts#L981-L1014
[bearer]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/auth/bearer.ts
[sigv4]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/auth/sigv4.ts
[presigned]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/auth/presigned.ts
[put]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/handlers/put-object.ts
[put-conditions]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/handlers/put-object.ts#L82-L145
[put-cleanup]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/handlers/put-object.ts#L484-L498
[get]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/handlers/get-object.ts
[head]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/handlers/head-object.ts
[bucket]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/handlers/bucket.ts
[delete]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/handlers/delete-object.ts
[schema]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/storage/schema.sql
[metadata]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/storage/metadata.ts
[metadata-credentials]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/storage/metadata.ts#L705-L737
[types]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/types.ts
[wrangler]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/wrangler.toml
[package]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/package.json
[lock]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/package-lock.json
[path]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/utils/path.ts
[headers]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/utils/headers.ts
[constants]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/constants.ts
[telegram-client]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/telegram/client.ts
[telegram-upload]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/telegram/upload.ts
[vps-client]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/media/vps-client.ts
[bot-webhook]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/bot/webhook.ts
[cron]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/src/index.ts#L231-L333
[deploy-init]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/deploy.sh#L318-L431
[deploy-webhook]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/deploy.sh#L450-L468
[deploy-summary]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/deploy.sh#L845-L860
[deployment-doc]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/docs/deployment.md
[compose]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/docker-compose.yml
[processor]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/processor/server.js
[processor-auth]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/processor/server.js#L32-L46
[processor-package]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/processor/package.json
[processor-docker]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/processor/Dockerfile
[migration1]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/migrations/0001_init.sql
[migration2]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/migrations/0002_add_is_public.sql
[migration3]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/migrations/0003_add_optimize_config.sql
[migration4]: https://github.com/gps949/tg-s3/blob/82bff102498658fd462ad478229fc49cb2f44c47/migrations/0004_add_default_encryption.sql
[migration-fix]: https://github.com/gps949/tg-s3/commit/a4e660a5e3e654febcdb21caca49e6595aec81bc
[repo-search]: https://github.com/search?q=tg-s3&type=repositories
[repo-api]: https://api.github.com/repos/gps949/tg-s3
[tree-api]: https://api.github.com/repos/gps949/tg-s3/git/trees/82bff102498658fd462ad478229fc49cb2f44c47?recursive=1
[issues-api]: https://api.github.com/repos/gps949/tg-s3/issues?state=all&per_page=100
[issue2]: https://github.com/gps949/tg-s3/issues/2
[issue2-comment]: https://github.com/gps949/tg-s3/issues/2#issuecomment-4585752057
[issue4]: https://github.com/gps949/tg-s3/issues/4
[issue4-comment]: https://github.com/gps949/tg-s3/issues/4#issuecomment-4933960227
[issue6-comment]: https://github.com/gps949/tg-s3/issues/6#issuecomment-6527574926
[issue7]: https://github.com/gps949/tg-s3/issues/7
[pr1]: https://github.com/gps949/tg-s3/pull/1
[music-worker]: https://github.com/C0verSnow/c0versnowmusic/blob/75d213e2795d055c33655140c50b51285eced08e/worker/index.js
[music-client]: https://github.com/C0verSnow/c0versnowmusic/blob/75d213e2795d055c33655140c50b51285eced08e/MusicApp/Online/CloudMusicStore.swift
[music-config]: https://github.com/C0verSnow/c0versnowmusic/blob/75d213e2795d055c33655140c50b51285eced08e/scripts/configure_music_backend.py
[music-schema]: https://github.com/C0verSnow/c0versnowmusic/tree/75d213e2795d055c33655140c50b51285eced08e/worker/migrations
[music-ci]: https://github.com/C0verSnow/c0versnowmusic/blob/75d213e2795d055c33655140c50b51285eced08e/.github/workflows/build-player.yml
[sending-files]: https://core.telegram.org/bots/api#sending-files
[send-document]: https://core.telegram.org/bots/api#senddocument
[telegram-getfile]: https://core.telegram.org/bots/api#getfile
[telegram-updates]: https://core.telegram.org/bots/api#getting-updates
[local-api]: https://core.telegram.org/bots/api#using-a-local-bot-api-server
[local-server]: https://github.com/tdlib/telegram-bot-api#moving-a-bot-to-a-local-server
[terms-operation]: https://telegram.org/tos/bot-developers#5-2-operation
[terms-data]: https://telegram.org/tos/bot-developers#6-3-account-management
[cf-cache]: https://developers.cloudflare.com/workers/runtime-apis/cache/
[cf-limits]: https://developers.cloudflare.com/workers/platform/limits/
[cf-bundling]: https://developers.cloudflare.com/workers/wrangler/bundling/#disable-bundling
[cf-deploy]: https://developers.cloudflare.com/workers/wrangler/commands/workers/#deploy
[cf-config]: https://developers.cloudflare.com/workers/wrangler/configuration/#bundling
[node-esm]: https://nodejs.org/download/release/v22.15.0/docs/api/esm.html#no-require-exports-or-moduleexports
