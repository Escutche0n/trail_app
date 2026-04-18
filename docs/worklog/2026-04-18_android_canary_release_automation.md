# 2026-04-18 — android_canary_release_automation

**Agent**: Dev (GPT)
**Session goal**: 为 Android canary 测试发布补一条自动化链路。

---

## Context

Elvis 明确表示当前阶段只需要自动化 Android 测试发布，不需要同时覆盖 iOS。目标是把“打 Android 测试包并发到 GitHub Release”收成一个稳定流程。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_clear_all_data_hotfix_friends_box_type.md ✅
- android/app/build.gradle.kts ✅
- pubspec.yaml ✅

## Done

- 新增 GitHub Actions workflow：
  - `.github/workflows/android-canary.yml`
  - 触发条件：push `android-canary-*` tag
  - 动作：拉代码 → 装 Flutter → `flutter analyze` → `flutter build apk --release` → 创建 GitHub pre-release → 上传 APK
- 新增本地触发脚本：
  - `scripts/release_android_canary.sh`
  - 动作：检查工作区干净 → push `main` → 创建 canary tag → push tag → 触发 workflow

## Decisions made

- 当前只自动化 Android canary，不碰 iOS。原因：这符合 Elvis 当前发布节奏，也避免引入证书/签名复杂度。
- workflow 产物明确标注为“debug keystore / internal testing only”。原因：当前 Android release build 仍使用 debug signing，只适合测试分发，不适合商店发布。
- 采用“本地脚本打 tag + GitHub Actions 构建 release”的两段式方案。原因：这样比纯手动点 workflow 更接近一键发布，同时不要求本地安装额外 GitHub CLI。

## In flight / blocked

- 尚未在真实 GitHub Actions 上跑一次完整 canary 流水线；需要 Elvis 用脚本触发并观察第一次运行结果。

## Handoff

下一次最合理的动作：

1. 在仓库根目录运行：
   - `./scripts/release_android_canary.sh`
   - 或带标签：`./scripts/release_android_canary.sh reset-flow`
2. 去 GitHub Actions 看 `Android Canary` workflow 是否成功。
3. 从生成的 pre-release 下载 APK 做 Android 测试。

## Questions for Elvis

- [ ] 目前没有新的阻塞问题。

## Ideas

- 等 Android canary 流水线跑顺后，可以再补一个“正式 Android release” workflow，把签名切到正式 keystore 并区分 prerelease / release。

---

## Files touched

- `.github/workflows/android-canary.yml`: new
- `scripts/release_android_canary.sh`: new
- `docs/worklog/2026-04-18_android_canary_release_automation.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
