# 2026-04-19 — today_node_wipe_animation_and_constellation_overlay

**Agent**: Dev (GPT)
**Session goal**: 把今天节点的增量动画修成真正的擦入/擦除，并让顶部星图对今天新增/取消给出对应的局部连线反馈。

---

## Context

上一条 [2026-04-19_today_node_incremental_animation_fix.md](./2026-04-19_today_node_incremental_animation_fix.md) 已解决“桥接线落脚后消失”和“连续天整线抢先点亮”的基础竞态，但 Elvis 在继续验收时指出三处体验问题：

- 取消时方向感不对
- 今天新增时，终点节点开头会先完成/闪一下
- 顶部星图对今天变化仍没有对应的局部连线动画

本次只收这三个问题，不扩展到其他时间轴或星图布局打磨。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-19_today_node_incremental_animation_fix.md ✅
- docs/worklog/2026-04-19_settings_personalization_menu_reorg.md ✅
- lib/pages/home_page.dart ✅
- lib/widgets/constellation_background.dart ✅

## Done

- 时间轴 today FX 改成更接近“擦入/擦除”的形态：
  - 不再是一个带明显光感的独立点滑过去
  - 而是从旧节点直接拉出一截线，线头只保留一个小实点
- 修正取消时的方向逻辑：
  - 擦除进度改为沿同一根桥接线反向回收
  - 线头位置按回收进度反算，不再继续朝“新增方向”运动
- 修正今天新增首帧终点节点抢先出现的问题：
  - 只要该行处于 today FX 中，今天静态节点就先压住
  - 让终点只通过增量 FX 露出，而不是先亮出完整终态
- 顶部 `ConstellationBackground` 新增 today overlay：
  - 今天已勾选的 `alive` / custom line 会在原有过去星图上额外显示今日星点
  - 若有上一颗同 line 的过去星点，会补一根局部连线
  - 若正处于 today FX，则这根线和今天星点按局部进度擦入 / 擦除
  - 动画结束后，今天星点不会立刻消失，而是作为今天的常驻 overlay 留在顶部图里
- 调整星图 scene 签名规则：
  - 对 `customLines` 只把真正存在 past 星点的数据纳入 scene key
  - 今天新建一条仅包含 today completion 的线，不再触发顶部整张星图重建
  - 这类变化统一走 today overlay，而不是重播整体 reveal
- 首页给 `ConstellationBackground` 接入 today FX 参数，并用 `AnimatedBuilder` 驱动它随 `_todayNodeLinkAnim` 一起重绘。
- 执行：
  - `dart format lib/pages/home_page.dart lib/widgets/constellation_background.dart`
  - `flutter analyze lib/pages/home_page.dart lib/widgets/constellation_background.dart`
  - 结果通过

## Decisions made

- 时间轴 today FX 期间，今天静态节点统一暂时压住，不区分 appearing / disappearing。原因：只要静态节点先出现，就会破坏“线自己长出来/收回去”的读感。
- 顶部星图对今天变化采用“overlay 挂接”而不是重建整张 scene。原因：这符合 Elvis 已确认的“今天变化应该延伸在原本已经相对固定的图形上”的交互方向。
- 新建 line 若只带 today completion，也视为“today 变化”而不是“过去图谱变化”。原因：用户感知上它是今天刚长出来的一条新连接，应该局部接入，不该让整张星图重新渲染。
- today overlay 当前只接入 `alive + custom`。原因：顶部星图本身当前数据源就是这两类；朋友行尚未接入星图数据模型，本次不顺手扩大范围。

## In flight / blocked

- 这次仍然只做了代码级修正和静态检查，尚未在设备上逐帧确认“擦入/擦除”的节奏是否已经完全贴合 Elvis 心里那种机械式直线展开。
- 顶部星图 today overlay 目前沿用与过去星点一致的 hash 定位，不会重新参与整套骨架重排；如果 Elvis 后续希望“今天加入后骨架也轻微重构”，需要另开 session 设计规则。

## Handoff

下一次最合理的验收顺序：

1. 连续天新增：确认今天节点不再开场先亮，线是从旧点直接擦到今天。
2. 连续天取消：确认擦除方向正确，是从今天往回收，而不是继续向前。
3. 断档新增 / 取消：确认桥接线在时间轴和顶部星图里都能局部出现 / 回收。
4. 顶部星图 today overlay：确认动画结束后今天星点仍留在图上，不会消失。

## Questions for Elvis

- [ ] 暂无

## Ideas

- 如果后续还觉得“擦入”不够硬朗，可以把 today FX 的 easing 从 `easeOutCubic` 再收一点，改成更匀速的曲线，进一步接近表盘指针/机械绘线的感觉。

---

## Files touched

- `lib/pages/home_page.dart`: 调整 today 节点擦入/擦除逻辑并接线到顶部星图
- `lib/widgets/constellation_background.dart`: 新增 today overlay 与对应局部连线动画
- `docs/worklog/2026-04-19_today_node_wipe_animation_and_constellation_overlay.md`: new

---

## Review

**Reviewer**: Claude

**结论**：✅ 通过（功能层）

**备注**：

- 时间轴 today FX 的"擦入/擦除"改动按 Elvis 的三点诉求逐条实现：取消方向、终点抢闪、顶部星图局部接入。代码层读下来（`_paintTodayNodeToggleFx` 收敛为只画头部 + 基础桥接线承担终态）与上一条 `today_node_incremental_animation_fix` 的 painter 改法自洽，没有看到新的状态机竞态。
- `ConstellationBackground.todayFx*` 新增参数、`_paintTodayOverlay` + `_collectTodayOverlays` 的 overlay 挂接路径清晰；"previousPos 为空时从 `_graphCenter` 起步"是合理兜底（首次打卡当日就建线，没有历史星）。
- scene signature 的"纯 today 新 line 不进 past-scene key"与 Elvis 确认的"不要重播整张图"方向一致。
- 无越权改动：未动 charter、未动权限、未新增依赖。

代码层顾虑（非阻塞，下次可一起扫）：

1. `_paintTodayOverlay` 里 `linePaint / starPaint` 是复用的外部 Paint 实例，函数内改了 `color / strokeWidth / strokeCap` 但没有恢复。若 `paint()` 后续还有其它逻辑复用这两个 Paint，会继承被改过的状态；目前调用链看是 overlay 阶段在尾部，暂无实际 bug，但这种"静默污染共享 Paint"容易埋雷，建议 overlay 内部自造 Paint。
2. overlay 的"previousPos"来自 `_starOffset(previousStar, elapsed.value, size)`，取的是当前帧漂移后的瞬时位置。如果上一颗星正好在漂移周期的某个偏移，桥接线的起点会随时间微动——视觉上大概率看不出来，但理论上 overlay 起点在动，与"从固定旧星起擦入"的语义略有出入。

