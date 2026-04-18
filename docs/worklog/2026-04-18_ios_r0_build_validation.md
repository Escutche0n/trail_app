# 2026-04-18 — ios_r0_build_validation

**Agent**: Dev (GPT)
**Session goal**: 对 `PrivacyInfo.xcprivacy` 和剩余 iOS R0 项做一次构建级验证，而不是继续停留在静态判断。

---

## Context

此前 R0 代码侧已基本收口，但 `PrivacyInfo.xcprivacy` 仍属于“推测没问题，尚未真实验证”的状态。Elvis 本次要求直接推进这条验证。

## Read

- AGENTS.md ✅
- docs/charter/04_release.md ✅
- ios/Runner/PrivacyInfo.xcprivacy ✅
- ios/Podfile ✅
- ios/Runner/Info.plist ✅
- ios/Runner.xcodeproj/project.pbxproj ✅

## Done

- 先用 `xcodebuild` 跑 iOS Release 构建，确认沙箱外才能进行可信验证。
- 发现并确认首个阻塞点不是 privacy manifest，而是 CocoaPods 沙盒不同步：
  - `ios/Pods/Manifest.lock` 缺失
  - `[CP] Check Pods Manifest.lock` 阶段失败
- 运行 `pod install` 恢复 Pods 沙盒同步，补回 `Manifest.lock`
- 重新执行：
  - `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos -destination generic/platform=iOS -derivedDataPath /tmp/trail_ios_build CODE_SIGNING_ALLOWED=NO build`
- 构建成功，并跑过：
  - `Validate ... -validate-for-store`

## Decisions made

- 本次不因为 `PrivacyInfo.xcprivacy` 仍为空数组就继续盲改。先以构建级验证为准，结果显示当前主 app manifest 没有立刻暴露出 store validation 错误。
- `pod install` 只用于恢复本地 iOS 构建沙盒一致性，不引入额外产品逻辑改动。

## Verification result

- `PrivacyInfo.xcprivacy` 已被实际拷贝进 `Runner.app`
- iOS Release build 成功
- Store validation 阶段成功
- 当前未出现新的 privacy manifest 错误

## Residual risk

- 这仍然不是 App Store Connect 上传后的最终裁决；但至少已经从“静态猜测”提升为“本地 store validation 通过”。
- Pods 里若干第三方目标仍有 `IPHONEOS_DEPLOYMENT_TARGET = 9.0` 的 warning，但它们当前只是 warning，不构成 R0 阻塞。

## Handoff

下一次最合理的动作：

1. 如继续 R0 收尾，可把重点转向真机流程验证，而不是再改 iOS 合规配置
2. 如后续要更稳，可做一次真实 archive / App Store Connect 上传前检查

## Questions for Elvis

- [ ] 目前没有新的阻塞问题。

## Ideas

- 后面如果你开始频繁做 iOS 本地构建，建议把一次 `pod install` / `flutter pub get` 作为升级依赖后的固定动作，避免再被 `Manifest.lock` 缺失卡住。

---

## Files touched

- `docs/worklog/2026-04-18_ios_r0_build_validation.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
