# 在线音乐与账号

Issue #9 在 `feature/issue-9-online-music` 实现。PR 等待用户 review，不自动合并。

## 操作

1. 右上角头像打开账户页，点 Music Settings 进入原设置。语言选系统、简体中文或 English；界面直接切换，选择保存在设备上。
2. 账户页可选 Google 登录、恢复和退出。本地音乐和公开在线功能不强制登录。
3. 搜索 Tab 选择 YouTube，输入歌名/歌手并提交。只显示视频结果的封面、标题和作者；作者是 YouTube 上传者，缺少录音元数据时不能保证等于真实演唱者。频道、播放列表和广告不会作为歌曲卡片。
4. 搜索成功后自动预下载第一首。点卡片播放，菜单可预下载或下载到资料库；同一时间一个下载，可取消。搜索不会批量下载整页结果，避免无意耗尽流量。
5. 在线缓存复用现有 AVPlayer、锁屏控制、后台播放和队列。缓存歌曲先完整下载并验证纯音频，再开始播放。收藏、编辑元数据和歌词功能需先下载到资料库。临时缓存播放队列不在重启后自动恢复，可从缓存列表重新播放。

## 缓存

完整音频位于 `Library/Caches/OnlineAudio`，按完成时间从新到旧排列。上限严格按 500,000,000 字节计；添加新文件前删除最旧缓存。清单原子写入；启动时排除已被系统清掉的文件。失败、取消的临时下载会清理，单文件超过上限会报错。

`OnlineStaging` 只存进行中的下载，不出现在可播放清单中；下载过程也限制为 500 MB。用户点「下载到资料库」后，现有导入事务将副本存入 `Application Support/MusicLibrary/Audio`；缓存清理永远不遍历该目录。手动歌曲不计入 500 MB。

## 无服务器打包

首次准备依赖：`python3 scripts/prepare_online_runtime.py`。只下载和解包，无本地编译。推荐使用 Python 3.12 以上运行准备脚本。

- 固定 BeeWare `3.13-b18` iOS device/simulator XCFramework，校验官方 SHA-256。
- `scripts/online-requirements.txt` 固定四个纯 Python wheel 的版本和 SHA-256。没有手机运行 pip、动态下载脚本或远程执行服务。
- Xcode 中 `Package on-device Python runtime` 使用发行包附带的官方 `install_python` helper，将标准库和扩展打为 iOS frameworks；unsigned CI 采用 ad-hoc 签扩展，正式应用按自己的签名配置处理。
- 使用 Swift Python C API，在串行后台队列管理初始化、GIL 和调用。WebKit 操作通过上游插件回到主线程；Swift 添加自己的导航/弹窗限制，避免上游已知的跳转 YouTube 问题。
- 只选 `bestaudio[ext=m4a][vcodec=none]`，无需 FFmpeg。文件仍通过 AVFoundation 的可播放性、音轨与无视频检查，才进入缓存。

二进制与 wheel 位于被 Git 忽略的 `Vendor/`；GitHub Actions 在编译前运行同一准备脚本。请保留发行包和 wheel 内的全部第三方许可。设计参考、候选取舍见 [调研](ONLINE_MUSIC_RESEARCH.md)，不复制 Palladium 的 GPL 实现。

## IPA 发布

推送以 `v` 开头的版本标签会运行已有完整 iOS CI，全部通过后自动将 `C0SnowMusic-unsigned.ipa` 上传到同名 GitHub Release。带连字符的标签（例如 `v1.1.0-beta.1`）标为预发布；常规 `v1.1.0` 为正式发布。Release 的 IPA 与该标签源码、测试提交一致。未签名 IPA 仍须用自己的 Apple 证书签名安装，不能把 ZIP 包直接当成已签名应用。

## Google 配置

Google 官方 SDK 固定 `10.1.0`。在 Google Cloud 为 `org.c0versnow.C0SnowMusic`（或你自己的 Bundle ID）创建 iOS OAuth client；将 `Config/Local.example.xcconfig` 复制为被忽略的 `Config/Local.xcconfig`，填入两个公开应用标识。工程将其写入 `GIDClientID` 与 `CFBundleURLSchemes`。不填写 Client Secret，也不需要新建后端。

启动恢复 Google 会话，回调先交 `GIDSignIn.handle`，未处理的文件 URL 继续导入。退出使用 SDK 清会话。客户端不自行保存 token。Google OAuth 代表账户身份，不是 YouTube 网页 cookie；不会借用其他开源应用的 Client ID。

## 验证与限制

本地只做源码阅读、Python AST、shell 语法、plist 与差异检查，禁止本地编译或运行会触发编译的测试。远端已有 `build-player.yml` 负责模拟器/真机 Release 编译、XCTest 和 XCUITest。

新增测试覆盖手机页面解析与去重、错误页识别、真实 M4A 缓存淘汰、重启清单恢复、手动导入副本保留、拒绝 HTML、Python/SSL/WebKit 执行、设置入口与语言切换。CI 的通过状态须以 PR checks 为准；测试不使用用户音乐。

真实 Google 登录需配置自己的 Client ID 后在设备验收。真实 YouTube 下载会受平台页面/签名变化、地区、PO Token 和机器人验证影响；不声称支持所有视频，也不把合成文件测试当作真实网站下载成功。搜索目前只取第一页，没有 continuation 分页。WebKit 插件使用 yt-dlp 私有 provider 接口，升级时须一起验证固定版本组合。
