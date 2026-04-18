# 2026-04-18 Android stable release baseline

## Goal

建立正式 stable 发布口径，先把当前主线收成 `v1.0.0`，之后继续让 `android-canary-*` 走更快的测试节奏。

## Completed

- 新增 GitHub Actions workflow [android-stable.yml](/Users/elvischen/Developer/trail/trail_app/.github/workflows/android-stable.yml)，在 `v*` tag push 时自动：
  - `flutter analyze`
  - `flutter build apk --release`
  - 生成 stable release notes
  - 创建 GitHub 正式 Release 并上传 APK
- 新增本地触发脚本 [release_android_stable.sh](/Users/elvischen/Developer/trail/trail_app/scripts/release_android_stable.sh)，固定从 `pubspec.yaml` 的当前版本裁出 stable tag
- 约定稳定版与测试版分层：
  - Stable: `vX.Y.Z`
  - Canary: `android-canary-vX.Y.Z-build.N-*`

## Notes

- 当前 Android `release` 仍使用 debug keystore 签名，因此这里的 stable 指 GitHub 对外稳定基线，不等于 Play Store 正式分发签名。
- 当前 app 版本仍为 `1.0.0+1`，所以首次 stable tag 应为 `v1.0.0`。

## Next

- 推送当前主线并触发第一次 stable release：`v1.0.0`
- 之后每个新功能继续走更快的 `android-canary-*` 预发布
