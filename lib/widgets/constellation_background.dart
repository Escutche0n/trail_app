import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/trail_line.dart';

/// 顶部背景星点层。
///
/// 当前实现采用“两层生成”：
/// - 骨架层：从 12 套抽象星座模板里选一套，只连骨架
/// - 背景层：剩余星点均匀铺开，不参与连线
///
/// 这样能保证：
/// - 图案始终有一个明确的、居中的“星座”骨架
/// - 背景不会因为硬绑轴顺序而显得杂乱
/// - 画面依然有足够的星点密度和缓慢生命感
class ConstellationBackground extends StatefulWidget {
  final Set<String> aliveCheckIns;
  final List<TrailLine> customLines;
  final DateTime today;
  final double topInset;
  final double bottomY;
  final double visibleHeight;
  final double todayFxValue;
  final String? todayFxLineId;
  final int? todayFxFromDayIndex;
  final bool todayFxAppearing;

  /// 时间轴当前 today-node 的屏幕坐标；由 home_page 计算后透传。
  /// 当前仅作为极罕见兜底 origin，正常路径由 past 星或 anchor 星提供 origin。
  final Offset? timelineTodayNodeScreenPos;

  const ConstellationBackground({
    super.key,
    required this.aliveCheckIns,
    required this.customLines,
    required this.today,
    required this.topInset,
    required this.bottomY,
    required this.visibleHeight,
    required this.todayFxValue,
    required this.todayFxLineId,
    required this.todayFxFromDayIndex,
    required this.todayFxAppearing,
    this.timelineTodayNodeScreenPos,
  });

  @override
  State<ConstellationBackground> createState() =>
      _ConstellationBackgroundState();
}

