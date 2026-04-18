# 2026-04-18 — appicon_dedupe_cleanup

**Agent**: Dev (GPT)
**Session goal**: 清理 iOS AppIcon 资源里带 `" 1"` 后缀的重复文件。

---

## Context

`docs/charter/04_release.md` 的 R1 清单里明确提到需要清理 AppIcon 冗余文件。当前 `ios/Runner/Assets.xcassets/AppIcon.appiconset` 中仍存在 4 个 `" 1"` 后缀文件，且它们仍被 `Contents.json` 的 iPad 图标槽位引用。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_ble_background_removal_and_readme_refresh.md ✅
- docs/charter/04_release.md ✅
- ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json ✅

## Done

- 将 iPad 图标槽位的 4 个引用改回无后缀文件：
  - `Icon-20@2x.png`
  - `Icon-29.png`
  - `Icon-29@2x.png`
  - `Icon-40@2x.png`
- 计划删除 4 个完全重复的 `" 1"` 后缀文件。

## Decisions made

- 删除前先校验了 4 对文件的 `sha1`，确认内容完全相同，再做去重。
- 本次只做资源清理，不顺带整理其余 icon 命名，避免把 session 扩大成资产重构。

## In flight / blocked

- 二进制 PNG 删除需要通过命令完成，补丁工具不能直接处理该删除。
- 尚未做 Xcode 级资源编译验证；本次先完成静态清理。

## Handoff

下一次最合理的动作：

1. 删除 4 个 `" 1"` 后缀重复文件。
2. 做一次基础校验，确认 `Contents.json` 与资源文件对齐。
3. 继续 R1 里剩余的上架收尾项。

## Questions for Elvis

- [ ] 目前没有新的阻塞问题。

## Ideas

- 如果后续统一重做图标资源，建议把 iOS / Android / marketing icon 的生成流程脚本化，避免再次产生手工复制残留。

---

## Files touched

- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json`: edited
- `docs/worklog/2026-04-18_appicon_dedupe_cleanup.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
