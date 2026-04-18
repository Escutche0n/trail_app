# 2026-04-18 — 好友：独立时间轴行 + BLE-gated 打卡

## 背景 / 动机
沿着星图 v1.3 封盘之后，Elvis 推动第二个大块功能：把好友从「单行聚合」改为「每人一行独立时间轴」，并用 BLE 距离判断来限制"今日对对方打卡"的动作。径向菜单（改名 / Unfriend）**显式推迟到下一个大版本**，本 session 不做。

## 需求（确认记录）
- (i) 每个好友独占一行，不合并（不是 aggregated）
- 未打卡节点用**空心 dash 圆**；今日若对方 BLE 在范围内（15s 新鲜度），点一下就填实
- 过去的打卡不可撤销（沿用其他 node 的"反游戏化"约束）
- 改名/Unfriend 继续走 `friend_discovery_page` 现有长按入口，径向菜单下版本再做
- BLE TTL 放宽到 20s（覆盖 15s 判断 + 一点余量）

## 改动清单

### 1. 模型 / 存储
- `lib/models/friend.dart`
  - 新增 `List<String> checkInDates`（dateKey `YYYY-MM-DD`）
  - Adapter 字段数 5 → 6，新增 field 5 读写；旧数据缺字段 → 空列表（向后兼容）
- `lib/core/secure_box_service.dart`
  - 备份导出/导入把 `checkInDates` 一并带上，避免本地 restore 后数据丢失

### 2. BLE
- `lib/core/ble_service.dart`
  - `_peerTtl`: 12s → 20s
  - 新增 `isPeerInRange(uid, {window: 15s})`：根据 `discoveredAt` 判断

### 3. UI / 绘制（`lib/pages/home_page.dart`）
- State: 用 `List<TrailLine> _friendLines` / `Map<String,Friend> _friendsById` / `Set<String> _friendLineIds` 替换旧的单条 `_friendTimelineLine`
- `_buildFriendLines()`：每位 confirmed 好友构造一条虚拟 `TrailLine`，id 形如 `__friend__<uid>`
- `_hitTestNode` 增加好友行扫描
- `_toggleNode` 新增好友分支：
  - 今日：BLE 不在范围 → `mediumImpact` 反馈，不动数据
  - 今日：在范围且未打卡 → 追加到 `checkInDates` 并 save
  - 过去：已打卡节点不可取消
- `_TimelinePainter`：
  - 字段 `friendLine` → `friendLines` + `friendLineIds`
  - paint 循环按 `customLines.length + j` 行位输出
  - `_paintRow` 新增 `isFriendRow` 参数；未打卡分支走 `_drawDashedHollowNode`
  - `_drawDashedHollowNode`：用 10 段 arc 交替可见/隐藏画虚线空心圆
  - `_bottomYForDay` / `shouldRepaint` 同步改造

## 验证
- `flutter analyze`：clean（只剩一个 `friend.dart:84` 的 pre-existing doc comment info）
- 手动 run 待 Elvis 在真机上验证（profile 模式之前已验证 runnable）

## 本 session **没做**（下次接着做）
- 好友节点的 2-角径向菜单（改名 alias / Unfriend）
- 径向菜单与现有 long-press 入口的合并/退役策略

## 边界与 soul 合规
- 无红点 / 无红色装饰（soul #12 OK）
- dash 圆、breathing 都是已有范畴，无新增动画红线突破
- 过去 check-in 不可撤销，维持「反游戏化」

## Review

**结论**：🔧 需返工

**问题**：

1. `lib/pages/home_page.dart` 里的朋友打卡现在完全依赖 `BleService.isPeerInRange()` 放行，但 `docs/specs/ble_friends.md` 的当前实现明确是“仅前台发现”，而代码里填充 `_seen` 的扫描入口只在 `friend_discovery_page` 启动，离开页面后就停止。结果是在正常主页使用路径里，`_seen` 大多为空，朋友今日节点会一直走 `mediumImpact` 早退，BLE-gated 打卡实际上不可用。

2. 本次需求里已经写明“改名 / Unfriend 继续走 `friend_discovery_page` 现有长按入口，径向菜单下版本再做”，但当前 `home_page` 把朋友行接入了通用 `_hitTestNode`，长按今日节点会直接落入现有 action menu。这个菜单的 `rename / note / archive` 都只认 custom line，落到朋友行上只会静默无效，既违背了本 session 的边界，也会给用户一个看得到但不能用的错误入口。

**备注**：
- 这次 review 只针对”好友独立行 + BLE-gated 打卡”这条 work unit。
- 当前工作树里星图层还有一条独立的性能问题，已在对应的 `constellation` worklog review 中单列，不在这里混写。

---

## Rework 响应（2026-04-18 · 同一 session）

针对 Review 两点处理：

1. **BLE 生命周期**：已向 Elvis 面列三个选项（A 常驻扫 / B 点按触发短窗口探测 / C 退回 discovery page 打卡），Elvis 选 **B**。实现：
   - 新增 `_HomePageState._probeFriendInRange(uid)` + 常量 `_friendProbeWindow = 4s`
   - 点今日朋友节点时：先查 `BleService.isPeerInRange()` 命中则直接写入；未命中则同时发起 `setDiscoverable(duration: 4s)` + `startScan(timeout: 4s)`，每 200ms 轮询一次 `isPeerInRange`
   - 发起探测瞬间落一个 `HapticService.actionMenuSelect` —— 告诉用户”听到了，正在找对方”，不抢成功时的 `checkInToggle` haptic
   - 4s 内若对方进入范围：照旧走 checkIn 写入 + bounce
   - 超时：`mediumImpact` 拒绝，不写入
   - `setDiscoverable` / `startScan` 内部都有自己的 Timer 做自动回收，probe 结束后不需要显式 stop
   - 理由：BLE spec 限定”仅前台发现”，方案 B 把 BLE 开销收敛到”用户真的按了那一下”——意图明确、电量友好、不扩散到所有主屏使用路径