class _ConstellationBackgroundState extends State<ConstellationBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _elapsed = ValueNotifier<double>(0.0);

  _ConstellationScene _scene = const _ConstellationScene(
    stars: <_Star>[],
    links: <_Link>[],
  );
  Size? _cachedSize;
  double _sceneBuiltAt = 0.0;
  bool _sceneShouldReveal = false;
  bool _didPresentInitialScene = false;

  // ── 今天增量语法 · FX session 缓存（spec: 今天增量语法 · 2026-04-19）
  // 一次 FX session = controller.forward(from:0) 到下一次 controller.forward(from:0)。
  // 内部锁定 origin（bridge 起点）；target 在 FX 持续期（value<1）内也锁定，避免
  // head 指向一个漂移的目标。FX 结束后（value>=1）target 解锁、随漂移呼吸。
  String? _fxSessionLineId;
  bool _fxSessionAppearing = false;
  double _fxPrevValue = 1.0;
  bool _fxSnapshotPending = false;
  Offset? _fxLockedOrigin;
  Offset? _fxLockedTarget;
  String? _fxTier; // 'light' | 'mid' | 'heavy'
  double? _fxHeavyBreathStartElapsed;

  static const double _heavyBreathDuration = 0.6;
  static const double _heavyBreathPeakScale = 1.2;

  void _resetFxCache() {
    _fxLockedOrigin = null;
    _fxLockedTarget = null;
    _fxTier = null;
    _fxHeavyBreathStartElapsed = null;
    _fxSnapshotPending = false;
  }

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
    final oldSignature = _sceneInputSignature(
      aliveCheckIns: old.aliveCheckIns,
      customLines: old.customLines,
      today: old.today,
    );
    final newSignature = _sceneInputSignature(
      aliveCheckIns: widget.aliveCheckIns,
      customLines: widget.customLines,
      today: widget.today,
    );
    if (oldSignature != newSignature ||
        old.topInset != widget.topInset ||
        old.bottomY != widget.bottomY ||
        old.visibleHeight != widget.visibleHeight ||
        old.today.day != widget.today.day ||
        old.today.month != widget.today.month ||
        old.today.year != widget.today.year) {
      _scene = const _ConstellationScene(stars: <_Star>[], links: <_Link>[]);
      _cachedSize = null;
    }

    // ── 今天增量语法：FX session 状态机 ──────────────────────────
    final lid = widget.todayFxLineId;
    final appearing = widget.todayFxAppearing;
    final v = widget.todayFxValue;

    // 识别一次新 session：lineId / appearing 变化，或 controller.forward(from:0)
    // 导致 value 从接近 1 跳回接近 0。
    final controllerReset = _fxPrevValue > 0.8 && v < 0.05;
    final sessionChanged =
        lid != _fxSessionLineId ||
        appearing != _fxSessionAppearing ||
        controllerReset;

    if (lid == null) {
      _resetFxCache();
    } else if (sessionChanged) {
      _resetFxCache();
      _fxSnapshotPending = true;
    }

    // FX 完成瞬间（value 由 <1 升到 ≥1 且 appearing）：若为 heavy 档，
    // 启动一次性呼吸。disappearing 完成时星点已不可见，忽略。
    if (lid != null &&
        appearing &&
        _fxPrevValue < 1.0 &&
        v >= 1.0 &&
        _fxTier == 'heavy' &&
        _fxHeavyBreathStartElapsed == null) {
      _fxHeavyBreathStartElapsed = _elapsed.value;
    }

    _fxSessionLineId = lid;
    _fxSessionAppearing = appearing;
    _fxPrevValue = v;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  void _rebuildCache(Size size) {
    final nextScene = _computeScene(
      size: size,
      topInset: widget.topInset,
      bottomY: widget.bottomY,
      visibleHeight: widget.visibleHeight,
      aliveCheckIns: widget.aliveCheckIns,
      customLines: widget.customLines,
      today: widget.today,
    );
    _scene = nextScene;
    _cachedSize = size;
    final hasScene = nextScene.stars.isNotEmpty;
    if (!_didPresentInitialScene && hasScene) {
      _sceneBuiltAt = _elapsed.value;
      _sceneShouldReveal = true;
      _didPresentInitialScene = true;
    } else {
      _sceneBuiltAt = _elapsed.value;
      _sceneShouldReveal = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ConstellationPainter(state: this, elapsed: _elapsed),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConstellationScene {
  final List<_Star> stars;
  final List<_Link> links;

  const _ConstellationScene({required this.stars, required this.links});
}

enum _StarLayer { anchor, recent, fading, distant }

class _Star {
  final String id;
  final String lineId;
  final String dateKey;
  final _StarLayer layer;
  final double anchorX;
  final double anchorY;
  final double radius;
  final double baseAlpha;
  final double ampAlpha;
  final double breathPeriod;
  final double breathPhase;
  final double driftRadiusX;
  final double driftRadiusY;
  final double driftPeriodX;
  final double driftPeriodY;
  final double driftPhaseX;
  final double driftPhaseY;
  final double motionScale;
  final bool inSkeleton;

  const _Star({
    required this.id,
    required this.lineId,
    required this.dateKey,
    required this.layer,
    required this.anchorX,
    required this.anchorY,
    required this.radius,
    required this.baseAlpha,
    required this.ampAlpha,
    required this.breathPeriod,
    required this.breathPhase,
    required this.driftRadiusX,
    required this.driftRadiusY,
    required this.driftPeriodX,
    required this.driftPeriodY,
    required this.driftPhaseX,
    required this.driftPhaseY,
    required this.motionScale,
    required this.inSkeleton,
  });

  _Star copyWith({
    double? anchorX,
    double? anchorY,
    double? radius,
    double? baseAlpha,
    double? ampAlpha,
    double? driftRadiusX,
    double? driftRadiusY,
    double? motionScale,
    bool? inSkeleton,
  }) {
    return _Star(
      id: id,
      lineId: lineId,
      dateKey: dateKey,
      layer: layer,
      anchorX: anchorX ?? this.anchorX,
      anchorY: anchorY ?? this.anchorY,
      radius: radius ?? this.radius,
      baseAlpha: baseAlpha ?? this.baseAlpha,
      ampAlpha: ampAlpha ?? this.ampAlpha,
      breathPeriod: breathPeriod,
      breathPhase: breathPhase,
      driftRadiusX: driftRadiusX ?? this.driftRadiusX,
      driftRadiusY: driftRadiusY ?? this.driftRadiusY,
      driftPeriodX: driftPeriodX,
      driftPeriodY: driftPeriodY,
      driftPhaseX: driftPhaseX,
      driftPhaseY: driftPhaseY,
      motionScale: motionScale ?? this.motionScale,
      inSkeleton: inSkeleton ?? this.inSkeleton,
    );
  }
}

class _Link {
  final int aIndex;
  final int bIndex;
  final bool dashed;
  final double shimmerPeriod;
  final double shimmerPhase;

  const _Link({
    required this.aIndex,
    required this.bIndex,
    required this.dashed,
    required this.shimmerPeriod,
    required this.shimmerPhase,
  });
}

class _TemplatePoint {
  final double x;
  final double y;

  const _TemplatePoint(this.x, this.y);
}

class _ConstellationTemplate {
  final String name;
  final List<_TemplatePoint> points;
  final List<(int, int)> edges;

  const _ConstellationTemplate({
    required this.name,
    required this.points,
    required this.edges,
  });
}

const List<_ConstellationTemplate> _templates = [
  _ConstellationTemplate(
    name: 'aries',
    points: [
      _TemplatePoint(0.18, 0.44),
      _TemplatePoint(0.30, 0.34),
      _TemplatePoint(0.43, 0.40),
      _TemplatePoint(0.55, 0.32),
      _TemplatePoint(0.67, 0.38),
    ],
    edges: [(0, 1), (1, 2), (2, 3), (3, 4)],
  ),
  _ConstellationTemplate(
    name: 'taurus',
    points: [
      _TemplatePoint(0.18, 0.28),
      _TemplatePoint(0.30, 0.40),
      _TemplatePoint(0.42, 0.28),
      _TemplatePoint(0.55, 0.42),
      _TemplatePoint(0.70, 0.52),
      _TemplatePoint(0.54, 0.18),
    ],
    edges: [(0, 1), (1, 2), (2, 5), (2, 3), (3, 4)],
  ),
  _ConstellationTemplate(
    name: 'gemini',
    points: [
      _TemplatePoint(0.24, 0.20),
      _TemplatePoint(0.22, 0.54),
      _TemplatePoint(0.38, 0.28),
      _TemplatePoint(0.40, 0.62),
      _TemplatePoint(0.56, 0.26),
      _TemplatePoint(0.58, 0.58),
      _TemplatePoint(0.72, 0.18),
      _TemplatePoint(0.74, 0.52),
    ],
    edges: [(0, 2), (2, 4), (4, 6), (1, 3), (3, 5), (5, 7), (2, 3), (4, 5)],
  ),
  _ConstellationTemplate(
    name: 'cancer',
    points: [
      _TemplatePoint(0.22, 0.44),
      _TemplatePoint(0.36, 0.34),
      _TemplatePoint(0.50, 0.44),
      _TemplatePoint(0.62, 0.30),
      _TemplatePoint(0.74, 0.40),
    ],
    edges: [(0, 1), (1, 2), (2, 3), (3, 4)],
  ),
  _ConstellationTemplate(
    name: 'leo',
    points: [
      _TemplatePoint(0.18, 0.48),
      _TemplatePoint(0.28, 0.28),
      _TemplatePoint(0.42, 0.20),
      _TemplatePoint(0.52, 0.34),
      _TemplatePoint(0.64, 0.26),
      _TemplatePoint(0.76, 0.44),
      _TemplatePoint(0.62, 0.56),
    ],
    edges: [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6)],
  ),
  _ConstellationTemplate(
    name: 'virgo',
    points: [
      _TemplatePoint(0.16, 0.20),
      _TemplatePoint(0.24, 0.50),
      _TemplatePoint(0.36, 0.26),
      _TemplatePoint(0.44, 0.58),
      _TemplatePoint(0.56, 0.24),
      _TemplatePoint(0.62, 0.56),
      _TemplatePoint(0.76, 0.34),
      _TemplatePoint(0.84, 0.50),
    ],
    edges: [
      (0, 1),
      (1, 3),
      (3, 5),
      (2, 4),
      (4, 6),
      (6, 7),
      (1, 2),
      (3, 4),
      (5, 6),
    ],
  ),
  _ConstellationTemplate(
    name: 'libra',
    points: [
      _TemplatePoint(0.22, 0.42),
      _TemplatePoint(0.34, 0.30),
      _TemplatePoint(0.48, 0.22),
      _TemplatePoint(0.62, 0.30),
      _TemplatePoint(0.76, 0.42),
    ],
    edges: [(0, 1), (1, 2), (2, 3), (3, 4)],
  ),
  _ConstellationTemplate(
    name: 'scorpio',
    points: [
      _TemplatePoint(0.14, 0.22),
      _TemplatePoint(0.18, 0.54),
      _TemplatePoint(0.32, 0.26),
      _TemplatePoint(0.38, 0.60),
      _TemplatePoint(0.50, 0.30),
      _TemplatePoint(0.58, 0.56),
      _TemplatePoint(0.70, 0.36),
      _TemplatePoint(0.82, 0.24),
    ],
    edges: [(0, 1), (1, 3), (3, 5), (5, 6), (6, 7), (1, 2), (3, 4)],
  ),
  _ConstellationTemplate(
    name: 'sagittarius',
    points: [
      _TemplatePoint(0.18, 0.58),
      _TemplatePoint(0.32, 0.42),
      _TemplatePoint(0.46, 0.30),
      _TemplatePoint(0.62, 0.18),
      _TemplatePoint(0.58, 0.44),
      _TemplatePoint(0.78, 0.50),
      _TemplatePoint(0.48, 0.56),
    ],
    edges: [(0, 1), (1, 2), (2, 3), (2, 4), (4, 5), (1, 6), (6, 5)],
  ),
  _ConstellationTemplate(
    name: 'capricorn',
    points: [
      _TemplatePoint(0.16, 0.34),
      _TemplatePoint(0.28, 0.48),
      _TemplatePoint(0.40, 0.32),
      _TemplatePoint(0.52, 0.50),
      _TemplatePoint(0.68, 0.22),
      _TemplatePoint(0.82, 0.30),
    ],
    edges: [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)],
  ),
  _ConstellationTemplate(
    name: 'aquarius',
    points: [
      _TemplatePoint(0.14, 0.30),
      _TemplatePoint(0.26, 0.22),
      _TemplatePoint(0.38, 0.30),
      _TemplatePoint(0.50, 0.22),
      _TemplatePoint(0.62, 0.30),
      _TemplatePoint(0.74, 0.22),
      _TemplatePoint(0.84, 0.30),
    ],
    edges: [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6)],
  ),
  _ConstellationTemplate(
    name: 'pisces',
    points: [
      _TemplatePoint(0.18, 0.20),
      _TemplatePoint(0.30, 0.34),
      _TemplatePoint(0.42, 0.44),
      _TemplatePoint(0.54, 0.34),
      _TemplatePoint(0.68, 0.20),
      _TemplatePoint(0.42, 0.60),
    ],
    edges: [(0, 1), (1, 2), (2, 3), (3, 4), (2, 5)],
  ),
];

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

