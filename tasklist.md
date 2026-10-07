# 本文档为4象限的任务清单，全文书写大白话

## 想做：
- 完成 issue #1：把 NeriPlayer 从 B 站登录到播放音乐的接口整理成 workflows.json，并用大白话说明。

## 做完：
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
- 没有真实账号或设备登录、播放出声的验证；本次交付是源码分析和请求模板。

## 在做：
- 接口分析和文档交付已完成，无待实现内容。
