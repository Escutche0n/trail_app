# 2026-04-18 — git_bootstrap_and_version_reset

**Agent**: Dev (GPT)
**Session goal**: 将当前可运行目录升级为主线 git 仓库，并把版本重置为 1.0.0。

---

## Context

Elvis 明确决定：以当前能跑的 `trail_app/` 目录作为主线起点，不再等待一个外部“更干净”的仓库壳来承接。目标是从这个目录直接开始 git 管理，并把当前版本定为 `1.0.0`。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_ios_release_r0_hardening.md ✅
- pubspec.yaml ✅
- .gitignore ✅
- 目录级生成物分布（`.dart_tool` / `build` / `ios/Pods` / `macos/Pods` / `xcuserdata` / `ephemeral`）✅

## Done

- 将 `pubspec.yaml` 版本从 `1.0.2+2` 重置为 `1.0.0+1`。
- 补齐 `.gitignore`，明确排除 Flutter / Xcode 生成目录：
  - `ios/Pods/`
  - `macos/Pods/`
  - `**/Flutter/ephemeral/`
  - `**/.symlinks/`
  - `**/xcuserdata/`
  - `ios/Flutter/Generated.xcconfig`
  - `ios/Flutter/flutter_export_environment.sh`
- 在当前目录执行 `git init`，并将默认分支改名为 `main`。

## Decisions made

- 主线直接从当前能跑的目录起步，而不是继续追一个外部“未来可能更干净”的 repo。原因：当前目录才是事实上的可运行版本和文档真相源。
- 版本号采用 `1.0.0+1`。原因：对外语义版本回到 `1.0.0`，同时保留 Flutter / iOS / Android 常见的 build number 从 1 起步。
- 本次只做 git 基线和版本归零，不顺手做别的结构清理，避免把 session 扩大成“既建仓又重构又清垃圾”。

## In flight / blocked

- 尚未完成首个 git commit；该动作将在本次 session 内继续。

## Handoff

如果下一位 agent 接手时本次 commit 已完成，下一步最合理的动作是：

1. 用这个 `main` 仓库作为唯一事实源继续开发。
2. 后续每个小版本按 Elvis 当前口径递增版本号。
3. 真机 / 构建验证优先在这个仓库里完成，不再维护平行目录。

## Questions for Elvis

- [ ] 目前没有新的阻塞问题。

## Ideas

- 等首个 commit 稳定后，可以补一个最小的发布规则文档，把“版本号怎么递增”写成仓库内约定，避免后续 agent 各自理解。

---

## Files touched

- `.gitignore`: edited
- `pubspec.yaml`: edited
- `docs/worklog/2026-04-18_git_bootstrap_and_version_reset.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
