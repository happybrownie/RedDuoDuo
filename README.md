<p align="center">
  <img src="RedDuoDuo/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" alt="RedDuoDuo 图标">
</p>

<h1 align="center">RedDuoDuo</h1>

<p align="center">
  红果漫剧的第三方 iOS 客户端（非官方），原生 SwiftUI 编写。<br>
  游客打开就能看，也可登录自己的账号；支持搜索、离线缓存、自动连播与明暗外观切换。
</p>

<p align="center">
  <a href="https://github.com/happybrownie/RedDuoDuo/releases/latest"><img src="https://img.shields.io/github/v/release/happybrownie/RedDuoDuo" alt="最新版本"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/happybrownie/RedDuoDuo" alt="许可证 GPL-3.0"></a>
  <img src="https://img.shields.io/badge/iOS-26.0%2B-black" alt="iOS 26.0+">
  <a href="https://github.com/happybrownie/RedDuoDuo/stargazers"><img src="https://img.shields.io/github/stars/happybrownie/RedDuoDuo" alt="Stars"></a>
</p>

<p align="center">
  <b><a href="https://github.com/happybrownie/RedDuoDuo/releases/latest">⬇️ 下载最新 IPA（Releases）</a></b> · 无需越狱，用 AltStore / SideStore 自签安装，见下方「下载与安装」
</p>

> 本项目仅供学习与技术研究使用，与北京抖音科技有限公司、红果短剧 / 红果漫剧官方无关。项目中的请求签名与媒体解密实现移植自社区开源项目（见文末「致谢」），其版权与许可归原作者所有；使用者应自行遵守所在地法律法规及目标服务的使用条款，并自行承担使用风险。

## 功能

- 首页推荐流（Hero 大卡、排行榜、横滑行）、分类与搜索
- 播放：双引擎（系统播放器 / VLC）、倍速、选集、自动连播与下一集预加载
- 短信验证码登录（可选，不登录也可游客浏览与播放）
- 离线追剧包：整剧批量下载、本地 CENC 解密播放、息屏听剧、画中画
- 观看历史、追剧收藏、续播进度
- 外观：跟随系统明暗模式，也可在「我的」页手动选浅色 / 深色
- 折叠屏适配：展开 / 折叠布局切换、半折状态处理

## 下载与安装（普通用户，不用编译）

1. 打开 [Releases 页面](https://github.com/happybrownie/RedDuoDuo/releases/latest)，下载最新的 `RedDuoDuo-x.y.z.ipa`。
2. IPA 是未签名包，用下面任一工具以你自己的 Apple ID 重签安装（不需要越狱）：
   - **AltStore**：iPhone 上打开 AltStore →「我的应用」→ 左上角「+」→ 选择下载的 IPA；
   - **SideStore**：导入 IPA 后按应用内指引签名安装；
   - **爱思助手**：连接电脑后用「IPA 签名」功能以自己的 Apple ID 签名并安装。
3. 打开 App 即可游客观看；想同步自己的账号，在「我的」页用手机号 + 短信验证码登录。

说明：免费 Apple ID 签名的应用有效期为 7 天，AltStore / SideStore 可在后台自动续签；付费开发者账号签名的有效期为 1 年。本应用未申请任何特殊权限（entitlement），也没有 App 分组与验签自检，重签不影响功能。

## 常见问题

- **需要越狱吗？** 不需要，自签安装即可。
- **收费吗？** 完全免费、开源（GPL-3.0）。
- **登录安全吗？** 登录会话只保存在本机系统 Keychain 里，请求只发往红果漫剧的上游服务，不经过任何第三方服务器，详见 [PRIVACY.md](PRIVACY.md)。
- **画质最高多少？** 平台对每集的供流上限为 1080p，App 会在可用档位中自动优先最高画质。
- **为什么有的剧搜不到？** 个别剧目在平台侧仅通过特定入口下发，搜索未收录时可先在官方端收藏，再回本 App 的收藏/历史里打开。

## 系统与构建要求

- **运行设备**：iOS 27.1 及以上（本项目面向 iPhone Duo 等新设备开发，部署目标 iOS 26.0，但部分布局 API 需要 iOS 27.1）
- **构建环境**：macOS + **Xcode 27.1 或更高版本**（必须包含 iOS 27.1 SDK，否则 `reservedRegions` 等 API 处会编译失败）
- **工具**：[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## 从源码构建

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

签名方式不限：个人开发者证书、免费 Apple ID、付费开发者账号均可。

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
- 播放内核 **MobileVLCKit** 为 **LGPL-2.1-or-later**，由 VideoLAN 维护，构建时单独拉取、不随仓库分发。

## 致谢

由衷感谢以下开源项目与作者，没有他们的公开工作就没有这个项目：

- **[iDuanJu](https://github.com/my-name-is-alan/iDuanJu)**（作者 Alan 及贡献者）——本项目签名、取流、解密的核心实现来源；
- **hongguo-open-player / OpenHongguo** 社区——签名算法的早期开源实现；
- **[VideoLAN](https://www.videolan.org/) / MobileVLCKit**——强大的开源播放内核；
- **hongguo-desktop、HGTV** 等同题材开源项目——接口行为对照参考。

也感谢所有愿意把逆向与移植成果公开出来的开发者。

如果这个项目对你有帮助，欢迎点一个 ⭐ Star 支持一下。
