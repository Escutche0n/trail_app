# 2026-04-18 — constellation_v0_static_render

**Agent**: Dev (Claude Opus 4.7)
**Session goal**: 给主界面加一个最小可视的星图背景层——把所有"今日以前、已完成"的节点作为静态星点渲染到 alive 轴之上的顶部区域。不引入 freeze 机制，不改数据 schema。

---

## Context

上一条 session [ios_privacy_manifest_rework](./2026-04-18_ios_privacy_manifest_rework.md) 已通过 Review，R0 iOS 第 1 项（PrivacyInfo）收口。本次 Elvis 指定方向转到星图——想"看得到变化"。

现状：
- `specs/constellation.md` 和 `specs/freeze.md` 都标注"设计完成，待 v2.0 实现"
- `lib/` 里没有 freeze 概念，也没有 `Star` / `Constellation` 相关代码
- `TrailNode` 状态只有 `completed / incomplete / today / future`

与 Elvis 对齐后方向收窄为**方案 A（最小可视原型）**：
- 不引入 freeze 机制、不改 schema、不改 `TrailNode` enum
- 数据源 = 现有所有已完成节点（alive 线打卡 + 所有未归档 custom 线的 `completedDates`）
- 粒度 = 每个 `(lineId, dateKey)` = 一颗星（Elvis 明确拍板）
- 层级 = **背景装饰**：插在 `AltoBackground` 之后、时间轴 `CustomPaint` 之前（时间轴线会穿过星，符合 spec"背景层"定位）

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_ios_privacy_manifest_rework.md ✅
- docs/worklog/2026-04-18_ios_r0_build_validation.md ✅
- docs/specs/constellation.md ✅
- docs/specs/freeze.md ✅
- lib/widgets/trail_node.dart ✅
- lib/models/trail_line.dart ✅
- lib/pages/home_page.dart（结构扫描 + 插入点定位）✅
- lib/services/storage_service.dart（确认 `getCustomLines()` 已过滤 archived）✅

## Done

- 新文件 `lib/widgets/constellation_background.dart`：
  - `ConstellationBackground` StatelessWidget + `_ConstellationPainter`
  - `IgnorePointer` 包裹 — 不吃触控，不破坏现有手势层
  - 画布区域：`[mediaPad.top + 8, aliveYpx - 24]`，左右内边距 16px
  - 坐标规则（v0 简化版，偏离 spec 的极坐标）：
    - `hash = FNV-1a(lineId|dateKey)`（32-bit 确定性哈希，跨平台稳定）
    - `x ← hash[0:16]`、`y ← hash[16:32]` 映射到画布矩形
    - 亮度 alpha ∈ [0.35, 0.80] 由 `hash[8:16]` 决定
    - 半径 ∈ [0.7, 1.6]px 由 `hash[24:32]` 决定
  - 过滤：`dateKey < todayKey`（字符串比较，ISO `YYYY-MM-DD` 可用），今日/未来节点不落星
  - 纯静态绘制，无动画、无闪烁、无连线
- `lib/pages/home_page.dart`：
  - import 新 widget
  - 在主 Stack 中 `AltoBackground` 之后、时间轴 `_buildGestureLayer` 之前插入 `Positioned.fill(child: ConstellationBackground(...))`，数据来自现有的 `_aliveCheckIns` / `_customLines` / `_today` / `mediaPad.top` / `aliveYpx`

- `flutter analyze lib/widgets/constellation_background.dart lib/pages/home_page.dart`：No issues found

## Decisions made

1. **坐标规则偏离 spec**：spec 要求极坐标（angle + radius），但本次画布是"顶部矩形条带"（高约 vh\*0.33），极坐标在矩形里会产生视觉中心聚集 + 四角稀疏，不合适。v0 改用直接二维 hash 映射，均匀分布于矩形。理由：spec 里极坐标是围绕"中心化星图"设计的，和当前"仅 alive 轴上方的背景"的用途错位。注：若未来星图真的铺满整屏，需要回到极坐标。
2. **不做连线**：spec 方案 B 要按时间顺序链式连曲线。v0 先只点，理由：连线需要引入整条曲线重算 + 跨线排序，且和现有时间轴线在视觉上会打架（都是白色曲线）。先交付"看得到过去在长"这一信号，连线下一个 session 再评估。
3. **不做交互**：IgnorePointer 包裹，长按/双击都留给后续 session（也还没有 overlay 表存储命名/备注的地方）。
4. **不区分 alive / custom / friend**：spec 要求朋友星集中在扇形区，但 `friend_encounter` 事件源（BLE）目前没有星图所需的数据格式（`pairId` 还没落到持久化里）。v0 只渲染 alive + custom 的完成节点。
5. **archived 线不渲染**：`_customLines` 已由 `getCustomLines()` 过滤掉 archived 线。与用户在主时间轴上看到的集合保持一致。
6. **哈希选 FNV-1a 32-bit**：spec 写的是 SHA-256，但 v0 完全不需要密码学强度——我们只要"稳定、均匀、跨平台一致"。FNV-1a 零依赖、一次遍历、Dart 原生。未来若要和 overlay 表 starId 对齐，再切到 SHA-256。

