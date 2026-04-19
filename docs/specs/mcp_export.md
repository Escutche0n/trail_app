# MCP Export（本地 stdio）

> 本文件是该功能的单一权威来源。实现与文档不一致时以本文件为准（或由 Elvis 裁定更新哪个）。
> 任何 spec 变更应由当次 Dev agent 写在 worklog 里，Review 审核后 Dev 才落到本文件。
>
> **状态**：方向草案（2026-04-19），未实现。付费层功能，排期未定。

---

## 目标

把 Trail 的本地打卡 / trail line / 朋友 / 节点状态，作为**本地 stdio MCP server** 暴露给第三方 AI CLI（Obsidian、Cursor、Claude Code 等），供用户在自己的 PKM 工作流里做"人生轨迹分析"。

## 非目标（明确不做的）

- **不做 remote MCP**：任何走网络的 MCP transport 都违反"数据不上云"红线，直接拒绝
- **不做写接口**：MCP 只读单向导出，第三方 AI 不能通过 MCP 反向改 Trail 数据
- **不做 schema 抽象 / 语义聚合**：原始粒度 dump，由 LLM 自行推导。不为"AI 将来分析"预设重要 property（设计观察：记录越整齐，property 越容易被 AI 更准地推导出来）
- **不做免费层**：MCP 导出是付费功能，打中 geek + PKM Ober 两圈，对 anti-social 圈无感 → 定位为护城河而非增长引擎

---

## Soul 对齐检查

- ✅ **红线**：本地 stdio only，不破"不上云"
- ✅ **红线**：只读导出，不破"反游戏化"（无法通过 MCP 改状态）
- ✅ **气质·诚实**：原始数据 dump，不做语义美化；历史名轮转、tamper 记录等 post-hoc 推不出来的 context 也都结构化落地
- ❓ **灰色**：付费门禁的实现方式（license 校验在本地完成，不能引入远端校验）

---

## 输出模型（草案）

每条打卡节点一行，缩进为该日的 notes（复用 `TrailLine.notes[dateKey]` 原文 markdown）：

```
- [x] 2026-04-19T00:00:00+08:00 line:<TrailLine.id>
    - 第一条 item（原样 markdown，≤ 40 字）
    - [ ] 第二条 item
    - 第三条 item
```

### 字段说明

| 字段 | 取值 | 来源 |
|---|---|---|
| 状态标记 | `[x]` 自己的打卡 / `[ ]` 未打卡 / `[@]` 好友 BLE 握手打卡 | `completedDates` / `Friend.checkInDates` |
| ISO 时间戳 | 该日本地零点 + 时区，`YYYY-MM-DDTHH:MM:SS±TZ` | dateKey (`YYYY-MM-DD`) + 当前时区 |
| 唯一 ID | `line:<TrailLine.id>` | `TrailLine.id`（已有字段，[trail_line.dart:15](../../lib/models/trail_line.dart:15)） |
| Notes | 原样 dump `notes[dateKey]` | `TrailLine.notes: Map<String, String>` |

### Line metadata（每次 session 开头 dump 一次）

```yaml
lines:
  - id: <TrailLine.id>
    type: alive | custom
    createdAt: <ISO>
    archived: <bool>
    archivedAt: <ISO?>
    nameHistory:          # 历史名轮转：生效日 → 名字
      "2025-11-03": "基金再平衡"
      "2026-02-14": "资产再平衡"
friends:
  - uid: <Friend.uid>
    displayName: <current>
    displayNameHistory: { ... }
    pairedAt: <ISO>
```

**改名不会失忆**：`nameHistory` / `displayNameHistory` 已在数据模型里结构化存储（`TrailLine.nameHistory` field 8，Friend 侧同构），MCP 直接原样透传即可。

---

## Schema / 数据结构

无新字段。复用现有模型：

- `TrailLine.id` ([trail_line.dart:15](../../lib/models/trail_line.dart:15))
- `TrailLine.notes: Map<String, String>` ([trail_line.dart:33](../../lib/models/trail_line.dart:33))
- `TrailLine.nameHistory: Map<String, String>` ([trail_line.dart:45](../../lib/models/trail_line.dart:45))
- `Friend.checkInDates` / `Friend.displayNameHistory`（已在 BLE friends spec 落地）

### 迁移策略

无。MCP 层是只读投影，底层存储不动。

---

## 状态机 / 流程

```
用户启动第三方 CLI （Obsidian/Cursor/…）
    ↓
CLI 配置本地 MCP server 指向 Trail 二进制
    ↓
Trail 启动 stdio 子进程（license 校验通过）
    ↓
CLI 按需 request → Trail 从 Hive 读取 → 按上述模型 dump 到 stdout
    ↓
用户关掉 CLI，stdio 子进程自然退出
```

---

## UI 决策

- **位置**：设置页新增"MCP 导出"区块（付费用户可见）
- **触发**：点击"复制配置到剪贴板" → 输出第三方 CLI 的 MCP config 片段（command + args）
- **空状态**：未订阅付费层时，该区块显示为付费升级 CTA
- **失败态**：license 校验失败 / 未订阅时，MCP 进程拒绝启动并在 stderr 打印原因（供第三方 CLI 回显）

---

## 边界 / Edge cases

- **时间被篡改**：dump 时带 `tamperLog`（已有字段），消费方自行决定是否信任
- **数据量极大**：不做分页——这是本地 stdio，直接流式 dump；真卡再优化
- **多设备备份恢复**：MCP 只读当前设备的 Hive，跨设备一致性由 Trail 自己的备份/恢复保证
- **并发访问**：Trail app 前台在用 + MCP 子进程同时读 Hive——Hive 本身读安全，不加锁
- **第三方 CLI 滥用**：MCP 只读，无写接口 → 不存在"被改坏数据"的路径

---

## 依赖

- **Charter**：`charter/00_soul.md` 的"数据不上云"硬约束
- **Other specs**：`specs/ble_friends.md`（Friend 模型）
- **技术**：MCP Rust/Dart SDK 调研未开始；付费门禁实现方式未定

---

## Open Questions（待 Elvis 决策）

- [ ] 付费层实现：订阅制 / 买断 / license key 模式？
- [ ] 输出格式：markdown 树状（如本文示例）vs JSON Lines vs 两种都提供？markdown 对 LLM 友好但对 CLI 程序化处理不便
- [ ] 是否暴露事件流（原子事件按时间排序）作为单独 MCP resource，还是只给当前状态 snapshot？
- [ ] 好友数据导出是否要征得对方同意？（BLE pair 时的 consent 是否延伸到 MCP 导出？）

---

## 变更历史

- 2026-04-19: initial draft by Dev（Elvis 方向确认后落地，Codex 此前 session 刚提交 BLE/星图相关代码）
