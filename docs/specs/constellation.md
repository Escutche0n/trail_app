# 星图 (Constellation)

> 状态：**v0 原型已上线**（2026-04-18），与下文 v2.0 完整设计存在显式偏离，见本文顶部"v0 实现现状"段
> 依赖：`specs/freeze.md`（冻结机制，v2.0）+ `specs/ble_friends.md`（BLE 相遇事件，v2.0）

---

## v0 实现现状（权威 · 与代码对齐）

代码入口：`lib/widgets/constellation_background.dart`

v0 是在 freeze 机制上线之前的最小可视原型。与下文 v2.0 完整设计的显式偏离：

1. **事件源**：v0 直接用 `aliveCheckIns + customLines[].completedDates` 里"严格早于今日"的完成记录作为星的来源——不是 `frozenDates / bleEncounters`。粒度：每个 `(lineId, dateKey)` = 一颗星。朋友星未启用。
2. **坐标规则**：v0 使用"salt 前缀 FNV-1a + Murmur3 风格 finalizer"的哈希把 `(lineId|dateKey)` 映射到矩形画布内的二维坐标，而不是 v2.0 的极坐标（angle + radius）。理由：v0 画布是 alive 轴之上的"顶部矩形条带"，极坐标在矩形里会中心聚集 + 四角稀疏。未来若画布真的铺满整屏，再切回极坐标。
3. **连线规则**：v0 **不**走"全局按诞生顺序一条曲线"；而是按 `lineId` 分组，**每条 trail 线一条独立虚线链**，组内按 `dateKey` 排序，直线段 3px-on / 3px-off 虚线，alpha 0.22。视觉上每条线在天上有自己独立的轨迹。今日节点不接入链尾。
4. **哈希强度**：v0 用 FNV-1a 32-bit + 一轮 Murmur3 finalizer，不是 SHA-256。v0 只要"稳定、均匀、跨平台一致"，不需要密码学强度。未来若要和 overlay 表 starId 对齐，再切到 SHA-256。
5. **无 overlay 表 / 无 freeze / 无朋友星**：v0 不落地任何星图专用持久化，也不渲染朋友星。
6. **历史分层**：v0 按时间衰减分三层渲染。
   - `0-30` 天：主层，承担当前骨架与今天增量语法。
   - `30-60` 天：过渡层，更暗更小，弱运动，不参与骨架连线。
   - `60+` 天：远景层，固定散落为极弱背景星，不参与骨架与 reveal。

v0 与 v2.0 共用的部分：

- 位置：主界面 alive 轴之上的背景层；`IgnorePointer` 包裹，不吃手势
- 星点保留稳定实心存在；允许极慢的背景级漂移与亮度呼吸
- 连线只负责勾出骨架，不要求把所有星点都绑进网络
- 不加独立入口 / 不显示总数 / 不做攒星解锁

v0 渲染架构（为满足"不拖累主帧"目标）：

- 每当输入数据（`aliveCheckIns / customLines / bottomY / topInset`）变化时，重算背景星点 + 星座骨架模板映射
- 每帧 Ticker 驱动极慢漂移：骨架星与背景星都轻微移动，但只有骨架参与连线
- `RepaintBoundary` 把重绘限制在星图层，不波及时间轴

v0 → v2.0 迁移计划（暂定）：

- 引入 `frozenDates` 和 `bleEncounters` 事件源后，`ConstellationBackground` 的数据输入替换；渲染层保留
- 极坐标切换与否取决于画布最终形状
- 链式连线按 v2.0 方案 B 的"全局时间顺序 + 贝塞尔"升级前，先观察当前"每条线独立链"的用户感受

本段是 v0 的权威描述；下文"核心模型 / 坐标规则 / 连线规则"等段保留为 v2.0 目标设计，不是当前代码行为。

---

## 目标

让用户主动冻结的每一天和每一次朋友相遇，在**主界面上方的背景层**以星星的形式逐渐积累，按时间顺序用线连接成一副属于自己的星图。

---

## 非目标

- 不做独立星图页面（星图就是主界面的一部分）
- 不显示星星总数
- 不做"攒星解锁"的任何机制
- 不加常驻动画

