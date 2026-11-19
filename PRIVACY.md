# RedDuoDuo 隐私说明

RedDuoDuo 是红果漫剧的第三方客户端（非官方，开源发布），与红果、抖音、北京字节跳动科技有限公司无关联。

## 不收集数据

- App 没有自建服务器，不收集、不上传、不出售个人信息或使用记录。
- 没有广告 SDK、统计 SDK 或第三方追踪。
- 账号登录为可选项：使用者登录自己的红果账号，凭据只在设备与红果服务之间传输；匿名设备注册只用于向红果请求公开内容与播放地址。

## 本机数据

- **登录会话（如已登录）**：会话 Cookie、x-tt-token、账号资料（含手机号）保存在系统 **Keychain**（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，仅本机、不随 iCloud 钥匙串同步）。旧版本曾明文存于 UserDefaults，升级后首次启动会自动迁入 Keychain 并删除明文残留；登出即从 Keychain 删除。
- **匿名设备身份**（device_id / iid / cdid 等）保存在本机 UserDefaults。
- **观看历史、搜索历史、追剧收藏、续播进度与播放偏好**保存在本机 UserDefaults。
- **离线缓存元数据**（已下载剧集记录，键 `redduoduo.offline.records.v1`）保存在本机 UserDefaults。
- **解密后的视频明文**只写入本机 Caches（`RedDuoDuoStreams/`），删除 App 即清除。
- **诊断日志**（Documents/`redduoduo.log`）：仅记录状态码、字节数、Cookie 名等脱敏元数据，不记录原始响应体、任何 token/cookie 值、手机号或账号昵称；文件超过 512 KB 自动清空重建。
- 请求直接从设备发往红果的字节上游域名，适用红果自己的隐私政策。为兼容少数上游 CDN，App 的 ATS 配置为允许任意加载（含 HTTP）；在不可信网络下存在明文传输风险，请自行留意。

## 内容

App 只做播放与目录展示，不存储、不分发片源；所有内容版权归原权利人。