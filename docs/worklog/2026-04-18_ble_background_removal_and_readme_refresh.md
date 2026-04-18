# 2026-04-18 — ble_background_removal_and_readme_refresh

**Agent**: Dev (GPT)
**Session goal**: 删除 iOS BLE 后台模式声明，并把 README 重写为当前主线版本说明。

---

## Context

当前主线仓库已稳定在 `main`，版本为 `1.0.0+1`。此前 iOS R0 合规收口里保留了 `UIBackgroundModes`，等待 Elvis 决策。Elvis 本次明确决定删除，优先收掉审核风险。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_mainline_remote_finalize.md ✅
- README.md ✅
- ios/Runner/Info.plist ✅
- docs/specs/ble_friends.md ✅

## Done

- 从 `ios/Runner/Info.plist` 删除 `UIBackgroundModes` 中的：
  - `bluetooth-central`
  - `bluetooth-peripheral`
- 重写 `README.md`，使其反映当前项目定位、已实现能力、开发方式、版本规则与文档入口。
- 在 `docs/specs/ble_friends.md` 增补当前主线约束：iOS BLE 发现按“仅前台发现”理解。

## Decisions made

- **⚠️ PERMISSION CHANGE**：删除 iOS BLE 后台模式声明。原因：Elvis 已明确确认删除，且这能减少审核追问与不稳定后台行为带来的误导。
- README 采用“当前主线状态说明”而不是模板式 Flutter 项目介绍。原因：仓库已进入真实产品开发阶段，默认模板信息只会制造噪音。

## In flight / blocked

- 尚未做真机 BLE 前台发现回归测试；本次只完成配置与文档收口。

## Handoff

下一次最合理的动作：

1. 跑一次基础校验，确认 `Info.plist` 删除后台模式后没有静态问题。
2. 如继续做上架收尾，进入剩余 R0 / R1 项。
3. 如继续功能开发，README 已可作为当前仓库入口说明。

## Questions for Elvis

- [ ] 目前没有新的阻塞问题。

## Ideas

- 如果后续要面对外部协作者或开源阅读者，可以在 README 再补一段简短截图或 GIF，但这不是当前必要项。

---

## Files touched

- `ios/Runner/Info.plist`: edited
- `README.md`: rewritten
- `docs/specs/ble_friends.md`: edited
- `docs/worklog/2026-04-18_ble_background_removal_and_readme_refresh.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
