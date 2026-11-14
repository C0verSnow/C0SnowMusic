# 参考来源与许可

本应用没有第三方运行时依赖，没有复制参考项目源码或品牌素材。保留仓库已有 MIT LICENSE 的版权声明。Apple 系统框架和 SF Symbols 按其平台条款使用。

开发前通过 GitHub 检索 `music player language:Swift`，并实际克隆、阅读五个仓库的 README、许可证、构建设置和相关源码：

| 项目与固定源码 | 提交 | 核对结论和借鉴范围 |
| --- | --- | --- |
| [Kaset-iOS](https://github.com/emoonadev/Kaset-iOS/tree/f176f995d75c574612ff60808af19e543782dd29) | `f176f995d75c` | MIT；iOS 26 / Swift 6；SwiftUI + WebKit/InnerTube。仅借鉴页面层级与唯一播放状态；不采用 WebView、登录或网络播放。 |
| [AppleMusicBottombarSwiftUI](https://github.com/ahmetbostanciklioglu/AppleMusicBottombarSwiftUI/tree/febe434aceafa86128fd98a3f557656c048673f0) | `febe434aceaf` | 未发现 LICENSE；iOS 26.1 / Swift 5。仅研究系统 bottom accessory 与 zoom API；不复制代码、素材或空按钮。 |
| [MyPlaylists](https://github.com/aisultanios/MyPlaylists/tree/3bc3e5221205a0fbb3f672329e853e3eabb4428c) | `3bc3e5221205` | 未发现 LICENSE；iOS 16，工程未显式设置 Swift 版本。SwiftUI/UIKit/MusicKit；仅研究拖动和取色思路，不使用订阅和在线 API。 |
| [Apple-Music-UI-Demo](https://github.com/sebjvidal/Apple-Music-UI-Demo/tree/9d7a0276ed9fd44e7bd261eac5bb3c22fe53ca76) | `9d7a0276ed9f` | 未发现 LICENSE；iOS 17 / Swift 5，UIKit 自定义转场；仅研究封面连续过渡，不使用其素材、代码或私有 API。 |
| [Petrichor](https://github.com/kushalpandya/Petrichor/tree/36236c597c14805ceff8641609f74c337ee766fa) | `36236c597c14` | MIT；活跃 macOS 原生播放器，使用独立 Crescendo 播放/元数据后端；借鉴引擎边界、队列条目 ID 和实际编码检测思想，不引入其依赖。 |

GitHub 核对时 Petrichor 为 1,770 stars，最近提交 2026-11-11；近期 issue/PR 有回复和关闭记录。Kaset 为 9 stars，最近提交 2026-11-13，实际 LICENSE 含 MIT 声明，尽管 GitHub 自动识别为 Other。其他三个演示项目没有明确许可证，不能当成可直接合并的代码来源。

取舍：优先采用 Apple 官方组件，避免演示项目中的静态歌曲、空按钮和旧 UIKit 私有行为。Petrichor 维护活跃但主要面向 macOS，且完整音频依赖会扩大本项目体积，因此只采用模块设计经验。Kaset 使用隐藏 WebView 播放，不适合本地音频核心。

CI 工具：GitHub 官方 checkout / upload-artifact 和 MIT 许可的 maxim-lobanov/setup-xcode；FFmpeg 只在远端 CI 生成非版权音频夹具，不链接到应用，不分发第三方音频样本。