double _lerp(double a, double b, double t) => a + (b - a) * t;

const String _aliveId = '__alive__';

/// 哨兵 dateKey：表示「该 line 的 anchor 星」（line 出生即生成，
/// 不绑任何 completion 日期）。用 '__anchor__' 是为了：
/// - lexically > 任意 'YYYY-MM-DD'，被 `_latestPastStarForLine` 自然过滤掉
/// - 与 `addStars` 内 `dk.compareTo(todayKey) < 0` 过滤天然不冲突
const String _anchorDateKey = '__anchor__';

bool _isAnchorStar(_Star star) => star.dateKey == _anchorDateKey;

String _todayKey(DateTime today) =>
    '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

DateTime _parseDateKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String _yesterdayKey(DateTime today) {
  final y = today.subtract(const Duration(days: 1));
  return '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
}

String _sceneInputSignature({
  required Set<String> aliveCheckIns,
  required List<TrailLine> customLines,
  required DateTime today,
}) {
  final todayKey = _todayKey(today);
  final parts = <String>[
    'alive:${(aliveCheckIns.where((dk) => dk.compareTo(todayKey) < 0).toList()..sort()).join(',')}',
  ];
  // 包含所有 line.id —— 无论是否有过去完成。新建一条空 line 也要触发 scene
  // 重建，以便在画布上加入该 line 的 anchor 星。
  for (final line in customLines) {
    final dates =
        line.completedDates.where((dk) => dk.compareTo(todayKey) < 0).toList()
          ..sort();
    parts.add('${line.id}:${dates.join(',')}');
  }
  return parts.join('|');
}

/// Anchor 星位置：围绕主星图中心的环带。
/// - 中心：对齐当前主骨架中心
/// - 内半径：基本覆盖主骨架，让 anchor 不会压进核心图形
/// - 外半径：限制在顶部星图安全区域内
/// hash from lineId 决定角度与半径。
Offset _donutAnchorPos({
  required Size size,
  required String lineId,
  required double left,
  required double right,
  required double top,
  required double bottomY,
}) {
  final areaW = right - left;
  final areaH = bottomY - top;
  final skeleton = _skeletonBounds(
    size: size,
    left: left,
    top: top,
    bottomY: bottomY,
    areaW: areaW,
    areaH: areaH,
  );
  final center = Offset(
    (skeleton.left + skeleton.right) / 2,
    (skeleton.top + skeleton.bottom) / 2,
  );
  final skeletonHalfW = (skeleton.right - skeleton.left) / 2;
  final skeletonHalfH = (skeleton.bottom - skeleton.top) / 2;
  final skeletonCoverRadius =
      math.sqrt(skeletonHalfW * skeletonHalfW + skeletonHalfH * skeletonHalfH) +
      12.0;
  final maxRadius = math.min(
    math.min(center.dx - left, right - center.dx),
    math.min(center.dy - top, bottomY - center.dy),
  );
  final innerRadius = math.min(
    skeletonCoverRadius,
    math.max(0.0, maxRadius - 24.0),
  );
  final outerRadius = math.max(innerRadius + 12.0, maxRadius - 6.0);

  final rawAngle = _unit(_hash('anchor-a:', lineId));
  final rawRadius = _unit(_hash('anchor-rpos:', lineId));
  final angle = rawAngle * math.pi * 2;
  final radius = _lerp(innerRadius, outerRadius, rawRadius);
  final candidate = Offset(
    center.dx + math.cos(angle) * radius,
    center.dy + math.sin(angle) * radius,
  );
  return Offset(
    candidate.dx.clamp(left + 6.0, right - 6.0),
    candidate.dy.clamp(top + 6.0, bottomY - 66.0),
  );
}

_Star _buildLineAnchorStar({
  required Size size,
  required String lineId,
  required double left,
  required double right,
  required double top,
  required double bottomY,
}) {
  final id = '__anchor__|$lineId';
  final pos = _donutAnchorPos(
    size: size,
    lineId: lineId,
    left: left,
    right: right,
    top: top,
    bottomY: bottomY,
  );
  final rawR = _unit(_hash('anchor-r:', lineId));
  final rawP = _unit(_hash('anchor-p:', lineId));
  return _Star(
    id: id,
    lineId: lineId,
    dateKey: _anchorDateKey,
    layer: _StarLayer.anchor,
    anchorX: pos.dx,
    anchorY: pos.dy,
    radius: 0.85 + rawR * 0.85,
    // baseAlpha 偏高：让 anchor 在 baseAlpha 排序里靠前 → index 低 →
    // 8s skip window 内自然现身，不被 reveal 动画延迟。
    baseAlpha: 0.62 + rawR * 0.10,
    ampAlpha: 0.08,
    breathPeriod: 9.0 + rawP * 5.0,
    breathPhase: _unit(_hash('anchor-bp:', lineId)) * math.pi * 2,
    driftRadiusX: 0.4 + _unit(_hash('anchor-dx:', lineId)) * 0.8,
    driftRadiusY: 0.3 + _unit(_hash('anchor-dy:', lineId)) * 0.6,
    driftPeriodX: 28.0 + _unit(_hash('anchor-dpx:', lineId)) * 18.0,
    driftPeriodY: 34.0 + _unit(_hash('anchor-dpy:', lineId)) * 20.0,
    driftPhaseX: _unit(_hash('anchor-dphx:', lineId)) * math.pi * 2,
    driftPhaseY: _unit(_hash('anchor-dphy:', lineId)) * math.pi * 2,
    motionScale: 0.55,
    inSkeleton: false,
  );
}

