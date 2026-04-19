# 2026-04-19 — version_bump_1_0_2_for_constellation_polish

**Agent**: Dev (GPT)
**Session goal**: 将当前包含星图与 today 动画优化的工作区版本抬到 `1.0.2`，便于 iOS 真机确认安装覆盖。

---

## Context

同日多轮星图与 today node 动画打磨都还停留在 `1.0.1+1`。Elvis 明确要求这轮直接抬到 `1.0.2`，避免继续因为版本号不变而难以判断手机上是否已经装到新版。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-19_constellation_today_overlay_polish_and_ios_sync_check.md ✅
- pubspec.yaml ✅
- ios/Runner.xcodeproj/project.pbxproj ✅

## Done

- 将 `pubspec.yaml` 版本从 `1.0.1+1` 提升到 `1.0.2+1`
- 将 `ios/Runner.xcodeproj/project.pbxproj` 中 Runner 相关 `MARKETING_VERSION` 从 `1.0.1` 对齐提升到 `1.0.2`

## Decisions made

- 本次只提升 marketing version，不改 build number。原因：Elvis 明确要的是“这次星图优化作为 1.0.2”，并未额外要求 build number 递增策略变更。
- iOS 工程静态 `MARKETING_VERSION` 一并改掉，避免 Flutter 版本号与 Xcode 工程显示继续分叉。

## In flight / blocked

- 本次只完成版本号落盘，尚未重新执行 iPhone 覆盖安装。

## Handoff

下一次最合理的动作：

1. 重新执行 iOS 安装。
2. 在手机上确认显示版本已变为 `1.0.2`。

## Questions for Elvis

- [ ] 暂无

## Ideas

- 如果后续进入更稳定的密集迭代，建议把 build number 也纳入显式规则，避免长期停在 `+1`。

---

## Files touched

- `pubspec.yaml`: `1.0.1+1` → `1.0.2+1`
- `ios/Runner.xcodeproj/project.pbxproj`: `MARKETING_VERSION` `1.0.1` → `1.0.2`
- `docs/worklog/2026-04-19_version_bump_1_0_2_for_constellation_polish.md`: new

---

## Review

**结论**：待 Review

**备注**：
