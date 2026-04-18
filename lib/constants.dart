import 'dart:io' show Platform;
import 'package:flutter/material.dart';

/// 全局常量：颜色、尺寸、动画时长、字体
/// Alto's Adventure 风格 — 低饱和度、低对比度、深色基调
class TrailColors {
  TrailColors._();

  // 轨迹线颜色
  static const Color warmGold = Color(0xFFD4A843);       // 「活着」基准线 — 暖金色
  static const Color trailWhite = Color(0xFFE8E8E8);     // 自定义行动线 — 白色
  static const Color trailGray = Color(0xFF5A5A5A);       // 未完成虚线
  static const Color trailGrayLight = Color(0xFF3A3A3A);  // 历史日期文字

  // 节点颜色
  static const Color todayHighlight = Color(0xFFE85D4A);  // 今日高亮 — 红色
  static const Color nodeGlow = Color(0x55FFFFFF);         // 完成节点微光
  static const Color nodeHollow = Color(0xFF4A4A4A);       // 空心节点边框

  // 背景
  static const Color deepBackground = Color(0xFF0A0A0F);  // 深色背景
  static const Color futureMist = Color(0x1AFFFFFF);       // 未来区域迷雾

  // 山脉剪影
  static const Color mountainFar = Color(0xFF1A1A2E);     // 远山
  static const Color mountainMid = Color(0xFF14142A);     // 中山
  static const Color mountainNear = Color(0xFF0E0E22);    // 近山

  // 天气元素
  static const Color starWhite = Color(0xCCFFFFFF);
  static const Color sunGlow = Color(0xFFFFD700);
  static const Color rainDrop = Color(0x66AACCEE);
  static const Color snowFlake = Color(0xAAFFFFFF);

  // UI 元素
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xAAFFFFFF);
  static const Color buttonBackground = Color(0xFFFFFFFF);
  static const Color buttonText = Color(0xFF000000);
  static const Color inputBackground = Color(0x22FFFFFF);
  static const Color divider = Color(0x1AFFFFFF);
}

/// 天空渐变色组 — 6个时间段
class SkyGradients {
  SkyGradients._();

  // 日出 (5:00-7:00)
  static const List<Color> sunrise = [
    Color(0xFF2D1B4E),
    Color(0xFF8B4570),
    Color(0xFFD4846A),
    Color(0xFFE8B87A),
  ];

  // 上午 (7:00-11:00)
  static const List<Color> morning = [
    Color(0xFF4A6FA5),
    Color(0xFF7BA3CC),
    Color(0xFFA8C8E8),
    Color(0xFFD4DFE8),
  ];

  // 正午 (11:00-16:00)
  static const List<Color> noon = [
    Color(0xFF3B6B9E),
    Color(0xFF5C8EBF),
    Color(0xFF8AB4D6),
    Color(0xFFB8D4E8),
  ];

  // 日落 (16:00-19:00)
  static const List<Color> sunset = [
    Color(0xFF1A1A3E),
    Color(0xFF6B3A5E),
    Color(0xFFCC6B4A),
    Color(0xFFE89B5A),
  ];

  // 夜晚 (19:00-22:00)
  static const List<Color> night = [
    Color(0xFF0A0A1E),
    Color(0xFF141428),
    Color(0xFF1E1E38),
    Color(0xFF282848),
  ];

  // 深夜 (22:00-5:00)
  static const List<Color> deepNight = [
    Color(0xFF050510),
    Color(0xFF0A0A18),
    Color(0xFF0F0F20),
    Color(0xFF141428),
  ];
}

/// 尺寸常量
class TrailSizes {
  TrailSizes._();

  static const double dayColumnWidth = 56.0;       // 每日列宽
  static const double nodeSize = 12.0;              // 普通节点直径
  static const double todayNodeSize = 16.0;         // 今日节点直径
  static const double nodeTapTarget = 44.0;         // 最小点击区域(无障碍)
  static const double trackLineHeight = 48.0;       // 轨迹行高度
  static const double dateLabelHeight = 32.0;       // 日期标签高度
  static const double lineStrokeWidth = 1.5;        // 实线宽度
  static const double dashedStrokeWidth = 1.0;      // 虚线宽度
  static const double mountainMaxHeight = 200.0;    // 山脉最大高度
  static const double borderRadius = 12.0;
  static const double borderRadiusLarge = 16.0;
}

/// 动画时长
class TrailDurations {
  TrailDurations._();

  static const Duration splash = Duration(milliseconds: 500);
  static const Duration stampRebound = Duration(milliseconds: 400);
  static const Duration dissipation = Duration(milliseconds: 300);
  static const Duration glowPulse = Duration(milliseconds: 800);
  static const Duration skyTransition = Duration(milliseconds: 2000);
  static const Duration weatherCycle = Duration(seconds: 3);
  static const Duration lineAdd = Duration(milliseconds: 300);
  static const Duration lineDelete = Duration(milliseconds: 250);
  static const Duration pageTransition = Duration(milliseconds: 300);
}

/// 字体配置 — iOS: SF Pro Display, Android: Roboto
class TrailFonts {
  TrailFonts._();

  static String get fontFamily {
    try {
      return Platform.isIOS || Platform.isMacOS ? '.SF Pro Display' : 'Roboto';
    } catch (_) {
      return 'Roboto';
    }
  }

  static const FontWeight light = FontWeight.w300;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
}

/// 全局主题
class TrailTheme {
  TrailTheme._();

  static ThemeData get darkTheme {
    final fontFamily = TrailFonts.fontFamily;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TrailColors.deepBackground,
      fontFamily: fontFamily,
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: TrailFonts.light,
          color: TrailColors.textPrimary,
          fontFamily: fontFamily,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: TrailFonts.light,
          color: TrailColors.textPrimary,
          fontFamily: fontFamily,
        ),
        bodyLarge: TextStyle(
          fontSize: 18,
          fontWeight: TrailFonts.light,
          color: TrailColors.textPrimary,
          fontFamily: fontFamily,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: TrailFonts.light,
          color: TrailColors.textSecondary,
          fontFamily: fontFamily,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: TrailFonts.light,
          color: TrailColors.trailGrayLight,
          fontFamily: fontFamily,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: TrailColors.warmGold,
        secondary: TrailColors.trailWhite,
        surface: TrailColors.deepBackground,
      ),
    );
  }
}
