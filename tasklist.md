# 本文档为4象限的任务清单，全文书写大白话

## 想做：
- 完成 issue #5：整合 AlgerMusicPlayer 和 B 站扫码播放模块，远端 CI 打包 ARM64 deb，服务器运行后每隔 10 秒截一张图，共 6 张；通过后提 PR 并关闭 issue。
- 完成 issue #3：保存扫码二维码，登录后下载收藏夹第一条视频的音频，生成同名 MD；放到指定服务器，提交 PR、远端测试并关闭 issue。
- 完成 issue #1：把 NeriPlayer 从 B 站登录到播放音乐的接口整理成 workflows.json，并用大白话说明。

## 做完：
- 2026-10-07：issue #5 最终源码 23c3aac7 的四个平台远端 CI 全部通过（模拟接口测试、类型检查、构建、打包）；服务器 deb 校验值一致，已安装 0.1.0，六张真实播放截图仍需扫码登录后取得。
- 2026-10-07：issue #3 已完成。服务器 /home/C0SnowMusic 的脚本和依赖已部署，文件校验值与提交一致。用户实际扫码登录成功，默认收藏夹第一条视频第一 P 已下载，产出 bilibili.png、流窜式养老100城.m4a（2,299,000 字节）和流窜式养老100城.MD。
- issue #3 的 24 项模拟接口测试在 Python 3.10、3.12 的远端 CI 全部通过：https://github.com/C0verSnow/C0SnowMusic/actions/runs/37606373499 。文档检查也通过：https://github.com/C0verSnow/C0SnowMusic/actions/runs/37606373477 。没有在本地或部署服务器运行测试。
- 已更新 PR #4 的交付与验证说明，并关闭 issue #3；PR 保持打开，等待审核，未合并。
- 2026-10-07：已提交 PR #4：https://github.com/C0verSnow/C0SnowMusic/pull/4 。文档检查通过，发现测试工作流的安装命令需要加引号，已修正；服务器脚本与依赖已安装。
- 2026-10-07：issue #3 的扫码下载脚本、依赖文件和使用文档已写好；已加入远端 CI 的模拟接口测试，暂未运行，正在准备服务器运行环境。
- 确认本仓库只有 issue #1 未完成，已同步远端并建立 feature/issue-1-bilibili-workflows 分支。
- 下载 NeriPlayer 源码供阅读，不执行本地编译。
- 固定参考源码提交为 3e1abcb704a76a3cd211878c7303d4058866c4d4，读完扫码登录、Cookie 保存、WBI 签名、选视频和分 P、取流、音质选择、媒体读取和播放器启动代码。
- 产出 workflows.json，包含 19 个请求模板、9 条路线、6 个本地步骤，并附源码链接。
- 更新 README，用大白话说明参数怎么接上、什么时候走备用路线、怎样区分取到地址和真正播放。
- 加入只检查 JSON 的脚本和 GitHub Actions。结构检查、关键参数检查、30 处源码行号和文字核对全部通过，差异空白检查通过。
- 已推送 feature 分支并提交 PR：https://github.com/C0verSnow/C0SnowMusic/pull/2 。PR 等待审核，未合并。
- 按 issue 要求，交付分析结果后已关闭 issue #1：https://github.com/C0verSnow/C0SnowMusic/issues/1 。
- 远端文档自动检查已启动，具体运行结果见 PR 的 Checks；检查只读文档，不编译播放器。

## 没做：
- 按仓库约定，不进行本地构建、编译或会触发编译的测试。
- issue #1 没有真实账号或设备登录、播放出声的验证，交付的是源码分析和请求模板。

## 在做：
- 2026-10-07：接着完成 issue #5，已确认最终远端构建全部通过；服务器软件仍在运行，旧二维码已过期，已操作软件重新生成，等待用户扫码后收集六张真实播放截图。
- 最终源码 23c3aac7 的 ARM64 完整 deb 已校验 GitHub artifact SHA-256 并安装到 /home/C0SnowMusic/deb.deb；最终 Linux ARM64/x64 和 macOS 构建通过，Windows 正在打包。软件已经生成新二维码，等待用户真实扫码，随后自动播放并截图。
- ARM64 deb 已安装到服务器，软件已用普通用户在虚拟桌面启动，已生成真实 B 站登录二维码。远端完整类型检查已在 Linux ARM64/x64 和 macOS 通过；正在收尾取消扫码时的处理，并统一窗口名称。
- Linux ARM64 和 x64、macOS ARM64 安装包已在第一轮远端 CI 构建成功；正在固定远端生成的依赖锁文件，并补上远端完整类型检查。服务器运行依赖已安装，不在服务器跑测试或编译。
- 已提交草稿 PR #6：https://github.com/C0verSnow/C0SnowMusic/pull/6 。第一轮 ARM64 的 11 项 B 站模块模拟接口测试通过，远端正在生成完整安装包；服务器正在安装运行依赖。
- B 站扫码登录、收藏夹选择和 WBI 签名已移入 Electron 主进程；音轨流式播放、暂停、拖动进度和六张真实进度截图已实现。正在提交第一版，交给远端 CI 测试与打包。
- 2026-10-07：已读取 issue #5，基于最新 main 建立 feature/issue-5-bilibili-player；确认服务器是 ARM64、没有桌面和可用声卡。用户同意使用虚拟桌面截图和真实播放进度验收。
- 开始导入 AlgerMusicPlayer，参考提交 b277ef17a8d6f05152d42528e6930205b95d0fab；只读源码，不在本地安装或编译。
- issue #3 开始时已读取需求、同步 main，并建立 feature/issue-3-favorite-audio 分支；过程中确认多收藏夹选择规则，修复 CI 配置，完成服务器部署和真实扫码下载，目前无待实现内容。
