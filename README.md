# C0SnowMusic

参考项目：[AlgerMusicPlayer](https://github.com/f1515x/AlgerMusicPlayer)、[NeriPlayer](https://github.com/f1515x/NeriPlayer)。

## 扫码下载收藏夹第一首歌

[scripts/download_favorite.py](scripts/download_favorite.py) 实现 [issue #3](https://github.com/C0verSnow/C0SnowMusic/issues/3)。它向 B 站申请二维码，保存为 `bilibili.png`，每隔 1.5 秒询问登录状态。你用 B 站客户端扫码并确认后，它读取自己的收藏夹，下载第一首歌并生成同名说明文件。

选歌规则：按 B 站返回的自建收藏夹顺序，取第一个非空收藏夹；夹内按收藏时间倒序，取第一条视频的第一 P。歌名用视频标题，不判断视频是不是音乐，也不读取订阅别人的收藏夹。第一条视频失效或没有独立音轨时直接报错，不换歌。

需要 Python 3.10 或更新版本。首次在指定服务器安装（以下都是服务器上的命令）：

```sh
ssh root@192.168.1.245
cd /home/C0SnowMusic
# 系统缺少 venv 时，先安装系统提供的 python3-venv 包。
python3 -m venv .venv
.venv/bin/python -m pip install --only-binary=:all: -r requirements.txt
.venv/bin/python scripts/download_favorite.py --download-only
```

看到“二维码已保存”后，从服务器取回图片，用 B 站客户端扫码。另开一个本地终端执行：

```sh
scp root@192.168.1.245:/home/C0SnowMusic/bilibili.png ./bilibili.png
```

默认等待 180 秒，可用 `--login-timeout 600` 延长。过期或超时后重新运行即可。成功会在 `/home/C0SnowMusic` 得到：

```text
bilibili.png
歌名.m4a
歌名.MD
```

音频使用 B 站实际提供的格式，可能是 `.m4a`、`.flac` 或 `.mp3`，不需要 ffmpeg，不做转码。请求可用音轨后按带宽选择最高的一条；权限、版权和 B 站风控可能影响可用音轨。下载中断会删除临时文件，并尝试同一音轨的备用地址；已有同名文件会添加序号保留。说明文件包含视频链接、收藏夹、分 P、文件名、大小和格式。

可选参数：

```sh
# 指定自己的收藏夹，不再遍历其他收藏夹。
.venv/bin/python scripts/download_favorite.py --download-only --folder-id 123456
# 修改输出目录和等待扫码时长。
.venv/bin/python scripts/download_favorite.py --output-dir /home/C0SnowMusic/output --login-timeout 600
```

Cookie 只保存在进程内存中，不写入文件，不发送给音频 CDN。每次运行都需重新扫码。输出目录应由你自己管理；不要把登录二维码和下载的音频提交到 Git。下载仅适用于账号有权访问的内容。

脚本测试由 [GitHub Actions](.github/workflows/test-download.yml) 在 Python 3.10、3.12 上执行，使用模拟响应检查扫码状态、收藏夹分页、WBI 签名、音轨选择、下载清理、重名保护和 PNG/音频/MD 整体流程。仓库约定禁止本地编译验证，这些测试不在本地或部署服务器运行。真实扫码和真实音频产出需要用户扫码，CI 模拟测试不能代替真实账号实测。

2026-10-07 已在指定服务器完成真实扫码登录和下载：生成 `bilibili.png`、`流窜式养老100城.m4a`（2,299,000 字节）及同名 `.MD`。[远端测试](https://github.com/C0verSnow/C0SnowMusic/actions/runs/37606373499) 的两个 Python 版本各 24 项测试全部通过。此记录验证了当时该账号的第一条收藏视频可下载，其他视频仍取决于各自权限和接口响应。

## B 站登录到播放音乐

[workflows.json](workflows.json) 整理了 NeriPlayer 的 19 个请求模板和 9 条流程路线，完成 [issue #1](https://github.com/C0verSnow/C0SnowMusic/issues/1) 的源码分析。依据的源码固定在提交 `3e1abcb704a76a3cd211878c7303d4058866c4d4`，每个请求都有对应源码链接，方便核对。

用大白话说，整个过程是：

1. 向 B 站要一个二维码，用 B 站客户端扫码并确认。程序每隔 1.5 秒询问是否确认，成功后从响应头收集 Cookie，并保存到本地加密存储。最关键的是 `SESSDATA`。
2. 搜索想听的视频，或者从收藏夹、合集里选视频。已经知道 BV 号或 AV 号时可以跳过搜索。
3. 读取视频详情，找到想听的那一 P 的 `cid`。BV/AV 号表示整个视频，`cid` 表示具体某一段，不能混用。已指定某一 P 时，找不到就报错，不会换成第一 P。
4. 请求播放地址之前，先获取 WBI 签名用的 key，再用参数和当前时间算出 `w_rid`。这个 key 缓存 10 分钟；获取失败还有 WebTicket 备用方式。签名计算本身不发网络请求。
5. 把 BV 号和 `cid` 发给 `playurl`，拿到普通、杜比或 Hi-Res 音轨及备用地址，再按用户音质设置选择。默认参数是 `fnval=272`。满足空音轨重试条件时最多请求 3 次，仍没有音轨就试 HTML5 的单段 MP4；播放器播放其中的声音。
6. 播放器用返回的完整媒体 URL 拉取字节，并带上适用的 Referer、User-Agent 和 Cookie。拿到地址只说明取流成功；还要能解码、开始播放并持续推进播放位置，才算真正播放起来。

扫码不方便时可以打开 B 站网页登录页。该页面内部的密码、短信等请求由 B 站网页管理，NeriPlayer 源码没有逐个实现，本文没有编造这些接口。评论、歌词、UP 主空间浏览、一起听等外围请求也不属于这里的登录到取流主线。

## 怎么读 JSON

- `requests`：每个 HTTP 请求的 URL、方法、请求头、查询参数、响应读取位置、执行条件和源码出处。媒体响应是二进制，网页登录页是 HTML，其余接口返回 JSON。
- `workflows`：主路线及备用路线的典型顺序。步骤有条件，不能把列表当成全部无条件执行的脚本。例如收藏条目是合集时走合集接口，是收藏夹时走收藏夹内容接口。
- `local_steps`：保存 Cookie、签名、选择分 P、选择音轨和启动播放器等本地操作。
- `wbi_signing`：key 来源、索引表、参数过滤、编码及 MD5 算法。
- `variables`：运行时变量的来源。`{{name}}` 是占位符，不能原样发送；其中签名结果占位符按 `wbi_signing` 计算。

Cookie 和媒体地址都应使用当前会话实际返回的值。文件只保存模板，没有真实账号凭据或真实媒体链接。源码的本地登录健康判断只看是否有 `SESSDATA`；`validate_login` 是独立的服务端检查方法，并不是扫码保存后的固定请求。

## 检查方式和实际验证范围

issue #1 的交付只做源码阅读、JSON 静态检查和差异检查，没有进行本地构建、编译或会触发编译的测试，也没有用真实 B 站账号或设备实测登录、播放出声。这份 JSON 是接口分析；issue #3 新增的下载脚本见本文前面的使用说明，脚本不负责播放出声。

只检查文档结构，不访问 B 站、不运行编译：

```sh
python3 scripts/validate_workflows.py
git diff --check
```

如果本地已经有上述固定提交的 NeriPlayer 源码，还可以核对所有源码链接的行号和文字：

```sh
python3 scripts/validate_workflows.py --source-root /path/to/NeriPlayer
```

PR 的 GitHub Actions 会执行相同的 JSON 静态检查，不安装 Android 工具链。真实登录与出声仍需账号、设备和当时可用的 B 站服务，静态检查通过不能代替这一验证。
