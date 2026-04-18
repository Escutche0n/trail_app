# 2026-04-18 — ios_release_r0_hardening

**Agent**: Dev (GPT)
**Session goal**: 推进 iOS 上架 R0 中无需 Elvis 拍板的合规配置项。

---

## Context

上一条 session 已完成 charter / specs / worklog 体系初始化，并建议下一步先推进 `docs/charter/04_release.md` 的 R0 清单。

本次工作目录中的实际项目位于 `trail_app/`，但该目录本身不是 git 仓库；同级目录 `/Users/elvischen/Developer/trail_app` 才有 `.git`。本次修改只发生在当前 workspace 的 `trail_app/` 副本中。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_charter_bootstrap.md ✅
- docs/charter/04_release.md ✅
- ios/Runner/Info.plist ✅
- ios/Runner/Runner.entitlements ✅
- ios/Runner/AppDelegate.swift ✅
- ios/Runner/Base.lproj/LaunchScreen.storyboard ✅
- ios/Runner.xcodeproj/project.pbxproj ✅
- pubspec.yaml ✅
- `.dart_tool/package_config.json` ✅
- 若干 iOS plugin / Pods 自带 `PrivacyInfo.xcprivacy`（用于核对 Required Reason API 归属）✅

## Done

- 新建 `ios/Runner/PrivacyInfo.xcprivacy`，将 app 自有 manifest 落盘并加入 Runner target resources。
- 在 `ios/Runner/Info.plist` 增加 `ITSAppUsesNonExemptEncryption = false`。
- 收紧 `UISupportedInterfaceOrientations~ipad` 为仅竖屏，避免 iPad 方向声明继续放宽。
- 将 `ios/Runner/Base.lproj/LaunchScreen.storyboard` 背景改为纯黑，避免冷启动闪白。
- 保留现有 `UIBackgroundModes = [bluetooth-central, bluetooth-peripheral]` 不动，等待 Elvis 决策。

## Decisions made

- `PrivacyInfo.xcprivacy` 当前采用空的 `NSPrivacyAccessedAPITypes`。原因：
  - 已核对到若干第三方依赖自带 privacy manifest。
  - `permission_handler_apple` 已声明 `UserDefaults`。
  - Pods 中图像相关依赖已声明 `File Timestamp`。
  - 当前 app 自身代码与 Runner 原生层未发现需要额外由 app 主体声明的 Required Reason API 命中。
- iPad 方向选择“仅竖屏”而不是进一步改 Supported Destinations。原因：这属于最小可完成收敛，不引入额外工程层分叉。
- 本次不触碰 BLE 后台模式，避免越过已存在的 Elvis 决策点。

## In flight / blocked

- `UIBackgroundModes` 仍保留。是否删除 `bluetooth-central` / `bluetooth-peripheral` 取决于 Elvis 的取舍。
- 尚未对 `PrivacyInfo.xcprivacy` 做一次真实 archive / App Store 校验；本次只完成了本地结构落盘和 manifest 归属审计。
- 当前 workspace 不是 git 仓库本体，无法在这里直接给出可信的 git diff / commit 状态。

## Handoff

下一次最合理的动作：

1. 由 Elvis 决定 BLE 后台模式保留还是删除。
2. 如果决定删除，修改 `Info.plist` 的 `UIBackgroundModes`，并在 worklog 明确写入审核影响。
3. 在真正的 git 仓库副本里复刻或同步本次修改，再做一次 Xcode / archive 级验证。

## Questions for Elvis

- [ ] **BLE 后台模式**：是否删除 `Info.plist` 里的 `bluetooth-central` + `bluetooth-peripheral`？当前我按上一条 log 的边界要求先保留不动。

## Ideas

- 如果后续决定长期只支持 iPhone，可以把“iPad 方向收敛”进一步升级为工程层完全关闭 iPad destination；但这比本次需要的最小变更更重，留待后续单独处理。

---

## Files touched

- `ios/Runner/Info.plist`: edited
- `ios/Runner/PrivacyInfo.xcprivacy`: new
- `ios/Runner/Base.lproj/LaunchScreen.storyboard`: edited
- `ios/Runner.xcodeproj/project.pbxproj`: edited
- `docs/worklog/2026-04-18_ios_release_r0_hardening.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