charter/03 的"必须停下来问"清单覆盖情况（v0 阶段）：
- 未加三方依赖
- 未改权限声明 / Info.plist / entitlements / AndroidManifest
- 未改 Hive schema
- 未改 BLE payload
- 未改 TimeIntegrityService
- **charter 本次有改**：v1 阶段触发了 soul #11 例外条款的新增；在向 Elvis 明确提示冲突并由其选 "b 永久改" 后落地。详见下方 "v1 增补 · soul / spec 变更" 段。

## In flight / blocked

无。v0 可交付。

## Handoff

下一次最合理的动作（按优先级）：

1. **跑一次真机 / 模拟器**确认视觉落位：星点是否太小/太亮、是否盖到 Header、是否和时间轴线打架。本次只做了静态分析，没做视觉验证。
2. **决策是否加链式连线**（spec 方案 B）。决定前先看看裸点的效果——可能 v2.0 就不需要连线。
3. **决策是否引入 freeze 机制**（spec `freeze.md`）。当前"每个完成节点 = 一颗星"和 spec 的"每次主动 freeze = 一颗星"不是一回事。如果未来要走 freeze 路线，本次的数据源会被整个替换，但 `ConstellationBackground` 的渲染层可以保留。
4. **Open Questions**（constellation.md 里的）仍未解：画布高度 / 扇形宽度 / 命名备注上线时机。

## Questions for Elvis

- [ ] 模拟器跑起来后视觉如何？若星点太弱/太散/太亮，告诉我要往哪调（下一轮改默认 alpha / radius / 画布 padding 一行搞定）。
- [ ] 本次偏离了 spec 的极坐标 + 连线规则（理由见 Decisions made 1/2），这是 v0 的务实选择。如果你希望 v0 就严格按 spec 走，告诉我——那会是另一个 session。

## Ideas

- 现在星点"出现时机" = 某天的线被勾了 **且** 跨过午夜变成"过去"。这个"第二天一打开 app 顶部多出几颗新星"的感觉可能比 freeze 机制还更贴合 soul 的"克制"气质——值得观察一段时间再决定是否引入 freeze。
- 如果未来要加 LOD（spec 提到 2000+ 颗触发），当前的 FNV-1a + 单次 loop 在 1000 颗规模下应该还很轻，不用急。
- 亮度/尺寸目前与 hash 绑定，导致每颗星"永远一个样"。spec 里朋友星有慢闪——如果未来引入朋友星，再用一个共享 `AnimationController` 驱动 phase（spec 架构里明确写过），当前静态层保持不动即可。

---

## v1 增补（同一 session · Elvis 反馈后）

**触发**：v0 装机后 Elvis 反馈三点：(1) 星点有明显聚团感 (2) 需要一根实心连线 (3) 完全静止看起来像坏点，希望轻微移动。

**soul / spec 变更**（Elvis 明确选 "b 永久改"）：

- `docs/charter/00_soul.md` #11：加上星图例外条款——星点允许极缓慢亮度呼吸（周期 ≥ 6s，振幅 ≤ 0.4，相位随机，不改位置 / 颜色）。连线、其他 UI 元素不在例外内。
- `docs/specs/constellation.md` 动画规则表：冻结星与朋友星共用一条 "平时慢呼吸" 规则（6–10s）；禁止列表中移除"呼吸动画"（限定为"连线呼吸禁止"）。

**代码变更**（`lib/widgets/constellation_background.dart` 重写）：

