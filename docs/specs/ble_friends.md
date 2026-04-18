# BLE 朋友系统

> 状态：v1 已实现，v2/v3 设计中
> 依赖：`charter/02_architecture.md` - BLE 章节

---

## 目标

让两位物理上接近的用户，不经过任何服务器，通过 BLE 在彼此的迹点里相互"登记"。
后续两人再相遇时，迹点里会产生一颗闪烁的朋友星作为见证。

**核心哲学**："平行见证" —— 我知道你在做，你知道我在做，我们不互相审问。

---

## 非目标

- 不做 streak 对比 / 排行榜
- 不做打卡内容共享（A 的打卡不同步到 B）
- 不做位置记录 / 任何地理信息
- 不做通过互联网"远程加好友"
- 不做大规模数据同步（BLE 带宽不够，会被错用）

---

## Soul 对齐检查

- ✅ 红线 #5（不做星星交易）：朋友星是各自独立的见证，不是转移
- ✅ 红线 #6（不做用户主页）：朋友列表仅本机可见
- ✅ 红线 #8（不加网络）：全部 BLE 近场
- ✅ 气质"克制"：要求双方手动确认才能持续识别

---

## 当前实现（v1）

### BLE Payload

**Manufacturer Data v2（10 字节）**：
- Company ID: `0xFFF1`
- Payload bytes[0-8]: pairingHandle(6) + selfPrefix(8) + stateChar(1)
- Payload byte[9]: `presenceByte`（v2 新增）

**iOS localName**：
```
tr@ + pairingHandle(6) + selfPrefix(8) + stateChar(1) + presence(2hex)
```

v1（9 字节，无 presence）向后兼容读取。

### 朋友状态机（4 态）

```
discoverable
    ↓ (self taps add)
pendingOutgoing
    ↓ (peer taps add)
confirmed
    ↓ (self unfriends)
discoverable

discoverable
    ↓ (peer taps add)
pendingIncoming
    ↓ (self taps confirm)
confirmed
```

### Presence 机制

- `_currentPresenceByte`：0-255 循环
- 扫到已确认朋友时，throttle 8 秒内最多 bump 一次
- 作用：两端都看到对方 presence 在变 = "我看到你看到我"的 mutual witness

### UI（friend_discovery_page）

- 好友卡片上的绿色小点：
  - 当前不在附近：静态暗点，alpha 0.4
  - 当前在附近：halo 16px + core 8px，2s reverse 呼吸动画（alpha 0.35-0.95 easeInOut）
- 长按好友卡片：打开本地改名 dialog（24 字符上限，仅本机保存）

---

## v2：共享线（Shared Lines）

> 待实现 · 2.1.x

### 机制

- 两位已确认朋友面对面，其中一位在 app 里发起"和 X 创建共享线"
- BLE 握手确认双方同意
- **线在两人的 app 里独立创建**：`pairId = hash(selfUid + friendUid)`
- 两人各自打各自的卡（数据不同步到对方加密盒）
- 下次 BLE 相遇时，在**当次会话内临时**拿到对方最近 30 天的 diff，仅做显示用（ghost dot），**不持久化**

### 数据归属

- **每个人的加密盒里只有自己的打卡记录**
- 共享线的元数据（pairId、friendHandle、createdAt）双方各存一份
- 对方的打卡状态**永远不复制进自己的加密盒**
- A 删除共享线 → A 本地记录清空 → B 那边的线不受影响（B 只是看不到 A 的任何 ghost dot 了）

### 为什么不持久对方数据

- 隐私原则：你不应持有对方未来可能想撤回的数据
- 简化冲突：没有对方数据就没有合并冲突
- 避免 BLE 带宽瓶颈：会话内 diff 是有限的，持久化全量是不可能的

---

## v3：会话内历史合并（或许不做）

> 只有 v2 用户反馈强烈需要才做

- BLE 会话建立 L2CAP channel，传输压缩过的历史 diff
- 仅在会话内呈现，依然不持久化
- 工程难度：L2CAP 在 iOS 后台极不稳定，必须双方都在前台
- **推荐：先不做**，等 v2 真实用户需求验证

---

## Edge cases

- **两人同时发起 pendingOutgoing**：双方各自看到对方的 pendingOutgoing → 任一方确认即进入 confirmed
- **unfriend 之后再遇到**：回到 discoverable，互不记得
- **设备换机 / 重装**：uid 重新生成 → 对方视为陌生人（设计如此：无账号无恢复）
- **后台扫描 iOS 限制**：如果后台模式被砍（见 `charter/04_release.md`），仅前台发现

---

## 依赖

- `flutter_blue_plus` 1.32.12
- `flutter_ble_peripheral` 2.1.0
- `charter/02_architecture.md` - BLE payload 规范

---

## Open Questions（待 Elvis 决策）

- [ ] iOS 后台模式是否保留？（倾向删除，见 release.md）
- [ ] 朋友星的 30 天节流是否合适？（和同一朋友频繁相遇只算一次）
- [ ] v2 共享线最多支持几条？（建议 ≤ 5，避免屏幕拥挤）
- [ ] unfriend 后历史朋友星是否消失？
  - A: 消失（彻底断联）
  - B: 保留但失去"闪烁"属性变成普通记忆星
  - **建议 B**，情感上更柔和

---

## 变更历史

- 2026-04-18: initial spec by Claude（整理现有 v1 实现 + v2/v3 设计）