---

## Soul 对齐检查

- ✅ 红线 #1-3（不做上线奖励 / 不显示总数 / 不做交易）：确定性推导，无货币行为
- ✅ 红线 #11（不做持续背景动画）：动画只出现在星诞生瞬间
- ✅ 红线 #14（星图推导式）：无独立落盘
- ✅ 气质"克制"：静默为默认，动为例外
- ✅ 气质"时间感"：星图随时间自然生长，无外部刺激

---

## 核心模型：推导式 + overlay 表

### 事件源（唯一持久化）
- `frozenDates: Set<DateTime>` — 主动冻结的日子
- `bleEncounters: List<{ date, friendHandle, pairId }>` — BLE 相遇记录

### 推导
```dart
Star deriveStar({required String cause, required DateTime date, String? friendHandle}) {
  final idInput = '$cause|${date.toIso8601String()}|${friendHandle ?? ""}';
  final starId = sha256(idInput).substring(0, 16);

  return Star(
    id: starId,
    birthDate: date,
    cause: cause, // 'freeze' | 'friend_encounter'
    coord: _coordFromHash(starId, cause, friendHandle),
    brightness: _brightnessFromHash(starId),
    flickers: cause == 'friend_encounter',
  );
}
```

### Overlay 表
```dart
// 仅存储用户主动添加的元数据
Map<String /* starId */, StarMeta> starMeta;

class StarMeta {
  String? name;
  String? note;
  DateTime createdAt;
}
```

底层事件丢失时 overlay 条目变成孤儿，UI 隐藏但数据保留（以防恢复）。

---

## 坐标规则

### 冻结星（cause = freeze）
- 坐标在整个星图画布中均匀分布
- `angle = hash(starId) % 360`
- `radius = (hash(starId) >> 8) % maxRadius`

### 朋友星（cause = friend_encounter）
- **同一朋友的所有相遇星集中在一个扇形区域**
- 每个朋友的扇形起始角 = `hash(pairId) % 360`
- 扇形宽度 = 30°
- 同一扇形内分布由 `hash(starId)` 决定

**效果**：用户使用久了会自然产生"Alex 在西南方 / Bob 在东北方"的空间化情感定位。

---

## 连线规则（方案 B：链式）

- 所有星星**按诞生时间顺序**依次连接成一条曲线
- 今日节点（主时间轴）是链的最新端点
- 线的渲染：贝塞尔曲线或低张力样条，避免直角感

### 线的视觉衰减
- 最近 7 天的线段：alpha 0.35
- 7-30 天：alpha 0.22
- 30+ 天：alpha 0.12
- 朋友星之间的连线颜色略偏暖（不是彩色，只是 warmth 上升）

---

## 动画规则（严格）

| 场景 | 动画 |
|---|---|
| **平时 · 连线** | 连线完全静止。零动画。 |
| **平时 · 星点（冻结 / 朋友星共用）** | alpha 在基线附近 easeInOut 缓慢明灭，周期 6–10 秒，**每颗星相位随机化**，振幅 ≤ 0.4，位置 / 颜色不变。避免"坏点"误读。与 soul #11 例外条款对齐。 |
| **刚冻结的瞬间** | 新星从今日节点位置点亮 → 沿新画出的线段升到它的坐标 → 停住。800ms，easeOutCubic。 |
| **刚 BLE 相遇的瞬间** | 新朋友星出现时闪烁一次（alpha 1.0 → 0.4 → 0.9，600ms），之后汇入常驻呼吸（周期更短，3-5 秒，以区分"新鲜"感）。 |
| **所有其他时刻** | 不动。 |

**禁止**：粒子流、常驻发光光晕、滚动视差、颜色渐变、连线呼吸。
（冻结星的亮度呼吸已由 soul #11 例外条款显式允许，不在本禁止列表。）

---

## 今天增量语法（Dev 增补 · 2026-04-19 · Elvis 已确认）

