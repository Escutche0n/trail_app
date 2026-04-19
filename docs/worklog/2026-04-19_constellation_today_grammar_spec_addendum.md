# 2026-04-19 — constellation_today_grammar_spec_addendum

**Agent**: Dev (Claude Opus 4.7)
**Session goal**: 把 today 增量（时间轴 / 星图 overlay / 新建 line）三处散落的动画规则统一成一套语法，落到 `specs/constellation.md` 里作为后续代码对齐的唯一真相；本 session 不改代码。

---

## Context

本次是在 Elvis 指派下先做 Review（审今日第 `+3` 条 build bump），再切为 Dev 回应他的一个更大问题：

> 真正离"够优雅了"还差的，不是大改，而是最后几类统一性问题：
> 1. 所有 today 增量路径都必须像同一种语言
> 2. 星图的局部新增 / 删除 / 断档桥接力度要有明确层级
> 3. 新轴第一颗点的出现方式要和"已有轴上的新点"形成自然亲缘
> 4. 需要一次真机完整走查，不再按单点 bug 修

今日同日在 today 动画与星图 overlay 上已经有四条 worklog 的改动（见 Read 段）。再加上条 `build_bump_1_0_2_plus_3_for_ios_rebuild` 已把 build number 推到 `1.0.2+3`。Elvis 本次明确：「这个版本更新已经够大了」——本 session 只到 spec + 走查脚本为止，代码改动分到下一条 session。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/specs/constellation.md ✅
- docs/worklog/2026-04-19_today_node_incremental_animation_fix.md ✅
- docs/worklog/2026-04-19_today_node_wipe_animation_and_constellation_overlay.md ✅
- docs/worklog/2026-04-19_constellation_today_overlay_polish_and_ios_sync_check.md ✅
- docs/worklog/2026-04-19_build_bump_1_0_2_plus_3_for_ios_rebuild.md ✅
- docs/worklog/_template.md ✅

## Done

- 在 `docs/specs/constellation.md` 的"动画规则"后新增一节 **今天增量语法（Dev 增补）**，包含四个小节：
  - **唯一动词**：所有 today 变化只用一个动作——从 origin 擦入到 anchor；取消 = 严格几何倒放；共享 `_todayNodeLinkAnim`，正向 `easeOutCubic` / 倒放 `easeInCubic`，800ms，时间轴与 overlay 共用 "today 级节点大小"的头部。
  - **Origin 决策表**：四种场景（已有轴连续 / 已有轴断档 / 新轴第一颗 / 取消）各自的 origin + anchor 规则。关键：
    - `_graphCenter` 不再作为兜底 origin。
    - 新轴第一颗点的 origin 改为 **timeline today-node 在屏幕坐标里的位置投影到星图画布**。
    - Origin 在一次 FX session 内锁定，FX 期间不跟随漂移 ticker。
  - **力度层级**：轻 / 中 / 重 三档，时长与曲线不变，只通过"线长 + 一次性点缀"表达差异。中档加 dotted 中点暗示跨越；重档加一次性半径呼吸（1.0×→1.2×→1.0×，600ms）作为 lineage 诞生的出生记号。
  - **取消 = 严格几何倒放**：overlay 层也要倒放回 origin，而不是淡出；`_latestCheckedDayBeforeToday` 必须双向可用。
- 在 `Edge cases` 后新增一节 **真机走查剧本（Dev 增补）**：六段连续场景脚本 + 判据说明。明确前置条件（build stamp + profile 装机 + 卸后再装）。
- 在"变更历史"追加 2026-04-19 条目，指回本 worklog。

## Decisions made

- **只动 spec，不动 soul**。今天语法 / 力度层级 / 走查脚本三件事都落在 spec 层；soul #11 的"常驻呼吸例外"与本节新增的"一次性出生呼吸"显式区分，不互相替代，不互相叠加。未触碰 soul 红线。
- **不自己拍 UI/UX 新样式**。spec 增补里写进去的每条具体参数（800ms / easeOutCubic / 1.2× 呼吸 / alpha ≤ 0.2 的 dotted 中点）都是对齐已有动画规则段的数字，不是新引入的风格决策；重档 / 中档的"加不加点缀"上一轮已在对话中取得 Elvis 确认（"都按照你的意思来"）。
- **本 session 不 bump 版本、不加 build stamp**。Elvis 明确"版本更新够大了"；build stamp 属于下一条代码 session 的内容。

## In flight / blocked

- 代码层三件事尚未开始，按下一条 session 做：
  - (a) overlay 的 origin 锁定机制（FX 期间不跟随漂移）。
  - (b) 新轴第一颗点的 origin 改为 timeline today-node 投影。
  - (c) 取消的几何倒放在 overlay 层对齐 + 中档 dotted 中点 + 重档一次性呼吸。
- build stamp 与 profile 装机脚本未做，是下一条 session 的 TODO（已在上条 `constellation_today_overlay_polish_and_ios_sync_check` Review 段列出，Elvis 已确认）。
- 走查脚本只写了剧本，尚未实际跑。等代码动完且 build stamp 就位后再跑。

## Handoff

下一位 Dev 请按以下顺序启动：

1. **必读**：本 log + `docs/specs/constellation.md` 新的"今天增量语法"节 + "真机走查剧本"节。spec 现在是这块的唯一真相。
2. **代码动手顺序**（建议分两个 session 而不是一口气做）：
   - Session A：origin 锁定 + 新轴第一颗点 origin 投影 + overlay 取消倒放。这三件事共用 origin 语义，耦合紧，合并做。
   - Session B：力度层级（中档 dotted 中点 + 重档一次性呼吸）+ build stamp + profile 装机走查。
3. **代码路径线索**（非指令，只提示在哪找）：
   - Timeline today FX：`lib/pages/home_page.dart` 里的 `_TimelinePainter._paintTodayNodeToggleFx` 与 `_latestCheckedDayBeforeToday`。
   - 星图 overlay：`lib/widgets/constellation_background.dart` 里的 `_paintTodayOverlay` / `_collectTodayOverlays`；previousPos 来自 `_starOffset(previousStar, elapsed.value, size)`，就是"漂移起点微动"的源头，改为 FX 启动时锁一次。
   - 共享 controller：`_todayNodeLinkAnim`。
4. **走查**放在 Session B 结尾，按 spec 新节六段剧本跑，判据是"整段是不是一种语言"，不是"每一步有没有 bug"。

## Questions for Elvis

- [ ] 暂无——spec 增补里所有需要拍板的选项（新轴 origin 语义 / 重档呼吸 / 中档 dotted 中点 / 分两个 session）都已在上一轮对话得到"都按照你的意思来"的确认。

## Ideas

- 如果 Session A 做完后 Elvis 觉得"其实轻档 / 中档肉眼没差"，重档一次性呼吸可以独立去留；spec 里三档用"时长不变 + 路径不变"的写法就是为了允许这种单档删除而不破坏语法一致性。
- 走查脚本未来可以演化成一个真机 smoke-test 清单（但不做成自动化——soul 克制气质不鼓励把"主观手感判断"机械化）。

---

## Files touched

- `docs/specs/constellation.md`: 新增"今天增量语法"、"真机走查剧本"两节 + 变更历史条目
- `docs/worklog/2026-04-19_constellation_today_grammar_spec_addendum.md`: new

---

## Review

**结论**：待 Review

**备注**：
