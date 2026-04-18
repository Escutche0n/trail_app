# 2026-04-18 — android_canary_release_notes_history

**Agent**: Dev (GPT)
**Session goal**: 让 Android canary release notes 自动带上最近一段 commit 历史。

---

## Context

Elvis 已决定后续每做完一个新功能就发一个 release。本次要补的是 canary 预发布说明，让 GitHub Release 不再是固定模板，而是自动带出本次 canary 覆盖的提交摘要。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_android_canary_release_automation.md ✅
- `.github/workflows/android-canary.yml` ✅
- `scripts/release_android_canary.sh` ✅

## Done

- 更新 `android-canary.yml`：
  - 自动识别上一个 `android-canary-*` tag
  - 若存在上一个 canary tag，则生成 `previous_tag..current` 的 commit 摘要
  - 若不存在，则回退到最近 12 条提交作为首次 canary 的 release notes 内容

## Decisions made

- release notes 只放 commit 摘要，不尝试自动生成“面向用户”的自然语言文案。原因：当前阶段每次一个功能一个 release，直接展示提交摘要更稳，也不会编造产品描述。
- 使用 canary tag 之间的区间，而不是任意 release tag。原因：这样最符合“每个新功能一个 canary release”的节奏，不会把正式版或别的 tag 混进来。

## In flight / blocked

- 尚未在真实 GitHub Actions 上跑一次带“自动 commit 摘要”的 canary release；需要 Elvis 触发下一次 canary 看实际 release notes。

## Handoff

下一次最合理的动作：

1. 运行 `./scripts/release_android_canary.sh`
2. 在 GitHub Actions / Releases 页面确认：
   - pre-release 已生成
   - release notes 包含自上个 canary 以来的提交列表

## Questions for Elvis

- [ ] 目前没有新的阻塞问题。

## Ideas

- 等你跑过几次之后，如果觉得 commit 摘要太工程化，可以再补一层“取最近 commit subject 生成更可读的小标题”，但现在没必要先做重。

---

## Files touched

- `.github/workflows/android-canary.yml`: edited
- `docs/worklog/2026-04-18_android_canary_release_notes_history.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