> 背景：截至 2026-04-19，"今天新增 / 取消"已经在时间轴、星图 overlay、新建 line 三处各自打过补丁。堆到一起观感像三种口音。本节把这三处统一成同一套语法，作为后续代码对齐的唯一真相。本节不改 soul，也不替代 v2.0 的连线规则；仅统一"今天这一天发生变化时，画面如何响应"。

### 唯一动词

今天的每一次变化，只有一个动作：**从一个明确的 origin 擦入到一个明确的 anchor**。取消 = 严格几何倒放，沿同一根路径回收，**不引入另一条动画**。

- 共享 controller：`_todayNodeLinkAnim`（已就位）。
- 正向曲线：`easeOutCubic`。倒放曲线：`easeInCubic`。时长：800ms，不因场景浮动。
- 头部形态：时间轴与星图 overlay 共用 **"today 级节点大小"的实心点**。不在某一层用大头、另一层用小点。
- 终态归属：动画只负责"过程态的头部"；终态由基础 painter 承担。今天星点在 FX 结束后以常驻 overlay 形式留存，**不是**"画完再淡出"。

### Origin 决策表

| 场景 | Origin | Anchor |
|---|---|---|
| 已有轴 · 昨日连续 · 今天新增 | 昨日同 line 老星 | 今日位（同 line 受控偏移） |
| 已有轴 · 中间断档 · 今天新增 | 最近一颗同 line 老星 | 今日位 |
| 新轴 · 第一颗点（该 line 在星图里还没有任何历史星） | **该 line 的 anchor 星位置**（line 创建时即已落在星图 donut 区域，详见下节） | bridge target 附近的今日位（见下节） |
| 任意场景 · 今天取消 | 当前 anchor | 当前 origin |

关键点：

- `_graphCenter` **不再**作为兜底 origin。"中心"在语义上不属于任何事件。
- Origin 在一次 FX session 内**锁定**：FX 启动时读一次坐标，整个 FX 持续期内不再跟随星图漂移 ticker；FX 结束后该星点才重新归入常驻漂移计算。这既修掉"起点随漂移微动"的 overlay 遗留，也让"新轴第一颗点来自 anchor 星"的语义可成立。
- **2026-04-19 第二轮 Dev 修订（Elvis 走查后确认）**：新轴第一颗点的 origin 由"timeline today-node 投影"改为"line 自带的 anchor 星"。理由：投影方案下新点从屏幕外/底部冒出来，缺少"这条 lineage 在画面里属于哪儿"的空间锚定；anchor 方案在 line 创建时即在星图里占位，第一次完成时桥接到一颗较远的存量星，画面有"起点 → 桥 → 落点"三段语义。详见下文"Anchor 星"节。

### Anchor 星（2026-04-19 第二轮 Dev 增补 · Elvis 已确认）

> Anchor 星 = 一条 custom line 在星图里的"占位星"。出现时机：line 被创建（哪怕今天还没完成）。消失时机：该 line 已经至少有一天过去完成 → anchor 让位给真实的 past 星。

- **位置约束（donut）**：避开外圈 15% 像素（上下左右四边各 15%）+ 避开中间 15% 横带 + 底部至少留 ≈3 行日期（66dp）。位置在 donut 区域内 hash 决定（`hash(lineId)`），全局均匀分布，不按 lineId 分扇形。
- **数据形态**：anchor 不是真实的事件星，使用 sentinel `dateKey = '__anchor__'`（lex 大于任意 `YYYY-MM-DD`），自然被"找最近一颗 past 星"的查询过滤。不落任何持久化。
- **视觉权重**：基础 alpha 略高于普通骨架星（0.62–0.72 区间），以保证它在 scene reveal 数组里排序靠前，能在首次 reveal 窗口内完整出现，避免"新建 line 之后 anchor 隔很久才显形"。
- **无连线**：anchor 星不参与骨架连线；它仅作为"今天第一次完成时的 origin"。
- **不入骨架**：anchor 星始终停留在主骨架外侧 ring 上，不能被抽进十二星座骨架模板里。
- **第一次今天完成的 anchor → bridge target → 今日点**：
  - **bridge target**：从全图非自身星里挑一颗与 anchor 距离 ≥ 100px 的星，按 `hash(lineId|todayKey)` 决定性挑选；候选不足时退化到最远者（小屏边界情况）。
  - **今日点位置**：bridge target 附近 + 8–20px 抖动。终态在 anchor 与 bridge target 之间形成一根明显较长的桥（视觉上比老轴的 100–180px 受控偏移更长）。
  - **anchor 命运**：今天完成那一刻起，这条 line 就有了真实 past（隔天滚动后），anchor 在下次 scene 重算时不再生成。
