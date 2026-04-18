# 2026-04-18 — version_bump_1_0_1_and_reinstall

**Agent**: Dev (GPT)
**Session goal**: 将版本抬到 `1.0.1`，并在 iOS / Android 重新安装当前工程构建。

---

## Context

当前仓库 `pubspec.yaml` 版本为 `1.0.0+1`。Elvis 明确要求把本次版本抬到 `1.0.1`，并把 iOS / Android 一起重新装一遍。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_friend_per_line_timeline_ble_gated_checkin.md ✅
- docs/worklog/2026-04-18_constellation_v0_static_render.md ✅
- pubspec.yaml ✅
- ios/Runner.xcodeproj/project.pbxproj ✅

## Done

- `pubspec.yaml`
  - 版本从 `1.0.0+1` 调整到 `1.0.1+1`
- `ios/Runner.xcodeproj/project.pbxproj`
  - 将静态 `MARKETING_VERSION` 默认值从 `1.0` 对齐到 `1.0.1`
- 查询本机设备：
  - Android 真机：`V2509A`
  - iPhone（wireless）：`00008140-00126D361E7B001C`
- Android：
  - 先通过 `flutter run -d 10AF9U3C5P002H5 --no-resident` 完成 debug 构建
  - 再用 `adb install -r build/app/outputs/flutter-apk/app-debug.apk` 显式重装
  - 用 `adb shell dumpsys package com.etc.trailApp` 核验：`versionName=1.0.1`
- iOS：
  - 通过 `flutter run -d 00008140-00126D361E7B001C --no-resident` 完成 Xcode build
  - 用 `xcrun devicectl device info apps --device ...` 核验设备上已安装 `com.etc.trailApp 1.0.1 (1)`
  - Flutter 在“Installing and launching...”阶段提示 macOS Automation 权限：需要允许控制 Xcode 才能由 Flutter 完成自动启动

## Decisions made

- 仅按 Elvis 指令提升 marketing version 到 `1.0.1`，不擅自改为其他版本策略。
- build number 维持 `+1`；本次需求只要求版本抬到 `1.0.1`，未额外指定 build number 变更。
- iOS 工程中的静态 `MARKETING_VERSION` 一并对齐，避免 Flutter 变量和工程默认值继续分叉。
- Android 在第一次 `flutter run` 后仍显示旧 `versionName=1.0.0`，因此补了一次 `adb install -r` 显式覆盖安装，并以设备侧 `dumpsys` 结果为准确认重装成功。

## In flight / blocked

- Android 重装已完成。
- iOS 安装已完成，版本已核验；若要由 Flutter 自动把 app 拉起，还需要在 macOS `Settings > Privacy & Security > Automation` 里放行对 Xcode 的控制。

## Handoff

下一步：

1. 如需验证 iPhone 端“自动启动”链路，先放行 Xcode Automation，再重跑一次 `flutter run -d 00008140-00126D361E7B001C --no-resident`
2. 如只关心安装结果，本次 session 已够用；Android / iOS 都已装上 `1.0.1`

## Questions for Elvis

- [ ] 暂无

## Ideas

- 如果后续准备进入真正的发版节奏，建议把 build number 改为显式递增策略，避免 marketing version 和 build number 长时间脱钩。

---

## Files touched

- `pubspec.yaml`: version `1.0.0+1` → `1.0.1+1`
- `ios/Runner.xcodeproj/project.pbxproj`: `MARKETING_VERSION` `1.0` → `1.0.1`
- `docs/worklog/2026-04-18_version_bump_1_0_1_and_reinstall.md`: new

---

## Review

**结论**：✅ 通过

**备注**：
- 本次版本号调整是 Elvis 在对话里直接下达的明确指令，不构成越权商业决策。
- 实际改动只涉及 `pubspec.yaml` 版本声明、iOS 工程里的测试 target 静态 `MARKETING_VERSION` 对齐，以及本条 worklog；未触碰 soul / charter 红线，也未改权限声明。
- Android 侧用设备 `dumpsys package` 核验到了 `versionName=1.0.1`，iPhone 侧用 `devicectl` 核验到了 `com.etc.trailApp 1.0.1 (1)`；“Flutter 不能自动拉起 app” 的剩余问题属于本机 Automation 权限，不影响“重新安装 1.0.1 成功”这一 session 目标。
- 追加复核：Android 设备侧还能读到 `lastUpdateTime=2026-04-18 19:19:54`，说明包体确实在本次 session 被覆盖安装。“看起来像老包”的现象目前没有被设备元数据证实，更像是后续需要单独排查的 UI / 构建内容问题，不影响这条 worklog 的安装结论。
- 若下一轮要继续追“像老包”的问题，建议另开一个 work unit，直接以设备截图 / 当前界面和源码插入点对照为目标；这已经超出本条“版本 bump + reinstall” session 的交付边界。
