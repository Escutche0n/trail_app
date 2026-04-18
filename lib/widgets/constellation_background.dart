import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/trail_line.dart';

/// 星图背景装饰层（v0 实现，权威描述见 `docs/specs/constellation.md` 顶部 "v0 实现现状"）
///
/// 渲染内容：
/// - 每个 (lineId, dateKey) 过去完成节点 → 一颗静态位置的星
/// - 按 lineId 分组，组内按 dateKey 串成虚线链
///
/// 动画：
/// - 仅星点 alpha 呼吸（周期 6–10s，相位随机，振幅 ≤ 0.4）
/// - 连线完全静止
///
/// 渲染架构（满足 spec "静态 cache 为 Picture，动画层单独承载动态部分"）：
/// - 输入数据变化时重算一次：`List<_Star>` + 静态虚线段 `ui.Picture`
/// - 每帧 Ticker 只推进 `elapsed`，painter 只重画星点 alpha + `drawPicture` 贴上
///   缓存好的连线
/// - `RepaintBoundary` 把重绘限制在星图层
class ConstellationBackground extends StatefulWidget {
  final Set<String> aliveCheckIns;
  final List<TrailLine> customLines;
  final DateTime today;
  final double topInset;
  final double bottomY;

  const ConstellationBackground({
    super.key,
    required this.aliveCheckIns,
    required this.customLines,
    required this.today,
    required this.topInset,
    required this.bottomY,
  });

  @override
  State<ConstellationBackground> createState() =>
      _ConstellationBackgroundState();
}