_ConstellationScene _computeScene({
  required Size size,
  required double topInset,
  required double bottomY,
  required double visibleHeight,
  required Set<String> aliveCheckIns,
  required List<TrailLine> customLines,
  required DateTime today,
}) {
  final naturalTop = topInset + 8.0;
  final top = math.max(naturalTop, bottomY - visibleHeight);
  if (bottomY <= top || visibleHeight <= 0) {
    return const _ConstellationScene(stars: <_Star>[], links: <_Link>[]);
  }
  final left = 14.0;
  final right = size.width - 14.0;
  if (right <= left) {
    return const _ConstellationScene(stars: <_Star>[], links: <_Link>[]);
  }

  final areaW = right - left;
  final areaH = bottomY - top;
  final todayKey = _todayKey(today);
  final rawStars = <_Star>[];

  void addStars(String lineId, Iterable<String> rawDateKeys) {
    final dateKeys =
        rawDateKeys.where((dk) => dk.compareTo(todayKey) < 0).toList()..sort();
    if (dateKeys.isEmpty) return;

    for (int i = 0; i < dateKeys.length; i++) {
      final dk = dateKeys[i];
      final id = '$lineId|$dk';
      final eventDate = DateUtils.dateOnly(_parseDateKey(dk));
      final ageDays = DateUtils.dateOnly(today).difference(eventDate).inDays;
      final layer = ageDays <= 30
          ? _StarLayer.recent
          : (ageDays <= 60 ? _StarLayer.fading : _StarLayer.distant);
      final recentness = dateKeys.length == 1 ? 1.0 : i / (dateKeys.length - 1);
      final rawX = _unit(_hash('x:', id));
      final rawY = _unit(_hash('y:', id));
      final rawR = _unit(_hash('r:', id));
      final rawP = _unit(_hash('p:', id));
      final fadeT = ((ageDays - 30) / 30).clamp(0.0, 1.0);
      final pos = switch (layer) {
        _StarLayer.recent => Offset(
          left + (0.08 + rawX * 0.84) * areaW,
          top + (0.10 + rawY * 0.84) * areaH,
        ),
        _StarLayer.fading => Offset(
          left + (0.04 + rawX * 0.92) * areaW,
          top + (0.06 + rawY * 0.88) * areaH,
        ),
        _StarLayer.distant => Offset(
          left + (0.02 + rawX * 0.96) * areaW,
          top + (0.04 + rawY * 0.92) * areaH,
        ),
        _StarLayer.anchor => Offset.zero,
      };
      rawStars.add(
        _Star(
          id: id,
          lineId: lineId,
          dateKey: dk,
          layer: layer,
          anchorX: pos.dx,
          anchorY: pos.dy,
          radius: switch (layer) {
            _StarLayer.recent => 0.48 + rawR * rawR * 1.18,
            _StarLayer.fading => _lerp(
              0.46 + rawR * 0.82,
              0.34 + rawR * 0.56,
              fadeT,
            ),
            _StarLayer.distant => 0.24 + rawR * 0.42,
            _StarLayer.anchor => 0.0,
          },
          baseAlpha: switch (layer) {
            _StarLayer.recent => 0.24 + recentness * 0.30 + rawR * 0.14,
            _StarLayer.fading => _lerp(
              0.17 + recentness * 0.10 + rawR * 0.08,
              0.09 + rawR * 0.05,
              fadeT,
            ),
            _StarLayer.distant => 0.05 + rawR * 0.07,
            _StarLayer.anchor => 0.0,
          },
          ampAlpha: switch (layer) {
            _StarLayer.recent => (0.12 - rawR * 0.04).clamp(0.05, 0.12),
            _StarLayer.fading => _lerp(0.06, 0.03, fadeT),
            _StarLayer.distant => 0.02 + rawR * 0.01,
            _StarLayer.anchor => 0.0,
          },
          breathPeriod: switch (layer) {
            _StarLayer.recent => 8.0 + rawP * 7.0,
            _StarLayer.fading => 9.0 + rawP * 8.0,
            _StarLayer.distant => 11.0 + rawP * 10.0,
            _StarLayer.anchor => 8.0,
          },
          breathPhase: _unit(_hash('bp:', id)) * math.pi * 2,
          driftRadiusX: switch (layer) {
            _StarLayer.recent => 0.24 + _unit(_hash('dx:', id)) * 0.84,
            _StarLayer.fading => 0.10 + _unit(_hash('dx:', id)) * 0.30,
            _StarLayer.distant => 0.0,
            _StarLayer.anchor => 0.0,
          },
          driftRadiusY: switch (layer) {
            _StarLayer.recent => 0.18 + _unit(_hash('dy:', id)) * 0.64,
            _StarLayer.fading => 0.08 + _unit(_hash('dy:', id)) * 0.22,
            _StarLayer.distant => 0.0,
            _StarLayer.anchor => 0.0,
          },
          driftPeriodX: 24.0 + _unit(_hash('dpx:', id)) * 22.0,
          driftPeriodY: 30.0 + _unit(_hash('dpy:', id)) * 24.0,
          driftPhaseX: _unit(_hash('dphx:', id)) * math.pi * 2,
          driftPhaseY: _unit(_hash('dphy:', id)) * math.pi * 2,
          motionScale: switch (layer) {
            _StarLayer.recent => 0.72,
            _StarLayer.fading => _lerp(0.34, 0.18, fadeT),
            _StarLayer.distant => 0.0,
            _StarLayer.anchor => 0.0,
          },
          inSkeleton: false,
        ),
      );
    }
  }

  addStars(_aliveId, aliveCheckIns);
  for (final line in customLines) {
    addStars(line.id, line.completedDates);
  }
  // 为每条「无任何过去完成」的 customLine 添加一颗 anchor 星：
  // 用户语义「新建一根轴 → 星图上立刻冒一个点」。已有过去完成的 line
  // 由 addStars 已经覆盖；无需重复 anchor。
  for (final line in customLines) {
    final hasPast = line.completedDates.any((dk) => dk.compareTo(todayKey) < 0);
    if (hasPast) continue;
    rawStars.add(
      _buildLineAnchorStar(
        size: size,
        lineId: line.id,
        left: left,
        right: right,
        top: top,
        bottomY: bottomY,
      ),
    );
  }
  if (rawStars.isEmpty) {
    return const _ConstellationScene(stars: <_Star>[], links: <_Link>[]);
  }

  rawStars.sort((a, b) {
    final layerCmp = _layerPriority(a.layer).compareTo(_layerPriority(b.layer));
    if (layerCmp != 0) return layerCmp;
    return b.baseAlpha.compareTo(a.baseAlpha);
  });

  final template = _pickTemplate(rawStars.length);
  final skeletonCandidates = <_Star>[
    ...rawStars.where((s) => s.layer == _StarLayer.recent),
    if (rawStars.every((s) => s.layer != _StarLayer.recent))
      ...rawStars.where((s) => s.layer == _StarLayer.fading),
    if (rawStars.every(
      (s) => s.layer != _StarLayer.recent && s.layer != _StarLayer.fading,
    ))
      ...rawStars.where((s) => s.layer == _StarLayer.distant),
  ];
  final skeletonCount = math.min(
    template.points.length,
    skeletonCandidates.length,
  );
  var skeletonStars = <_Star>[];
  final backgroundStars = <_Star>[];
  final skeletonBounds = _skeletonBounds(
    size: size,
    left: left,
    top: top,
    bottomY: bottomY,
    areaW: areaW,
    areaH: areaH,
  );

  final skeletonIds = <String>{
    for (int i = 0; i < skeletonCount; i++) skeletonCandidates[i].id,
  };
  var skeletonIndex = 0;
  for (final star in rawStars) {
    if (skeletonIds.contains(star.id) && skeletonIndex < skeletonCount) {
      final point = template.points[skeletonIndex];
      final targetX = _lerp(skeletonBounds.left, skeletonBounds.right, point.x);
      final targetY = _lerp(skeletonBounds.top, skeletonBounds.bottom, point.y);
      skeletonStars.add(
        star.copyWith(
          anchorX: targetX,
          anchorY: targetY,
          radius: star.radius + 0.20,
          baseAlpha: (star.baseAlpha + 0.20).clamp(0.0, 0.88),
          ampAlpha: (star.ampAlpha + 0.02).clamp(0.0, 0.18),
          driftRadiusX: math.min(star.driftRadiusX, 1.0),
          driftRadiusY: math.min(star.driftRadiusY, 0.8),
          motionScale: 1.0,
          inSkeleton: true,
        ),
      );
      skeletonIndex += 1;
    } else {
      backgroundStars.add(star);
    }
  }

  skeletonStars = _relaxSkeleton(
    stars: skeletonStars,
    template: template,
    bounds: skeletonBounds,
  );

  final allStars = <_Star>[...skeletonStars, ...backgroundStars];
  final links = <_Link>[];
  for (final edge in template.edges) {
    if (edge.$1 >= skeletonCount || edge.$2 >= skeletonCount) continue;
    final seed = _hash(
      'skel-link:',
      '${template.name}|${skeletonStars[edge.$1].id}|${skeletonStars[edge.$2].id}',
    );
    links.add(
      _Link(
        aIndex: edge.$1,
        bIndex: edge.$2,
        dashed: _unit(seed) > 0.55,
        shimmerPeriod: 14.0 + _unit(seed >> 4) * 12.0,
        shimmerPhase: _unit(seed >> 8) * math.pi * 2,
      ),
    );
  }

  return _ConstellationScene(stars: allStars, links: links);
}

