# 上架与合规 Gate

> 列出所有上架前必须通过的 gate。Dev 在路上新发现的合规问题应追加到本文件并在 worklog 中提及。

---

## iOS App Store R0（硬性门槛 · 不过即拒审）

- [ ] `ios/Runner/PrivacyInfo.xcprivacy` 自有隐私清单（必须列出 UserDefaults、systemBootTime、fileTimestamp、diskSpace 中实际命中的类别）
- [ ] `Info.plist` 加 `ITSAppUsesNonExemptEncryption = false`（使用系统标准加密，符合豁免）
- [ ] iPad 方向声明收敛（仅竖屏 / 或通过 Supported Destinations 关闭 iPad）
- [ ] BLE 后台模式决策（倾向删除 `bluetooth-central` + `bluetooth-peripheral`，如保留需在 App Review Notes 说明）

---

## R1（大概率被人工挑刺）

- [ ] 设置页"清除所有数据"入口（应用现有 `debugReset` 基础设施）
- [ ] 隐私政策 URL（托管在 GitHub Pages 静态页）
  - 必须覆盖：本地加密、蓝牙 handle 交换、不上传、不追踪、备份文件归属用户
- [ ] Age Rating 问卷（生日采集 → 可能 12+）
- [ ] AppIcon 冗余文件清理（删除 `Icon-20@2x 1.png`、`Icon-29 1.png` 等 " 1" 后缀残留）
- [ ] 确认 `LaunchScreen.storyboard` 纯黑背景（避免启动闪白）

---

## R2（HIG 软合规）

- [ ] Dynamic Type 基本支持（至少设置页 / 按钮 / 标题响应系统字号）
- [ ] VoiceOver Semantics 覆盖时间轴节点（CustomPainter 内容需 overlay）
- [ ] 44×44pt 点击区保障（时间轴节点当前 6-8px 半径需透明扩展层）
- [ ] 状态栏隐藏范围收敛（仅主界面隐藏，其他页恢复）
- [ ] Haptic 反馈在低端设备（iPhone SE）静默 fallback 验证

---

## R3 上架元数据（非代码）

- [ ] 截图：6.9" (iPhone 17 Pro Max) + 6.5" 两套，各 3-10 张
- [ ] App 名称 / 副标题（中 + 英）
- [ ] App 描述（中 + 英）
- [ ] 关键词（中 + 英）
- [ ] Support URL（GitHub Issues 页面够用）
- [ ] Marketing URL（可选）
- [ ] 类别：Lifestyle / Productivity
- [ ] Age Rating 问卷
- [ ] Export Compliance 问卷
- [ ] **App Review Notes**：主动说明
  - 完全离线、无账号
  - BLE 用于近场朋友发现，双方手动确认后才能持续识别
  - 所有数据本机加密，无服务器

---

## 版本号策略

- 1.0.0 = 初始上架（R0 + R1 完成）
- 1.0.x = 上架后 bugfix
- 1.1.x = 本地提醒 + 小组件
- 1.2.x = Obsidian 单向同步（首个 Pro 功能）
- 1.3.x = Obsidian 反向手动同步
- 2.0.0 = 主动冻结 + 星图（产品形态跃迁）
- 2.1.x = 好友双轨 v1
- 2.2.x = 好友双轨 v2

**任何跨大版本号跳变（x.0.0）必须 Elvis 确认。**

---

## 发布前最终 checklist（每次 release 都过一遍）

- [ ] `flutter analyze` 零 issue
- [ ] 真机全流程测试（冷启动 → 首次设置 → 打卡 → 备份 → 恢复）
- [ ] 时间篡改场景测试（往前 / 往后调系统时间）
- [ ] BLE 场景测试（两部设备互相发现 → 确认 → 重连）
- [ ] 性能 profile（滚动帧率、冷启动时间）
- [ ] `PrivacyInfo.xcprivacy` 与实际 API 使用对齐
- [ ] 版本号 / build number bump
- [ ] 本次 release 对应的 worklog 存在且 Review 已过
