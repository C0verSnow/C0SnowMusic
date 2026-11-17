# 应用内 Debug

入口：账户 → Music Settings → Debug。build 18 开始提供，界面继续使用英文。

当前真机《第57次取消发送》在旧 build 17 长时间显示 Preparing，尚未播放。原版把仓库请求、Python 提取、WebKit 挑战与音频封装都收在这一条状态里，无法从画面确定是哪一步停住。用户怀疑网络，现阶段没有足够日志确认根因；本次先增加可观察性，不声称网络问题已经解决。

Debug 显示当前活动、当前阶段与累计耗时，保留最近 300 条会话事件，提供取消准备、Check connections、复制、分享和清空日志。页面打开后每秒更新耗时。网络检查分别请求 YouTube 和当前仓库，不能把站点可达当作具体视频可下载。

记录范围：

- AudioRepository 的本机缓存、仓库查询/取回、手机提取、缓存写入；导入永久副本与开始播放。
- 仓库和 YouTube Music HTTP 请求的主机、操作、超时配置、实际状态码、字节数和耗时；仓库内容另外显示 `X-Music-Storage` 与 `X-Cache`，便于确认 tg-s3 与缓存路径。
- Python 初始化、yt-dlp 提取日志、WebKit 创建/挑战执行、已收到字节与总量、错误、M4A 封装。下载进度每秒最多记录一次，取消时明确显示仍在等待当前操作返回。

Swift 会话日志只保存在内存。Python 使用当前下载暂存目录内的脱敏 `diagnostics.jsonl` 传递进度，正常结束或失败后随原暂存目录清理。没有上传日志、记录音频内容、请求正文或请求头；URL 仅保留主机，Authorization、Cookie、管理员密钥等敏感信息脱敏。分享动作由用户主动触发。

复现流程：先在 Search 点播放目标歌曲，再从账户进入 Debug，看最后停住的阶段与耗时。Check connections 分别核对 YouTube 与仓库，复制诊断日志供后续分析。若仓库已返回而 WebKit 阶段一直不结束，应继续检查挑战；若收到 NSURLErrorDomain 错误或 HTTP 非成功状态，再按实际错误处理网络或服务问题。这里只列判定方法，没有预先认定根因。

实现复用现有 URLSession、yt-dlp 与固定的 [yt-dlp-apple-webkit-jsi v0.1.1](https://github.com/grqz/yt-dlp-apple-webkit-jsi/blob/v0.1.1/yt_dlp_plugins/extractor/ytjsc.py)。本轮在 GitHub 核对 `_get_webview_lazy` 与 `_run_js_runtime` 的实际接口，仅在 App 自有适配层加入阶段记录；未修改下载请求、会话材料、上游插件或签名处理算法，没有新增依赖。

远端验证沿用现有 CI：新增 4 项日志/脱敏/进度文件测试，已有 AudioRepository 回退回归增加真实链路阶段断言；新增 Debug 入口与复制 UI 用例；Python 的实际 logger 落盘脱敏由远端执行。原有运行时连续调用、真实音频与 UI 测试继续运行。本地只做代码、语法、plist、YAML 和差异静态检查，没有本地编译或测试执行。build 18 的 CI、安装和真机复现结果见 [验收记录](VERIFICATION.md)。
