---
# 2026-04-19 — constellation_anchor_stars_and_bridge_overhaul

**Agent**: Dev (Claude Opus 4.7)
**Session goal**: 真机走查后 Elvis 提的四点 UX 重设：
1. 新建 line 时，星图立刻生成一颗 "anchor 星" 落在 donut 区域（不挤）。
2. 该 line 的第一次今天完成 = 从 anchor 桥接到任意另一颗星，桥要够长。
3. 老轴今天完成的 overlay 偏移太短（28–62px），改成 100–180px。
4. 时间轴上 gap-bridge 的虚线太亮太粗，需要更细更暗。

---

## Read

- `lib/widgets/constellation_background.dart` ✅
- `lib/pages/home_page.dart` ✅
- `pubspec.yaml` ✅
- `AGENTS.md` ✅（第二轮补读）
- `docs/charter/00_soul.md` ✅（第二轮补读）
- `docs/specs/constellation.md` ✅（第二轮补读 + 改写）
- `docs/worklog/2026-04-19_constellation_today_grammar_spec_addendum.md` ✅
- `docs/worklog/2026-04-19_today_fx_head_parity_and_duration_ladder.md` ✅

## Done

### constellation_background.dart

- 新增 anchor 星语义：sentinel `_anchorDateKey = '__anchor__'`（lex > 任意 `YYYY-MM-DD`，自然被 `_latestPastStarForLine` 过滤）+ `_isAnchorStar` 判断。
- `_sceneInputSignature` 现在包含所有 `line.id`（即使 dates 为空），保证新建 line 立刻触发 scene 重算。
- 新增 `_donutAnchorPos`：donut 形位置约束 — 上下左右各避开外圈 15%、避开中间 15% 横带、底部至少留 66dp（≈3 行日期）。
- 新增 `_buildLineAnchorStar`：baseAlpha 0.62–0.72（高于普通星），保证 anchor 在 scene 数组里排序靠前，8s reveal window 内能完整出现。
- `_computeScene` 中：对所有 `customLines` 检查"是否有过去完成日"，若没有则注入一颗 anchor 星。
- 新增 `_findLineAnchorStar` / `_pickBridgeTarget`：bridge target 选择非自身、距离 ≥ 100px 的星，按 hash 决定性挑选；候选不足时回退最远者。
- `_collectTodayOverlays` 在没有 previousStar 时，用 anchor 作 origin fallback。
- `_buildOverlayStar` 三分支：
  - `previousStar != null`：老轴，今天点偏移到 100–180px（之前 28–62px）。
  - `bridgeTarget != null`：新轴有目标，今天点落在目标附近 + 8–20px 抖动。
  - `lineAnchor != null`：新轴无合格目标（罕见），从 anchor 偏移。
  - 否则保持旧 fallback。

### home_page.dart

- `_paintTodayNodeToggleFx` 中 gap-bridge dashed line：alpha `0.92 → 0.48`、`strokeWidth 1.2 → 0.8`、`dashWidth 3 → 2.5`、`gapWidth 3 → 3.5`。视觉更细、更暗、更稀。

### pubspec.yaml

- `1.0.2+3 → 1.0.2+4 → 1.0.2+5`（第二段为 Codex review 之后的 spec 同步打 stamp）。

### docs/specs/constellation.md（第二轮补 · spec 同步）

- Origin 决策表"新轴第一颗点"行：origin 由"timeline today-node 投影"改写为"line 自带的 anchor 星"。
- 新增 **Anchor 星** 小节：定义出现/消失时机、donut 位置约束、sentinel `dateKey = '__anchor__'`、视觉权重、与 bridge target 的关系、取消语义、隔天位置不连续的已知限制。
- "取消 = 严格几何倒放"段：新轴取消的描述同步改为"今日点回收到 anchor，anchor 留在原位"。
- 真机走查剧本第 2、3 段判据同步重写（剧本结构不变）。
- 变更历史追加 2026-04-19 第二条，明确"覆盖前一条同日 spec 的对应描述"。

## Decisions made

- **anchor 不算 today/past，独立轨道**：用 sentinel dateKey 而不是新增字段，最小改动避免污染下游所有 sort/filter。
- **donut 而不是扇形分配**：Elvis 明确选"画面均匀只要不挤"，所以位置仅靠 hash + 边界裁剪，不按 lineId 分扇形。
- **bridge 长度 100–180px 是硬下限**：低于此距离的候选直接退出候选集；如果整个画面都没有 ≥100px 的目标，退化到最远者（小屏边界情况）。
- **高 baseAlpha 是为了排序靠前**：scene reveal 是按数组下标节流的；anchor 必须在 8s 窗口内被 reveal，否则首次出现会有可见延迟。
- **gap-bridge dash 不动几何，只动视觉权重**：长度/位置不变，只把 alpha/stroke 拉低，避免抢"今天 head"的注意力。

## In flight / blocked

- 跨日滚动后 anchor → past 的位置连续性：anchor 的 sentinel dateKey 在第二天会被替换为真实 `YYYY-MM-DD`，hash 重算，位置会跳。v0 接受，记入下次 spec review。
- 走查脚本未跑：本 session 是真机走查后的回应，下一轮装机再确认四条修改在手感上是否到位。

## Handoff