1. **哈希升级**：从单次 FNV-1a 改为 "带 salt 前缀 + 额外 avalanche（Murmur3 finalizer 风格 xor/mul 三轮）"。`x / y / alpha / period / phase / radius` 每项独立 salt 哈希，消除短 ISO 日期串输入下的相关性聚团。
2. **画布底部延伸**：底部 margin 从 24px 收到 2px，紧贴 alive 轴，让连线可与时间轴视觉上形成延续。
3. **链式连线**：按 `(dateKey, lineId)` 排序全部星，midpoint quadratic bezier smoothing，单根白色实心线，`strokeWidth 0.7`，`alpha 0.18`（压到最弱以免抢主时间轴的注意力）。
4. **星点呼吸**：`SingleTickerProviderStateMixin` + `Ticker` 驱动 `ValueNotifier<double> elapsed`，painter `super(repaint: elapsed)` 每帧重绘。每颗星 alpha = `baseAlpha + sin(2π * (t/period) + phase) * ampAlpha`，数值范围均严格符合 soul 例外上限（周期 6–10s，振幅 ≤ 0.30，baseAlpha 0.45–0.85）。
5. **`RepaintBoundary` 包裹**：把每帧重绘圈在星图层内，不波及外层时间轴 CustomPaint。

`flutter analyze` 两文件均 `No issues found`。

**Decisions made (v1)**：

- **连线 alpha 0.18 / stroke 0.7px**：比 spec 方案 B 的 0.35/0.22/0.12 三段衰减更克制。v1 先统一一个弱值，等视觉验证后再决定是否分段衰减——过度设计的风险大于收益。
- **仍不做朋友星差异化**：朋友星 spec 里周期是 3–5s，比普通星更快。v1 无 BLE 数据源，全体共用 6–10s。
- **排序键 (dateKey, lineId)**：同一天多条线的星按 lineId 字典序前后相连，保证跨会话稳定。未来引入 `birthTime` 精度或 freeze 时间戳时再升级。

**v1.1 追加（Elvis 反馈链式后）**：
- 把"单根贯穿全部星"改为"每条 trail 线一条独立星链"。按 `lineId` 分组，组内按 `dateKey` 排序，midpoint quadratic smoothing 逐组成链。视觉上每条线在天上有自己独立的轨迹，不跨线互连。

**v1.2 追加（Elvis 反馈"星座感" + 底部范围）**：
- `home_page.dart` 里 `bottomY` 从 `aliveYpx` 改为 `aliveYpx - 96`，与 inline header 的"暂居天数"文本上沿齐平（header 占 [aliveY-92, aliveY-44]）。底部不再压到 Header 三行文字。
- 星点尺寸从 `0.8..1.8` 扩到 `0.6..3.4`，用三次方分布（`0.6 + u³ * 2.8`）——绝大多数仍是小点，少数显著大。更像真实星空的尺寸重尾分布。
- 亮度与尺寸正相关：大星更亮更稳（baseAlpha 高 / ampAlpha 低），小星更暗变化更明显（ampAlpha 到 0.35，仍 ≤ soul 上限 0.4）。
- **位置仍静止**：Elvis 原话"缓缓移动"按"亮度呼吸 + 尺寸差异"解读，位置飘移会撞刚立的 soul #11 例外条款"不改位置"。若未来要字面位移需再开一次 soul 讨论。

**v1.3 追加（Elvis 参考 Swatch Sistem51 表盘星座视觉）**：
- 连线改为虚线直线段：dash 3px on / 3px off，alpha 0.22。去掉 midpoint quadratic smoothing。
- 星链拓扑不变（每条 trail 线独立一条）。视觉从"流畅轨迹"切到"星图标注连线"。
- 未采用参考图中的同心圆 + 径向辐条（装饰过重、与现有 alive 轴结构冲突）和红点（撞 soul #12 极简黑白）。

**封盘**：Elvis 确认 v1.3 效果后转向朋友节点设计——另开 session，本 log 待 Review。

**Files touched (v1 追加)**：

- `docs/charter/00_soul.md`: edited（#11 加例外）
- `docs/specs/constellation.md`: edited（动画表 + 禁止项）
- `lib/widgets/constellation_background.dart`: 重写（Stateful + Ticker + 链式连线 + 新哈希）

---

## Files touched

- `lib/widgets/constellation_background.dart`: new → 重写
- `lib/pages/home_page.dart`: +11 -0（import 1 行 + Stack 插入 10 行）
- `docs/charter/00_soul.md`: edited（#11 星图例外）
- `docs/specs/constellation.md`: edited（动画规则 + 禁止项）
- `docs/worklog/2026-04-18_constellation_v0_static_render.md`: new

---

## Review

**结论**：🔧 需返工

**问题**：

