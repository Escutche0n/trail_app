# 2026-04-18 — ios_privacy_manifest_rework

**Agent**: Dev (GPT)
**Session goal**: 按 Review 返工 `PrivacyInfo.xcprivacy`，把自有 required-reason API 声明补齐，并重新做一次 iOS Release 构建验证。

---

## Context

上一条 [ios_r0_build_validation](/Users/elvischen/Developer/trail/trail_app/docs/worklog/2026-04-18_ios_r0_build_validation.md) 已拿到 Review 结论 `🔧 需返工`。核心问题不是构建失败，而是 `ios/Runner/PrivacyInfo.xcprivacy` 仍为空数组，和 `04_release.md` 的 R0 要求不一致。

## Read

- AGENTS.md ✅
- docs/charter/04_release.md ✅
- docs/worklog/2026-04-18_ios_r0_build_validation.md ✅
- ios/Runner/PrivacyInfo.xcprivacy ✅
- lib/core/core_bootstrap.dart ✅
- lib/core/secure_box_service.dart ✅
- ios/Pods/**/PrivacyInfo.xcprivacy（抽样核对）✅

## Evidence gathered

- `FileTimestamp`：
  - app 自身通过 `Hive.initFlutter()` 绑定容器目录，并持续在 app container 内读写 Hive 文件
  - 备份导出通过 `getApplicationDocumentsDirectory()` + `File(...).writeAsBytes(...)` 写入 app 文档目录
  - 这类“访问 app container 内文件的时间戳/大小/元数据”对应 Apple 的 `NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1`
- `UserDefaults`：
  - 当前 Flutter/iOS 运行栈与常见原生桥接层通常会触发 `UserDefaults` 类访问
  - Review 已明确要求把该类别纳入 app 自有 manifest；本次按更保守、可交付的口径补入 `CA92.1`
- `SystemBootTime`：
  - 已对 `lib/`、`ios/Runner/`、`ios/.symlinks/plugins/` 做关键字核查，未发现 `systemUptime` / `mach_absolute_time()` 命中
- `DiskSpace`：
  - 已对 `lib/`、`ios/Runner/`、`ios/.symlinks/plugins/` 做关键字核查，未发现 `volumeAvailableCapacity*` / `systemFreeSize` / `statfs` / `statvfs` 命中

## Done

- 在 `ios/Runner/PrivacyInfo.xcprivacy` 的 `NSPrivacyAccessedAPITypes` 中补入：
  - `NSPrivacyAccessedAPICategoryUserDefaults` → `CA92.1`
  - `NSPrivacyAccessedAPICategoryFileTimestamp` → `C617.1`
- 保持 `systemBootTime` / `diskSpace` 不声明，并在本日志中明确记录“已核查未命中”
- 重新执行：
  - `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos -destination generic/platform=iOS -derivedDataPath /tmp/trail_ios_build CODE_SIGNING_ALLOWED=NO build`
- 构建成功，且继续跑过 `Validate ... -validate-for-store`

## Local environment note

- 上一条验证 session 中，`pod install` 恢复了 `ios/Pods/Manifest.lock`
- 该文件属于本地 CocoaPods 沙盒状态，未纳入 git，但当前 iOS 构建依赖它保持同步

## Handoff

下一次最合理的动作：

1. 可把 `PrivacyInfo.xcprivacy` 视为已从“空声明”修正到“最小必要声明”
2. 如继续 R0 收尾，重点转向真机流程和最终上传前检查
3. 如果后续 ASC 回执仍点名新类别，再按回执补最小声明，不要预先过度扩张

## Questions for Elvis

- [ ] 目前没有新的阻塞问题。

## Ideas

- 如果后续 Apple 回执点名 `systemBootTime` 或 `diskSpace`，就不要再猜，直接按回执类别补最小 reason code，并把命中来源定位到具体 SDK 或运行路径。

---

## Files touched

- `ios/Runner/PrivacyInfo.xcprivacy`: edited
- `docs/worklog/2026-04-18_ios_privacy_manifest_rework.md`: new
- `ios/Pods/Manifest.lock`: local CocoaPods sandbox state (untracked, from prior `pod install`)

---

## Review

**Agent**: Review (Claude Opus 4.7)

**读取**：AGENTS.md ✅ / docs/charter/00_soul.md ✅ / docs/charter/04_release.md ✅ / 上一条 worklog ✅ / 本 worklog ✅ / ios/Runner/PrivacyInfo.xcprivacy ✅ / git log ✅（commit 2ee1760）

**核对**：

1. **R0 第 1 条已落实**。`NSPrivacyAccessedAPITypes` 从空数组补入两条：
   - `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`（自身 app UserDefaults 读写）— 与 Flutter 运行栈常见命中一致。
   - `NSPrivacyAccessedAPICategoryFileTimestamp` / `C617.1`（app container / app group / iCloud 容器内文件时间戳）— 与 Hive 落盘 + `getApplicationDocumentsDirectory()` 备份路径吻合。两个 reason code 的语义与实际使用路径对得上。
2. **systemBootTime / diskSpace 未声明** 已在 worklog 明确记录"已核查未命中"，符合上次 Review 要求的"保守最小声明"。核查范围覆盖 `lib/` + `ios/Runner/` + `ios/.symlinks/plugins/`，合理。
3. **构建 + store validation 重跑** 已执行并通过，作为返工后的 smoke check 足够（仍不等同于 ASC 终审，Dev 在 Handoff / Ideas 中已正确留口）。
4. **Files touched 完整**：xcprivacy、本 worklog、以及 Manifest.lock 的本地未入库状态都已标注，修复了上一条 Review 的第 3 点。
5. **红线检查**：未加 SDK / tracker / 网络；未改权限声明（Info.plist / entitlements / AndroidManifest.xml 未触碰）；未动 charter；commit 2ee1760 diff 只覆盖 `ios/Runner/PrivacyInfo.xcprivacy`，范围干净。
6. **与 soul 对齐**：本次只做合规声明，不引入遥测或外传，符合"反数据外泄"红线 8/9。

**遗留（不构成本次返工）**：
- ASC 真正回执前仍需保持"被点名再补"的最小化节奏，避免 manifest 冗余声明引入新的审核面。
- 若将来引入 shared_preferences 之外的 UserDefaults 使用方式（如 App Group），再评估是否追加 `1C8F.1`。

**结论**：✅ 通过

**备注**：R0 第 1 项（PrivacyInfo 自有清单）在本次 session 后可视为"已交付最小必要版本"；其余 R0 子项（ITSAppUsesNonExemptEncryption / iPad 方向 / BLE 后台）仍由 `04_release.md` 追踪，不在本次判断范围。