int _layerPriority(_StarLayer layer) {
  return switch (layer) {
    _StarLayer.recent => 0,
    _StarLayer.anchor => 1,
    _StarLayer.fading => 2,
    _StarLayer.distant => 3,
  };
}

_ConstellationTemplate _pickTemplate(int starCount) {
  _ConstellationTemplate best = _templates.first;
  var bestScore = 1 << 30;
  for (final template in _templates) {
    final score = (template.points.length - starCount).abs();
    if (score < bestScore) {
      best = template;
      bestScore = score;
    }
  }
  return best;
}

({double left, double right, double top, double bottom}) _skeletonBounds({
  required Size size,
  required double left,
  required double top,
  required double bottomY,
  required double areaW,
  required double areaH,
}) {
  final topBound = math.max(top + areaH * 0.04, size.height * 0.12);
  final bottomBound = math.min(
    top + areaH * 0.44,
    bottomY - size.height * 0.14,
  );
  return (
    left: left + areaW * 0.14,
    right: left + areaW * 0.86,
    top: topBound,
    bottom: math.max(topBound + 28.0, bottomBound),
  );
}

List<_Star> _relaxSkeleton({
  required List<_Star> stars,
  required _ConstellationTemplate template,
  required ({double left, double right, double top, double bottom}) bounds,
}) {
  if (stars.length < 2) return stars;

  final positions = [for (final s in stars) Offset(s.anchorX, s.anchorY)];
  final targets = [
    for (int i = 0; i < stars.length; i++)
      Offset(
        _lerp(bounds.left, bounds.right, template.points[i].x),
        _lerp(bounds.top, bounds.bottom, template.points[i].y),
      ),
  ];

  final connected = <(int, int)>[
    for (final edge in template.edges)
      if (edge.$1 < stars.length && edge.$2 < stars.length) edge,
  ];

  for (int iter = 0; iter < 18; iter++) {
    final forces = List<Offset>.filled(stars.length, Offset.zero);

    for (int i = 0; i < stars.length; i++) {
      for (int j = i + 1; j < stars.length; j++) {
        final delta = positions[j] - positions[i];
        final dist = delta.distance.clamp(0.001, 9999.0);
        final repelRadius = 28.0 + stars[i].radius * 6 + stars[j].radius * 6;
        if (dist >= repelRadius) continue;
        final dir = delta / dist;
        final strength = (repelRadius - dist) * 0.22;
        forces[i] -= dir * strength;
        forces[j] += dir * strength;
      }
    }

    for (final edge in connected) {
      final a = edge.$1;
      final b = edge.$2;
      final delta = positions[b] - positions[a];
      final dist = delta.distance.clamp(0.001, 9999.0);
      final targetDelta = targets[b] - targets[a];
      final targetDist = targetDelta.distance.clamp(18.0, 9999.0);
      final dir = delta / dist;
      final stretch = (dist - targetDist) * 0.16;
      forces[a] += dir * stretch;
      forces[b] -= dir * stretch;
    }

    for (int i = 0; i < stars.length; i++) {
      final toTarget = targets[i] - positions[i];
      forces[i] += toTarget * 0.10;
      var next = positions[i] + forces[i];
      next = Offset(
        next.dx.clamp(bounds.left, bounds.right),
        next.dy.clamp(bounds.top, bounds.bottom),
      );
      positions[i] = next;
    }
  }

  return [
    for (int i = 0; i < stars.length; i++)
      stars[i].copyWith(anchorX: positions[i].dx, anchorY: positions[i].dy),
  ];
}

class _ConstellationPainter extends CustomPainter {
  final _ConstellationBackgroundState state;
  final ValueNotifier<double> elapsed;

  _ConstellationPainter({required this.state, required this.elapsed})
    : super(repaint: elapsed);

  static const double _dashOn = 4.5;
  static const double _dashOff = 4.0;
  static const double _revealPerStarDelay = 0.055;
  static const double _revealDuration = 1.75;
  static const double _linkRevealLag = 0.42;
  static const double _linkRevealDuration = 1.10;

  @override
  void paint(Canvas canvas, Size size) {
    if (state._cachedSize != size || state._scene.stars.isEmpty) {
      state._rebuildCache(size);
    }
    final scene = state._scene;
    if (scene.stars.isEmpty) return;

    final t = elapsed.value;
    final focus = _graphCenter(size);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.82
      ..strokeCap = StrokeCap.round;
    final starPaint = Paint()..style = PaintingStyle.fill;

    for (final link in scene.links) {
      final shimmer =
          0.5 + 0.5 * math.sin(t / link.shimmerPeriod + link.shimmerPhase);
      final linkProgress = math.min(
        _linkRevealProgress(link.aIndex, t),
        _linkRevealProgress(link.bIndex, t),
      );
      if (linkProgress <= 0.0) continue;
      linePaint.color = Colors.white.withValues(
        alpha: (0.08 + shimmer * 0.13) * linkProgress,
      );
      final a = _revealedOffset(
        scene.stars[link.aIndex],
        link.aIndex,
        t,
        size,
        focus,
      );
      final bFull = _revealedOffset(
        scene.stars[link.bIndex],
        link.bIndex,
        t,
        size,
        focus,
      );
      final b = Offset.lerp(
        a,
        bFull,
        Curves.easeOutCubic.transform(linkProgress),
      )!;
      if (link.dashed) {
        _drawDashedSegment(canvas, a, b, linePaint, _dashOn, _dashOff);
      } else {
        canvas.drawLine(a, b, linePaint);
      }
    }

    for (int i = 0; i < scene.stars.length; i++) {
      final star = scene.stars[i];
      final reveal = _nodeRevealProgress(star, i, t);
      if (reveal <= 0.0) continue;
      final pos = _revealedOffset(star, i, t, size, focus);
      final breath = math.sin(
        2 * math.pi * (t / star.breathPeriod) + star.breathPhase,
      );
      final alpha = (star.baseAlpha + breath * star.ampAlpha).clamp(0.0, 1.0);
      starPaint.color = Colors.white.withValues(alpha: alpha * reveal);
      final radius =
          star.radius * (0.55 + 0.45 * Curves.easeOut.transform(reveal));
      canvas.drawCircle(pos, radius, starPaint);
    }

    _paintTodayOverlay(canvas, size, scene, t);
  }

  double _nodeRevealProgress(_Star star, int index, double t) {
    if (star.layer == _StarLayer.fading || star.layer == _StarLayer.distant) {
      return 1.0;
    }
    if (!state._sceneShouldReveal) return 1.0;
    final local = t - state._sceneBuiltAt - index * _revealPerStarDelay;
    if (local <= 0) return 0.0;
    return (local / _revealDuration).clamp(0.0, 1.0);
  }