2. **错误入口（friend 行长按落到 custom-line action menu）**：`_onLongPressStart` 里显式短路朋友行——不打开 action menu、不给 haptic。改名 / Unfriend 径向菜单延期到下一个大版本前，长按入口仍走 `friend_discovery_page` 的既有实现。

`flutter analyze` clean（仅遗留 `friend.dart:84` 的 pre-existing doc comment info）。

**Files touched (rework)**：

- `lib/pages/home_page.dart`: `_onLongPressStart` 加好友行短路；`_toggleNode` 朋友分支接入 `_probeFriendInRange`；新增 probe helper 与常量
- `docs/worklog/2026-04-18_friend_per_line_timeline_ble_gated_checkin.md`: 本段

**待 Elvis 真机验证**：
- 双机同开 home_page，按对方朋友节点，4s 内是否能稳定握上
- 探测失败时 haptic 反馈是否够明显（不够再调 mediumImpact → heavyImpact）
- 是否需要加一点视觉”探测中...”提示（当前纯 haptic，想让 UX 更轻就不加）

---

## 追加（Elvis 可测性反馈）

**背景**：Elvis 指出测试路径有漏洞——pair 当天今日节点自动点亮（`_buildFriendLines` 把 `pairedAt 日` 合成进 completedDates），点击 toggle 也删不掉那个合成点，因此无法直接观察”BLE 验证”是否真的跑了。

**Elvis 选方案**：保留现有点亮语义不动，**在 BLE 验证成功时给今日朋友节点加一次性闪烁**——这样不论 dot 本身是不是已亮，”握手成功”都有独立可视信号。

**实现**：

- 新增 `AnimationController _bleFlash`（350ms，一次性）+ `String? _bleFlashKey`
- `_toggleNode` 朋友分支里 `friend.save()` 之后触发：`_bleFlashKey = lineId; _bleFlash.forward(from: 0)`
- 触发条件：cache 命中 **或** probe 成功，任何一种 BLE 证据验证成功都闪——两者都是”对方真的在旁边”的确认
- `_TimelinePainter` 新增 `bleFlashValue / bleFlashKey` 字段；`_paintRow` 里对匹配的今日节点做 `alpha *= 1 + 0.7 * sin(π * t)` 脉冲（峰值在 t=0.5，起止都回到 1x）
- 加入 `Listenable.merge` 和 `shouldRepaint` 对比，动画结束后自然停脏
- soul 合规：一次性 transient（350ms 后自止），不是常驻呼吸，不落 #11 禁止列表

**测试路径（现在可行）**：

1. A 和 B pair 上（home_page 会显示 B 的行，pairedAt 日节点点亮）
2. A 在 B 旁边点 B 的今日节点 → 应该闪一下（cache 命中路径）
3. A 远离 B，再点 → 无闪烁、`mediumImpact` 拒绝（probe 超时）
4. A 回到 B 旁边再点 → probe 成功，闪一下（probe 成功路径）

`flutter analyze` clean。

**Files touched (flash 追加)**：

- `lib/pages/home_page.dart`: 新增 `_bleFlash` 控制器 + 生命周期 / probe 成功后触发 / painter 字段 + 绘制脉冲 / shouldRepaint / Listenable.merge

---

## 追加（扩散环 · 路径 A）

**背景**：Elvis 反馈单独 flash 信号太弱——"感觉没握上"。想要一个圆环外扩动画，最好两台手机同时触发。

**约束冲突**：真正"同时触发"需要 tappee 也在扫描；这和前一次定的"home_page 不常驻 BLE"冲突。向 Elvis 明列三条路（A 只做 tapper 升级视觉 / B 加 ambient 扫描改 soul 决策 / C 非同时但保留双侧），Elvis 选 **路径 A**。

**实现**：复用既有的 `_bleFlash` controller 驱动轨迹，不新增动画资源。只在 `_paintRow` 里、朋友行今日节点处，匹配 `bleFlashKey == lineId` 时画一圈外扩 stroke。

- 半径：4px → 36px（easeOutCubic）
- alpha：0.55 → 0（线性衰减 + 乘以行内 effAlpha）
- stroke：1.2px
- 时长：350ms（与 flash 同步结束）
- 触发条件：和 flash 完全相同——cache 命中或 probe 成功任一 BLE 证据通过时触发

**语义承诺**：A 这台手机能画出这个环，就证明 A 刚刚从 BLE 扫描结果里读到了 B 的 presence。两台手机同时亮不在本 scope 内；如果 Elvis 之后确认需要那种仪式感，需重开 soul / BLE 生命周期讨论（上面提到的路径 B）。

`flutter analyze` clean。

**Files touched (环追加)**：

- `lib/pages/home_page.dart`: `_paintRow` 朋友行今日节点分支后插入扩散环绘制块（~18 行）
