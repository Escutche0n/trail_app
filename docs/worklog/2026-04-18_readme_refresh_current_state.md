# 2026-04-18 — readme_refresh_current_state

**Agent**: Dev (GPT)
**Session goal**: 按当前主线实际状态完整更新 README，并补一条可交接的文档 worklog。

---

## Context

当前仓库位于 `main`，HEAD 为 `06f9d26`。现有 `README.md` 仍停留在较早阶段，版本号、已实现能力、上架进度和文档入口都不够准确，无法作为当前主线入口说明。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_mainline_remote_finalize.md ✅
- docs/worklog/2026-04-18_version_bump_1_0_1_and_reinstall.md ✅
- README.md ✅
- docs/charter/02_architecture.md ✅
- docs/charter/04_release.md ✅
- docs/specs/ble_friends.md ✅
- docs/specs/constellation.md ✅
- pubspec.yaml ✅

## Done

- 重写 `README.md`，使其反映当前主线真实状态：
  - 版本更新为 `1.0.1+1`
  - 明确 iPhone-only、离线优先、无账号无服务器
  - 补齐当前已实现能力与仍未完成的发布闭环
  - 增加权威 charter / spec / release 文档入口
  - 补充本地开发、版本规则、协作约定

## Decisions made

- README 不写“已经可以上架”这类过度结论，只写“主要配置已落地、发布闭环仍未完成”。原因：这和 `docs/charter/04_release.md` 以及现有 worklog 状态更一致。
- README 把星图描述为“v0 静态背景渲染原型”，不把 v2.0 设计稿误写成已上线能力。原因：`docs/specs/constellation.md` 已明确区分 v0 实现现状与后续目标设计。
- README 中直接链接 charter / specs，而不是重复抄完整规则。原因：仓库权威信息应继续以文档原文为准。

## In flight / blocked

- 本次只做文档收口，没有执行 `flutter analyze` 或真机构建。
- `docs/charter/04_release.md` 的 checklist 仍是待持续维护状态，本次未改动该文件。

## Handoff

下一次最合理的动作：

1. 如果继续做上架收尾，优先推进真机全流程验证、时间篡改测试和 BLE 双机回归。
2. 如果继续做功能开发，README 现在可以作为当前主线入口说明使用。
3. 若后续有新的稳定功能落地，记得同步更新 README 的“目前已实现”与“还没完成的事”两节。

## Questions for Elvis

- [ ] 暂无

## Ideas

- 备注区未来可以支持“用户自建可复用标签”，作为自由输入的补充，而不是替代：
  - 例：`#体重`、`#BMI`
  - 目的：减少重复输入，适合健康管理等长期记录场景
  - 当前仅记为路线方向，不在本次 session 实现

---

## Files touched

- `README.md`: rewritten
- `docs/worklog/2026-04-18_readme_refresh_current_state.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
