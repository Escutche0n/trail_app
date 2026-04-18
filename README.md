# 迹点

一个离线优先的、极简的人生轨迹记录工具。

它不追求 streak、排行、推送提醒，也不把你的数据交给服务器。你主动冻结某一天，它才在自己的时间线上留下痕迹；后续星图、Obsidian 同步和近场朋友系统，都围绕这个前提展开。

## 当前状态

- 主线版本：`1.0.0+1`
- 当前分支：`main`
- 数据存储：本地加密
- 网络依赖：无服务器、无账号
- BLE：仅用于近场朋友发现与确认
- iOS BLE 发现范围：前台使用，不启用后台蓝牙模式

## 已实现

- 生日初始化与时间线生成
- 本地加密存储
- 时间篡改防御基础设施
- 首页时间线与归档页
- 设置页与本地备份导入导出
- BLE 朋友发现、确认、presence 感知、本地改名
- iOS 上架 R0 的部分合规收口

## 设计原则

- 离线优先
- 反游戏化
- 反社交异化
- 不做云端同步
- 极简黑白视觉

项目权威约束写在：

- `AGENTS.md`
- `docs/charter/00_soul.md`
- `docs/charter/03_boundaries.md`

## 仓库结构

- `lib/`: Flutter 业务代码
- `docs/charter/`: 产品与工程宪法
- `docs/specs/`: 功能设计说明
- `docs/worklog/`: 每次 session 的交接记录
- `ios/`, `android/`, `macos/`, `linux/`, `windows/`, `web/`: 平台工程

## 本地开发

要求：

- Flutter SDK `3.11.4` 对应环境
- Dart SDK `^3.11.4`

常用命令：

```bash
flutter pub get
flutter analyze
flutter run
```

## 文档约定

每次改动后都应补 `docs/worklog/`。

如果修改以下文件，必须在 worklog 中显式记录：

- `ios/Runner/Info.plist`
- `ios/Runner/Runner.entitlements`
- `android/app/src/main/AndroidManifest.xml`

## 版本规则

当前基线从 `1.0.0+1` 起。

- 小版本递增示例：`1.0.1+2`、`1.0.2+3`
- 大版本跳变必须经过 Elvis 确认

## 相关文档

- `docs/specs/freeze.md`
- `docs/specs/ble_friends.md`
- `docs/specs/obsidian_sync.md`
- `docs/charter/04_release.md`
