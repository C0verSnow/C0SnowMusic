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

真实扫码和六张播放截图尚在等待完成。完成后会在此补上截图、时间间隔和播放进度。
