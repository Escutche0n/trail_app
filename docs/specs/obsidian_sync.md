# Obsidian 同步

> 状态：设计完成，待 1.2 实现
> 这是 Pro 版首个付费闸门功能

---

## 目标

让用户的迹点数据（打卡、冻结、自定义线）能与自己的 Obsidian vault 双向连接：
- 迹点是产生事件的**移动端快捷入口**
- Obsidian 是最终的**知识归档**
- 用户不为"同步服务"付费，而是为"两个工具之间的桥"付费

---

## 非目标

- 不做 Notion / Logseq / Bear 对接
- 不做云端同步（数据只流向用户自己的 vault）
- 不做后台自动 pull（iOS 限制 + 冲突复杂度）

---

## Soul 对齐检查

- ✅ 红线 #8（无云端）：数据只流向用户自有文件
- ✅ 红线 #9（无追踪）：文件操作全部本地
- ✅ 气质"克制"：手动 pull 而非后台监听

---

## 数据流（关键决策）

### 推送：Trail → Obsidian（**自动**）
- 触发时机：
  - App 进入后台
  - 主动冻结一天
  - **不做**每次打卡触发（文件 IO 吵）
- 冲突策略：Trail 为源，直接覆写对应 section
- 失败降级：文件不可写 → silent skip + 下次进后台重试

### 拉取：Obsidian → Trail（**手动**）
- 用户主动点击"从 Obsidian 同步"按钮
- 展示 diff UI：显示外部新增 / 移除 / 修改的条目
- 用户按条目确认"接受 / 拒绝 / 全部接受 / 全部拒绝"
- **永远不静默覆盖本地**

---

## Markdown Schema（v1，冻结后不得破坏性修改）

### 每日写入格式

写入目标文件：用户指定的 daily note（例如 `Daily/2026-04-18.md`）
写入目标 section：用户配置（默认 `## Trail`）

```markdown
## Trail

- [x] 2026-04-18 alive #trail/alive
- [x] 2026-04-18 gym #trail/gym ^trail-gym-20260418
- [x] 2026-04-18 read #trail/read ^trail-read-20260418
- [F] 2026-04-18 #trail/frozen ^trail-frozen-20260418
```

### 字段说明

- `[x]` / `[ ]` —— 该线当天打卡状态
- `[F]` —— 该天已被主动冻结（自定义 checkbox 状态，Obsidian 会显示为特殊样式）
- `#trail/<line_slug>` —— 用于 Dataview 按线查询
- `^trail-<line>-YYYYMMDD` —— block reference，用于精确引用

### Dataview 示例（用户侧，不在 app 内生成）

```dataview
TABLE length(rows) as "Days"
FROM #trail/gym
WHERE checked
GROUP BY yearmonth(date)
```

---

## 配置项

### 用户可在 Pro 设置页配置

- **Vault 路径**：通过 iOS 文件选择器选择（需 `NSDocumentsFolderUsageDescription`）
- **Daily note 路径模板**：默认 `Daily/YYYY-MM-DD.md`，可改
- **Section 标题**：默认 `## Trail`，可改（因为不同用户的 template 五花八门）
- **自动推送开关**：默认开
- **冲突策略**：
  - "Trail 优先"（默认 · 推送时直接覆写 section）
  - "问我"（推送前 diff 确认）

---

## iOS 文件访问

- Vault 目录通过 `UIDocumentPickerViewController` 选择
- 拿到 `security-scoped URL`，保存 bookmark 到 Keychain
- 每次读写前调用 `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`
- Flutter 侧通过 platform channel 调用

---

## 错误处理

| 场景 | 行为 |
|---|---|
| Vault 路径失效 | 设置页显示红色提示，自动推送暂停 |
| Daily note 不存在 | 自动创建（仅在当前目标日对应文件） |
| Section 标题找不到 | 文件末尾追加该 section |
| 文件只读 | 推送失败，settings 标记"Vault 只读"，用户需改权限 |
| 文件在 iCloud 未下载 | iOS 会自动触发下载；失败则 silent skip |

---

## 状态机（推送）

```
idle → [trigger: freeze/background] → checking_vault → writing
                                                          ↓
                                             success → idle
                                                          ↓
                                             failure → idle + log warning
```

---

## 状态机（拉取）

```
idle → [user tap] → reading_vault → parsing → computing_diff
                                                     ↓
                                              diff_presented
                                                     ↓
                                         [user accept/reject per item]
                                                     ↓
                                              applying → idle
```

---

## Edge cases

- **时间篡改**：只影响推送时间戳（tampered 下仍推送，但用 TimeIntegrityService 推算时间）
- **同一天多次打卡**：直接覆写 section 内对应行（不 append）
- **用户在 Obsidian 里手动改了某一天的状态**：下次用户主动 pull 时 diff 显示
- **Vault 目录被用户移动**：bookmark 失效 → 引导重新选择

---

## 依赖

- `charter/01_product.md` - Pro 边界定义
- `charter/02_architecture.md` - Hive schema
- iOS 文件选择器 / bookmark
- 需要新增 Flutter 包：`file_picker`（已有） + 自定义 platform channel（可能需要）

---

## Open Questions（待 Elvis 决策）

- [ ] Pro 启用后，**首次同步**如何处理？（一键把历史全部写进 vault，还是只从启用日起）
- [ ] `[F]` 这种自定义 checkbox 在 Obsidian 里需要配合 CSS snippet，用户愿意装吗？替代方案用普通 `[x]` + tag `#trail/frozen`
- [ ] 多 vault 支持 v1 做不做？（建议推迟到 v2）
- [ ] Section 标题冲突处理（如果用户已经有 `## Trail` 放别的东西）

---

## 变更历史

- 2026-04-18: initial spec by Claude（基于与 Elvis 的对话）
