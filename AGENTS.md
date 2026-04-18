# AGENTS.md — 两位 AI 开工前必读

本文件是两位 AI（Claude 做开发 / GPT 做 review，或反之）每次上线的**第一个读取对象**。
若本文件与你此刻的推理或"我觉得应该这样"冲突 —— 以本文件为准。

---

## 身份

- **用户**：Elvis，迹点的产品与最终决策人。商业、定价、红线、功能边界的决定权**只属于他**。
- **Dev agent**：执行具体代码与设计落地。可自主推进的边界见 `docs/charter/03_boundaries.md`。
- **Review agent**：读 Dev 本次改动，按 `docs/charter/00_soul.md` 和对应 `docs/specs/` 文档核对。
  不越权做"我觉得这里更好"的主动重构；只指出问题，不替 Dev 重写。

Elvis 会在每次对话开始时指派哪一位是 Dev、哪一位是 Review。如果没指派，默认本次先进入的 AI 是 Dev。

---

## 每次开工前的读取顺序

**必读（顺序）：**

1. `AGENTS.md`（本文件）
2. `docs/charter/00_soul.md`
3. `docs/charter/03_boundaries.md`
4. `docs/worklog/` 里最近 2 条 session log

**按当次任务再读：**

5. 涉及功能对应的 `docs/specs/<feature>.md`
6. 涉及架构决策的 `docs/charter/02_architecture.md`
7. 涉及上架 / 合规的 `docs/charter/04_release.md`
8. 涉及产品 / 商业的 `docs/charter/01_product.md`

**禁止**：未读上述必读文件前修改任何 `lib/` 下的代码或 `docs/charter/` 下的任何文档。

---

## 每次收工前的写入

**Dev agent**：每次收工（不管是功能做完还是只改了一行），**必须**在 `docs/worklog/` 写一份新 log，命名 `YYYY-MM-DD_<slug>.md`，模板见 `docs/worklog/_template.md`。

**Review agent**：在同一份 log 里追加一个 `## Review` 小节，写三种结论之一：
- ✅ 通过
- 🔧 需返工（列出具体问题）
- ⚠️ 升级给 Elvis（说明为什么 AI 层解决不了）

---

## 红线（无例外）

1. 不得修改 `docs/charter/00_soul.md` 和 `docs/charter/01_product.md`，除非 Elvis 在对话里明确说"改 charter"或"改 soul"。
2. 不得自作主张加三方 SDK、分析、tracker、网络请求。
3. 不得修改 `ios/Runner/Info.plist`、`Runner.entitlements`、`android/app/src/main/AndroidManifest.xml` 的权限声明而不在 worklog 里以 `⚠️ PERMISSION CHANGE` 标红。
4. 商业决策（定价、Pro 边界、何时上架、版本号跳变）出现时——停下来，在 worklog 里写 "Questions for Elvis"，不要继续推进。
5. 触及 `docs/charter/00_soul.md` 任一红线条目时——停下来，不要尝试"优雅地绕过"。

---

## 冲突处理

| 场景 | 处理方式 |
|---|---|
| Dev 和 Review 意见不一致 | 两边都把理由写到同一条 worklog `## Conflict` 小节，等 Elvis 裁定 |
| spec 和 soul 冲突 | 按 soul 办，worklog 里写冲突并建议修 spec，不要动 soul |
| 用户口头要求与 soul 冲突 | 提醒 Elvis 本条与 soul 冲突，让他确认是"改 soul" 还是"本次例外" |
| 新想法 | 可在 worklog 的 "Ideas" 小节写下建议，不要在对话中反复推销 |

---

## 工作单元原则

- 一次 session 只做一个连贯的小单元。不要"既修 bug 又加功能又重构"。
- 宁可写完一个小任务就收工，也不要留未提交的半成品让下一位 agent 猜测状态。
- 任何"我注意到顺手也可以改"的冲动 —— 写进 worklog 的 "Ideas"，不要实际改。

---

## 从这里开始就是团队协作

在这份文件写下之前，Elvis 和单个 AI 在对话中做出的所有决策，已被整理进 `docs/charter/` 和部分 `docs/specs/`。
从现在起，**那些对话记录不再是权威 —— 本仓库的文档才是**。如果文档和你记得的对话有冲突，相信文档。
