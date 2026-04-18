import 'package:flutter/services.dart';

/// 触觉反馈服务 — iOS17.2+ 灵动触觉 / Android 原生震动
/// 全操作触控反馈（灵动不生硬）
class HapticService {
  HapticService._();

  /// 横向滑动切换日期：轻量灵动滑感反馈
  static void dateSlide() {
    HapticFeedback.mediumImpact();
  }

  /// 点击今日节点切换打卡：核心动作，明显但不过分沉重
  static void checkInToggle() {
    HapticFeedback.heavyImpact();
  }

  /// 新增自定义行动线：柔和确认反馈
  static void lineAdded() {
    HapticFeedback.mediumImpact();
  }

  /// 长按自定义节点进入删除模式：稳实反馈
  static void longPressEnter() {
    HapticFeedback.mediumImpact();
  }

  /// 删除自定义行动线：清晰结束反馈
  static void lineDeleted() {
    HapticFeedback.heavyImpact();
  }

  /// 纵向拉动过阈值，+ 号变实：轻量反馈
  static void pullThresholdReached() {
    HapticFeedback.selectionClick();
  }

  /// 引导消失：柔和收尾反馈
  static void onboardingComplete() {
    HapticFeedback.lightImpact();
  }

  /// 间断打卡显示天数
  static void gapNotice() {
    HapticFeedback.selectionClick();
  }

  /// 连续次日启动
  static void welcomeBack() {
    HapticFeedback.lightImpact();
  }

  /// 0.3s 短按唤起节点操作菜单：轻量触发反馈
  static void actionMenuOpen() {
    HapticFeedback.mediumImpact();
  }

  /// 选中某个操作图标：清晰确认
  static void actionMenuSelect() {
    HapticFeedback.mediumImpact();
  }

  /// 查看过去备注：比今天操作更轻，但不至于完全没存在感
  static void historicalNoteOpen() {
    HapticFeedback.lightImpact();
  }

  /// 归档 / 恢复线
  static void lineArchived() {
    HapticFeedback.mediumImpact();
  }

  /// 纵向滑动手感 — 行切换时轻触反馈
  static void verticalScrollTick() {
    HapticFeedback.selectionClick();
  }
}
