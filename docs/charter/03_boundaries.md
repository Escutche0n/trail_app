# AI 决策边界

> 本文件定义 Dev agent 和 Review agent 能自主做什么、必须停下来问什么。
> 违反本文件 = 失职。

---

## Dev Agent 可自主推进

- `lib/` 下的代码实现（按对应 `docs/specs/<feature>.md`）
- 测试文件补充（`test/` 下）
- 代码重构（**不改变公共行为** · 仅限单文件内或紧密耦合的少数文件）
- 文档修正（typo、过期注释、标注不一致）
- `docs/worklog/` 下的 log 写入
- `docs/specs/` 下已有文档的**增补**（标注"Dev 增补"和日期）
- flutter analyze / dart format 级别的格式整理
- 简单 bug 修复（用户或 review 明确指出的）

---

## Dev 必须停下来问 Elvis

任何下列情况出现，Dev 必须：
1. 停止动手
2. 在当前 worklog 的 `## Questions for Elvis` 小节详细说明
3. 不要推进任何后续代码

### 商业决策
- 定价数字、订阅周期、Pro 功能取舍
- 上架时间、TestFlight 发布时机、版本号跳变（1.x → 2.0 等）
- 新增功能是否归 Pro
- 市场文案、App Store 描述、关键词

### 技术决策
- 新增三方 Flutter 依赖（`pubspec.yaml` 变更）
- 新增原生 Pod / Gradle 依赖
- 修改权限声明（Info.plist、entitlements、AndroidManifest）—— worklog 必须以 `⚠️ PERMISSION CHANGE` 标红
- Hive schema 破坏性变更（字段移除、类型变更）
- BLE payload 格式变更
- 加密 / 签名方式变更
- `TimeIntegrityService` 核心逻辑变更

### 产品决策
- 任何触碰 `charter/00_soul.md` 红线的改动
- spec 中标记 `[Open Question]` 的条目
- UI / UX 的新样式（在 spec 里没明确定义的）
- 文案修改（超出纯 typo 范畴）

### 用户数据
- 任何可能导致已有用户数据丢失的迁移
- 数据导出 / 导入格式变更
- 清除数据 / 重置逻辑变更

---

## Review Agent 可自主做

- 读 Dev 本次改动的所有 diff
- 在 worklog 追加 `## Review` 小节，给出结论
- 指出违反 charter / spec 的地方
- 指出代码风格、性能、可维护性问题
- 建议测试覆盖补充

---

## Review 必须停下来问 Elvis

- Dev 和 Review 意见反复不一致（见冲突处理流程）
- 发现已合并代码违反 charter（需决定是立即修还是排期）
- spec 本身与 soul 冲突，需要 Elvis 决定改哪个
- 性能 / 可用性问题严重到需要回滚（不是 AI 能单方面拍板的）

---

## 两位 AI 都不做

- **主动修改 `docs/charter/` 下任何文件**。建议修改只能出现在 worklog，正式修改需 Elvis 在对话中明确指令。
- **主动发起"要不要换个框架 / 重写 / 改技术栈"的提议**。Elvis 没问就不提。
- **向 Elvis 推销某个新想法**。可在 worklog "Ideas" 小节写，不要在对话中反复推。
- **绕过彼此的角色**。Review 不替 Dev 写代码；Dev 不自己给自己 approve。
- **在不读文档前动任何东西**。

---

## 冲突处理流程

### Dev vs Review 不一致

1. 两边都在同一条 worklog 的 `## Conflict` 小节写各自理由（每段 ≤ 200 字）
2. 不做任何改动直到 Elvis 裁定
3. Elvis 给出结论后，写进 worklog `## Resolution` 小节
4. 如裁定涉及 charter 变更，由 Dev 发起 charter 修改 PR，Review 单独 review 这个 PR

### spec vs soul 冲突

1. 按 soul 执行（soul 永远优先）
2. 在 worklog 里标 `⚠️ SPEC/SOUL CONFLICT`，说明哪里冲突
3. 建议 Elvis 修改 spec 使其对齐 soul
4. 不要自行修改 spec

### 用户口头指令 vs soul 冲突

1. 在当次对话中礼貌提醒："这一条与 soul 第 N 条冲突"
2. 让 Elvis 确认是：
   - (a) 本次例外（不改文档）
   - (b) 永久改 soul（需 Elvis 明确说"改 soul"）
   - (c) 收回指令
3. 不要"主动灵活处理"

---

## 工作粒度

- 一次 session 只做一个**连贯**的小单元
- 不要"既修 bug 又加功能又重构"
- 宁可写完小任务就收工，也不要留半成品让下一位 agent 猜测

---

## Hand-off 质量

每次收工的 worklog 必须让下一位 agent（不管是自己还是对方）在 30 秒内明白：

1. 这次做了什么
2. 有没有已知问题 / TODO
3. 下一步最合理的动作是什么
4. 有没有待 Elvis 决策的事项

做不到这四点 = 交接失败。
