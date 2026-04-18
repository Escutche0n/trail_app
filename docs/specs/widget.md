# 小组件 (Widget)

> 状态：stub · 待 1.1 启动时完善

---

## 目标

在 iOS 主屏 / 锁屏提供一个 app 的轻量入口，以及一个 Obsidian daily note 的快捷跳转。

---

## 非目标

- 不在 widget 里渲染完整时间轴
- 不做可交互复杂 widget（超出 Apple 预算）
- 不做 Live Activities（过度）

---

## Soul 对齐检查

- ✅ 红线 #2（不显示总数）：widget 里不出现星星 / 打卡总数数字
- ✅ 气质"克制"：极简单色设计

---

## 初步设计（待细化）

### 候选样式

1. **锁屏 Circular（iOS 16+）**：今日节点一颗点 · 已打卡实心 / 未打卡空心
2. **锁屏 Rectangular**：7 日迷你时间轴
3. **主屏 Small**：今日状态 + 一个 Obsidian daily note 跳转按钮
4. **主屏 Medium**：当月迷你星图（静态截图）

### 数据共享

- iOS Widget 无法访问 Hive 加密盒
- 需要 App Group 共享容器
- 每次数据变化时写一份**明文摘要**到共享 UserDefaults：
  ```
  { todayChecked: bool, lastFrozenDate: String?, recentStarCount: int }
  ```
- 摘要要能被 iCloud 备份且内容无害

---

## Open Questions

- [ ] 所有样式 1.1 都做，还是分阶段？
- [ ] Obsidian 跳转按钮是否 Pro only？
- [ ] 主屏中等 widget 里放什么（当月星图静态 vs 本周时间轴）？

---

## 变更历史

- 2026-04-18: stub created by Claude
