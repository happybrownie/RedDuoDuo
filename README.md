# RedDuoDuo

红果漫剧的第三方 iOS 客户端（非官方），原生 SwiftUI 编写。支持短剧浏览、搜索、播放、账号登录、离线缓存与自动连播，界面针对 iPhone 与折叠屏（横向展开）布局做了适配。

> 本项目仅供学习与技术研究使用，与北京抖音科技有限公司、红果短剧 / 红果漫剧官方无关。项目中的请求签名与媒体解密实现移植自社区开源项目（见文末「致谢」），其版权与许可归原作者所有；使用者应自行遵守所在地法律法规及目标服务的使用条款，并自行承担使用风险。

## 功能

- 首页推荐流（Hero 大卡、排行榜、横滑行）、分类与搜索
- 播放：双引擎（系统播放器 / VLC）、倍速、选集、自动连播与下一集预加载
- 短信验证码登录（可选，不登录也可游客浏览与播放）
- 离线追剧包：整剧批量下载、本地 CENC 解密播放、息屏听剧、画中画
- 观看历史、追剧收藏、续播进度
- 折叠屏适配：展开 / 折叠布局切换、半折状态处理

## 系统与构建要求

- **运行设备**：iOS 27.1 及以上（本项目面向 iPhone Duo 等新设备开发，部署目标 iOS 26.0，但部分布局 API 需要 iOS 27.1）
- **构建环境**：macOS + **Xcode 27.1 或更高版本**（必须包含 iOS 27.1 SDK，否则 `reservedRegions` 等 API 处会编译失败）
- **工具**：[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## 快速开始

1. 拉取播放内核（MobileVLCKit，构建必需，仓库内不含二进制）：

   ```sh
   ./scripts/fetch-vlckit.sh
   ```

2. 改成你自己的 Bundle ID：编辑 `project.yml`，把 `com.yourname.redduoduo` 换成你自己的（例如 `com.example.redduoduo`），测试目标的 Bundle ID 同步修改。

3. 生成工程：

   ```sh
   xcodegen generate
   ```

4. 用 Xcode 打开 `RedDuoDuo.xcodeproj`，在 Signing & Capabilities 里选择你自己的开发团队（Team），即可编译、安装到自己的设备。

签名方式不限：个人开发者证书、免费 Apple ID、付费开发者账号均可。导出的 IPA 也可通过 AltStore、爱思助手等方式重签安装——本应用未申请任何特殊权限（entitlement），也没有 App 分组与验签自检，重签不影响功能。

## 使用说明

- 首次启动会以游客身份自动注册匿名设备身份，直接可看。
- 登录为可选功能：在「我的」页用手机号 + 短信验证码登录。上行短信验证等风控流程取决于上游服务，登录失败不影响游客使用。
- 应用内写死的个别上游常量随上游版本更新可能失效，属预期情况，欢迎按上游开源项目的更新同步修正。

## 隐私

- 不收集、不上传任何统计或个人信息到第三方服务器；请求只发往红果漫剧的上游服务。
- 本地仅保存：匿名设备身份、登录会话（如已登录，存于系统 Keychain）、观看历史、搜索历史、追剧收藏与离线缓存。详见 [PRIVACY.md](PRIVACY.md)。

## 许可证

本项目以 **GPL-3.0-only** 发布，完整文本见 [LICENSE](LICENSE)。采用「only」口径是因为核心代码派生自 GPL-3.0 的 iDuanJu，其上游 only/or-later 口径无法在本仓库内核验，保守起见组合作品锁定 GPL-3.0（不接受「或后续版本」）。

项目中包含或移植了多个开源项目的代码，各自的许可证与归属声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [Licenses/](Licenses/) 目录（构建时会随 App 资源一并打包）。简要说明：

- 请求签名、取流与 CENC 解密链主要移植自 **iDuanJu**（GPL-3.0）；
- 播放签名曾含与 **hongguo-open-player**（GPL-3.0-only）交叉核对的 551 方言，因未被调用已在本公开版中移除，仓库内不再含该项目代码；
- 签名变换的早期血统来自 **OpenHongguo**（Apache-2.0）；
- 工程骨架源自 **DouDuo**（MIT）；
- 播放内核 **MobileVLCKit** 为 **LGPL-2.1-or-later**，由 VideoLAN 维护，构建时单独拉取、不随仓库分发。

## 致谢

由衷感谢以下开源项目与作者，没有他们的公开工作就没有这个项目：

- **[iDuanJu](https://github.com/my-name-is-alan/iDuanJu)**（作者 Alan 及贡献者）——本项目签名、取流、解密的核心实现来源；
- **[DouDuo](https://github.com/81199000/DouDuo)**（作者 81199000）——工程骨架与播放器思路的来源；
- **hongguo-open-player / OpenHongguo** 社区——签名算法的早期开源实现；
- **[VideoLAN](https://www.videolan.org/) / MobileVLCKit**——强大的开源播放内核；
- **hongguo-desktop、HGTV** 等同题材开源项目——接口行为对照参考。

也感谢所有愿意把逆向与移植成果公开出来的开发者。