- **取消语义**：今天取消时，今日点沿同一根桥回收到 anchor，anchor 留在原位。
- **限制（v0 接受，记入 Open Questions）**：anchor 与"该 line 的第一颗 past 星"位置不连续——隔天滚动后，past 星位置由 `hash(lineId|firstPastDateKey)` 决定，与 anchor 位置不同。短期内会"今天看是 A 位，明天看是 B 位"。等真机走查后决定是否要把 anchor 位置 freeze 进 overlay 表。

### 力度层级

力度只通过"线长（天然变量）"和"一次性后续点缀"表达；**时长、曲线、路径几何不随档位变化**。

| 档 | 场景 | 力度表达 |
|---|---|---|
| 轻 | 连续天 · 同 line 相邻 | 桥接线短，head 单次落定，无后续 |
| 中 | 断档桥接 · 跨 N 天 | 同一根实线；仅在线中段压一个极淡的 dotted 中点（alpha ≤ 0.2）暗示"跨越"，无其它追加动画 |
| 重 | 新轴第一颗点（整条 lineage 诞生） | 擦入完成后，today 星点 **一次性** 半径呼吸：1.0× → 1.2× → 1.0×，600ms，easeOut，**仅此一次**；之后汇入常驻漂移 |

重档的"一次性呼吸"与 soul #11 例外条款的"常驻呼吸"不是同一回事——前者是事件标记（出生记号），后者是防"坏点误读"的背景级存在感。两者互不替代，也不叠加。

### 取消 = 严格几何倒放

- 今天取消 → today 星点 / bridge 沿同一根路径从 anchor 回收到 origin，最后在 origin 位消失。**不是**淡出。
- 新轴第一颗点被取消 → 星点沿"bridge target 附近的今日位 → anchor 星位置"回收，anchor 星本身留在原位。
- `_latestCheckedDayBeforeToday` 这类 painter 级查询必须同时服务于新增和取消两个方向，不能只为新增而写。

---

## 渲染架构

### 分层
1. **Background layer**：CustomPainter 渲染所有星点 + 连线
   - 静态部分 cache 为 `Picture`，每次数据变化才重绘
2. **Animation layer**：仅渲染正在诞生的星 + 朋友星闪烁
   - 用单一 `AnimationController` 驱动全部朋友星的 phase（每颗通过不同 offset 取值）
3. **Timeline layer**：现有的时间轴渲染在星图之上

### 性能目标
- 1000 颗星时仍保持 60fps
- 低端机（iPhone SE 2）≥ 50fps
- 星数超过 2000 时触发 LOD：远期星不绘制细节

---

## UI 决策

- **位置**：主界面的 `alive` 轴之上的整个区域（从顶部 SafeArea 到 `alive` 轴 Y）
- **星图不占用任何独立入口**。没有"查看星图"按钮。
- **2026-04-19 Dev 增补（Elvis 已确认）**：设置页新增"个性化"二级菜单，用户可关闭顶部星图；开启时，高度只提供离散档位 `紧凑 / 标准 / 开阔`，默认 `标准`。
- **2026-04-19 Dev 增补（Elvis 已确认 · 本次例外）**：背景层允许持续但极慢的点位/连线动画；此处按“背景动画好看优先”处理，不把它当作严格静态信息图。
- **2026-04-19 Dev 增补（Elvis 已确认）**：最终只连“骨架星”，骨架做成十二套抽象星座模板之一；剩余星点均匀分布为背景，不强行参与连线。
- **长按星星**：显示一个 ephemeral popup —— "2026-04-18 · 冻结" 或 "2026-05-02 · 与 Alex 相遇"
- **双击星星**：（未来）打开命名 / 备注 overlay
- **空状态**：没有星时，顶部区域就是纯黑。不放引导文案。用户会在第一次冻结后自然理解。

