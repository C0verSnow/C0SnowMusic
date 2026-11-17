# 首播延迟：build 18 证据与实现取舍

Research snapshot: **2026-11-17 UTC**, Unix Timestamp **1794938756**. This is background research, not an implementation or an acceptance report. It reads the parent `AGENTS.md`, current tasklist, Python downloader, Swift downloader, repository/cache, Worker and playback interfaces. It uses official documentation, pinned upstream source and read-only GitHub searches. Only this document is written; no code/tasklist edits, commits, builds, tests, device work, deployment or credential disclosure are part of this research.

The comparison baseline is committed build18, `9b189dfbffaea96aeb46110a1947d649e420bf8f`. Other work began changing downloader/client files during this investigation; those uncommitted changes are not evidence of completed optimization. The [latest tasklist](../tasklist.md) remains the source for measured device results. Read-only GitHub verification found [PR16](https://github.com/C0verSnow/c0versnowmusic/pull/16) open, draft, unmerged, with that same head. **Continue the remaining implementation and remote-CI work, defer real-device testing, and keep PR16 draft/unmerged until device acceptance.** This report does not change PR state.

## 本轮采用的方案（build 19）

本报告的一手资料支持三处改动：复用相同 Cookie 快照的 yt-dlp 与播放器 JS；YouTube Music 首页上下文在内存复用 5 分钟；YouTube 前台仓库索引改为 5 秒无数据等待超时，完整传输保留原配置。实际实现和验收以 [验收记录](VERIFICATION.md) 为准，下面的候选方案不代表全部已经实现。

已保留上游默认网页、客户端和 player 请求。没有启用 player_skip，也没有缓存签名媒体 URL。会话失败后关闭，下次操作重新创建；没有增加无条件的自动下载重试。鉴于上游连续使用的报告，本轮补同一 WebKit provider 连续执行、跨两次 Swift 调用复用的真实 iOS 回归；Ubuntu 回归另核对真实 yt-dlp 两次下载只取一次同版本 JS、文件与日志目录切换、账户隔离和取消恢复。

渐进播放完成接口评估，尚未实现。当前播放器、缓存和元数据入口都接收完整本地文件；有鉴权的远程加载需要新增数据源、Range/seek、完整缓存晋升及失败回退，无法只把本地路径换成 URL。新提取的 DASH M4A 还有已复现的双倍时长约束。先落实本轮可独立验证的重复请求优化；新的渐进播放流程另列后续，不把已支持的 Worker Range 当作 App 已边播边下。真机复测按用户指令搁置，因此没有 build 19 实测速度，也不承诺普遍 1–2 秒出声。

## 1. Recommendation

First reduce repeat extraction work within the existing pinned runtime. Then add progressive playback for **already stored, playable warehouse objects**. Keep the complete-download-plus-normalization path for new YouTube DASH M4A until a separate device check proves that another path preserves duration, seeking and sound.

The practical order is:

1. Count and time the actual webpage, client-config, player-JS and player-API requests separately. Two player calls can represent different clients, not accidental duplicates.
2. Evaluate reuse of the player-JS memory cache across downloads, with explicit WebKit lifecycle checks. Merely enabling `cachedir` does not remove the pinned extractor's raw player-JS request.
3. Trial supported `player_skip` settings conservatively, with one fallback to unchanged defaults. Do not globally skip JS, hard-code one client, or weaken format requirements.
4. Bound the YouTube-track warehouse lookup separately from full media downloads. Preserve the Telegram-only path, which has no extraction fallback.
5. Introduce an owned `AVAssetResourceLoader`/`URLSession` source for warehouse playback and caching. The current player interface is file-only; a remote URL alone cannot implement this.

These are proposals, not measured speedups. **There is no support for promising universal 1–2-second startup.** Source extraction, authentication, network conditions and container layout remain variable. The pinned source details below explain which work each proposal can actually remove. [Extractor][yt-video], [cache][yt-cache], [EJS provider][yt-ejs], [Apple resource loader][apple-loader].

## 2. What the measurements establish

The tasklist's build18 entries at timestamp `1794929268` record:

| Path | Recorded preparation | Interpretation |
| --- | --- | --- |
| Existing local cache | About 0.2 s | Preserve the existing local-first path. |
| Existing cloud synthetic MP3, absent locally | 2.7 s; 24,641 bytes; TG-S3 HIT | Confirms cloud retrieval, not representative of a multi-megabyte song. |
| New third song | 19.4 s total; 18.1 s Python | Extraction/download dominates this sample. |
| New fourth song, 《龙卷风》 | 65.6 s total; 8.4 s warehouse; 57.1 s Python | Slow warehouse lookup and extraction both matter. |
| Fourth-song Python stages | Webpage ~12 s; player JS ~22 s; two player calls ~7 s; WebKit ~1 s; ~4 MB audio ~10 s | The largest recorded wait is fetching JS, not executing the challenge. |

Third/fourth background uploads took 24.3/70.3 s and did not block playback. Do not put upload back on the first-play path. These are individual runs and approximate stage durations, not percentiles, a controlled benchmark or a fully additive timing trace. [Tasklist](../tasklist.md).

**Inference:** eliminating a repeated fetch of the same JS version could materially improve a later uncached song in the same session. It cannot remove the first cold fetch, new player versions, webpage/player requests or audio transfer. Warehouse streaming could avoid waiting for an entire stored song, but it cannot explain away or remove the 57.1 s spent in the new-song Python path.

## 3. Exact bundled versions and current interfaces

Do not substitute current `master` behavior for the shipped versions. The app pins pure Python wheels and hashes in [online-requirements.txt](../scripts/online-requirements.txt); [prepare_online_runtime.py](../scripts/prepare_online_runtime.py) obtains the precompiled Python runtime and disables compilation during wheel installation. This research did not run either installer.

| Component | Bundled pin | Source used for behavior |
| --- | --- | --- |
| Python-Apple-support | `3.13-b18`; archive SHA-256 `d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d` | [Official release](https://github.com/beeware/Python-Apple-support/releases/tag/3.13-b18); repository packaging script |
| yt-dlp | `2026.10.26`; wheel SHA-256 `a05c5b5d8562f7e8a62f5334348b406af4930d56d3a65f8021d14af0e22339ae` | Tag resolves to [`f264a6cbd1f630894da0f368df00f8aae50140e0`](https://github.com/yt-dlp/yt-dlp/commit/f264a6cbd1f630894da0f368df00f8aae50140e0) |
| yt-dlp-ejs | `0.8.0`; wheel SHA-256 `79300e5fca7f937a1eeede11f0456862c1b41107ce1d726871e0207424f4bdb4` | [Official 0.8.0 release](https://github.com/yt-dlp/ejs/releases/tag/0.8.0); host integration is the pinned yt-dlp `EJSBaseJCP` |
| Apple WebKit plugin | `0.1.1`; wheel SHA-256 `1892b14e7ee7161deaae11040b38b2e2b229178e1b96102ca2c1d5a0ed136688` | `v0.1.1` resolves to [`e466daca67cc0e1ca63b68cb8fbe80af16ce00a4`](https://github.com/grqz/yt-dlp-apple-webkit-jsi/commit/e466daca67cc0e1ca63b68cb8fbe80af16ce00a4) |
| certifi | `2026.10.23`; wheel SHA-256 `e9b54de76e530bb6cf0ccd036787103acb58fd42ba930ea8bf948ddbaa2f61d1` | Local lock and [third-party inventory](THIRD_PARTY.md) |

Build18's [Python entry point][app-python] creates a new `YoutubeDL` context for every download, sets `cachedir=False`, imports current cookie records, and calls `extract_info(..., download=True)`. It requires audio-only M4A and returns duration after the complete file exists. Python/plugin setup is already process-wide and guarded against re-registration. The URL passed is mobile YouTube, but the pinned extractor reconstructs its watch URL and chooses player clients itself; changing `m.youtube.com` to `www.youtube.com` is not evidence of one fewer extraction request. [Extractor][yt-video].

The [Swift downloader][app-downloader] serializes Python calls, then awaits passthrough normalization. [AudioRepository][app-repository] checks local cache, waits for warehouse retrieval, falls back to extraction for YouTube sources, and inserts a complete validated file. [CloudMusicStore][app-cloud] currently awaits `URLSession.data(for:)` for the full body before writing it. [OnlineMusicStore][app-online] starts playback after resolution and starts uploads/statistics afterward. [AVPlayerEngine][app-player] explicitly requires `fileExists`; [PlayerEngine][app-engine] accepts only a URL. [OnlineAudioCache][app-cache] validates complete assets and moves them into its indexed cache. These contracts must change deliberately before progressive playback is possible.

## 4. Repeated YouTube requests and cache behavior

### Disk cache is not the raw-JS cache

The pinned `YoutubeIE` initializes `_code_cache` and `_player_cache` on the extractor instance. `_load_player` keys raw JS by player identity/variant and fetches only when that key is absent. It does **not** read raw JS from `ydl.cache`. Signature-timestamp caching also defaults to memory; comments explicitly defer disk use. Creating a fresh `YoutubeDL` therefore loses this extractor memory. [Pinned extractor][yt-video].

`Cache.enabled` is false only for `cachedir=False`; otherwise it stores versioned JSON under the chosen directory and treats ordinary read failures as misses. This is an extractor data cache, not an HTTP response cache or a saved-media cache. A writable app Caches subdirectory is preferable to relying on desktop `~/.cache`, but switching it on is not itself the recorded 22-second fix. [Pinned cache implementation][yt-cache].

The pinned EJS integration loads the bundled Python EJS package before considering disk/web sources. Its `_ENABLE_PREPROCESSED_PLAYER_CACHE` is **False**; its comment cites large files and absent rotation. The WebKit subclass does not override that flag. Thus enabling disk cache neither activates processed-player caching nor avoids bundled EJS loading. Do not flip this private flag as an optimization. [Pinned EJS integration][yt-ejs], [WebKit provider][webkit-provider].

### Reuse helps, but preserve lifecycle and request ownership

`YoutubeDL.get_info_extractor` reuses instances inside one downloader. Its context exit closes the request director and calls close hooks. The plugin attaches a lazy WebView/factory to the extractor; its `close` tears both down. Keeping a single live downloader can retain raw JS and WebKit state across songs, whereas repeatedly entering/exiting the same closed object does not provide that lifecycle. [Pinned YoutubeDL][yt-ydl], [plugin mixin][webkit-mixin].

**Recommendation/inference:** trial one serial, session-owned downloader first only if its request-specific directory, progress callback, logger, cancellation marker and cookies are rebound without retaining the previous request. Reset on login/logout/account replacement, rather than retaining accumulated cookies. Close on disposal or failed-provider reset. Keep existing navigation/popup suppression and single plugin registration.

This needs meaningful repeated-download checks: upstream [plugin #4][webkit-issue4] reports second/subsequent URL failures, and [#7][webkit-issue7] reports the same message-handler symptom on a newer beta/runtime. Neither report proves failure in this app/version combination. If safe live reuse fails, prefer a small **bounded app-owned raw-JS cache across fresh downloader instances**, keyed by the pinned extractor's player identity/variant, over retaining the failed WebView. That would be a private-API adapter, requiring version-specific checks; it is not an upstream disk-cache feature. Choose one approach, not two overlapping caches.

No persistent cache of signed media URLs, account responses or cookies is required for this improvement. Retain native TLS verification, EJS script verification and per-request authentication. Preserve readable errors instead of silently accepting a missing/throttled format. [Cache][yt-cache], [EJS verification][yt-ejs], [app format selection][app-python].

### Request-skipping options: bounded trials, not blanket defaults

Python API spelling is `extractor_args={"youtube": {"player_skip": ["configs"]}}`; values are lists. Keep the existing format selector. The following are independent candidates, not instructions to enable all options together. [Pinned option documentation][yt-readme].

| Option | What it avoids | Constraint and recommendation |
| --- | --- | --- |
| `player_skip=configs` | Additional client-configuration fetches | Retains initial watch page. Trial first; client/session defaults can be incomplete. On compatible-format/extraction failure, retry defaults once. |
| `player_skip=initial_data` | `/next` fallback when usable initial data was not embedded | It does not stop parsing embedded initial data. Missing initial data affects Premium detection and metadata. Trial for anonymous ordinary songs first, not globally for logged-in accounts. |
| `player_skip=webpage` | Initial watch page | Can lose embedded player response, session/account context, Premium detection and player URL. May introduce iframe/config/next requests. Leave out of the first change. |
| `player_skip=js` | JS-player work | Can remove formats or their required n/signature solving. Do not use as a general speed switch for AAC playback. |
| `webpage_skip=...` | Parsing of embedded data only | Does not eliminate HTTP requests. Not a latency fix. |
| One explicit `player_client` | Requests to other clients | Account support, PO requirements and available formats differ. Do not globally pin a single client from an old recipe. |

These limits follow both the pinned `_download_initial_data`/`_get_requested_clients` control flow and the option warnings. Defaults vary for anonymous, free-cookie and Premium sessions, so two player calls are not inherently duplicate work. [Pinned extractor][yt-video].

The official wiki specifically warns that visitor-data-only extraction with skipped webpages can require **more requests** and be less stable. Do not fabricate/reuse visitor data independently of cookies. [Official extractors guide][yt-guide]. Upstream added the initial-data skip following [#12826][yt-12826]; it is an intentional tradeoff, not an undocumented shortcut. Current [SABR issue #17666][yt-sabr] and a [member response][yt-sabr-response] show why `mweb`/embedded recipes can lose suitable formats. Keep one unchanged-default fallback; cancellation, rate-limit responses and network failures must not trigger an unbounded retry loop.

## 5. Maintained, licensed alternatives checked on GitHub

Actual GitHub repository searches included `yt-dlp-apple-webkit`, `CachingPlayerItem`, and `AVAssetResourceLoader cache`; metadata, fixed source, recent commits and issue comments were then read. Stars are a dated snapshot, not a quality or availability guarantee. `pushed_at` is not automatically a source-code commit; dates below distinguish them.

| Project | Scale, license and activity at lookup | Design/dependencies | Issues and decision |
| --- | --- | --- | --- |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | 208,640 stars; Unlicense; repository pushed 2026-11-17. Already bundled at the fixed version above. [API](https://api.github.com/repos/yt-dlp/yt-dlp) | Existing Python runtime, EJS and platform JS provider. Handles client selection, formats and download retries. | Member responded with a client-format fix in [#17666][yt-sabr-response]. Retain; current activity does not mean latest behavior exists in the shipped pin. |
| [grqz Apple WebKit plugin](https://github.com/grqz/yt-dlp-apple-webkit-jsi) | 167 stars; Apache-2.0; latest inspected default-branch commit 2026-04-23, pushed 2026-04-25; latest release still 0.1.1. [API](https://api.github.com/repos/grqz/yt-dlp-apple-webkit-jsi), [commits](https://github.com/grqz/yt-dlp-apple-webkit-jsi/commits/master/) | Python ctypes/Objective-C bridge to system WebKit; imports a private yt-dlp EJS base. No desktop Node/Deno executable needed. | [#5][webkit-issue5] has reporter reproductions of unwanted YouTube navigation; its four inspected replies were from the reporter, not a maintainer. #4/#7 have no inspected maintainer resolution. Retain the app's existing suppression; do not call this actively maintained at yt-dlp's level. |
| [sukov/CachingPlayerItem](https://github.com/sukov/CachingPlayerItem) | 126 stars; MIT; latest inspected commit 2026-09-24, `635dc8a3fead1f34474c984328cb69a12fd6dbd7`; release 2.3.0. [API](https://api.github.com/repos/sukov/CachingPlayerItem), [release](https://github.com/sukov/CachingPlayerItem/releases/tag/2.3.0), [license][suk-license] | Swift `AVPlayerItem` subclass, resource loader, disk buffering and uncached seek requests. Swift tools 5.6; iOS 13.4+; package declares **no dependencies**. [Package][suk-package] | Owner confirmed disk-full crash fixed in [#38][suk-38]; owner confirmed macOS support on 2026-11-05 in [#37][suk-37]. Best recent implementation reference. API/header caveat below prevents calling it a drop-in solution. |
| [ChangbaDevs/KTVHTTPCache](https://github.com/ChangbaDevs/KTVHTTPCache) | 2,516 stars; MIT; latest inspected code commit 2025-09-04, `388da9af7891ea081e2631e09483ff5cbb09639b`. [API](https://api.github.com/repos/ChangbaDevs/KTVHTTPCache), [license][ktv-license] | Objective-C local HTTP proxy, range/disk cache, HLS/preload/AirPlay scope; pod 3.1.0 adds CocoaAsyncSocket. [Podspec][ktv-pod], [README][ktv-readme] | Member explained Range/content-type failures in [#25][ktv-25]. Recent [#199][ktv-199] reports HTTP 400 caching; zero comments at lookup, with proposed PR #200. More dependencies and broader server scope than needed; historical reference, not preferred addition. |
| [neekeetab/CachingPlayerItem](https://github.com/neekeetab/CachingPlayerItem) | 551 stars; MIT; pushed 2024-07-30. [API](https://api.github.com/repos/neekeetab/CachingPlayerItem) | Original resource-loader lineage referenced by sukov's README. | Older activity than the maintained fork; exclude from a new dependency shortlist. No fresh issue-response claim was established. |

No inspected candidate combines very high stars, frequent recent code changes and a verified plug-in fit for this app. The relatively small sukov fork has the strongest recent maintenance evidence among the inspected direct resource-loader caches. That supports borrowing its design, not claiming it satisfies every high-star screening preference.

**Critical integration detail:** sukov's fixed initializer reads headers from the string `AVURLAssetHTTPHeaderFieldsKey`, then passes them to its own `URLSession` requests, including range requests. It also forwards that options dictionary to `AVURLAsset`. Apple staff explicitly say that key is **not a supported API**. Thus “library accepts auth headers” is true, but “its documented header recipe is entirely supported AVFoundation API” is false. Prefer an explicit `URLRequest`/header input on an app-owned loader, or review a narrowly scoped adaptation before choosing the dependency. Do not merely paste its initializer recipe. [Fixed initializer][suk-item], [request implementation][suk-pending], [Apple staff statement][apple-headers].

The fork requires a file extension or explicit `customFileExtension`; the Worker `/content` route has none. HLS caching is outside that fork's supported caching scope. These are real interface mismatches, not hypothetical edge cases. [Fork README][suk-readme]. No source code from these libraries was copied in this research.

## 6. Supported progressive playback through the authenticated Worker

### Why warehouse playback is the bounded first target

Apple supports local/remote URL assets and incremental byte supply through `AVAssetResourceLoaderDelegate`. A custom-scheme URL can route loading through an owned delegate; the delegate uses a normal HTTPS `URLRequest` carrying the existing Bearer header. This is an implementation inference combining Apple's loading API with the inspected cache design, not an Apple-provided turnkey audio-cache class. [Apple URL assets](https://developer.apple.com/documentation/avfoundation/avurlasset), [delegate][apple-loader], [fixed library design][suk-item].

Build18's [Worker][app-worker] authenticates requests and supports GET/HEAD `/api/tracks/{id}/content`. The TG-S3 adapter forwards Range and streams the response body; the legacy path slices the Telegram stream itself. It sets private/no-store on delivery. Its Range parser handles single ordinary/open-ended/suffix ranges and rejects unsupported/unsatisfiable ranges. **The service already has the route required; no new public endpoint or device key in a URL is needed.** [Worker adapter][app-s3].

Inference: legacy delivery may still read/discard a long prefix upstream for a far seek. A correct 206 is necessary but does not establish cheap random access, TG-S3 cache warmth, low first-byte latency, or phone reachability. Prior tasklist Range/HIT checks are useful history, not validation of a new AVPlayer loading flow.

### Minimal contract to implement later

1. Preserve the complete-file local branch. Add a distinct remote playback source that owns its loader, request and staging file. Resolve metadata/available warehouse content before constructing it. Avoid placing a growing `.part` file into `OnlineAudioCache` or pretending it is a permanent local song. This follows the current [repository][app-repository], [cache][app-cache] and [player][app-player] contracts.
2. Attach the resource-loader delegate before loading asset properties or creating its item. Keep a strong owner while the item exists: Apple does not strongly retain the delegate. Use its designated serial queue and avoid blocking that queue with network waits. [Apple delegate ownership][apple-setdelegate].
3. Fill content information with the recognized **UTI**, full object length and actual byte-range capability. A 206 `Content-Length` is only the returned segment length; obtain full length from `Content-Range` or suitable metadata. Check the HTTP response at this network boundary, then use the validated values internally. [Apple content information][apple-info], [RFC 9110 §14][http-range].
4. Supply requested bytes from `currentOffset`, respecting requested length or all-data-to-end. Call `respond(with:)` repeatedly as bytes arrive; finish only once that request is satisfied. Early completion makes AVFoundation treat the shortened content as EOF. Honor request cancellation and return HTTP failures as failures. [Apple data requests][apple-data], [incremental response][apple-respond], [cancellation callbacks][apple-loader].
5. Keep Bearer authorization on the Worker's HTTPS HEAD/GET/range requests through `URLSession`. Preserve exact 206/Content-Range/body offsets; handle 200 as a full representation, not a segment at the requested offset. Do not cache authentication-error bodies. A real seek to unreceived bytes requires a corresponding range request; inspect status/offset once at receipt. [HTTP range semantics][http-range], [fork range design][suk-pending].
6. Write received bytes to staging while playback consumes them. Track which bytes are present if seeking creates holes. Promote only a complete, validated file through the existing cache insertion path; cancel/delete incomplete staging on stop/error according to ownership. Keep cache eviction/clear consistent with the player. This is a proposed application contract, informed by [fork loader][suk-loader] and the app's existing [complete-file cache][app-cache].

Prefer this limited media-loading seam over replacing the player, adding an HTTP proxy, changing storage services, or building a general HLS framework. A direct `AVPlayer(url:)` plus a separate whole-file downloader can download the same bytes twice and still does not solve supported Bearer-header injection or shared disk caching.

Apple's `automaticallyWaitsToMinimizeStalling` defaults to true on modern linked apps. Setting false can attempt playback as soon as buffered media exists, but an empty buffer then pauses rather than providing the same automatic waiting behavior. Measure startup and stalls before choosing it. **The cache README's blanket “Apple strongly recommends false” is not what the official API documentation says.** This setting cannot accelerate the Python work that happens before a player item exists. [Official waiting behavior][apple-waits].

`timeControlStatus`, `reasonForWaitingToPlay`, item readiness and failures should distinguish data acquisition from AVPlayer buffering. App preparation finishing is not proof of audible output; later device acceptance is still required. [Apple waiting reason][apple-waitreason], [current engine][app-player].

## 7. M4A DASH normalization remains a hard constraint

The app has a recorded device bug: DASH M4A reported roughly double duration. Its current fix uses `AVAssetExportPresetPassthrough`, a time range bounded by the extractor's source duration, and standard `.m4a` output. Upstream likewise has `FFmpegFixupM4aPP` for `container == m4a_dash`, using stream-copy remuxing. [Tasklist problem24](../tasklist.md), [current normalizer][app-downloader], [pinned upstream fixup][yt-fixup], [Apple export presets][apple-presets].

**Inference:** playing the raw growing yt-dlp file before that fix can reintroduce incorrect duration/end/seek behavior. Renaming the file, increasing a buffer or returning a resolved Google media URL does not perform the remux. `AVAssetExportSession` is not documented here as a live producer whose unfinished output AVPlayer can safely tail. Do not remove the normalization barrier merely to advertise streaming.

For the next change, finish and normalize newly extracted songs; stream warehouse MP3 or previously normalized M4A. Imported/legacy warehouse M4A is not automatically proven normalized merely by MIME type. Preserve a full-download fallback when the asset is not playable progressively. For future uploads, evaluate `shouldOptimizeForNetworkUse` on the existing export and measure container layout/startup; the property expresses network optimization, not a documented guarantee of a particular startup time or moov placement. Do not rewrite stored objects or their hash mappings in this task. [Apple network export option][apple-network-export], [existing upload/hash path][app-cloud].

Direct first-extraction streaming would need a separate, evidenced design: suitable progressive AAC/container output, reliable headers/session lifetime, correct duration, seek/end behavior, cancellation and a final normalized cache. No such result is established by this research. Avoid introducing FFmpeg or a new player/runtime to chase it now.

## 8. Bounded work and verification handoff

| Order | Proposed scope | Expected effect and limit |
| --- | --- | --- |
| A | Keep local-first and background uploads; record per-request category, cache hit/miss, elapsed time, selected format/container and fallback reason without secrets | Makes the suspected duplicate work measurable. Keep existing redaction; do not enable raw traffic/cookie dumps. |
| B | Trial one player-JS reuse strategy with the fixed packages | Can save a repeated same-version JS fetch across songs. Does not improve an entirely cold player or bypass required challenge solving. |
| C | Trial `configs` skip; separately anonymous `initial_data` skip; unchanged-default retry at most once | May remove extra requests. Missing metadata/formats or extra fallbacks can erase gains; retain defaults for unsupported/account-sensitive cases. |
| D | Give only YouTube metadata existence lookup a shorter, measured deadline instead of inheriting the 180 s whole-download timeout | A starting experiment around 5 s trades a slow cloud hit for extraction. It may worsen some hits; measure. Do not apply this to Telegram-only tracks or blindly truncate actual media downloads. |
| E | Warehouse-only progressive source and complete-cache promotion | Removes full-object waiting when header/layout and network permit. Initial metadata/auth/first-byte latency remains. |

These are bounded changes around observed waits, not a proposal for speculative races, parallel duplicate downloads, global client overrides, retry machinery, URL-prefetch pools or cache migration. Existing [source resolution][app-repository] and [180 s request default][app-cloud] establish the concrete branch for D.

Later verification belongs in the repository's existing **remote CI**. Useful cases are: two real calls through one Python runtime; different per-request paths/cookies/cancellation; a repeated versus changed player-JS key; fallback when a reduced-request extraction lacks the required audio; real Worker-like HTTP auth/HEAD/206/200/416/error bodies; incremental playable MP3/M4A delivery; seek to unreceived bytes; cancellation and complete-only cache promotion; existing DASH duration/end/seek regression. Tests should call the real implementation and protocol boundaries, not duplicate its algorithms. No checks were executed by this research.

Device work is explicitly deferred. When resumed by the main task, compare cold runtime, same-session new song, warehouse warm/cold object and local replay under comparable phone/network conditions. Record several runs and both first playable state and user-confirmed sound, stalls, duration, seek, lock-screen behavior and cancellation. Retain all original device data and report distributions rather than one best sample. Until that acceptance, **PR16 remains draft and unmerged**.

## Primary sources

[yt-video]: https://github.com/yt-dlp/yt-dlp/blob/f264a6cbd1f630894da0f368df00f8aae50140e0/yt_dlp/extractor/youtube/_video.py
[yt-cache]: https://github.com/yt-dlp/yt-dlp/blob/f264a6cbd1f630894da0f368df00f8aae50140e0/yt_dlp/cache.py
[yt-ydl]: https://github.com/yt-dlp/yt-dlp/blob/f264a6cbd1f630894da0f368df00f8aae50140e0/yt_dlp/YoutubeDL.py
[yt-ejs]: https://github.com/yt-dlp/yt-dlp/blob/f264a6cbd1f630894da0f368df00f8aae50140e0/yt_dlp/extractor/youtube/jsc/_builtin/ejs.py
[yt-readme]: https://github.com/yt-dlp/yt-dlp/blob/f264a6cbd1f630894da0f368df00f8aae50140e0/README.md#youtube
[yt-fixup]: https://github.com/yt-dlp/yt-dlp/blob/f264a6cbd1f630894da0f368df00f8aae50140e0/yt_dlp/postprocessor/ffmpeg.py
[yt-guide]: https://github.com/yt-dlp/yt-dlp/wiki/Extractors#passing-visitor-data-without-cookies
[yt-12826]: https://github.com/yt-dlp/yt-dlp/issues/12826
[yt-sabr]: https://github.com/yt-dlp/yt-dlp/issues/17666
[yt-sabr-response]: https://github.com/yt-dlp/yt-dlp/issues/17666#issuecomment-5696145964
[webkit-provider]: https://github.com/grqz/yt-dlp-apple-webkit-jsi/blob/e466daca67cc0e1ca63b68cb8fbe80af16ce00a4/yt_dlp_plugins/extractor/ytjsc.py
[webkit-mixin]: https://github.com/grqz/yt-dlp-apple-webkit-jsi/blob/e466daca67cc0e1ca63b68cb8fbe80af16ce00a4/yt_dlp_plugins/extractor/webkit_jsi.py
[webkit-issue4]: https://github.com/grqz/yt-dlp-apple-webkit-jsi/issues/4
[webkit-issue5]: https://github.com/grqz/yt-dlp-apple-webkit-jsi/issues/5
[webkit-issue7]: https://github.com/grqz/yt-dlp-apple-webkit-jsi/issues/7
[suk-package]: https://github.com/sukov/CachingPlayerItem/blob/635dc8a3fead1f34474c984328cb69a12fd6dbd7/Package.swift
[suk-item]: https://github.com/sukov/CachingPlayerItem/blob/635dc8a3fead1f34474c984328cb69a12fd6dbd7/Source/CachingPlayerItem.swift
[suk-pending]: https://github.com/sukov/CachingPlayerItem/blob/635dc8a3fead1f34474c984328cb69a12fd6dbd7/Source/PendingRequest.swift
[suk-loader]: https://github.com/sukov/CachingPlayerItem/blob/635dc8a3fead1f34474c984328cb69a12fd6dbd7/Source/ResourceLoaderDelegate.swift
[suk-readme]: https://github.com/sukov/CachingPlayerItem/blob/635dc8a3fead1f34474c984328cb69a12fd6dbd7/README.md
[suk-license]: https://github.com/sukov/CachingPlayerItem/blob/635dc8a3fead1f34474c984328cb69a12fd6dbd7/LICENSE
[suk-38]: https://github.com/sukov/CachingPlayerItem/issues/38#issuecomment-5813713960
[suk-37]: https://github.com/sukov/CachingPlayerItem/issues/37#issuecomment-6665500164
[ktv-pod]: https://github.com/ChangbaDevs/KTVHTTPCache/blob/388da9af7891ea081e2631e09483ff5cbb09639b/KTVHTTPCache.podspec
[ktv-readme]: https://github.com/ChangbaDevs/KTVHTTPCache/blob/388da9af7891ea081e2631e09483ff5cbb09639b/README.md
[ktv-license]: https://github.com/ChangbaDevs/KTVHTTPCache/blob/388da9af7891ea081e2631e09483ff5cbb09639b/LICENSE
[ktv-25]: https://github.com/ChangbaDevs/KTVHTTPCache/issues/25#issuecomment-2482365244
[ktv-199]: https://github.com/ChangbaDevs/KTVHTTPCache/issues/199
[apple-loader]: https://developer.apple.com/documentation/avfoundation/avassetresourceloaderdelegate
[apple-setdelegate]: https://developer.apple.com/documentation/avfoundation/avassetresourceloader/setdelegate(_:queue:)
[apple-info]: https://developer.apple.com/documentation/avfoundation/avassetresourceloadingcontentinformationrequest
[apple-data]: https://developer.apple.com/documentation/avfoundation/avassetresourceloadingdatarequest
[apple-respond]: https://developer.apple.com/documentation/avfoundation/avassetresourceloadingdatarequest/respond(with:)
[apple-headers]: https://developer.apple.com/forums/thread/671139
[apple-waits]: https://developer.apple.com/documentation/avfoundation/avplayer/automaticallywaitstominimizestalling
[apple-waitreason]: https://developer.apple.com/documentation/avfoundation/avplayer/reasonforwaitingtoplay
[apple-presets]: https://developer.apple.com/documentation/avfoundation/export-presets
[apple-network-export]: https://developer.apple.com/documentation/avfoundation/avassetexportsession/shouldoptimizefornetworkuse
[http-range]: https://www.rfc-editor.org/rfc/rfc9110.html#name-range-requests
[app-python]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/MusicApp/Resources/Python/c0snow_downloader.py
[app-downloader]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/MusicApp/Online/OnDeviceDownloader.swift
[app-repository]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/MusicApp/Online/AudioRepository.swift
[app-cloud]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/MusicApp/Online/CloudMusicStore.swift
[app-online]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/MusicApp/Online/OnlineMusicStore.swift
[app-cache]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/MusicApp/Online/OnlineAudioCache.swift
[app-player]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/MusicApp/Playback/AVPlayerEngine.swift
[app-engine]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/MusicApp/Playback/PlayerEngine.swift
[app-worker]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/worker/index.js
[app-s3]: https://github.com/C0verSnow/c0versnowmusic/blob/9b189dfbffaea96aeb46110a1947d649e420bf8f/worker/tg-s3-store.js