1. `docs/specs/constellation.md` 仍把星图定义为 `freeze + BLE encounter` 推导出来的系统，并要求"所有星按诞生时间顺序连成一条曲线，今日节点是最新端点"（见 spec 第 35-37、91-93 行）。但当前实现实际从 `aliveCheckIns + customLines.completedDates` 取数，并在 [`lib/widgets/constellation_background.dart`](/Users/elvischen/Developer/trail/trail_app/lib/widgets/constellation_background.dart:192) 和 [`lib/widgets/constellation_background.dart`](/Users/elvischen/Developer/trail/trail_app/lib/widgets/constellation_background.dart:199) 按 `lineId` 分组画多条虚线链，也没有把今日节点接入链尾。按 AGENTS 的约定，仓库文档才是权威；既然 Elvis 已经把方向改成 v0 原型，就需要把 spec 同步成当前真实规则，或者把代码收回到现有 spec。

2. spec 的渲染架构明确要求"静态部分 cache 为 Picture，动画层单独承载动态部分"并给出 1000 星 / SE2 的性能目标（spec 第 121-130 行）。当前 `ConstellationBackground` 用常驻 `Ticker` 驱动整层 `CustomPaint`，且 `paint()` 每帧都会重新组装 `stars`、重排 `byLine`、重画全部虚线段（[`lib/widgets/constellation_background.dart`](/Users/elvischen/Developer/trail/trail_app/lib/widgets/constellation_background.dart:47), [`lib/widgets/constellation_background.dart`](/Users/elvischen/Developer/trail/trail_app/lib/widgets/constellation_background.dart:160), [`lib/widgets/constellation_background.dart`](/Users/elvischen/Developer/trail/trail_app/lib/widgets/constellation_background.dart:199)）。`RepaintBoundary` 只能隔离外层，不等于满足 spec 的分层和缓存要求；在星数增长后这部分风险会直接落到主界面常驻帧循环上。

3. worklog 自身记录不一致：前半段写"未动 charter"（第 65-71 行），但同一篇 log 后半段和 `Files touched` 又明确写了 `docs/charter/00_soul.md` 已修改（第 103-106、142、152 行）。Review 需要能靠 log 在 30 秒内判断边界是否被触碰；这里必须改成一致表述，至少明确这是 Elvis 当场拍板的 charter 变更，而不是"未动 charter"。

**备注**：
- 本次问题主要在文档对齐和渲染架构，没有要求你重写视觉方案本身。

---

## Rework 响应（2026-04-18 · 同一 session）

针对 Review 三点逐条处理：

1. **Spec ↔ 代码对齐**：在 `docs/specs/constellation.md` 顶部新增 "v0 实现现状（权威）" 段，显式列出 v0 与 v2.0 目标设计的五处偏离（事件源 / 坐标 / 连线 / 哈希 / 无 overlay），声明下文保留的设计段为 v2.0 目标，不是当前代码行为。文档现在与 `lib/widgets/constellation_background.dart` 的实际规则一一对应。状态标签从 "设计完成，待 v2.0 实现" 改为 "v0 原型已上线，与 v2.0 完整设计显式偏离"。

2. **渲染分层 + 缓存**：重构 `lib/widgets/constellation_background.dart`：
   - 把 `stars` 列表和静态虚线链抽到 `_ConstellationBackgroundState` 的缓存字段（`_stars`, `_linesPicture`, `_cachedSize`）
   - `didUpdateWidget` 比较输入数据 / 几何，变化时清缓存；paint 里 lazy 重建一次
   - 静态虚线段一次性 rasterize 成 `ui.Picture`，后续每帧只 `canvas.drawPicture` 贴回
   - 每帧 Ticker 驱动的部分**只剩**逐颗星的 alpha 呼吸绘制
   - 与 spec 第 121-130 行 "静态部分 cache 为 Picture / 动画层单独承载动态部分" 对齐
   - 未做 LOD（2000 星触发），当前规模远未到，下次必要时再加

3. **Worklog 一致性**：把"Decisions made"下的"均未触碰 charter/03 清单"表述改为显式说明 v1 阶段触发了 soul #11 例外条款的修改，并由 Elvis 明确选 "b 永久改" 后落地；Review 扫一眼就能看到 charter 变更而不是两个段落打架。

`flutter analyze` clean（仅遗留 `friend.dart:84` 的 pre-existing doc comment info）。

**Files touched (rework)**：

- `docs/specs/constellation.md`: 新增顶部 v0 现状段 + 改状态标签
- `lib/widgets/constellation_background.dart`: 重构为缓存 + 分层
- `docs/worklog/2026-04-18_constellation_v0_static_render.md`: charter 表述改为一致
