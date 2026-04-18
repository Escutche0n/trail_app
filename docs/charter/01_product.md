# 产品与商业

> **修改需 Elvis 同意。AI 可在 worklog 里建议修改，不可自行修改本文件。**

---

## 功能层级

### 免费版（核心 · 永久免费）

- 时间轴（活着轴 + 自定义轴）
- 每日打卡
- 主动冻结一天
- 星图（融入主界面，非独立页面）
- BLE 近场朋友发现（不限数量）
- 本地加密备份导出 / 导入
- 本地晚间提醒（可选）
- 锁屏小组件（基础）

### Pro 版（未来 · 定价待定）

- **Obsidian 双向同步**（自动推送 + 手动反向 diff）
- 多 vault / 多 section 配置
- 星图导出高清 PNG（免费版导出带水印）
- 小组件更多样式

### 预留（不保证做）

- 好友双轨共享线（技术难度最高，见 `specs/ble_friends.md` 阶段规划）
- 星的命名 / 备注扩展
- 其他 widget 布局

---

## 定价

**候选方案**：
- 买断 ¥88（一次性）
- 订阅 ¥12/月 或 ¥128/年
- 双轨（买断 ¥128 + 订阅 ¥12/月）

**当前倾向**：买断。理由：
1. 符合产品"反 SaaS"气质
2. Obsidian 用户群对买断有好感
3. 无服务器成本，不需要持续收入
4. 和 app "永久保存、不会消失" 的叙事一致

**决策权**：Elvis。AI 不得在实现 Pro 功能时自行设定价格。

---

## 分发

- **iOS App Store**（首个目标）
- **Android**（Google Play + 国内商店，暂不排期）
- **macOS / iPadOS**：暂不考虑
- **Web / Desktop**：永不考虑

---

## 不做什么（明确的负面清单）

- 不做团队版 / 企业版
- 不做 API / 第三方开发者生态（除 Obsidian 互通）
- 不做数据导出到 Notion / Logseq / Bear（至少 MRR 破万之前）
- 不做社交 feed / 公开主页
- 不做 Apple Health / HealthKit 集成（避免扩大数据面）
- 不做 Apple Watch 独立 app（狭窄屏不适合这个产品）

---

## 版本路线（当前规划，可调整）

| 版本 | 主要内容 | 对应 specs |
|---|---|---|
| 1.0.0 | R0 + R1 合规，上架初版 | `charter/04_release.md` |
| 1.1.x | 本地提醒 + 锁屏小组件 | `reminder.md` `widget.md` |
| 1.2.x | Obsidian 单向推送（Pro 首闸） | `obsidian_sync.md` |
| 1.3.x | Obsidian 反向手动同步 | `obsidian_sync.md` |
| 2.0.0 | 主动冻结 + 星图 | `freeze.md` `constellation.md` |
| 2.1.x | 好友双轨 v1（共同创建线） | `ble_friends.md` |
| 2.2.x | 好友双轨 v2（会话内 diff） | `ble_friends.md` |

Pro 功能何时上线、何时定价生效，由 Elvis 在接近 1.2.0 时决定。
