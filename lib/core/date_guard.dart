// ─────────────────────────────────────────────────────────────────────────────
// date_guard.dart
//
// 模块定位（CORE REQ 5）：
//   强制「只有今天的节点可编辑」，所有历史/未来节点 100% 只读。
//
//   这是「迹点」的核心心智模型：时间轴上的每一天都是一次「不可回改」的存证。
//   允许用户修改过去 = 打破所有叙事可信度 → 绝对禁止。
//
//   语义细节：
//     - 「今天」严格由 `TimeIntegrityService.now()` 决定（见 REQ 2 防回拨）。
//     - 对比只看 Y-M-D，不看小时分钟 — 跨午夜自动切换到「昨天只读」。
//     - 「未来」也一并禁止编辑，避免用户滑到未来日期点击打卡。
//     - 同时暴露 `isEditable(date)` 供 UI 层预判（灰掉按钮），
//       和 `assertEditableToday(date)` 供服务层在真正写入前做最后一道防线。
// ─────────────────────────────────────────────────────────────────────────────

import 'time_integrity_service.dart';

/// 违反「只可编辑今日」规则时抛出。
/// 服务层应直接向上抛，UI 层 catch 后可提示用户。
class ReadOnlyPastException implements Exception {
  final DateTime attemptedDate;
  final DateTime today;
  ReadOnlyPastException(this.attemptedDate, this.today);

  @override
  String toString() =>
      'ReadOnlyPastException: date=${_fmt(attemptedDate)} is not today (${_fmt(today)})';

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 只读/可写日期的守门员。纯静态工具类。
class DateGuard {
  DateGuard._();

  /// 返回 `DateTime` 的「纯日期」部分（00:00:00）
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 获取「今天」（来自可信时间服务）
  static DateTime today() => dateOnly(TimeIntegrityService.instance.now());

  /// 是否是「今天」(Y-M-D 相等)
  static bool isToday(DateTime target) => dateOnly(target) == today();

  /// 目标日期是否可编辑（只有今天可编辑）
  static bool isEditable(DateTime target) => isToday(target);

  /// 断言「目标日期 == 今天」；否则抛 [ReadOnlyPastException]。
  /// 在 storage 写入路径上调用，作为服务层最后的防线。
  static void assertEditableToday(DateTime target) {
    final t = today();
    if (dateOnly(target) != t) {
      throw ReadOnlyPastException(target, t);
    }
  }
}
