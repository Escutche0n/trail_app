# 2026-04-18 — ios_drop_ipad_destination

**Agent**: Dev (GPT)
**Session goal**: 把 iOS 工程从“iPhone + iPad”收敛为仅 iPhone，避免继续承担 iPad 上架和适配负担。

---

## Context

`docs/charter/04_release.md` 的 R0 允许两种方向：收紧 iPad 方向声明，或直接关闭 iPad。Elvis 本次明确选择后者，原因是当前产品形态更适合先只做 iPhone。

## Read

- AGENTS.md ✅
- docs/charter/04_release.md ✅
- ios/Runner/Info.plist ✅
- ios/Runner.xcodeproj/project.pbxproj ✅

## Done

- 从 `ios/Runner.xcodeproj/project.pbxproj` 中将剩余 `TARGETED_DEVICE_FAMILY = "1,2"` 配置统一改为 `1`
- 从 `ios/Runner/Info.plist` 删除 `UISupportedInterfaceOrientations~ipad`

## Decisions made

- 选择“工程层关闭 iPad destination”，而不是继续保留 iPad 但只支持竖屏。原因：前者边界更清楚，审核语义也更一致。

## In flight / blocked

- 尚未做一次 Xcode archive / App Store Connect 级验证；本次完成的是工程声明收敛。

## Handoff

下一次最合理的动作：

1. 做一次 iOS archive / Xcode 层校验
2. 继续处理剩余 R0 验证项，重点是 `PrivacyInfo.xcprivacy`

## Questions for Elvis

- [ ] 目前没有新的阻塞问题。

## Ideas

- 如果将来真的要回到 iPad，再单独做一轮版式、触控区和时间轴密度适配，而不是现在挂着“名义支持”。

---

## Files touched

- `ios/Runner/Info.plist`: edited
- `ios/Runner.xcodeproj/project.pbxproj`: edited
- `docs/worklog/2026-04-18_ios_drop_ipad_destination.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
