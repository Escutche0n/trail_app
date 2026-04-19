# 2026-04-18 — llm_feature_brief_for_sponsor_pitch

**Agent**: Dev (GPT)
**Session goal**: 新增一份给 LLM 使用的产品叙事底稿，用于生成更有吸引力的功能介绍和赞助向外部表达。

---

## Context

当前仓库主线已具备 README 与 charter / specs 体系，但还缺一份专门面向“外部叙事生成”的文档：既要让 LLM 理解产品为什么存在、当前已经能做什么、未来会走向哪里，又要避免把未上线功能说成已经完成。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_mainline_remote_finalize.md ✅
- docs/worklog/2026-04-18_version_bump_1_0_1_and_reinstall.md ✅
- docs/charter/01_product.md ✅
- docs/charter/02_architecture.md ✅
- docs/specs/ble_friends.md ✅
- docs/specs/constellation.md ✅
- docs/specs/obsidian_sync.md ✅
- README.md ✅

## Done

- 新增 [docs/promo/trail_llm_feature_brief.md](/Users/elvischen/Developer/trail/trail_app/docs/promo/trail_llm_feature_brief.md)
- 文档内容覆盖：
  - 产品存在理由
  - 当前已实现能力
  - 当前最值得传播的“钩子”
  - 未来明确方向与可保留的想象空间
  - 给 LLM 的语气与边界约束
  - 可直接复用的一段提示词基底与若干核心句子

## Decisions made

- 这份文档定位为“对外叙事底稿”，而不是权威 spec。原因：它需要更有传播力，但不能替代功能边界文档。
- 文档里显式区分“当前已实现”和“未来路线”。原因：用户明确要求可以“画饼”，但不能把路线图误写成已交付。
- 文案重点放在产品气质、时间观、隐私立场和现实世界的朋友见证，而不是堆砌技术细节。原因：这更符合赞助页 / 视频口播 / 介绍页的真实使用场景。

## In flight / blocked

- 本次未改任何功能代码，也未补新的 spec。
- 这份文档的传播效果仍需要 Elvis 在真实外部场景里继续压口径、筛句子。

## Handoff

下一次最合理的动作：

1. 如果要做赞助页、官网介绍或视频口播，可直接把这份文档喂给 LLM 继续生成不同风格版本。
2. 如果后续产品路线发生变化，需要同步修订文档中的“已实现 / 未来方向”段落。
3. 若要进一步落地，可以再拆一份更短的“30 秒口播版”或“赞助页首屏文案版”。

## Questions for Elvis

- [ ] 暂无

## Ideas

- 后续可以从这份长文档再裁两个派生版本：
  - 极短版：只保留一句话定位、3 个钩子、1 段未来愿景
  - 视频口播版：按 30 秒 / 60 秒节奏改成更自然的口语句子

---

## Files touched

- `docs/promo/trail_llm_feature_brief.md`: new
- `docs/worklog/2026-04-18_llm_feature_brief_for_sponsor_pitch.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
