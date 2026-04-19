# 迹点

一个离线优先的、极简的人生轨迹记录工具。

它不追求 streak、排行、推送提醒，也不把数据交给服务器。你主动留下某一天，它才在自己的时间线上留下痕迹；后续的星图、Obsidian 同步和近场朋友系统，都建立在这个前提上。

## 当前状态

- 当前主线版本：`1.0.2+5`
- 当前分支：`main`
- 当前定位：本地优先的 iPhone 版 Flutter 应用
- 数据归属：仅本机加密存储，无账号、无服务器
- BLE：仅用于近场朋友发现与确认
- iOS BLE 发现范围：仅前台使用，不启用后台蓝牙模式

## 目前已实现

- 首次启动生日初始化
- 基于本地数据的时间线 / 归档页
- Hive 加密盒持久化
- 时间篡改防御基础设施
- `.trail` 备份导出与导入
- BLE 朋友发现、确认、presence 感知、本地改名
- 设置页“清除所有数据”入口
- 星图 v0 静态背景渲染原型
- iOS R0 的主要配置收口：
  - `PrivacyInfo.xcprivacy` 最小必要声明
  - `ITSAppUsesNonExemptEncryption = false`
  - iPhone only
  - 移除 BLE 后台模式声明

## 还没完成的事

仓库里已经有不少 R0/R1 的配置和实现，但还没到“可直接上架”的闭环状态。当前更像：

- 主线功能基线已可继续开发
- iOS 上架前的主要配置项大致落地
- 真机全流程验证、时间篡改测试、BLE 双机回归、上架元数据仍需继续完成

权威发布 gate 在 [docs/charter/04_release.md](/Users/elvischen/Developer/trail/trail_app/docs/charter/04_release.md)。

## 产品边界

- 不做账号系统
- 不做云同步
- 不做广告、分析、tracker
- 不做排行榜、streak、上线奖励
- 不显示“你有多少颗星”这类累计数字

权威约束见：

- [AGENTS.md](/Users/elvischen/Developer/trail/trail_app/AGENTS.md)
- [docs/charter/00_soul.md](/Users/elvischen/Developer/trail/trail_app/docs/charter/00_soul.md)
- [docs/charter/03_boundaries.md](/Users/elvischen/Developer/trail/trail_app/docs/charter/03_boundaries.md)
- [docs/charter/02_architecture.md](/Users/elvischen/Developer/trail/trail_app/docs/charter/02_architecture.md)

## 仓库结构

- `lib/`: Flutter 业务代码
- `docs/charter/`: 产品、工程、发布边界
- `docs/specs/`: 功能 spec
- `docs/worklog/`: 每次 session 的交接记录
- `scripts/`: 发布与自动化脚本
- `ios/`, `android/`: 平台工程

## 关键功能文档

- [docs/specs/freeze.md](/Users/elvischen/Developer/trail/trail_app/docs/specs/freeze.md)
- [docs/specs/constellation.md](/Users/elvischen/Developer/trail/trail_app/docs/specs/constellation.md)
- [docs/specs/ble_friends.md](/Users/elvischen/Developer/trail/trail_app/docs/specs/ble_friends.md)
- [docs/specs/obsidian_sync.md](/Users/elvischen/Developer/trail/trail_app/docs/specs/obsidian_sync.md)

## 本地开发

环境：

- Flutter SDK：按本机已安装版本运行当前工程
- Dart SDK：`^3.11.4`

常用命令：

```bash
flutter pub get
flutter analyze
flutter run
```

iOS 相关：

- 当前工程按 iPhone-only 收敛
- 如做 iOS 本地构建，遇到 CocoaPods 沙盒不同步时先执行 `pod install`
- 真实发布前仍需做真机流程验证，不要只看模拟器或静态分析

## 版本规则

版本策略以 [docs/charter/04_release.md](/Users/elvischen/Developer/trail/trail_app/docs/charter/04_release.md) 为准。

- `1.0.0`：初始上架（R0 + R1 完成）
- `1.0.x`：上架后 bugfix
- `1.1.x`：本地提醒 + 小组件
- `1.2.x`：Obsidian 单向同步
- `2.0.0`：主动冻结 + 星图形态跃迁

任何跨大版本号跳变都必须 Elvis 确认。

## 协作约定

- 开工前先读 `AGENTS.md`、`docs/charter/00_soul.md`、`docs/charter/03_boundaries.md` 和最近两条 worklog
- 每次收工必须新增一条 `docs/worklog/` 记录
- 修改权限声明文件时，必须在 worklog 里明确标注 `⚠️ PERMISSION CHANGE`
- 任何商业、上架时机、三方依赖、权限、破坏性迁移决策都不能由 agent 自行拍板
