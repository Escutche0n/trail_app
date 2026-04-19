# 2026-04-19 — today_node_incremental_animation_fix

**Agent**: Dev (GPT)
**Session goal**: 修正今天新打卡/取消时的增量节点动画，让桥接线跟随动画正确落到最终状态，而不是整屏重播或动画落脚后消失。

---

## Context

当前仓库位于 `main`。本次是在同日 `settings_personalization_menu_reorg` 基础上继续收敛首页时间轴交互，只处理“今天节点增量动画”这一条，不扩散到其他视觉层。开工前，`lib/pages/home_page.dart` 已经接入了 today-node FX controller，但基础线段层和 FX 层仍是两套逻辑，导致持续态与过渡态打架。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-19_settings_personalization_menu_reorg.md ✅
- docs/worklog/2026-04-18_readme_refresh_current_state.md ✅
- lib/pages/home_page.dart ✅
- docs/worklog/_template.md ✅

## Done

- 在 `_TimelinePainter` 内新增 painter 级 `_latestCheckedDayBeforeToday`，让“今天桥接线”可以直接基于当前行数据求最终锚点。
- 把今天桥接线的最终状态并回 `_paintRow` 的基础连线层，不再只依赖 `_paintTodayNodeToggleFx` 临时覆盖：
  - 今天新勾选时，桥接线按 `todayNodeFxValue` 从旧节点推进到今日节点。
  - 动画结束后，桥接线直接留在最终状态，不再出现“落脚后闪退”。
  - 今天取消时，桥接线按反向进度收回，结束后自然消失。
- 对“昨天本来连续”的情况做了特殊处理：FX 生效期间跳过那一段默认相邻实线，避免一开始就整根亮起，保证过程态和终态是同一根线。
- 将 `_paintTodayNodeToggleFx` 收敛为只画移动头部与柔光，不再额外拥有一根独立线，避免和基础桥接线重复渲染。
- 执行 `dart format lib/pages/home_page.dart`。
- 执行 `flutter analyze lib/pages/home_page.dart lib/widgets/constellation_background.dart`，结果通过。

## Decisions made

- 今天节点的增量动画不再通过“额外画一层完整临时线”实现，而是让基础线段本身承担终态，再由 FX 只负责进度头部。原因：这样连续天和断档桥接都能落到统一的渲染真相，不会出现一层负责动画、一层负责终态而互相打架。
- 取消今天打卡时不重播整行，也不重建顶部背景。原因：Elvis 已明确要求今天的变化应是相对固定图形上的局部延伸/回收，而不是刷新整套动画。

## In flight / blocked

- 本次只完成了代码级修复与静态分析，尚未在模拟器或真机上逐帧目测“出现新点/回收旧线”的手感。
- 顶部星图相关 spec 与 soul 的边界争议仍在上一条 worklog 的 Review 中，不在本次修复范围内。

## Handoff

下一次如果继续验收这块，优先在设备上验证三种场景：

1. 今天新增打卡且昨天连续，线应从旧点推进到今日点，不能先整根亮起。
2. 今天新增打卡但中间断档，桥接线应在动画结束后稳定留住，不应闪退。
3. 今天取消打卡，线应从今日点回收到上一锚点，而不是整行重绘。

## Questions for Elvis

- [ ] 暂无

## Ideas

- 如果后续还想强化“今天新增”的感知，可以只给新点再加一个极轻的半径扩散，而不是再引入第二根过渡线。

---

## Files touched

- `lib/pages/home_page.dart`: 修正今天节点增量桥接线的持久态与过渡态
- `docs/worklog/2026-04-19_today_node_incremental_animation_fix.md`: new

---

## Review

**Reviewer**: Claude

**结论**：✅ 通过

**备注**：

- 本次修复已同时覆盖两个目标：
  - 断档桥接线动画结束后，最终连线会留在静态结果里，不再闪退。
  - 连续天勾选时，首帧也不会先闪出整根实线，再切回增量动画。
- Review 未在这次增量动画逻辑里看到新的明显竞态；建议下一步直接在设备上确认实际节奏与手感。
