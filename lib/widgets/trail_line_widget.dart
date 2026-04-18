import 'package:flutter/material.dart';
import '../models/trail_line.dart';
import '../theme/app_theme.dart';

/// 单条轨迹线 — 节点 + 连接线
class TrailLineWidget extends StatelessWidget {
  final TrailLine line;
  final DateTime date;
  final bool isToday;
  final VoidCallback onToggle;

  const TrailLineWidget({
    super.key,
    required this.line,
    required this.date,
    required this.isToday,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = line.isCompletedOn(date);
    final isFuture = isToday ? false : date.isAfter(DateTime.now());

    // 节点状态颜色
    Color nodeColor;
    double nodeSize;

    if (isFuture) {
      // 未来：迷雾
      nodeColor = AppTheme.trailGray.withValues(alpha: 0.2);
      nodeSize = 6;
    } else if (isToday) {
      // 今日：高亮红
      nodeColor = AppTheme.todayHighlight;
      nodeSize = 14;
    } else if (isCompleted) {
      // 已完成
      nodeColor = line.type == TrailLineType.alive ? AppTheme.warmGold : AppTheme.trailWhite;
      nodeSize = 8;
    } else {
      // 未完成历史
      nodeColor = Colors.transparent;
      nodeSize = 7;
    }

    return GestureDetector(
      onTap: isFuture ? null : onToggle,
      child: Container(
        width: nodeSize,
        height: nodeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isFuture || isCompleted || isToday ? nodeColor : Colors.transparent,
          border: (!isFuture && !isCompleted && !isToday)
              ? Border.all(color: AppTheme.trailGray.withValues(alpha: 0.4), width: 1.0)
              : isToday
                  ? Border.all(color: AppTheme.todayHighlight, width: 1.5)
                  : null,
          boxShadow: (isToday || isCompleted)
              ? [
                  BoxShadow(
                    color: nodeColor.withValues(alpha: isToday ? 0.5 : 0.3),
                    blurRadius: isToday ? 10 : 5,
                    spreadRadius: isToday ? 3 : 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