---

## Edge cases

- **时间篡改 tampered**：冻结被拒绝 → 无新星产生（正确行为）
- **用户删除了自己数据**：星图清空，overlay 表清空
- **某颗星的 overlay 条目存在但底层事件没了**：UI 隐藏该星，overlay 数据保留
- **同一天既冻结又 BLE 相遇**：产生两颗独立星（不同 cause）
- **星坐标碰撞**：hash 空间足够大基本不会碰撞；万一碰撞由绘制顺序决定，较新的盖在较旧的上面

---

## 真机走查剧本（Dev 增补 · 2026-04-19 · Elvis 已确认）

> 用法：不按单点 bug 验收，而是按"六段连起来看，像不像同一个人写的句子"判断。
> 前置条件：
>
> 1. `pubspec.yaml` build number 已 bump（当前 `1.0.2+3`）。
> 2. 设置页加上 build stamp（见上条 worklog TODO，尚未落地；下次 session 做）。
> 3. 用 `flutter run --profile` 或 `flutter build ipa --release` + 侧载装机，不走 debug attach。
> 4. 装前先卸载旧 app。

走查六段：

1. 从"昨天没任何勾选"的状态进入今天 → 勾一个已有轴 → 取消 → 再勾 → 勾一个有历史断档的轴 → 取消。观察：轻档 vs 中档的 dotted 中点是否分得清、倒放是否沿同一根线回到 origin。
2. 新建一条 custom line（今天新建 + 今天完成）→ 观察 anchor 星是否在 line 创建瞬间就在 donut 内出现；今天完成后，今日点是否从 anchor 桥接到一颗较远的存量星（桥明显比老轴的 100–180px 受控偏移更长）；擦入完成后是否出现一次性呼吸。
3. 新建一条 custom line + 不完成今天 → 观察顶部星图是否**有且仅有一颗 anchor 星**落在 donut 区域（不在外圈 15%、不在中间 15% 横带、不压日期 3 行），且无任何连线。
4. 同日连续勾多个轴（alive + 2 条 custom）→ 观察多个 FX 是否互不干扰、origin 是否各自锁定、头部是否不互相污染 Paint。
5. 勾 → 立刻取消 → 立刻再勾（打断动画）→ 观察中断衔接是否自然（会不会出现两个 head、origin 会不会错位）。
6. 朋友行（朋友星尚未接入星图数据模型）→ 仅验时间轴侧不崩。

判据：**不是"这一步有没有 bug"，而是"六段连起来，整段是不是一种语言"**。任一段给出"突兀""像另一个人写的"就算不过。

---

## 依赖

- `charter/02_architecture.md` - 星图推导规则
- `specs/freeze.md` - 冻结事件源
- `specs/ble_friends.md` - BLE 相遇事件源
- Flutter `CustomPainter`、`AnimationController`

---

## Open Questions（待 Elvis 决策）

- [ ] 朋友星扇形宽度 30° 是否合适？（可能需要 20° 避免扇形重叠）
- [ ] 命名 / 备注功能是否 2.0 上线，还是推迟到 2.1？

---

## 变更历史

- 2026-04-18: initial spec by Claude（基于与 Elvis 的对话）
- 2026-04-19: Dev 增补（Claude）——新增"今天增量语法"与"真机走查剧本"两节，统一时间轴 / 星图 overlay / 新建 line 三处的 today 增量语法。见 `docs/worklog/2026-04-19_constellation_today_grammar_spec_addendum.md`
- 2026-04-19（第二轮 · 真机走查后）：Dev 修订（Claude）——新轴第一颗点的 origin 由"timeline today-node 投影"改为"line 自带的 anchor 星"；新增"Anchor 星"小节（donut 位置约束 / sentinel dateKey / bridge target ≥ 100px / 视觉权重）；同步更新走查剧本第 2、3 段判据。覆盖前一条同日 spec 的对应描述。见 `docs/worklog/2026-04-19_constellation_anchor_stars_and_bridge_overhaul.md`
