import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 轨迹节点状态
enum TrailNodeState {
  completed, // 已完成 — 实心 + 微光
  incomplete, // 未完成 — 空心虚线
  today, // 今日 — 高亮红
  future, // 未来 — 迷雾
}

/// 轨迹节点组件
class TrailNode extends StatelessWidget {
  final TrailNodeState state;
  final bool isToday;
  final bool canTap;
  final VoidCallback? onTap;

  const TrailNode({
    super.key,
    required this.state,
    this.isToday = false,
    this.canTap = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _fillColor,
          border: _border,
          boxShadow: _glow,
        ),
      ),
    );
  }

  double get _size => isToday ? 16.0 : 10.0;

  Color get _fillColor {
    switch (state) {
      case TrailNodeState.completed:
        return AppTheme.trailWhite;
      case TrailNodeState.incomplete:
        return Colors.transparent;
      case TrailNodeState.today:
        return AppTheme.todayHighlight;
      case TrailNodeState.future:
        return Colors.transparent;
    }
  }

  BoxBorder? get _border {
    switch (state) {
      case TrailNodeState.completed:
        return null;
      case TrailNodeState.incomplete:
        return Border.all(color: AppTheme.trailGray, width: 1.5, strokeAlign: BorderSide.strokeAlignInside);
      case TrailNodeState.today:
        return Border.all(color: AppTheme.todayHighlight, width: 2, strokeAlign: BorderSide.strokeAlignInside);
      case TrailNodeState.future:
        return Border.all(color: AppTheme.trailGray.withValues(alpha: 0.3), width: 1, strokeAlign: BorderSide.strokeAlignInside);
    }
  }

  List<BoxShadow>? get _glow {
    switch (state) {
      case TrailNodeState.completed:
        return [
          BoxShadow(
            color: AppTheme.nodeGlow,
            blurRadius: 6,
            spreadRadius: 2,
          ),
        ];
      case TrailNodeState.today:
        return [
          BoxShadow(
            color: AppTheme.todayHighlight.withValues(alpha: 0.4),
            blurRadius: 8,
            spreadRadius: 3,
          ),
        ];
      default:
        return null;
    }
  }
}
