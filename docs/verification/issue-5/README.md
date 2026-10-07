# issue #5 的真实运行记录

本次验收在 `root@192.168.1.245` 的 `/home/C0SnowMusic` 进行。服务器为 ARM64 Armbian / Ubuntu 24.04，没有可用声卡和桌面。用户确认使用虚拟桌面截图和真实播放进度验收，不要求音箱实际出声。

软件源码位于 `feature/issue-5-bilibili-player`，运行包由 GitHub Actions 的 [远端构建](https://github.com/C0verSnow/C0SnowMusic/actions/runs/37619675006) 产出。服务器安装完整 deb，软件用普通用户、Xvfb 和 PulseAudio 空输出启动；本地和服务器都没有执行编译或测试脚本。

B 站扫码、Cookie 验证、收藏夹读取和音轨获取都由安装的软件完成，登录必须经真实账号扫码确认。六张图由软件在实际播放中调用窗口截图接口保存，不使用网页效果图或旧版下载的音频文件。`manifest.json` 记录截图时间和 HTMLAudioElement 的实际播放状态。

远端 CI 的 Linux ARM64、Linux x64、Windows x64、macOS ARM64 四个任务均已通过：模拟 B 站接口测试、完整类型检查、软件构建和安装包上传全部成功。

运行包对应源码提交 `23c3aac7`，服务器已安装版本 `0.1.0`。

- 服务器文件：`/home/C0SnowMusic/deb.deb`
- GitHub Actions ARM64 artifact：`11481731571`
- 原始 artifact SHA-256：`8ed8584fbed1972f5577ce91cf52ba061383ca21fcf36299389e146f56685c87`（与 GitHub 元数据一致）
- deb SHA-256：`6c7573e852e7f9d84e43ec9158051ac22d094b2482fff27de3f8a71f1c58a679`

2026-10-07 用户用 B 站手机客户端真实扫码并确认登录成功。软件自动获取默认收藏夹第一条视频《流窜式养老100城》（`BV1TzdnBkEqo`，第一 P），通过网络音轨实际解码播放，时长 203.917 秒。六张窗口截图均已逐张查看，界面显示登录成功、正在播放和持续增加的进度。

| 截图 | 时间（美国东部 EDT） | 实际播放进度 | 距上一张 |
| --- | --- | --- | --- |
| [playback-01.png](playback-01.png) | 10:00:53.166 | 8.321 秒 | — |
| [playback-02.png](playback-02.png) | 10:01:03.163 | 18.323 秒 | 9.997 秒 |
| [playback-03.png](playback-03.png) | 10:01:13.165 | 28.323 秒 | 10.002 秒 |
| [playback-04.png](playback-04.png) | 10:01:23.167 | 38.324 秒 | 10.002 秒 |
| [playback-05.png](playback-05.png) | 10:01:33.170 | 48.324 秒 | 10.003 秒 |
| [playback-06.png](playback-06.png) | 10:01:43.171 | 58.325 秒 | 10.001 秒 |

[manifest.json](manifest.json) 为软件原始运行记录。六次记录均为 `paused: false`、`readyState: 4`、`error: false`。这里只核对真实运行产物，没有在本地或服务器运行测试脚本。

六张 PNG 和 manifest 同时保存在服务器 `/home/C0SnowMusic/evidence` 及本目录；二维码和账号登录凭据不提交到仓库。
