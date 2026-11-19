# Third-party notices

本项目包含以下第三方代码/组件，按各自许可证使用。整仓组合作品以 **GPL-3.0-only** 发布（见根目录 `LICENSE` 与 `README.md`）：iDuanJu 以 GPL-3.0 发布，其上游「only / or-later」口径无法在本仓库内核验，故组合作品保守采用 GPL-3.0-only；MIT（DouDuo）与 Apache-2.0（OpenHongguo）均向 GPL-3.0 兼容。

所有派生文件的文件头均带版权行、许可证与修改声明（修改者：RedDuoDuo 作者；修改日期见各文件头）。

## DouDuo — MIT

Copyright (c) 2026 DouDuo contributors。上游：<https://github.com/81199000/DouDuo>。全文：`Licenses/DouDuo-MIT.txt`。

借用/派生文件清单：

| 本仓库文件 | 上游来源 | 关系 |
| --- | --- | --- |
| `RedDuoDuo/Theme/Theme.swift` | DouDuo 主题/颜色系统（DDColor 等） | 大幅改写（Faceted Ruby 设计语言） |
| `RedDuoDuo/Theme/CachedAsyncImage.swift` | `DouDuo/CachedAsyncImage.swift` | 借用，去掉 ProgressiveImage / DYStorageFiles 依赖 |
| `RedDuoDuo/Player/VLCPlayerBridge.swift` | DouDuo VLC 播放桥（上游血统：無为 影库播放器） | 改写（常驻单一 VLCVideoView 等） |
| `RedDuoDuo/Player/RDVideoFit.swift` | `DouDuo/DYVideoFit.swift` | 做法与交互改编 |
| `RedDuoDuo/Player/RDPlayerGestureOverlay.swift` | DouDuo 播放器手势层做法 | 改编 |
| `RedDuoDuo/Services/DuoFoldLayout.swift` | DouDuo 折叠屏布局处理 | 改编（iPhone Duo 半折几何引擎） |
| `scripts/fetch-vlckit.sh` | `scripts/fetch-vlckit.sh` | 逐字拷贝（仅加署名头） |
| `Vendor/VLCKit/Package.swift` | `Vendor/VLCKit/Package.swift` | 逐字拷贝（仅加署名头） |
| `Vendor/VLCKit/Sources/VLCKitSPM/VLCKit.swift` | 同路径 | 逐字拷贝（仅加署名头） |

## iDuanJu — GPL-3.0

上游：<https://github.com/my-name-is-alan/iDuanJu>（作者 Alan 及贡献者），仓库整体 GPL-3.0。以下文件为**直接拷贝/改写自 iDuanJu 现有 Swift 源码**（并非经 Go 移植转写）：

| 本仓库文件 | 上游来源 | 关系 |
| --- | --- | --- |
| `RedDuoDuo/Net/ByteUtils.swift` | `STV/Providers/Common/ByteUtils.swift` | 逐字拷贝 |
| `RedDuoDuo/Net/HGCurrentProfile.swift` | `STV/Providers/Hongguo/HGCurrentProfile.swift` | 逐字拷贝（内嵌常量物料，出处见下方 NOTICE） |
| `RedDuoDuo/Net/Medusa.swift` | `STV/Providers/Hongguo/Medusa.swift` | 改写：公开版仅保留 SM3 哈希；未调用的 X-Medusa 白盒表路径（依赖未随仓库分发的 `medusa_tables.bin`）已删除 |
| `RedDuoDuo/Net/HGCurrentPlayer.swift` | `STV/Providers/Hongguo/HGCurrentPlayer.swift` | 直接拷贝，仅将 appID/licenseID/sdkVersion/envVersion 4 个常量改为 `static var` |
| `RedDuoDuo/Net/HGPlayerSign.swift` | `STV/Providers/Hongguo/HGPlayerSign.swift` | 直接拷贝，仅将 6 个常量改为 `static var`；公开版另删除了未调用的 551 方言（见下） |
| `RedDuoDuo/Net/SpadeKey.swift` | `STV/Providers/Hongguo/HGSign.swift` 的 spade 段 | 逐行摘录，仅保留取密钥所需函数（GPL-3.0 血统；Apache-2.0 NOTICE 不覆盖 spade） |
| `RedDuoDuo/Player/CENCDecryptor.swift` | `STV/Playback/CENCDecryptor.swift` | 移植 + 少量本地补丁（saiz/saio 辅助 box 一并清除等） |

## OpenHongguo — Apache-2.0（签名变换源头）

- 当前播放器签名（`HGCurrentPlayer.swift` / `HGCurrentProfile.swift`）中的 KS/custom 变换源头为 OpenHongguo（commit `05aa580a2fa914becabc5ae4be5b05539c66bda6`，Apache-2.0），经 iDuanJu 的 Go 实现（`current*.go`）与本地验证后，以其**现有 Swift 文件**形式进入本仓库。
- 出处与常量来源（`libmetasec_ml.so` / APK 的 SHA-256）说明：`Licenses/HGCurrentPlayer-NOTICE.md`；Apache-2.0 全文：`Licenses/HGCurrentPlayer-Apache-2.0.txt`。
- 该 NOTICE 仅覆盖 current*.go 变换血统，不覆盖 spade 与其余签名代码。

## hongguo-open-player / hongguoTV — GPL-3.0-only（历史交叉核对，代码已移除）

- 原 `HGPlayerSign.swift` 的 Playback 551 framing 与协议常量曾与 hongguo-open-player（GPL-3.0-only，源头 fqapp/hongguoTV）交叉核对并适配。
- **本公开版已删除该未调用的 551 方言**（`playbackHeaders` 及其私有辅助函数），本仓库不再包含来自该项目的代码。

## VLCKit / MobileVLCKit — LGPL-2.1-or-later

- 播放内核 MobileVLCKit 3.6.0（VideoLAN，Copyright (C) 2010-2023 Pierre d'Herbemont and VideoLAN）按其实源头文件声明为 **LGPL-2.1 or later**（`MobileVLCKit.h` / `vlc/vlc.h`：「either version 2.1 of the License, or (at your option) any later version」）。全文：`Licenses/VLCKit-LGPL-2.1.txt`（亦见 <https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>）。
- 二进制不随仓库分发：由 `scripts/fetch-vlckit.sh` 从公开的 tylerjonesio/vlckit-spm Release 下载并校验 SHA-256；SPM 包装层在 `Vendor/VLCKit/`（包装层代码为 DouDuo MIT，见上）。
- MobileVLCKit 为动态库，与本程序动态链接，满足 LGPL 对组合作品的要求。

## 接口参考（未复制代码）

- hongguo-desktop、HGTV 等公开项目仅作接口行为参考（bookmall/cell、登录流程等），未复制其代码；其仓库未附许可证文件。

## 二进制分发的随附许可

`project.yml` 已将根目录 `LICENSE`、`THIRD_PARTY_NOTICES.md` 与整个 `Licenses/` 目录打包进 App 资源，IPA/.app 二进制分发时随附完整许可文本（Apache-2.0 §4(a)、MIT、GPL-3.0 §6 要求）。