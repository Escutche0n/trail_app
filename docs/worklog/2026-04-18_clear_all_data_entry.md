# 2026-04-18 — clear_all_data_entry

**Agent**: Dev (GPT)
**Session goal**: 在设置页实现“清除所有数据”入口，并把 app 恢复到首次启动状态。

---

## Context

`charter/00_soul.md` 明确要求必须存在“清除所有数据”入口；`charter/04_release.md` 也将其列为 R1 项。Elvis 已在对话中明确确认按该方向实现。

## Read

- AGENTS.md ✅
- docs/charter/00_soul.md ✅
- docs/charter/03_boundaries.md ✅
- docs/worklog/2026-04-18_appicon_dedupe_cleanup.md ✅
- lib/pages/settings_page.dart ✅
- lib/services/storage_service.dart ✅
- lib/core/ble_service.dart ✅
- lib/core/core_bootstrap.dart ✅
- lib/core/secure_box_service.dart ✅
- lib/core/time_integrity_service.dart ✅
- lib/core/uid_service.dart ✅

## Done

- 在设置页新增危险操作入口“清除所有数据”。
- 实现双重确认弹窗，避免误触。
- 补齐清档链路：
  - 停止 BLE 扫描与广播
  - 删除 `birthday` / `custom_lines` / `trail_data` / `friends` 的 Hive 物理盒
  - 重置 UID / 时间完整性 / 加密盒运行态
  - 重新执行 bootstrap
  - 跳回生日初始化页

## Decisions made

- 清档后不尝试“热恢复到 app 根组件状态”，而是直接把当前导航栈切回生日初始化页。原因：这样最直接，也最符合“恢复到首次启动状态”的语义。
- `debugReset` 系列不再直接从设置页调用；本次补了一层正式可用的 wipe API，避免把测试专用接口泄露到生产调用点。

## In flight / blocked

- 尚未做真机手点验证；本次只完成了实现和静态校验。

## Handoff

下一次最合理的动作：

1. 由 Elvis 本地编译 Android / iOS 测试包。
2. 重点验证设置页“清除所有数据”流程：
   - 双确认是否符合预期
   - 清档后是否回到生日初始化页
   - 重新设置生日后是否可正常进入主页
3. 若验证通过，可把本功能视为一个可测试小版本收口。

## Questions for Elvis

- [ ] 目前没有新的阻塞问题。

## Ideas

- 后续如果做“导入恢复”增强，可以考虑在清档确认弹窗里提示用户“先导出备份再继续”，但当前不必额外加阻拦。

---

## Files touched

- `lib/services/storage_service.dart`: edited
- `lib/core/ble_service.dart`: edited
- `lib/core/secure_box_service.dart`: edited
- `lib/core/time_integrity_service.dart`: edited
- `lib/core/uid_service.dart`: edited
- `lib/pages/settings_page.dart`: edited
- `docs/worklog/2026-04-18_clear_all_data_entry.md`: new

---

## Review

<待 Review agent 补充。>

**结论**：待 Review

**备注**：
