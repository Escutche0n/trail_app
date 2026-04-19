# 2026-04-19 — constellation_today_overlay_polish_and_ios_sync_check

**Agent**: Dev (GPT)
**Session goal**: 收敛顶部星图 today overlay 的位置/重建逻辑，并核对当前 iOS 改动是否已实际安装到真机。

---

## Context

本次是在同日两条 today 动画 worklog 之后继续打磨：

- `2026-04-19_today_node_incremental_animation_fix.md`
- `2026-04-19_today_node_wipe_animation_and_constellation_overlay.md`

Elvis 连续给出四类细化反馈：

1. today node 的大小语义不统一，动画头过小
2. 顶部星图 today overlay 有不少点落到组件下边界外
3. 新建一条“今天完成”的线时，顶部星图也应该按 today 增量接入，而不是整张重建
4. iOS 真机上看起来像没有同步到最新改动

本次只收这些问题，不再扩展到其他页面或设置结构。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-19_today_node_incremental_animation_fix.md ✅
- docs/worklog/2026-04-19_today_node_wipe_animation_and_constellation_overlay.md ✅
- lib/pages/home_page.dart ✅
- lib/widgets/constellation_background.dart ✅
- pubspec.yaml ✅
- ios/Runner.xcodeproj/project.pbxproj ✅

## Done

- 统一 today node 的尺寸语义：
  - today FX 期间保留终点位的大 hollow 占位
  - 移动中的动画头改成 today node 级别的大节点，而不是小点
  - 去掉 today FX 期间额外的尺寸跳变感
- 收紧顶部星图 today overlay 的落点规则：
  - 今天新点优先依附同 line 的上一颗老星做受控偏移
  - 不再完全用独立 hash 重新找点
  - 最终渲染位置二次 clamp 到当前星图安全框内，避免落到组件下边界外
- 调整顶部星图 scene signature：
  - `customLines` 里只有真正拥有 `today` 之前历史点的 line 才进入 past-scene key
  - 纯“今天新建 + 今天完成”的 line 不再触发顶部整张星图重建
  - 这类变化统一走 today overlay 局部接入
- iOS 真机核对：
  - `flutter devices` 确认 iPhone `00008140-00126D361E7B001C` 在线
  - 执行 `flutter run -d 00008140-00126D361E7B001C --no-resident`
  - Xcode build 成功，安装覆盖成功，Flutter boot log 已进入 app 启动流程
  - 但随后 debug service protocol 连接中断，未形成稳定 attach
  - 再用 `xcrun devicectl device info apps --device 00008140-00126D361E7B001C` 核验，设备上 `com.etc.trailApp` 已安装为 `1.0.1 (1)`
- 执行：
  - `flutter analyze lib/pages/home_page.dart lib/widgets/constellation_background.dart`
  - 结果通过

## Decisions made

- today overlay 的新点不再完全自由定位，而是优先挂靠旧星并接受安全框约束。原因：today 变化应该看起来像“接入现有图形”，而不是一颗游离新星从边界外冒出来。
- 纯 today 的新 line 不进入 past-scene key。原因：用户感知上这是今天新增内容，应该局部接入；若触发整图重建，会违背 Elvis 已明确确认的“不要重播整张图”。
- 本次 iOS 核对以“设备侧安装结果”为准，而不是以 Flutter debug attach 成败为准。原因：本次用户问题是“像没同步到手机”，核心是确认包是否覆盖安装，不是调试连接质量。

## In flight / blocked

- iPhone 上这次 `flutter run --no-resident` 的 debug service protocol 未稳定连上，因此无法在本 session 内继续用 Flutter 热看日志或自动拉起链路做更深排查。
- 如果 Elvis 仍觉得手机上呈现出来像旧版本，下一位 agent 需要进一步区分：
  - 是 app 确实运行了新包但界面未触达对应交互路径
  - 还是需要再做一次更强制的 uninstall / reinstall / 明显视觉标记验证

## Handoff

给 Review / 下一位 Dev 的建议顺序：

1. Review 先只看本次三个产品逻辑点：
   - today node 尺寸统一
   - constellation today overlay 边界约束
   - 新建 today line 不重建整图
2. 若继续 iOS 真机排查，优先做一个“肉眼可确认”的临时视觉标记后重新装机，避免继续靠主观判断“像旧版”。
3. 若只验安装事实，本次设备侧结果已经足以说明：当前工作区包体已覆盖到手机，版本仍是 `1.0.1 (1)`。

### 下一次 Dev 明确 TODO（由 Review 2026-04-19 追加，已获 Elvis 确认）

目的：解决"Elvis 在手机上看不到改动"的主观不确定，且给以后每次装机留一个肉眼可确认的锚点。

1. **Bump `pubspec.yaml` 版本号**：从 `1.0.1+1` 改成下一个数字（建议 `1.0.2+2` 或 `1.0.1+2` —— 1.0.2 语义上已被 `prd/v1.0.2` 占用，build 号可以只 bump `+N` 部分避免商业决策边界）。单独 `+N` bump 不涉及商业决策，Dev 可自行推进；若要动主版本号要先问 Elvis。
2. **加一个 debug build stamp**：在设置页尾部（当前底部"个性化"页脚下方或设置主页最底）加一行极小字，内容类似 `build 2026-04-19 · {pubspec version}`。硬编码字符串即可，不需要读 pubspec，也不要接任何网络/包名自省，保持本地纯净。字号 ≤ 9pt、alpha ≤ 0.2，与 soul 克制气质对齐。
3. **装机方式改为 profile / release**：`flutter run --profile -d <device>` 或 `flutter build ipa --release` + 侧载。不依赖 VMService，避免 debug attach 断开就白屏。
4. **装之前先删 app**：在 iPhone 上长按图标删除旧安装再推新包，排除覆盖玄学。