  double _linkRevealProgress(int index, double t) {
    if (!state._sceneShouldReveal) return 1.0;
    final local =
        t - state._sceneBuiltAt - index * _revealPerStarDelay - _linkRevealLag;
    if (local <= 0) return 0.0;
    return (local / _linkRevealDuration).clamp(0.0, 1.0);
  }

  Offset _revealedOffset(
    _Star star,
    int index,
    double t,
    Size size,
    Offset focus,
  ) {
    final target = _starOffset(star, t, size);
    final reveal = Curves.easeOutCubic.transform(
      _nodeRevealProgress(star, index, t),
    );
    return Offset.lerp(focus, target, reveal)!;
  }

  Offset _graphCenter(Size size) => Offset(size.width / 2, size.height * 0.26);

  void _paintTodayOverlay(
    Canvas canvas,
    Size size,
    _ConstellationScene scene,
    double t,
  ) {
    final top = math.max(
      state.widget.topInset + 8.0,
      state.widget.bottomY - state.widget.visibleHeight,
    );
    if (state.widget.bottomY <= top || state.widget.visibleHeight <= 0) return;
    final left = 14.0;
    final right = size.width - 14.0;
    final safetyBounds = _overlaySafetyBounds(
      size: size,
      left: left,
      right: right,
      top: top,
      bottomY: state.widget.bottomY,
    );
    final todayKey = _todayKey(state.widget.today);
    final overlays = <_TodayOverlayStar>[
      ..._collectTodayOverlays(
        lineId: _aliveId,
        checkedDates: state.widget.aliveCheckIns,
        todayKey: todayKey,
        scene: scene,
        size: size,
        bounds: safetyBounds,
      ),
      for (final line in state.widget.customLines)
        ..._collectTodayOverlays(
          lineId: line.id,
          checkedDates: line.completedDates.toSet(),
          todayKey: todayKey,
          scene: scene,
          size: size,
          bounds: safetyBounds,
        ),
    ];

    // 每次绘制用本地 Paint，避免污染共享 Paint 状态。
    final overlayLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.82
      ..strokeCap = StrokeCap.round;
    final overlayStarPaint = Paint()..style = PaintingStyle.fill;
    final overlayDotPaint = Paint()..style = PaintingStyle.fill;

    for (final overlay in overlays) {
      final isFxLine = state.widget.todayFxLineId == overlay.star.lineId;
      final v = state.widget.todayFxValue.clamp(0.0, 1.0);
      // 今天增量语法 · 唯一动词：appearing = easeOutCubic，取消 = easeInCubic
      // 使 cancel 的几何正好是 appearing 的时间倒放。
      final easedFx = state.widget.todayFxAppearing
          ? Curves.easeOutCubic.transform(v)
          : Curves.easeInCubic.transform(v);
      final progress = isFxLine
          ? (state.widget.todayFxAppearing ? easedFx : 1.0 - easedFx)
          : 1.0;
      if (progress <= 0.0) continue;

      // target：FX 持续期（value<1）内使用 FX session 锁定的快照；
      // FX 结束后（或非 FX line）跟随正常漂移。
      final liveTarget = _clampToBounds(
        _starOffset(overlay.star, t, size),
        safetyBounds,
      );
      final fxActive = isFxLine && v < 1.0;
      final target = (fxActive && overlay.lockedTarget != null)
          ? overlay.lockedTarget!
          : liveTarget;

      final origin = overlay.origin;
      final hasBridge = origin != null;
      final anchor = origin ?? target;
      final head = hasBridge ? Offset.lerp(anchor, target, progress)! : target;

      final restingAlpha = (overlay.star.baseAlpha + 0.08).clamp(0.0, 1.0);
      final heavyScale = _heavyBreathScale(isFxLine, overlay.tier, t);

      // 预先计算 head 的"感知 alpha"，用于让 bridge line 与 head 同步淡出。
      // 之前 line 用 0.15 * progress（峰值 0.15），head 用 progress→restingAlpha
      // (峰值 ~0.7)；倒放时 line 远早于 head 跌破感知阈值，造成"线先消失、点
      // 还亮"的不对称。现在 line 跟 head 走同一根曲线，退场齐步。
      const settleStart = 0.78;
      final double headEffectiveAlpha;
      if (fxActive) {
        final settleT = progress > settleStart
            ? (progress - settleStart) / (1.0 - settleStart)
            : 0.0;
        headEffectiveAlpha = _lerp(
          progress,
          restingAlpha,
          settleT,
        ).clamp(0.0, 1.0);
      } else {
        headEffectiveAlpha = (restingAlpha * progress).clamp(0.0, 1.0);
      }

      if (hasBridge) {
        // 0.22 系数 = "head 满亮时 line 的相对亮度"，保留之前的视觉权重；
        // 关键变化是把 progress 替换成 headEffectiveAlpha。
        overlayLinePaint.color = Colors.white.withValues(
          alpha: (0.22 * headEffectiveAlpha).clamp(0.0, 0.22),
        );
        canvas.drawLine(anchor, head, overlayLinePaint);

        // 中档力度：gap bridge 在线中段压一个极淡的 dotted 中点。
        // 仅在 head 走过中点后可见，alpha ≤ 0.2，随 progress 淡入。
        if (overlay.tier == 'mid') {
          final mid = Offset.lerp(anchor, target, 0.5)!;
          // head 越过中点前不显示，避免出现在头部未到的前方。
          final midAppearT = ((progress - 0.5) / 0.5).clamp(0.0, 1.0);
          if (midAppearT > 0.0) {
            overlayDotPaint.color = Colors.white.withValues(
              alpha: 0.18 * midAppearT,
            );
            canvas.drawCircle(mid, 0.9, overlayDotPaint);
          }
        }
      }

      if (fxActive) {
        // 今天增量语法 · 头部形态：FX 期间 overlay 头与 timeline today node
        // 大小与 halo 对齐（spec 「时间轴与星图 overlay 共用 today 级节点大小
        // 的实心点」）。最后 ~20% 收口到 constellation star 尺寸，让 v=1 时
        // 与基础 painter 的 resting star 无突跳；这是「终态由基础 painter
        // 承担」的视觉过渡。
        const fxSourceRadius = 3.6;
        const fxPeakRadius = 5.0; // 与 timeline 非 alive today node 同径
        const settleStart = 0.78;
        final restingRadius = overlay.star.radius;

        final double headRadius;
        final double settleT;
        if (progress <= settleStart) {
          headRadius = _lerp(
            fxSourceRadius,
            fxPeakRadius,
            progress / settleStart,
          );
          settleT = 0.0;
        } else {
          settleT = (progress - settleStart) / (1.0 - settleStart);
          headRadius = _lerp(fxPeakRadius, restingRadius, settleT);
        }
        final scaledRadius = headRadius * heavyScale;

        // Glow halo：跟随 head，最后 ~20% 与 head 一同收口。
        final glowFade = 1.0 - settleT;
        if (glowFade > 0.0) {
          final glowAlpha = (0.06 * progress * glowFade).clamp(0.0, 1.0);
          final glowPaint = Paint()
            ..color = Colors.white.withValues(alpha: glowAlpha)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              scaledRadius + 1.8,
            );
          canvas.drawCircle(head, scaledRadius + 1.2, glowPaint);
        }

        // Head alpha：FX 中段近白，settle 期 lerp 到 resting baseAlpha。
        final headAlpha = _lerp(
          progress,
          restingAlpha,
          settleT,
        ).clamp(0.0, 1.0);
        overlayStarPaint.color = Colors.white.withValues(alpha: headAlpha);
        canvas.drawCircle(head, scaledRadius, overlayStarPaint);
      } else {
        // Resting star（包括非 FX line 的今日点 + FX 完成后的 line）。
        overlayStarPaint.color = Colors.white.withValues(
          alpha: restingAlpha * progress,
        );
        final restingEase = hasBridge ? 1.0 : (0.36 + 0.64 * progress);
        final radius = overlay.star.radius * restingEase * heavyScale;
        canvas.drawCircle(head, radius, overlayStarPaint);
      }
    }
  }

  /// 重档「一次性呼吸」缩放。仅在 heavy tier 的 FX line 上、呼吸窗口内返回 >1；
  /// 其它情况始终返回 1.0。
  double _heavyBreathScale(bool isFxLine, String? tier, double t) {
    if (!isFxLine || tier != 'heavy') return 1.0;
    final start = state._fxHeavyBreathStartElapsed;
    if (start == null) return 1.0;
    final phase =
        (t - start) / _ConstellationBackgroundState._heavyBreathDuration;
    if (phase <= 0.0 || phase >= 1.0) return 1.0;
    // 1.0 → peak → 1.0，easeOut 单峰曲线。phase=0.5 到顶。
    final bell = math.sin(phase * math.pi); // 0→1→0
    final eased = Curves.easeOut.transform(bell);
    return 1.0 +
        (_ConstellationBackgroundState._heavyBreathPeakScale - 1.0) * eased;
  }

  List<_TodayOverlayStar> _collectTodayOverlays({
    required String lineId,
    required Set<String> checkedDates,
    required String todayKey,
    required _ConstellationScene scene,
    required Size size,
    required ({double left, double right, double top, double bottom}) bounds,
  }) {
    final hasToday = checkedDates.contains(todayKey);
    final isFxLine = state.widget.todayFxLineId == lineId;
    if (!hasToday && !(isFxLine && !state.widget.todayFxAppearing)) {
      return const <_TodayOverlayStar>[];
    }

    final previousStar = _latestPastStarForLine(scene, lineId, todayKey);
    // 没有过去同 line 星 → 看 anchor（line 出生时种下的那颗）。anchor 也找不到
    // 才落到「无 bridge」状态（极罕见：alive line 无任何 alive checkin 的极初装）。
    final lineAnchorStar = previousStar == null
        ? _findLineAnchorStar(scene, lineId)
        : null;
    final originStar = previousStar ?? lineAnchorStar;

    // 新 line 第一次完成今天：bridge 目标 = 任意非自身 line 的星。
    final bridgeTargetStar = (previousStar == null && lineAnchorStar != null)
        ? _pickBridgeTarget(scene, lineId, lineAnchorStar)
        : null;

    final overlayStar = _buildOverlayStar(
      lineId: lineId,
      dateKey: todayKey,
      previousStar: previousStar,
      lineAnchor: lineAnchorStar,
      bridgeTarget: bridgeTargetStar,
      bounds: bounds,
    );

    // ── 力度档识别 ──
    // heavy：无任何过去同 line 星点（整条 lineage 今天诞生）
    // mid：有过去星点，但最近那颗不是昨天（存在断档）
    // light：有过去星点，且最近那颗就是昨天（连续天）
    final String tier;
    if (previousStar == null) {
      tier = 'heavy';
    } else {
      final yesterdayKey = _yesterdayKey(state.widget.today);
      tier = previousStar.dateKey == yesterdayKey ? 'light' : 'mid';
    }

    // ── FX session 快照（origin 锁定 + target 锁定）──
    // 仅对 FX 正在进行的那条 line 做快照；其它 line 实时跟随漂移。
    Offset? origin;
    Offset? lockedTarget;
    if (isFxLine) {
      if (state._fxSnapshotPending) {
        // 首次进入 session：计算并缓存 origin + target + tier。
        final live = _clampToBounds(
          _starOffset(overlayStar, elapsed.value, size),
          bounds,
        );
        final Offset snapOrigin;
        if (originStar != null) {
          // 有 origin 星（past 或 anchor）：用其漂移位作 origin。
          snapOrigin = _starOffset(originStar, elapsed.value, size);
        } else {
          // 兜底（极罕见）：父层提供的 timeline today-node 投影；再不行画布顶中央。
          snapOrigin =
              state.widget.timelineTodayNodeScreenPos ??
              Offset(size.width / 2, bounds.top);
        }
        state._fxLockedOrigin = snapOrigin;
        state._fxLockedTarget = live;
        state._fxTier = tier;
        state._fxSnapshotPending = false;
      }
      origin = state._fxLockedOrigin;
      lockedTarget = state._fxLockedTarget;
    } else if (originStar != null) {
      // 非 FX line 的 resting 状态：origin 跟随 origin 星漂移（与星点组同步）。
      origin = _starOffset(originStar, elapsed.value, size);
    }
    // 非 FX line 且无 origin 星：没有 bridge（star 独立显示）。

    final effectiveTier = isFxLine ? (state._fxTier ?? tier) : tier;

    return <_TodayOverlayStar>[
      _TodayOverlayStar(
        star: overlayStar,
        origin: origin,
        lockedTarget: lockedTarget,
        tier: effectiveTier,
      ),
    ];
  }

  _Star? _latestPastStarForLine(
    _ConstellationScene scene,
    String lineId,
    String todayKey,
  ) {
    _Star? latest;
    for (final star in scene.stars) {
      if (star.lineId != lineId) continue;
      if (_isAnchorStar(star)) continue;
      if (star.dateKey.compareTo(todayKey) >= 0) continue;
      if (latest == null || star.dateKey.compareTo(latest.dateKey) > 0) {
        latest = star;
      }
    }
    return latest;
  }

  _Star? _findLineAnchorStar(_ConstellationScene scene, String lineId) {
    for (final star in scene.stars) {
      if (star.lineId == lineId && _isAnchorStar(star)) return star;
    }
    return null;
  }

  /// 新轴第一次完成今天时：从画布上挑一颗「非自身 line」的星作为 bridge 目标。
  /// 优先距离 ≥ 100px 避免短桥；不够远的池里挑最远的兜底；都没有返回 null。
  _Star? _pickBridgeTarget(
    _ConstellationScene scene,
    String selfLineId,
    _Star originStar,
  ) {
    final originPos = Offset(originStar.anchorX, originStar.anchorY);
    final candidates = <_Star>[];
    for (final star in scene.stars) {
      if (star.lineId == selfLineId) continue;
      if (_isAnchorStar(star)) continue;
      candidates.add(star);
    }
    if (candidates.isEmpty) return null;

    const minDistance = 100.0;
    final farEnough = candidates.where((s) {
      final d = (Offset(s.anchorX, s.anchorY) - originPos).distance;
      return d >= minDistance;
    }).toList();

    if (farEnough.isNotEmpty) {
      final pick = _unit(
        _hash('bridge-target:', '$selfLineId|${originStar.id}'),
      );
      return farEnough[(pick * farEnough.length).floor().clamp(
        0,
        farEnough.length - 1,
      )];
    }
    // 没有足够远的：挑现有里最远的那颗
    candidates.sort((a, b) {
      final da = (Offset(a.anchorX, a.anchorY) - originPos).distance;
      final db = (Offset(b.anchorX, b.anchorY) - originPos).distance;
      return db.compareTo(da);
    });
    return candidates.first;
  }

  _Star _buildOverlayStar({
    required String lineId,
    required String dateKey,
    required _Star? previousStar,
    required _Star? lineAnchor,
    required _Star? bridgeTarget,
    required ({double left, double right, double top, double bottom}) bounds,
  }) {
    final id = '$lineId|$dateKey';
    final rawR = _unit(_hash('r:', id));
    final rawP = _unit(_hash('p:', id));
    final offsetSeed = _hash('overlay-offset:', id);
    final rawAngle = _unit(offsetSeed) * math.pi * 2;
    final angle = -math.pi / 2 + math.sin(rawAngle) * 1.15;
    // 老轴桥长 100~180px（旧 28~62px 太短，hardly 像「延伸」）
    final distance = 100.0 + _unit(offsetSeed >> 7) * 80.0;
    final fallbackX = _lerp(
      bounds.left,
      bounds.right,
      0.28 + _unit(_hash('fx:', id)) * 0.44,
    );
    final fallbackY = _lerp(
      bounds.top,
      bounds.bottom,
      0.18 + _unit(_hash('fy:', id)) * 0.32,
    );

    final Offset anchor;
    if (previousStar != null) {
      // 老轴：从 previousStar 拉出长偏移
      anchor = _clampToBounds(
        Offset(
          previousStar.anchorX + math.cos(angle) * distance,
          previousStar.anchorY + math.sin(angle) * distance * 0.78,
        ),
        bounds,
      );
    } else if (bridgeTarget != null) {
      // 新轴第一次：today 落在 bridge 目标星附近（小 jitter，不重叠）
      final jitterAngle = _unit(_hash('jitter-a:', id)) * math.pi * 2;
      final jitterDist = 8.0 + _unit(_hash('jitter-d:', id)) * 12.0;
      anchor = _clampToBounds(
        Offset(
          bridgeTarget.anchorX + math.cos(jitterAngle) * jitterDist,
          bridgeTarget.anchorY + math.sin(jitterAngle) * jitterDist,
        ),
        bounds,
      );
    } else if (lineAnchor != null) {
      // 新轴 + 没找到 bridge target（画布上只有 anchor 自己）：在 anchor 边上
      anchor = _clampToBounds(
        Offset(
          lineAnchor.anchorX + math.cos(angle) * distance,
          lineAnchor.anchorY + math.sin(angle) * distance * 0.78,
        ),
        bounds,
      );
    } else {
      anchor = Offset(fallbackX, fallbackY);
    }
    return _Star(
      id: id,
      lineId: lineId,
      dateKey: dateKey,
      layer: _StarLayer.recent,
      anchorX: anchor.dx,
      anchorY: anchor.dy,
      radius: 0.62 + rawR * rawR * 1.52,
      baseAlpha: 0.54 + rawR * 0.22,
      ampAlpha: (0.11 - rawR * 0.04).clamp(0.04, 0.11),
      breathPeriod: 8.0 + rawP * 7.0,
      breathPhase: _unit(_hash('bp:', id)) * math.pi * 2,
      driftRadiusX: 0.24 + _unit(_hash('dx:', id)) * 0.72,
      driftRadiusY: 0.18 + _unit(_hash('dy:', id)) * 0.54,
      driftPeriodX: 24.0 + _unit(_hash('dpx:', id)) * 22.0,
      driftPeriodY: 30.0 + _unit(_hash('dpy:', id)) * 24.0,
      driftPhaseX: _unit(_hash('dphx:', id)) * math.pi * 2,
      driftPhaseY: _unit(_hash('dphy:', id)) * math.pi * 2,
      motionScale: 0.72,
      inSkeleton: false,
    );
  }

  ({double left, double right, double top, double bottom})
  _overlaySafetyBounds({
    required Size size,
    required double left,
    required double right,
    required double top,
    required double bottomY,
  }) {
    final areaW = right - left;
    final areaH = bottomY - top;
    final base = _skeletonBounds(
      size: size,
      left: left,
      top: top,
      bottomY: bottomY,
      areaW: areaW,
      areaH: areaH,
    );
    return (
      left: base.left,
      right: base.right,
      top: base.top,
      bottom: math.min(base.bottom, top + areaH * 0.58),
    );
  }

  Offset _clampToBounds(
    Offset point,
    ({double left, double right, double top, double bottom}) bounds,
  ) {
    return Offset(
      point.dx.clamp(bounds.left, bounds.right),
      point.dy.clamp(bounds.top, bounds.bottom),
    );
  }

  Offset _starOffset(_Star star, double t, Size size) {
    if (star.motionScale <= 0.0) {
      return Offset(star.anchorX, star.anchorY);
    }
    final center = _graphCenter(size);
    final baseVector = Offset(
      star.anchorX - center.dx,
      star.anchorY - center.dy,
    );
    final orbitRadius = baseVector.distance.clamp(12.0, 240.0);
    final baseAngle = math.atan2(baseVector.dy, baseVector.dx);
    final sweep =
        math.sin((t / 26.0) * math.pi * 2) * 0.05 +
        math.sin((t / 43.0) * math.pi * 2) * 0.025;
    final starBias = (star.inSkeleton ? 0.012 : 0.02) * star.motionScale;
    final angularOffset =
        sweep * star.motionScale +
        math.sin(t / 31.0 + star.breathPhase) * starBias;
    final fanDx =
        (math.cos(baseAngle + angularOffset) * orbitRadius - baseVector.dx) *
        star.motionScale;
    final fanDy =
        (math.sin(baseAngle + angularOffset) * orbitRadius - baseVector.dy) *
        star.motionScale;
    final dx =
        math.sin((t / star.driftPeriodX) * math.pi * 2 + star.driftPhaseX) *
        star.driftRadiusX *
        star.motionScale;
    final dy =
        math.cos((t / star.driftPeriodY) * math.pi * 2 + star.driftPhaseY) *
        star.driftRadiusY *
        star.motionScale;
    return Offset(star.anchorX + fanDx + dx, star.anchorY + fanDy + dy);
  }

  void _drawDashedSegment(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dashOn,
    double dashOff,
  ) {
    final delta = end - start;
    final length = delta.distance;
    if (length < 0.001) return;
    final ux = delta.dx / length;
    final uy = delta.dy / length;
    var travelled = 0.0;
    var drawing = true;
    while (travelled < length) {
      final step = math.min(length - travelled, drawing ? dashOn : dashOff);
      if (drawing) {
        final p0 = Offset(start.dx + ux * travelled, start.dy + uy * travelled);
        final p1 = Offset(
          start.dx + ux * (travelled + step),
          start.dy + uy * (travelled + step),
        );
        canvas.drawLine(p0, p1, paint);
      }
      travelled += step;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) => false;
}

class _TodayOverlayStar {
  final _Star star;

  /// Bridge 起点（origin）。null 表示没有 bridge（极罕见：非 FX line + 无过去同 line 星）。
  final Offset? origin;

  /// FX session 期间的 target 快照；null 表示未锁定（跟随实时漂移）。
  final Offset? lockedTarget;

  /// 力度档位：'light' | 'mid' | 'heavy'
  final String tier;

  const _TodayOverlayStar({
    required this.star,
    required this.origin,
    required this.lockedTarget,
    required this.tier,
  });
}
