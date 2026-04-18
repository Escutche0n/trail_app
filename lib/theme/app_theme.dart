import 'package:flutter/material.dart';

/// 迹点 App 主题定义 — Alto 风深色基调
class AppTheme {
  AppTheme._();

  /// 暖金色 — 「活着」基准线专用
  static const Color warmGold = Color(0xFFD4A843);

  /// 白色 — 自定义行动线
  static const Color trailWhite = Color(0xFFE8E8E8);

  /// 浅灰虚线 — 未完成
  static const Color trailGray = Color(0xFF5A5A5A);

  /// 今日高亮红
  static const Color todayHighlight = Color(0xFFE85D4A);

  /// 节点微光
  static const Color nodeGlow = Color(0x33FFFFFF);

  /// 迷雾色 — 未来区域
  static const Color futureMist = Color(0x1AFFFFFF);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: warmGold,
        secondary: trailWhite,
        surface: Colors.black,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          fontFamily: 'SF Pro Display',
          fontWeight: FontWeight.w300,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'SF Pro Display',
          fontWeight: FontWeight.w300,
        ),
        titleLarge: TextStyle(
          fontFamily: 'SF Pro Display',
          fontWeight: FontWeight.w300,
        ),
      ),
    );
  }
}
