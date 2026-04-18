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

v0 与 v2.0 共用的部分：

- 位置：主界面 alive 轴之上的背景层；`IgnorePointer` 包裹，不吃手势
- 星点 alpha 呼吸（soul #11 例外条款）：周期 6–10s，相位随机，振幅 ≤ 0.4，位置 / 颜色不变
- 连线完全静止
- 不加独立入口 / 不显示总数 / 不做攒星解锁

v0 渲染架构（为满足"不拖累主帧"目标）：

- 每当输入数据（`aliveCheckIns / customLines / bottomY / topInset`）变化时，**一次性**算出 `List<_Star>` 并把静态虚线段 rasterize 成一张 `ui.Picture` 缓存下来
- 每帧 Ticker 只驱动 `elapsed` → painter 重新绘制星点 alpha（`drawPicture` 把缓存好的连线一次贴上）
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

## 依赖

- `charter/02_architecture.md` - 星图推导规则
- `specs/freeze.md` - 冻结事件源
- `specs/ble_friends.md` - BLE 相遇事件源
- Flutter `CustomPainter`、`AnimationController`

---

## Open Questions（待 Elvis 决策）

- [ ] 星图画布高度具体是多少？（当前 alive 轴在 `vh * 0.40`，星图可用空间约 vh * 0.35）
- [ ] 朋友星扇形宽度 30° 是否合适？（可能需要 20° 避免扇形重叠）
- [ ] 命名 / 备注功能是否 2.0 上线，还是推迟到 2.1？

---

## 变更历史

- 2026-04-18: initial spec by Claude（基于与 Elvis 的对话）