class _ConstellationBackgroundState extends State<ConstellationBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _elapsed = ValueNotifier<double>(0.0);

  // 缓存：数据/几何不变时复用，每帧只读不改
  List<_Star> _stars = const <_Star>[];
  ui.Picture? _linesPicture;
  Size? _cachedSize;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      _elapsed.value = d.inMicroseconds / 1e6;
    });
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant ConstellationBackground old) {
    super.didUpdateWidget(old);
    if (!identical(old.aliveCheckIns, widget.aliveCheckIns) ||
        !identical(old.customLines, widget.customLines) ||
        old.topInset != widget.topInset ||
        old.bottomY != widget.bottomY ||
        old.today.day != widget.today.day ||
        old.today.month != widget.today.month ||
        old.today.year != widget.today.year) {
      _stars = const <_Star>[];
      _linesPicture?.dispose();
      _linesPicture = null;
      _cachedSize = null;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    _linesPicture?.dispose();
    super.dispose();
  }

  void _rebuildCache(Size size) {
    final stars = _computeStars(
      size: size,
      topInset: widget.topInset,
      bottomY: widget.bottomY,
      aliveCheckIns: widget.aliveCheckIns,
      customLines: widget.customLines,
      today: widget.today,
    );
    _stars = stars;
    _linesPicture?.dispose();
    _linesPicture = _rasterizeLines(stars, size);
    _cachedSize = size;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ConstellationPainter(
            state: this,
            elapsed: _elapsed,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Star {
  final double x;
  final double y;
  final double baseAlpha;
  final double ampAlpha;
  final double period;
  final double phase;
  final double radius;
  final String dateKey;
  final String lineId;

  _Star({
    required this.x,
    required this.y,
    required this.baseAlpha,
    required this.ampAlpha,
    required this.period,
    required this.phase,
    required this.radius,
    required this.dateKey,
    required this.lineId,
  });
}

// ── 哈希 ───────────────────────────────────────────────────────────────
// FNV-1a 32-bit with salt prefix + Murmur3-style finalizer avalanche.
int _hash(String salt, String s) {
  int h = 0x811c9dc5;
  for (int i = 0; i < salt.length; i++) {
    h ^= salt.codeUnitAt(i);
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  for (int i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  h ^= (h >> 16);
  h = (h * 0x85ebca6b) & 0xFFFFFFFF;
  h ^= (h >> 13);
  h = (h * 0xc2b2ae35) & 0xFFFFFFFF;
  h ^= (h >> 16);
  return h;
}

double _unit(int h) => (h & 0xFFFFFFFF) / 0xFFFFFFFF;

const String _aliveId = '__alive__';

String _todayKey(DateTime today) =>
    '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

List<_Star> _computeStars({
  required Size size,
  required double topInset,
  required double bottomY,
  required Set<String> aliveCheckIns,
  required List<TrailLine> customLines,
  required DateTime today,
}) {
  final double top = topInset + 8.0;
  final double bottom = bottomY;
  if (bottom <= top) return const <_Star>[];
  final double left = 14.0;
  final double right = size.width - 14.0;
  if (right <= left) return const <_Star>[];
  final double areaW = right - left;
  final double areaH = bottom - top;

  final todayKey = _todayKey(today);
  final stars = <_Star>[];

  void addStars(String lineId, Iterable<String> dateKeys) {
    for (final dk in dateKeys) {
      if (dk.compareTo(todayKey) >= 0) continue;
      final id = '$lineId|$dk';
      final hx = _hash('x:', id);
      final hy = _hash('y:', id);
      final hp = _hash('p:', id);
      final hr = _hash('r:', id);
      final u = _unit(hr);
      final radius = 0.6 + u * u * u * 2.8;
      final baseAlpha = 0.40 + u * 0.50;
      final ampAlpha = (0.35 - u * 0.20).clamp(0.10, 0.35);
      final period = 6.0 + _unit(hp) * 4.0;
      final phase = _unit(hp >> 8) * math.pi * 2;
      stars.add(_Star(
        x: left + _unit(hx) * areaW,
        y: top + _unit(hy) * areaH,
        baseAlpha: baseAlpha,
        ampAlpha: ampAlpha,
        period: period,
        phase: phase,
        radius: radius,
        dateKey: dk,
        lineId: lineId,
      ));
    }
  }

  addStars(_aliveId, aliveCheckIns);
  for (final line in customLines) {
    addStars(line.id, line.completedDates);
  }
  return stars;
}

ui.Picture _rasterizeLines(List<_Star> stars, Size size) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  if (stars.isNotEmpty) {
    final byLine = <String, List<_Star>>{};
    for (final s in stars) {
      (byLine[s.lineId] ??= <_Star>[]).add(s);
    }
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    const double dashOn = 3.0;
    const double dashOff = 3.0;
    for (final chain in byLine.values) {
      if (chain.length < 2) continue;
      chain.sort((a, b) => a.dateKey.compareTo(b.dateKey));
      for (int i = 0; i < chain.length - 1; i++) {
        _drawDashedSegment(
          canvas,
          Offset(chain[i].x, chain[i].y),
          Offset(chain[i + 1].x, chain[i + 1].y),
          dashOn,
          dashOff,
          linePaint,
        );
      }
    }
  }
  return recorder.endRecording();
}

void _drawDashedSegment(
  Canvas canvas,
  Offset a,
  Offset b,
  double dashOn,
  double dashOff,
  Paint paint,
) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final total = math.sqrt(dx * dx + dy * dy);
  if (total < 0.5) return;
  final ux = dx / total;
  final uy = dy / total;
  double t = 0.0;
  bool drawing = true;
  while (t < total) {
    final step = drawing ? dashOn : dashOff;
    final end = math.min(t + step, total);
    if (drawing) {
      canvas.drawLine(
        Offset(a.dx + ux * t, a.dy + uy * t),
        Offset(a.dx + ux * end, a.dy + uy * end),
        paint,
      );
    }
    t = end;
    drawing = !drawing;
  }
}

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.state,
    required this.elapsed,
  }) : super(repaint: elapsed);

  final _ConstellationBackgroundState state;
  final ValueNotifier<double> elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    // Lazy rebuild：数据变化或尺寸首次可用时才重算 stars + Picture
    if (state._cachedSize != size || state._linesPicture == null) {
      state._rebuildCache(size);
    }
    final stars = state._stars;
    final picture = state._linesPicture;
    if (stars.isEmpty) return;

    if (picture != null) {
      canvas.drawPicture(picture);
    }

    final t = elapsed.value;
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (final s in stars) {
      final breath = math.sin(2 * math.pi * (t / s.period) + s.phase);
      final alpha = (s.baseAlpha + breath * s.ampAlpha).clamp(0.0, 1.0);
      starPaint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(s.x, s.y), s.radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter old) => false;
}
