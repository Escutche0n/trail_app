# 2026-04-18 — Charter Bootstrap

**Agent**: Dev (Claude)
**Session goal**: 把 Elvis 和我在过去若干轮对话中达成的设计共识落成文档体系，为后续 AI 协作奠基。

---

## Context

这是第一条 worklog。在此之前 Elvis 和 Claude 通过对话完成了：
- 时间篡改防御 4 层封闭
- BLE 好友系统 v1 实现（payload v2、presence byte、nearby pulse、本地改名）
- 时间轴间隔 gap 文字重定位 + 垂直滚动 snap 边界修复
- 完整的产品灵魂讨论（memento mori / 主动冻结 / 星图 / Obsidian 互通 / 商业化路径）

从今天起，上述对话记录不再是权威，本仓库的 `docs/` 是唯一真相源。

## Read

- 先前会话的所有上下文（已内化到 charter）
- `lib/core/time_integrity_service.dart` 现有实现
- `lib/core/ble_service.dart` 现有实现
- `lib/pages/home_page.dart` 垂直滚动边界 + gap 文字位置
- `ios/Runner/Info.plist` 现有权限声明

## Done

- 新建 `AGENTS.md`（仓库根 · 两位 AI 必读）
- 新建 `docs/charter/00_soul.md`（产品灵魂 + 红线）
- 新建 `docs/charter/01_product.md`（产品与商业）
- 新建 `docs/charter/02_architecture.md`（技术架构原则）
- 新建 `docs/charter/03_boundaries.md`（AI 决策边界）
- 新建 `docs/charter/04_release.md`（上架 Gate / 合规 checklist）
- 新建 `docs/specs/_template.md`（功能 spec 模板）
- 新建 `docs/specs/constellation.md`（星图 · 完整设计）
- 新建 `docs/specs/obsidian_sync.md`（Obsidian 同步 · 完整设计）
- 新建 `docs/specs/ble_friends.md`（BLE · v1 现状 + v2/v3 规划）
- 新建 `docs/specs/freeze.md`（主动冻结 · 完整设计）
- 新建 `docs/specs/widget.md`（stub）
- 新建 `docs/specs/reminder.md`（stub）
- 新建 `docs/worklog/_template.md`（worklog 模板）
- 新建本文件

## Decisions made

- **文档结构采用 AGENTS.md + `docs/{charter, specs, worklog}` 三层**，其中：
  - AGENTS.md 放仓库根（Codex / Claude Code 惯例位置）
  - charter 分 5 个小文件（减少每次上下文成本）
  - specs 每功能一份，强制模板
  - worklog 每次开工必写，Review 追加 `## Review` 小节

- **Charter / Soul 的书写语气**选择"宪法式"，条目清晰、禁止项明确列出。理由：AI 更擅长对照明确的 negative list 而不是诗意的 positive description。

- 没有合并"charter/01_product.md"到 soul，因为商业决策可改，soul 不可改，两者需要分离。

## In flight / blocked

无。本 session 是文档初始化，不涉及代码。

## Handoff

**下一次 Dev session 的推荐起点**：

1. 按 `charter/04_release.md` 的 **R0 清单**推进上架硬性合规：
   - `ios/Runner/PrivacyInfo.xcprivacy` 起草（需要先审计实际 Required Reason API 命中）
   - `Info.plist` 加 `ITSAppUsesNonExemptEncryption = false`
   - iPad 方向声明收敛
   - **BLE 后台模式决策**（见 Questions for Elvis）

2. 开工顺序建议：先做不依赖 Elvis 决策的三项，把 BLE 后台模式留空等确认。

**给下一位 agent 的备忘**：
- 读完 AGENTS + 00_soul + 03_boundaries 再动手
- 读 release.md 找到具体 checklist 条目
- R0 任务不涉及 `lib/` 代码，主要是 iOS 工程配置
- 修改 Info.plist / entitlements 是 `⚠️ PERMISSION CHANGE`，必须在 worklog 标红

## Questions for Elvis

- [ ] **BLE 后台模式**：iOS `Info.plist` 当前声明 `bluetooth-central` + `bluetooth-peripheral`。倾向删除（减少审核追问、后台扫描在 iOS 也极不稳定）。你要保留还是删掉？
- [ ] **Pro 定价**：倾向买断 ¥88。但这个决策可以等到 1.2 临近时再敲定。现在先记录候选。
- [ ] **首次 Pro 启用的历史迁移**（见 `specs/obsidian_sync.md`）：历史打卡是否一次性推进 vault？

## Ideas

以下是 session 中闪过但未实现、未进 spec 的念头，留作未来参考：

- 星图长按后可能需要一个"今日整条链的回放"动画（按诞生顺序依次点亮）—— 但这违反红线 #11 的"不做持续动画"，除非定义为"用户主动触发的一次性回放"。可在 2.0 之后评估。
- Obsidian 同步的反向 diff UI，可以参考 `git difftool` 的双栏布局。但移动端屏幕小，可能需要单栏 per-item 卡片式。
- 朋友系统长期可能演化出"和 X 最近 30 天相遇过 N 次"的空间化展示（在朋友的扇形星域里密度升高），但这已经接近"显示数字"的边界 —— 需要慎重评估是否触红线 #2。

---

## Files touched

- `AGENTS.md`: new
- `docs/charter/00_soul.md`: new
- `docs/charter/01_product.md`: new
- `docs/charter/02_architecture.md`: new
- `docs/charter/03_boundaries.md`: new
- `docs/charter/04_release.md`: new
- `docs/specs/_template.md`: new
- `docs/specs/constellation.md`: new
- `docs/specs/obsidian_sync.md`: new
- `docs/specs/ble_friends.md`: new
- `docs/specs/freeze.md`: new
- `docs/specs/widget.md`: new
- `docs/specs/reminder.md`: new
- `docs/worklog/_template.md`: new
- `docs/worklog/2026-04-18_charter_bootstrap.md`: new

---

## Review

<等 GPT 或另一位 Claude 审阅本次 bootstrap。建议 review 重点：>
- AGENTS.md 是否完整覆盖两位 AI 的协作场景
- charter 红线是否可执行（每条都能被 Dev / Review 对照）
- specs 是否遗漏了对话中的关键决策
- 文档之间是否有前后矛盾

**结论**：（待 Review）