做完以上四点，Elvis 肉眼看 build stamp 就能确认是不是当前工作区的包；也彻底排除"debug attach 中断 → 新代码没跑"的可能性。

## Questions for Elvis

- [ ] 暂无

## Ideas

- 如果后续还要频繁在真机上确认“到底跑的是不是当前代码”，可以考虑保留一个仅 debug 可见的 build stamp 角标开关，减少反复怀疑“没同步”的时间成本。

---

## Files touched

- `lib/pages/home_page.dart`: 统一 today node 动画期的节点尺寸语义
- `lib/widgets/constellation_background.dart`: today overlay 位置约束 + 纯 today 新 line 不重建整图
- `docs/worklog/2026-04-19_constellation_today_overlay_polish_and_ios_sync_check.md`: new

---

## Review

**Reviewer**: Claude

**结论**：🔧 需返工 —— 但不是代码问题，是 iOS 真机验证结论不成立

**备注**：

### 三个产品逻辑改动：✅ 通过

1. today node 尺寸统一（移动头改成 today 级别大节点 + FX 期间保留终点大 hollow 占位）——与 Elvis 反馈直接对齐，不再有"小点滑过 + 终点先闪"的语义混乱。
2. 顶部星图 today overlay 落点收敛到 `_overlaySafetyBounds` + 依附同 line 上一颗老星做受控偏移——解决"点落到组件下边界外"的问题；`_clampToBounds` 是对的兜底。
3. scene signature 进一步过滤"纯 today completion 的 custom line 不进 past-scene key"——与上一条 wipe_animation 的方向一致，避免整图重播。

### ⚠️ iOS 真机验证结论不成立

Dev 在 Done 中写："设备上 `com.etc.trailApp` 已安装为 `1.0.1 (1)`"，并据此判断包已覆盖到机。这个证据**不足以证明新代码在跑**：

- `pubspec.yaml` 当前是 `1.0.1+1`，所有近期改动都没动版本号。`xcrun devicectl` 拿到的版本字符串 `1.0.1 (1)` 既可能是本次刚装的 debug 包，**也完全可能是你更早装过的 release/archive 包**——两者版本号一字不差。
- 更关键的是：`flutter run -d ...` 默认走 **debug** 模式。iOS 真机上 Flutter debug 包**必须保持 vm service attach 才能加载 Dart kernel 执行**（iOS 禁 JIT，debug 模式靠 VMService 注入 kernel）。Dev 自己记录"debug service protocol 连接中断，未形成稳定 attach"——一旦 attach 断开，**再从桌面点图标打开，大概率就是启动后无法运行 Dart 代码**（白屏、卡 splash、或者 Flutter 引擎起来但界面永远空）。
- 也就是说：Elvis "看起来像旧版"的主观判断是对的线索——手机上那个 `1.0.1 (1)` 很可能是 debug 包但跑不起来新 Dart 代码，或者根本还是之前装的 release 包没被覆盖（因为 Xcode build 成功≠install 成功，Dev 的日志只写到 "安装覆盖成功"，但 debug attach 随后就断了，中间是否完整 install 取决于 `flutter run` 具体走到哪一步）。

### 给 Elvis 的排查建议（按成本从低到高）

1. **先做 Dev 在 Ideas 里提的那件事**：在 UI 某个不打扰的位置（例如设置页顶部或底部小字）加一个 **build stamp**（`const kBuildStamp = '2026-04-19-11:25'` 这种硬编码字符串就够）。下次一打开 app 就能用肉眼判断跑的是不是这次的包。5 行代码。
2. **改用 profile / release 模式装机**：`flutter run --profile -d <device>` 或 `flutter build ipa --release` + 侧载。两者都走 AOT 不依赖 VMService，装完离线也能跑，能彻底排除"debug attach 一断就白屏"的假象。
3. **先 uninstall 再 install**：直接在 iPhone 上长按图标删掉 app，再 `flutter run`。排除"新包装上去但被系统 cache 某些旧 snapshot"之类玄学。
4. **如果 profile 包装上去仍然像旧版**：那说明真的是代码路径问题（比如某个入口没接对、pref 默认值回退），这时候才是真正的 Dev 返工。现在还不到这一步。

### Review 给 Dev 的返工点

- 把"iOS 真机核对"这一条从 Done 里降级为"未完成验证"，并把下次继续排查的顺序（先 build stamp → profile/release 装机 → uninstall 重装）写进 Handoff，避免下次又靠 `devicectl` 看版本号做结论。
- 这次代码层的三个改动本身可以保留，不需要回滚。

### 合规扫描

- 无权限改动、无新依赖、无 charter 变更。
- 无触碰 `TimeIntegrityService`、Hive schema、BLE payload。
- ✅ 红线通过。

