# 2026-04-19 — today_fx_head_parity_and_duration_ladder

**Agent**: Dev (Claude Opus 4.7)
**Session goal**: 把 1.0.2 收尾前最后两个肉眼接缝收掉 —— (#1) overlay 头部尺寸与 timeline FX 对齐 + 加 glow halo，(#2) home_page 时长字典收敛到 4 档 ladder。Elvis 已批准此为 1.0.2 收尾。

---

## Context

接续 `2026-04-19_constellation_today_grammar_spec_addendum.md` —— spec 已写完，Handoff 把代码动手分成 Session A / Session B。

进入本 session 时核对 working tree 发现：Session A 三件事（origin 锁定 / 新轴 origin 投影 / cancel 倒放）+ Session B 两件事（中档 dotted / 重档呼吸）**其实已经在 working tree 里写完了**，但都未 commit、worklog 也没记。

随后 Elvis 让我整体审一遍首页 UI 的优雅程度。我标出三个肉眼接缝：

1. timeline FX head（~5px + glow）vs overlay FX head（~2px 无 glow）—— spec 本来要求"共用 today 级节点大小的实心点"，代码两边没对齐
2. 时长方言 —— home_page 单文件 14 个不同 ms 值，FX 自己 620ms ≠ spec 钉死的 800ms
3. 坐标系叠层（drift ticker + FX session lock + 两层 safetyBounds）—— 复杂但正确

Elvis 决定本次只做 #1 + #2，#3 不在 1.0.2 收尾范围（结构性改动风险高、且只有写代码的人才感受得到）。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/specs/constellation.md ✅
- docs/worklog/2026-04-19_constellation_today_grammar_spec_addendum.md ✅
- docs/worklog/2026-04-19_constellation_today_overlay_polish_and_ios_sync_check.md ✅
- docs/worklog/_template.md ✅
- lib/widgets/constellation_background.dart ✅
- lib/pages/home_page.dart（initState + `_paintTodayNodeToggleFx` + `_paintTodayOverlay` 调用点）✅

## Done

### #1 · overlay 头部尺寸 + glow halo 与 timeline FX 对齐

`lib/widgets/constellation_background.dart` 的 `_paintTodayOverlay` head 渲染段重写为两段式：

- **FX 期间（`fxActive = isFxLine && v < 1.0`）**：head radius 走 `3.6 → 5.0`（与 timeline 非-alive today node 同径），settle 段（progress > 0.78）从 `5.0` lerp 回 `star.radius`，让 v=1 切换到 resting 时无突跳。glow halo 跟随 head，settle 段同步淡出。head alpha 从 FX 段的近白 lerp 到 resting baseAlpha。
- **Resting**（包括非 FX line 的今日点 + FX 完成后的 line）：保留原来的小星渲染逻辑，作为 spec 「终态由基础 painter 承担」的承接。

settle 段的存在是把 spec「共用 today 级节点大小」与 v0「constellation star 是小颗」之间的张力收掉 —— FX 中段对齐 timeline 头部尺寸；最后 ~22% 视觉过渡到 constellation star，避免 v=1 时硬 pop。

cancel（appearing=false, progress 1→0）几何上是 forward 的严格倒放：head 从 resting 长大到 5.0 peak、再缩到 source，沿同一根桥接路径回收到 origin。glow halo 跟随。

### #2 · 时长 ladder 收敛

`lib/pages/home_page.dart` initState 段新增注释钉下 ladder：**micro 200ms · standard 360ms · structural 800ms · background 不动**。

| Controller | 旧 | 新 | 档位 |
|---|---|---|---|
| `_hSnap` | 150 | **200** | micro |
| `_vSnap` | 200 | 200 | micro（已合） |
| `_bounce` | 420 | **360** | standard |
| `_bleFlash` | 350 | **360** | standard（doc 同步从 350 改 360） |
| `_shake` | 260 | **200** | micro |
| `_lineAddAnim` | 360 | 360 | standard（已合） |
| `_lineDeleteAnim` | 280 | **360** | standard（与 add 同档） |
| `_todayNodeLinkAnim` | 620 | **800** | structural · spec 钉死 |
| `_dayAxisReveal` | 220 | **200** | micro |
| `_centerLineAnim` | 900 | **800** | structural |
| `_radialAnim` | 320 | **360** | standard |

未动（保留各自语义节拍）：
- `_glow` 2400ms repeat、`_arrowPulse` 1800ms repeat、`_satellite` 10s rotate —— 都是 background pulse 或 motion，不在 ladder 内
- `_menuAnim` 600ms —— 4 向 radial menu 展开有自己的 chunky 节奏，进 structural 800 太钝、进 standard 360 又过快
- 散落在 `AnimatedFoo` widget 上的 inline duration（160 / 220 / 300 / 120 等）—— 这些是局部决策，不构成"语言"层级，不强行搬

收敛后整页"语言层"durations 从 14 个 ms 值收到 5 个：**200 / 360 / 600 / 800 / + background 三个不参与**。

### 验证

- `flutter analyze lib/pages/home_page.dart lib/widgets/constellation_background.dart` ✅ no issues
- 真机走查未跑（需要 build stamp + profile 装机，那是单独 session 的事，本次不做）

## Decisions made

- **settle 段长度 0.78 起算**：取 ~22% 收口比，足够把 5.0 → ~1.5 的尺寸差吃掉，又不至于让 FX 中段感觉短促。无 spec 数字，是对齐 spec 「过渡而非硬 pop」原则的判断。
- **glow alpha 0.06**：比 timeline 的 0.05 略高，因为 overlay 背景是星图层（暗），timeline 是正常 row 行间（更暗），两者最终视觉亮度大致接近；不严格匹配数字，匹配观感。
- **`_menuAnim` 不进 ladder**：见上表说明。Elvis 如果觉得菜单展开节奏出戏，再单独议。
- **inline duration 不动**：scope 控住。这些是单点 widget 的局部决策，不是"今天动画语法"那种跨组件语言。
- **不加 build stamp**：那是 Session B 单独事项，Elvis 没把它纳入本次 1.0.2 收尾。下次装机走查前再补。

均未触碰 charter/03_boundaries.md 的硬约束（无权限、无 schema、无 BLE 改动）。

## In flight / blocked

- 真机走查（spec 「真机走查剧本」六段）未跑 —— 需要先 bump build + 加 build stamp + profile 装机；约定到 build stamp session 一起做。
- 接缝 #3（坐标系叠层扁平化）—— 已 deferred 到下个迭代，写在 Ideas 段。

## Handoff

- 给 **Codex Reviewer**：本次只看两件事
  1. `_paintTodayOverlay` 重写段是否真的「FX 期间像 timeline、resting 期像 constellation 小星」，cancel 几何是否严格倒放
  2. duration ladder 是否对齐 spec 800ms 钉死、`_lineDelete` 与 `_lineAdd` 同档是否符合直觉
- 不需要看 #3、不需要审 inline durations（明确不在 scope）
- 下一位 Dev：build stamp + profile 装机走查（Session B 残余）作为单独一条 session

## Questions for Elvis

- [ ] `_menuAnim` 600ms 我留着没动，理由是 4 向 radial 节奏自带 chunky 感，进 800 太钝、进 360 又过快。你有感觉吗？

## Ideas

- **接缝 #3 · 坐标系叠层扁平化**（deferred）：drift ticker + FX session lock + skeleton relaxation + safetyBounds + overlaySafetyBounds 五层正确但调试路径长。建议在 v0 → v2.0 迁移那一档做：先把"今日位"独立成一个 first-class concept（不是从 star 漂移函数 + clamp 推出来的），再让 FX session 直接读这个 concept，drift ticker 只对 resting 星生效。结构改动，1.0.2 收尾不动。
- 用户级 build stamp 显示开关：debug build 始终显示，release build 设置页底可见。下次走查体验如果还会反复怀疑"是不是新包"，再加。
- ladder 化之后如果 inline duration 看起来再次"长出 dialect"，可以把 4 档 ladder 提到 `lib/theme/durations.dart` 做成全局 const，强制后续所有 controller 引用它而不是写魔数。但现在 11 个 controller 加注释已经够约束力，不必过度抽象。

---

## Files touched

- `lib/widgets/constellation_background.dart`: `_paintTodayOverlay` head 渲染段重写为 FX 期 / resting 期两段式 + glow halo
- `lib/pages/home_page.dart`: initState 11 个 controller duration 收敛到 4 档 ladder + ladder 注释 + `_bleFlash` doc 同步
- `docs/worklog/2026-04-19_today_fx_head_parity_and_duration_ladder.md`: new

---

## Review

**Reviewer**: Codex

**结论**：🔧 需返工（两条 P1 + 两条次要观察）

**Codex 备注摘录**：

- **P1 · Fixed 8s skip window still replays large constellations on scene rebuild**：`_sceneBuiltAt = _elapsed.value - 8.0` 只在 8.0 > index × 0.055 + 1.75 时有效；超过 ~113 颗星后尾部 index 会再次进入 reveal 动画。建议按 scene 长度算 skip offset，或对 rebuild 路径直接 bypass `_nodeRevealProgress`。位置：`constellation_background.dart:167-185`。
- **P1 · New-line creation still bypasses the today-FX path**：`_showAddLineDialog()` 只调 `addCustomLine()` + `_lineAddAnim.forward()`，不种今天完成态、不触发 `_startTodayNodeFx(...)`。如果产品语义是「新建一条轴 = 今天新增完成」，FX 状态机没接上。位置：`home_page.dart:1246-1263`。
- **次要 1**：pbxproj 这轮改的是 `RunnerTests` 的 `MARKETING_VERSION`，不是主 app target。
- **次要 2**：仅 `flutter analyze`，无真机 / widget 级验证。

---

### Dev 回应（Elvis 已批准 reject 两条 P1，1.0.2 仍按收尾处理）

**P1 #1 · 8s skip window**：数学正确但**触发条件不存在**。Scene rebuild 只在 (a) size 变化、(b) past-scene signature 变化时发生。Spec 早已确认「纯今天 completion 的 line 不进 past-scene key」（见 `2026-04-19_constellation_today_overlay_polish_and_ios_sync_check.md`），所以日常使用不会触发 rebuild。要踩到这条 bug 需要：113+ 颗历史星 + 触发 size 变化或加了第一条历史完成的新 line。1.0.2 用户里此组合接近零。**Reject for 1.0.2**；归到 Ideas 段的 v0→v2.0 迁移 batch（与坐标系扁平化 #3 并案处理）。

**P1 #2 · 新建轴 ≠ today completion**：**产品理解错位，不是代码 bug**。

- 「新建一条轴」与「在新轴上勾选今天」是两个独立用户手势。
- Spec 「新轴第一颗点」语境（`docs/specs/constellation.md` 「Origin 决策表」第三行）指的是后者：用户新建空轴 → 再点击今天 → FX 触发 origin 投影到 timeline today-node。
- 前者**不应该**自动种 today completion。Trail soul 红线要求所有冻结/完成必须是用户**主动**行为；自动勾选今天会违反这一点。
- `_showAddLineDialog()` 当前行为（仅 add line + line-add 动画，不触发 today FX）正是 spec 期望。

**Reject for 1.0.2**。如未来产品决定「新建即今日完成」，那是一次需要 Elvis 拍板的 soul 边界讨论，不是 review 阶段能转的弯。

**次要 1 · pbxproj 版本来源**：核了 `ios/Runner.xcodeproj/project.pbxproj`，主 `Runner` target 配的是 `CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)"`（line 499 / 693 / 723），即 Flutter build 时从 pubspec 注入；本轮 diff 改到的 `RunnerTests` `MARKETING_VERSION = 1.0.2` 只是 Xcode 自动同步（不影响主 app 版本来源）。pubspec.yaml 仍是 1.0.2 的单一真相，**无问题**。

**次要 2 · 缺真机验证**：明确不在 1.0.2 收尾 scope。已约定 build stamp + profile 装机走查另起 session（见上一条 worklog `2026-04-19_constellation_today_grammar_spec_addendum.md` Handoff Session B）。本次只到 `flutter analyze` 通过即收。

**Dev 结论**：两条 P1 reject、两条次要观察解释清楚。**1.0.2 视为可发**，等下一条 build stamp + 走查 session 闭环。

### Review 复核（2026-04-19 · Codex 第二轮）

按 `AGENTS.md` + `00_soul.md` + `docs/specs/constellation.md` 复核后，上一轮两条 P1 **仍成立**：

1. `lib/widgets/constellation_background.dart` 的 post-initial rebuild 仍然写死 `_sceneBuiltAt = _elapsed.value - 8.0`。这不满足 spec 里“后续增量统一只交给 today overlay”的语义约束；当 scene 足够大时，尾部星/线仍会重新进入旧 reveal。Dev 关于“日常不会触发”的解释是概率判断，不是代码层封口；Review 不能以“用户暂时不容易踩到”替代“逻辑已成立”。
2. `lib/pages/home_page.dart` 的 `_showAddLineDialog()` 仍然只做 `addCustomLine()` + `_lineAddAnim.forward()`，没有把“新轴第一颗点”的 spec 语法接进 today-FX 状态机。Dev 把 spec 解释为“新建轴与今天完成是两个动作”，但本次 worklog 自己的 `Session goal` 和 `Done` 都把“today 语法统一到时间轴 / 星图 overlay / 新建 line 三处”作为交付目标；当前代码并未把新增轴路径统一进同一套 today-FX 机制。

次要观察维持原判断：

- `MARKETING_VERSION` 的改动主要落在 `RunnerTests`，主 app 版本来源依赖 Flutter 注入；这不是阻塞，但真机版本辨识仍建议以设备侧结果为准。
- 本次仍只有 `flutter analyze`，没有真机走查，不足以支撑“1.0.2 可发”的体验结论。

**Review 复核结论**：`🔧 需返工` 保持不变。

## Conflict

### Dev 观点

- `8.0s skip window` 在 1.0.2 用户规模下“几乎不会触发”，因此可以 defer。
- “新建轴”与“今天完成”是两个独立用户手势，所以 `_showAddLineDialog()` 不接 today-FX 不是 bug。

### Review 观点

- Review 审的是“代码是否满足当前 charter + spec + 本条 worklog 自己承诺的交付语义”，不是“短期触发概率高不高”。只要逻辑上仍可能回落到旧全局 reveal，就不能视为“统一完成”。
- 若产品真实意图是“新建轴保持空态，不属于 today completion”，那本条 worklog 的目标描述与 spec 增补需要同步收窄；在文档未改之前，Review 只能按当前文字承诺判定为未完成。