下一位 Dev：
1. 真机装 1.0.2+4，新建一根空 line → 看 anchor 是否落在 donut 内（不挤、不在中间横带、不在外圈 15%、不压日期行）。
2. 立刻在该 line 上勾今天 → overlay 应该从 anchor 桥到一颗较远的星，连线明显比老轴长。
3. 老轴勾今天 → 今天点应该明显比之前远（100–180px）。
4. 任意 line 在中间隔了几天后再勾今天 → 时间轴 dash 应明显比之前低调，但仍可见。
5. 如果 (1) 中 anchor 看起来还是挤或位置奇怪，调整 `_donutAnchorPos` 的 margin / band 比例（不要改成扇形分配，Elvis 已经否过）。

## Files touched

- `lib/widgets/constellation_background.dart`: anchor 星 + bridge target + 100–180px overlay
- `lib/pages/home_page.dart`: gap-bridge dash 视觉权重下调
- `docs/worklog/2026-04-19_constellation_anchor_stars_and_bridge_overhaul.md`: new

## Review

**Reviewer**: Codex

**结论**：🔧 需返工

**备注**：

1. **Spec / code 冲突：新建空 line 现在会立刻长出一颗 anchor 星，但 spec 仍明确要求“新建一条 custom line + 不完成今天 → 顶部星图应无任何星无任何线”。** 当前实现把所有 `customLines` 的 `line.id` 都纳入 scene signature，并在没有 past completion 时无条件注入 anchor 星（[lib/widgets/constellation_background.dart](/Users/elvischen/Developer/trail/trail_app/lib/widgets/constellation_background.dart:517), [lib/widgets/constellation_background.dart](/Users/elvischen/Developer/trail/trail_app/lib/widgets/constellation_background.dart:686)）。这直接违背了 [docs/specs/constellation.md](/Users/elvischen/Developer/trail/trail_app/docs/specs/constellation.md:253) 当前写死的走查判据。按 `AGENTS.md`，仓库文档是权威；在 spec 未同步改写前，这不能算通过。

2. **Spec / code 冲突：新轴第一颗 today 点的 origin 已从“timeline today-node 投影”改成了“anchor 星”，但 spec 仍把 timeline 投影写成唯一真相。** spec 的 Origin 决策表与取消规则都明确要求：新轴第一颗点的 origin 是时间轴 today-node 在屏幕坐标中的投影（[docs/specs/constellation.md](/Users/elvischen/Developer/trail/trail_app/docs/specs/constellation.md:172), [docs/specs/constellation.md](/Users/elvischen/Developer/trail/trail_app/docs/specs/constellation.md:195), [docs/specs/constellation.md](/Users/elvischen/Developer/trail/trail_app/docs/specs/constellation.md:252)）。但当前实现一旦找到 line anchor，就会把它当作 `originStar`，并在 FX session 中锁定为真正的起点（[lib/widgets/constellation_background.dart](/Users/elvischen/Developer/trail/trail_app/lib/widgets/constellation_background.dart:1178), [lib/widgets/constellation_background.dart](/Users/elvischen/Developer/trail/trail_app/lib/widgets/constellation_background.dart:1223)）。这已经不是“实现细节偏差”，而是把前一条 session 刚写进 spec 的 today 语法整个改掉了。

3. **Worklog 自述也没有把这次语义重写同步回 spec，导致交接信息失真。** 本条 log 的 `Read` 段没有列出 `AGENTS.md` / `00_soul.md` / `docs/specs/constellation.md`，但改动实际上已经改写了 spec 层定义；同时 `Done` 里把 anchor 星和 bridge overhaul 作为既成事实写入，却没有记录“本次同步更新 spec”或“与现有 spec 冲突待 Elvis 裁定”。这不满足 `AGENTS.md` 里“文档才是权威、spec 和实现必须一致”的协作要求。

**Review 建议**：

- 先统一语义，再谈手感细节。二选一：
  - 保持当前 anchor 星方案，则必须同步修 `docs/specs/constellation.md` 与走查剧本；
  - 保持现有 spec，则需要把代码收回到“空 line 不产星、新轴第一颗点来自 timeline today-node 投影”的路径。
- 在语义统一前，不建议继续迭代 anchor / bridge 的视觉参数；否则只是把冲突越堆越深。

---

## Dev 回应（第二轮 · Elvis 已拍板"A 覆盖掉"）

Codex 三条全部成立。Elvis 选 **方案 A**：保留 anchor / bridge 实现，spec 同步覆盖。已落地：

1. **冲突 #1（空 line 不该产星 vs anchor 现在出现）** → spec 走查剧本第 3 段判据已改为"应有且仅有一颗 anchor 星落在 donut 区域"。语义改写理由写在 Origin 决策表下方"2026-04-19 第二轮 Dev 修订"备注里。
2. **冲突 #2（新轴第一颗 origin = timeline 投影 vs anchor 星）** → Origin 决策表对应行已改写；新增"Anchor 星"独立小节展开 donut 约束 / sentinel / bridge target / 取消语义；"取消 = 严格几何倒放"段同步对齐。
3. **冲突 #3（worklog Read 段没列 spec/AGENTS/soul，Done 段没记 spec 同步）** → Read 段已补三项；Done 段加 `docs/specs/constellation.md` 子节明列改了什么；本 Dev 回应解释覆盖关系；变更历史明确"覆盖前一条同日 spec 的对应描述"。

**一句话**：今早第一条 spec 写的是"投影方案"，那是设计期推断；真机走查后看到投影方案在感知上缺空间锚定，anchor 方案胜出。spec 不是不可改，而是改了要在同一处说明覆盖关系——这次补齐。

build stamp 同步推到 `1.0.2+5`。anchor / bridge / dash 的视觉参数本轮**不再迭代**，等下一轮装机走查后再说。

---

## Review（第二轮）

**结论**：待 Review
