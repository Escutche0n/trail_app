# 2026-04-19 — constellation_recency_layers_and_reveal_bypass

**Agent**: Dev (GPT)
**Session goal**: 把顶部星图收成近中远三层，并去掉 scene rebuild 后重新跑整图 reveal 的老逻辑。

---

## Context

接续 2026-04-19 同日多条星图迭代。上一轮 review 指出了两个残留点：`constellation_background.dart` 仍在 scene rebuild 时用固定 8s skip window 跳 reveal；同时 anchor 方案已经成为 spec 权威，但代码里骨架 / 背景 / anchor 的职责边界还不够清晰。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-19_constellation_anchor_stars_and_bridge_overhaul.md ✅
- docs/worklog/2026-04-19_today_fx_head_parity_and_duration_ladder.md ✅
- docs/specs/constellation.md ✅
- lib/widgets/constellation_background.dart ✅
- lib/pages/home_page.dart ✅
- lib/services/storage_service.dart ✅

## Done

- `lib/widgets/constellation_background.dart`
  - 给星点加入 `_StarLayer`：`anchor / recent / fading / distant`。
  - 历史星按天数分层：
    - `0-30` 天进入主层，承担骨架候选与 today overlay 的上下文。
    - `30-60` 天进入衰减层，更暗更小、运动更弱，不参与骨架。
    - `60+` 天进入远景层，固定散落、极弱呼吸、无位置运动。
  - 骨架候选现在只从 `recent` 层取；若没有近星才回退到更老层。`anchor star` 明确排除在骨架之外，只留在 donut ring 里做 origin。
  - scene rebuild 不再用固定 `8.0` 秒跳 reveal；改成：
    - 首次出现非空 scene 时保留 reveal
    - 后续所有 rebuild 直接稳定呈现，`_nodeRevealProgress / _linkRevealProgress` 返回 1
  - `fading / distant` 两层即使在首次 scene 也不再跑统一 reveal，避免远景背景像主事件一样“重新出生”。
  - 新轴第一次完成的 bridge target 过滤掉其它 line 的 anchor 星，只桥到真实历史星。
- `lib/pages/home_page.dart`
  - 仅把“时间轴 today-node 屏幕坐标”相关注释改为“极罕见兜底 origin”，与当前 anchor 语义对齐；未引入“新建轴自动今日完成”。
- `docs/specs/constellation.md`
  - 补写 v0 当前实现的三层历史衰减说明。
  - 明确 anchor 星“不参与骨架，只停留在骨架外 ring 上”。
- 验证
  - `dart format lib/widgets/constellation_background.dart lib/pages/home_page.dart lib/services/storage_service.dart` ✅
  - `flutter analyze lib/widgets/constellation_background.dart lib/pages/home_page.dart lib/services/storage_service.dart` ✅

## Decisions made

- **不再修 fixed 8s skip，而是直接取消 rebuild reveal**：spec 的 today 增量语法已经要求“后续变化交给 overlay”，继续保留整图 reveal 只会反复回潮。
- **anchor 永远不进骨架**：anchor 的职责是“空间占位 + 今日 origin”，不是主图骨骼的一部分；否则会破坏“中心骨架 + 外圈占位”的视觉语义。
- **60+ 天固定不动**：远景星保留存在感，但不再参与 fan motion 或 drift，避免历史越多越像整张图在游动。
- **这轮不改新增轴的产品语义**：新增轴仍是“生成空 anchor”；真正点击今天时才进入统一 today FX。没有自动代用户完成今天。

## In flight / blocked

- 真机手感还没跑，尤其是：
  - 30-60 天层是否还需要再弱一点
  - 60+ 天层是否已经足够“像背景而不是脏点”
- `showAddLineDialog()` 语义本轮不动；如果未来产品要“新建即今日完成”，那是单独的产品决策，不在本次收口范围。

## Handoff

- 下一位如果要继续调视觉，只动三层参数，不要再把 anchor 拉回骨架，也不要恢复 rebuild reveal。
- 真机重点看三件事：
  1. 历史很多时，任何重建场景都不应再触发尾部整图 reveal。
  2. 60+ 天星点应该固定弱存在，不跟主骨架一起扇形摆动。
  3. 新建空轴的 anchor 要稳定停在主骨架外围 ring 上，不挤进中心骨架。

## Questions for Elvis

- [ ] 无

## Ideas

- 如果真机看起来 60+ 天层还是太“平铺”，下一轮可以只给它保留极轻的 alpha 呼吸，不做任何位移。

---

## Files touched

- `lib/widgets/constellation_background.dart`: 星图分层、anchor 排骨架、rebuild reveal bypass
- `lib/pages/home_page.dart`: 注释对齐 anchor/origin 语义
- `docs/specs/constellation.md`: v0 三层说明、anchor 不入骨架
- `docs/worklog/2026-04-19_constellation_recency_layers_and_reveal_bypass.md`: new

---

## Review

**Reviewer**: Codex

**结论**：✅ 通过

**Elvis 裁定记录**：

- 2026-04-19 对话中已明确确认：**星图上的持续动画按本次例外处理**，不改 `soul`；除此之外的持续动画仍按红线执行。

**Review 说明**：

- 在上述“本次例外”前提下，本轮改动与当前 spec 对齐，Review 不再把“星图持续漂移/连线动态”记为阻塞项。
- `60+` 天层确实被收成静态弱背景：`motionScale: 0.0`，不会跟主骨架一起扇形摆动（`lib/widgets/constellation_background.dart:770-774`）。
- scene rebuild 的 reveal 也确实改成“仅首次非空 scene 触发，后续 rebuild 直接稳定呈现”（`lib/widgets/constellation_background.dart:181-187`, `lib/widgets/constellation_background.dart:1090-1102`）。

**边界提醒**：

- 本次放行仅覆盖“星图上的持续动画”这一个已获 Elvis 明确许可的例外；后续若把同类持续动画扩到非星图区域，仍应按 `docs/charter/00_soul.md` 红线拦下。
