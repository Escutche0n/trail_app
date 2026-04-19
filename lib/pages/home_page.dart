import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../core/ble_service.dart';
import '../core/time_integrity_service.dart';
import '../models/trail_line.dart';
import '../models/friend.dart';
import '../services/storage_service.dart';
import '../services/haptic_service.dart';
import '../widgets/alto_background.dart';
import '../widgets/constellation_background.dart';
import 'friend_discovery_page.dart';
import 'settings_page.dart';

/// 主界面 — 全屏多行时间轴
/// - 纯黑背景 + 白/灰节点 + 连线 + 暂居天数
/// - 横向滑动：切换日期，所有行同步滚动
/// - 纵向滑动：浏览自定义行动线；向上拉过阈值 → 弹出新增输入框
/// - 今日节点：点击切换打卡（核心逻辑，永不改变）
/// - 短按节点：唤起 4 向操作菜单（仅当新功能启用）
/// - 长按节点：删除自定义线（仅当新功能关闭，回到原始行为）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _Axis { none, horizontal, vertical }

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── 数据 ──────────────────────────────────────
  late final DateTime _birthday;
  late final DateTime _startDate;
  late final DateTime _today;
  late int _survivalDays;
  late int _totalDays; // 从 startDate 到 today 的天数
  // 时间轴只延伸到「今日」为止 —— 未来天没有意义，不提供空白预览。
  static const int _futureDays = 0;
  late Set<String> _aliveCheckIns;
  late List<TrailLine> _customLines;
  late Map<int, int> _gapData;

  // ── 横向滚动（磁吸到日） ──────────────────────
  static const double _dayWidth = 64.0;
  double _hScroll = 0.0;
  double _hScrollMin = 0.0;
  double _hScrollMax = 0.0;
  int _lastHapticDayIndex = -1;
  late AnimationController _hSnap; // 150 ms 软磁吸到最近日
  double _hSnapFrom = 0;
  double _hSnapTo = 0;

  // ── 纵向滚动 ────────────────────────────────
  /// 行间距 — 由用户在设置中通过滑块调整（48-80 dp），默认 64 dp。
  /// 新功能关闭时回到原始 72 dp。
  double _rowSpacing = StorageService.defaultNodeSpacing;
  static const double _pullUpThreshold = 84.0; // 旧版兼容保留
  double _vScroll = 0.0;
  double _vScrollMax = 0.0;
  int _lastVScrollRow = 0; // 纵向滑动时追踪行索引变化，用于触觉反馈
  late AnimationController _vSnap; // 纵向松手 snap
  double _vSnapFrom = 0;
  double _vSnapTo = 0;
  double _pullUp = 0.0; // 始终为 0（旧版兼容）
  final bool _pullLatched = false; // 始终 false（旧版兼容）
  late AnimationController _vSpring;

  // ── 手势轴锁定 ────────────────────────────────
  _Axis _axis = _Axis.none;
  bool _panLive = false;
  double _panStartHScroll = 0.0;
  double _panStartVScroll = 0.0;
  double _panDeltaDx = 0.0;
  double _panDeltaDy = 0.0;

  // ── 动画 ──────────────────────────────────────
  late AnimationController _glow; // 今日节点呼吸
  late AnimationController _bounce; // 点击微光回弹
  String? _bounceKey; // "aliveLineId" 或 customLine.id

  /// BLE-验证成功的闪烁（仅朋友行今日节点）
  ///
  /// 用途：点击今日朋友节点且 BLE 确认对方在范围内时，在该节点上跑一次一次性
  /// 亮度脉冲，给 Elvis 观察"BLE 真的握上了"的可视信号。不论是 cache 命中还是
  /// probe 成功都触发——两者都是有效 BLE 证据。
  ///
  /// 与 soul #11 的关系：一次性 transient 动画（360ms 后自止），不是常驻呼吸，
  /// 不在禁止列表内。
  late AnimationController _bleFlash;
  String? _bleFlashKey;
  late AnimationController _shake; // 长按抖动
  late AnimationController _arrowPulse; // 引导箭头脉动
  late AnimationController _lineAddAnim; // 新增行动线淡入
  late AnimationController _lineDeleteAnim; // 删除行动线淡出
  late AnimationController _satellite; // 卫星点旋转（10 s 一圈）
  late AnimationController _todayNodeLinkAnim; // 今日节点连线出现/消失
  late AnimationController _menuAnim; // 节点 4 向菜单展开
  late AnimationController _dayAxisReveal; // 日期列虚线出现
  String? _deletingLineId;
  String? _todayNodeFxLineId;
  int? _todayNodeFxFromDayIndex;
  bool _todayNodeFxAppearing = true;

  // ── 删除态（仅旧版） ─────────────────────────
  String? _deleteModeLineId;
  Offset? _deleteButtonPos;

  // ── 节点操作菜单（新版） ─────────────────────
  bool _actionMenuOpen = false;
  String? _actionMenuLineId;
  int? _actionMenuDayIndex;
  Offset? _actionMenuCenter;

  // ── 引导 ──────────────────────────────────────
  bool _showHOnboarding = false;
  bool _showVOnboarding = false;
  // 点击今日节点引导：首次使用时显示节点脉动 + 指示箭头
  bool _showTapTodayOnboarding = false;
  bool _showRadialMenuOnboarding = false;
  // 是否已经添加过第一条行动线（控制中央虚线是否可见）
  bool _hasFirstTrack = false;
  // 中央虚线出现动画（从「今日」节点向下延伸）
  late AnimationController _centerLineAnim;
  // 首日教学态：totalDays==1 且无自定义线
  bool get _isFirstDayTutorial =>
      _totalDays == 1 && _customLines.isEmpty && !_hasFirstTrack;

  // ── 视口 ──────────────────────────────────────
  Size _viewport = Size.zero;
  double _topInset = 0.0;

  // ── 偏好（v2 升级） ──────────────────────────
  // “新版交互”已成为唯一入口，旧总开关不再对用户暴露。
  bool _newFeaturesEnabled = true;
  bool _satelliteRotationEnabled = true;
  bool _constellationVisible = true;
  ConstellationHeightMode _constellationHeightMode =
      ConstellationHeightMode.standard;
  int _pendingFriendCount = 0;
  int _confirmedFriendCount = 0;
  // 每位 confirmed 朋友一条时间线；按 pairedAt 升序排列
  List<TrailLine> _friendLines = const <TrailLine>[];
  // 与 _friendLines 一一对应；id 为 `__friend__<uid>`
  Map<String, Friend> _friendsById = const <String, Friend>{};
  // 朋友时间线 id 集合（painter / hit test 快速判定）
  Set<String> _friendLineIds = const <String>{};

  // ── 全局径向菜单（长按触发） ─────────────────
  bool _radialMenuOpen = false;
  late AnimationController _radialAnim;
  Offset _radialAnchor = Offset.zero;
  String? _radialHover;

  // ── 常量 ──────────────────────────────────────
  static const String _aliveId = '__alive__';
  static const double _nodeHitRadius = 26.0;
  static const double _satelliteRingRadius = 11.0;
  static const double _headerBlockHeight = 92.0;
  static const double _headerTopPadding = 24.0;
  static const double _constellationHeaderGap = 4.0;
  // 4 向操作菜单：45° 对角菱形排布
  static const double _menuIconRadius = 52.0;
  static const double _menuIconHitSize = 36.0;

  @override
  void initState() {
    super.initState();

    final birthday = StorageService.instance.getBirthday();
    if (birthday == null) {
      // 防御：生日数据丢失时回退到默认值
      debugPrint('==== WARNING: birthday is null, using fallback ====');
      _birthday = DateTime(2000, 1, 1);
    } else {
      _birthday = birthday;
    }
    _startDate = DateUtils.dateOnly(StorageService.instance.getStartDate());
    _today = DateUtils.dateOnly(DateTime.now());
    _survivalDays = _today.difference(DateUtils.dateOnly(_birthday)).inDays;
    _totalDays = max(1, _today.difference(_startDate).inDays + 1);
    _aliveCheckIns = StorageService.instance.getCheckInDates();
    _customLines = StorageService.instance.getCustomLines();
    _computeGapData();
    _loadPrefs();

    // 旧版横向/纵向引导：在新手势体系下默认不显示
    _showHOnboarding = false;
    _showVOnboarding = false;
    _showTapTodayOnboarding = !StorageService.instance.tapTodayOnboardingDone;
    _showRadialMenuOnboarding =
        StorageService.instance.tapTodayOnboardingDone &&
        !StorageService.instance.radialMenuOnboardingDone;
    _hasFirstTrack =
        StorageService.instance.firstTrackAdded || _customLines.isNotEmpty;

    // 时长 ladder（spec 「今天增量语法」延伸 · 2026-04-19）：
    //   micro 200ms · standard 360ms · structural 800ms · background 不动
    _hSnap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200), // micro
    )..addListener(_onHSnapTick);

    _vSpring = AnimationController.unbounded(vsync: this)
      ..addListener(_onVSpringTick);

    _vSnap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(_onVSnapTick);

    _glow = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);

    _bounce = AnimationController(
      duration: const Duration(milliseconds: 360), // standard
      vsync: this,
    );

    _bleFlash = AnimationController(
      duration: const Duration(milliseconds: 360), // standard
      vsync: this,
    );

    _shake = AnimationController(
      duration: const Duration(milliseconds: 200), // micro
      vsync: this,
    );

    _arrowPulse = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);

    _lineAddAnim = AnimationController(
      duration: const Duration(milliseconds: 360),
      vsync: this,
      value: 1.0,
    );

    _lineDeleteAnim = AnimationController(
      duration: const Duration(milliseconds: 360), // standard，与 add 同档
      vsync: this,
      value: 1.0,
    );

    _todayNodeLinkAnim =
        AnimationController(
          duration: const Duration(milliseconds: 800), // structural，spec 钉死
          vsync: this,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() {
              _todayNodeFxLineId = null;
              _todayNodeFxFromDayIndex = null;
            });
          }
        });

    _satellite = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _applySatelliteRotation();

    _menuAnim = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _dayAxisReveal = AnimationController(
      duration: const Duration(milliseconds: 200), // micro
      vsync: this,
      value: 1.0,
    );

    _centerLineAnim = AnimationController(
      duration: const Duration(milliseconds: 800), // structural
      vsync: this,
      value: _hasFirstTrack ? 1.0 : 0.0,
    );

    _radialAnim = AnimationController(
      duration: const Duration(milliseconds: 360), // standard
      vsync: this,
    );

    unawaited(_loadFriendSummary());

    // 注册生命周期监听，检测时间回拨
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 显式 stop + removeListener，避免 in-flight tick 在 dispose 后回调。
    _hSnap
      ..stop()
      ..removeListener(_onHSnapTick)
      ..dispose();
    _vSpring
      ..stop()
      ..removeListener(_onVSpringTick)
      ..dispose();
    _vSnap
      ..stop()
      ..removeListener(_onVSnapTick)
      ..dispose();
    _glow
      ..stop()
      ..dispose();
    _bounce
      ..stop()
      ..dispose();
    _bleFlash
      ..stop()
      ..dispose();
    _shake
      ..stop()
      ..dispose();
    _arrowPulse
      ..stop()
      ..dispose();
    _lineAddAnim
      ..stop()
      ..dispose();
    _lineDeleteAnim
      ..stop()
      ..dispose();
    _todayNodeLinkAnim
      ..stop()
      ..dispose();
    _satellite
      ..stop()
      ..dispose();
    _menuAnim
      ..stop()
      ..dispose();
    _dayAxisReveal
      ..stop()
      ..dispose();
    _centerLineAnim
      ..stop()
      ..dispose();
    _radialAnim
      ..stop()
      ..dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── 生命周期：时间防篡改 ────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      TimeIntegrityService.instance.onAppPaused();
      // 暂停所有「一直转」的循环动画，释放 vsync tick。
      // 注意：一次性动画（_lineAddAnim / _lineDeleteAnim / _radialAnim / _vSnap …）
      // 不需要 stop —— 它们到 dismissed 后自然会 idle，且 stop 会破坏正在进行的反馈。
      if (_glow.isAnimating) _glow.stop(canceled: false);
      if (_arrowPulse.isAnimating) _arrowPulse.stop(canceled: false);
      if (_satellite.isAnimating) _satellite.stop(canceled: false);
    } else if (state == AppLifecycleState.resumed) {
      TimeIntegrityService.instance.onAppResumed().then((_) {
        if (mounted && TimeIntegrityService.instance.tampered) {
          setState(() {}); // 刷新 UI 显示警告
        }
      });
      // 恢复循环动画 — 与首次 initState 对齐
      if (!_glow.isAnimating) _glow.repeat(reverse: true);
      if (!_arrowPulse.isAnimating) _arrowPulse.repeat(reverse: true);
      _applySatelliteRotation();
    }
  }
  // ─────────────────────────────────────────────

  void _loadPrefs() {
    final s = StorageService.instance;
    _newFeaturesEnabled = true;
    _satelliteRotationEnabled = s.satelliteRotationEnabled;
    _constellationVisible = s.constellationVisible;
    _constellationHeightMode = s.constellationHeightMode;
    _rowSpacing = s.nodeSpacing;
  }

  void _applySatelliteRotation() {
    if (_satelliteRotationEnabled) {
      if (!_satellite.isAnimating) _satellite.repeat();
    } else {
      _satellite.stop();
      _satellite.value = 0;
    }
  }

  double _constellationBandHeight(double vh) {
    if (!_constellationVisible) return 0.0;
    return switch (_constellationHeightMode) {
      ConstellationHeightMode.compact => (vh * 0.10).clamp(84.0, 104.0),
      ConstellationHeightMode.standard => (vh * 0.15).clamp(116.0, 146.0),
      ConstellationHeightMode.expansive => (vh * 0.21).clamp(156.0, 202.0),
    };
  }

  double _constellationVisibleHeight(double aliveY, double topInset) {
    if (!_constellationVisible) return 0.0;
    final bottomY = aliveY - 96.0;
    final available = max(0.0, bottomY - (topInset + 8.0));
    return min(available, _constellationBandHeight(_viewport.height));
  }

  double _constellationBottomY(double aliveY) {
    return switch (_constellationHeightMode) {
      ConstellationHeightMode.compact => aliveY - 56.0,
      ConstellationHeightMode.standard => aliveY - 34.0,
      ConstellationHeightMode.expansive => aliveY - 26.0,
    };
  }

  // ─────────────────────────────────────────────
  // 数据辅助
  // ─────────────────────────────────────────────

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _computeGapData() {
    _gapData = {};
    int? lastIdx;
    for (int i = 0; i < _totalDays; i++) {
      final date = _startDate.add(Duration(days: i));
      if (_aliveCheckIns.contains(_dateKey(date))) {
        if (lastIdx != null) {
          final gap = i - lastIdx - 1;
          if (gap > 0) _gapData[i] = gap;
        }
        lastIdx = i;
      }
    }
  }

  int get _todayIndex => _totalDays - 1;

  bool _isTodayColumn(int dayIndex) => dayIndex == _todayIndex;

  /// 当前视口中心对应的日列下标
  int get _centerDayIndex {
    return _todayIndex + (_hScroll / _dayWidth).round();
  }

  /// 从时间轴起始日到 dayIndex（含）累计已勾选的节点总数（所有行动线的并集）
  int _trailCountUpTo(int dayIndex) {
    if (dayIndex < 0) return 0;
    final upper = min(dayIndex, _totalDays - 1); // 未来日不累加
    int count = 0;
    for (int i = 0; i <= upper; i++) {
      final date = _startDate.add(Duration(days: i));
      final key = _dateKey(date);
      if (_aliveCheckIns.contains(key)) count++;
      for (final l in _customLines) {
        if (l.completedDates.contains(key)) count++;
      }
    }
    return count;
  }

  int _lineStartDayIndex(DateTime createdAt) {
    final created = DateUtils.dateOnly(createdAt);
    final diff = created.difference(_startDate).inDays;
    return diff.clamp(0, _todayIndex + _futureDays);
  }

  static String _friendLineId(String uid) => '__friend__$uid';

  /// 按"每位 confirmed 朋友一条时间线"构建：
  /// - id = `__friend__<uid>`
  /// - name = displayName
  /// - createdAt = pairedAt 的日期零点
  /// - completedDates = {pairedAt 所在日} ∪ friend.checkInDates
  List<TrailLine> _buildFriendLines(List<Friend> friends) {
    final confirmed =
        friends.where((f) => f.state == FriendState.confirmed).toList()
          ..sort((a, b) => a.pairedAt.compareTo(b.pairedAt));
    if (confirmed.isEmpty) return const <TrailLine>[];

    return confirmed.map((f) {
      final created = DateUtils.dateOnly(f.pairedAt);
      final dates = <String>{_dateKey(created), ...f.checkInDates}.toList()
        ..sort();
      return TrailLine.fromType(
        id: _friendLineId(f.uid),
        type: TrailLineType.custom,
        name: f.displayName,
        createdAt: created,
        completedDates: dates,
        notes: const {},
      );
    }).toList();
  }

  // ─────────────────────────────────────────────
  // BLE 近距探测（方案 B · 点按触发的短窗口）
  // ─────────────────────────────────────────────
  //
  // 为什么不让 home_page 常驻扫描：BLE spec 限定"仅前台发现"，常开会把电量代价
  // 扩散到所有主屏使用路径。方案 B 把 BLE 生命周期收敛到"用户真的按了今日朋友
  // 节点"那一下 —— 意图明确、电量友好。
  //
  // 探测窗口 4s：覆盖一次 Android lowLatency 扫描批次 + iOS 通告间隔。再长
  // 用户会觉得无响应；再短容易错过对方的慢广播周期。
  static const Duration _friendProbeWindow = Duration(seconds: 4);

  Future<bool> _probeFriendInRange(String peerUid) async {
    final ble = BleService.instance;
    // 告诉用户"听到了，正在找对方"。不抢 checkInToggle 的成功 haptic。
    HapticService.actionMenuSelect();
    // 同时广播 + 扫描。对方也在前台（home_page 同路径）时才会互相看到。
    unawaited(ble.setDiscoverable(duration: _friendProbeWindow));
    unawaited(ble.startScan(timeout: _friendProbeWindow));
    final deadline = DateTime.now().add(_friendProbeWindow);
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return false;
      if (ble.isPeerInRange(peerUid)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return ble.isPeerInRange(peerUid);
  }

  // ─────────────────────────────────────────────
  // 布局计算（所有手势/绘制共用）
  // ─────────────────────────────────────────────

  double _screenXForDay(int dayIndex, double vw) =>
      vw / 2 + (dayIndex - _todayIndex) * _dayWidth - _hScroll;

  /// 「活着」基准行的 Y：由顶部版式预算推导，而不是固定写死百分比。
  /// 星图关闭或变紧凑时，header 与主轴会一起上移，避免顶部留下空白壳层。
  double _aliveY(double vh) {
    final topBudget =
        _topInset +
        _headerTopPadding +
        _headerBlockHeight +
        _constellationBandHeight(vh) +
        (_constellationVisible ? _constellationHeaderGap : 0.0);
    return topBudget.clamp(132.0, vh * 0.52);
  }

  /// 第 k 个自定义行的 Y（k 从 0 起）
  double _customRowY(int k, double vh) =>
      _aliveY(vh) + (k + 1) * _rowSpacing - _vScroll;

  void _recomputeBounds(Size size) {
    _viewport = size;
    final vh = size.height;

    if (_isFirstDayTutorial) {
      // 首日教学：横向只允许滚动到「出生日」（唯一可达的历史位置）。
      _hScrollMin = -_survivalDays * _dayWidth;
      _hScrollMax = 0.0;
    } else {
      _hScrollMin = -(_totalDays - 1) * _dayWidth;
      _hScrollMax = _futureDays * _dayWidth;
    }
    if (_hScrollMin > _hScrollMax) {
      final t = _hScrollMin;
      _hScrollMin = _hScrollMax;
      _hScrollMax = t;
    }
    _hScroll = _hScroll.clamp(_hScrollMin, _hScrollMax);

    // 首日教学态：今日节点默认居中（_hScrollMax = 0，会显示在右边缘外侧），
    // 直接置为 _hScrollMax 确保节点在屏幕内可直接点击。
    if (_isFirstDayTutorial) {
      _hScroll = _hScrollMax;
    }

    // 纵向滚动：底部停在最后一条自定义行，不允许继续向下空滚。
    // 当最后一行已经在视口内时，_vScrollMax 保持 0。
    //
    // 关键：_vScrollMax 必须刚好落在 snap 栅格（_rowSpacing 的整数倍）上，
    // 否则松手 snap 将目标 clamp 到非栅格值，导致最后一行停在吸附之间，
    // 视觉上像「穿模」到屏幕底部。
    // 因此这里以「最大可吸附行数」为上限：
    //   maxSnapRows = floor(rawMax / rowSpacing)
    //   _vScrollMax = maxSnapRows * rowSpacing
    // 最终最后一行距屏幕顶部的 Y 会在 [desiredBottom, desiredBottom + rowSpacing)
    // 区间内动态浮动 —— 满足用户要求的「动态合适距离」。
    final visibleRowCount = _customLines.length + _friendLines.length;
    final lastCustomRaw = _aliveY(vh) + visibleRowCount * _rowSpacing;
    final desiredBottom = vh * 0.75;
    final rawMax = max(0.0, lastCustomRaw - desiredBottom);
    if (_rowSpacing > 0) {
      final maxSnapRows = (rawMax / _rowSpacing).floor();
      _vScrollMax = maxSnapRows * _rowSpacing.toDouble();
    } else {
      _vScrollMax = rawMax;
    }
    _vScroll = _vScroll.clamp(0.0, _vScrollMax);
  }

  // ─────────────────────────────────────────────
  // 横向滚动
  // ─────────────────────────────────────────────

  /// 软磁吸 tick —— 将 _hScroll 从 _hSnapFrom 平滑插值到 _hSnapTo（150 ms easeOutCubic）。
  void _onHSnapTick() {
    if (!mounted) return;
    final t = _hSnap.value.clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(t);
    _hScroll = _hSnapFrom + (_hSnapTo - _hSnapFrom) * eased;
    if (t >= 1.0 &&
        _dayAxisReveal.value == 0.0 &&
        !_dayAxisReveal.isAnimating) {
      _dayAxisReveal.forward(from: 0);
    }
    _maybeHaptic();
    setState(() {});
  }

  void _maybeHaptic() {
    final centerIndex = (_hScroll / _dayWidth).round() + _todayIndex;
    if (centerIndex != _lastHapticDayIndex) {
      _lastHapticDayIndex = centerIndex;
      HapticService.dateSlide();
    }
  }

  /// 磁吸到最近一日 —— 加入一点速度 projection，保留手势惯性感，但最终必定对齐。
  void _snapHorizontal(double velocityPxPerSec) {
    final currentIndex = (_panStartHScroll / _dayWidth).round();
    final draggedDays = (_hScroll - _panStartHScroll) / _dayWidth;
    final swipeSign = _panDeltaDx.abs() > 0.01
        ? -_panDeltaDx.sign.toInt()
        : (velocityPxPerSec.abs() > 10 ? velocityPxPerSec.sign.toInt() : 0);
    double target;
    if (_isFirstDayTutorial) {
      // 只有两个合法停靠点：今天(0) 与 出生日(_hScrollMin)
      if (swipeSign == 0) {
        final mid = _hScrollMin / 2.0;
        target = _hScroll < mid ? _hScrollMin : 0.0;
      } else {
        target = swipeSign > 0 ? _hScrollMin : 0.0;
      }
    } else {
      int idx;
      if (draggedDays.abs() < 0.6 && swipeSign != 0) {
        idx = currentIndex + swipeSign;
      } else {
        idx = currentIndex + draggedDays.round();
      }
      target = (idx * _dayWidth).clamp(_hScrollMin, _hScrollMax).toDouble();
    }
    _hSnapFrom = _hScroll;
    _hSnapTo = target;
    if ((_hSnapTo - _hSnapFrom).abs() < 0.5) return;
    _dayAxisReveal
      ..stop()
      ..value = 0.0;
    _hSnap
      ..stop()
      ..forward(from: 0);
  }

  // ─────────────────────────────────────────────
  // 纵向：弹簧回弹（用于 pullUp 回收）
  // ─────────────────────────────────────────────

  final double _vSpringFrom = 0;
  final double _vSpringTo = 0;

  void _onVSpringTick() {
    if (!mounted) return;
    final t = _vSpring.value;
    _pullUp = _vSpringFrom + (_vSpringTo - _vSpringFrom) * t;
    if (t >= 1.0) {
      _pullUp = _vSpringTo;
      _vSpring.stop();
    }
    setState(() {});
  }

  /// 纵向 snap tick — 平滑插值到目标行对齐位置
  void _onVSnapTick() {
    if (!mounted) return;
    final t = _vSnap.value.clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(t);
    _vScroll = _vSnapFrom + (_vSnapTo - _vSnapFrom) * eased;
    // 行切换触觉反馈
    if (_rowSpacing > 0) {
      final currentRow = (_vScroll / _rowSpacing).round();
      if (currentRow != _lastVScrollRow) {
        _lastVScrollRow = currentRow;
        HapticService.verticalScrollTick();
      }
    }
    setState(() {});
  }

  /// 纵向松手：惯性 projection + 行对齐 snap
  void _snapVertical(double velocityPxPerSec) {
    if (_vScrollMax <= 0 || _rowSpacing <= 0) return;
    final currentRow = (_panStartVScroll / _rowSpacing).round();
    final draggedRows = (_vScroll - _panStartVScroll) / _rowSpacing;
    final swipeSign = _panDeltaDy.abs() > 0.01
        ? -_panDeltaDy.sign.toInt()
        : (velocityPxPerSec.abs() > 10 ? velocityPxPerSec.sign.toInt() : 0);
    int targetRow;
    if (draggedRows.abs() < 0.6 && swipeSign != 0) {
      targetRow = currentRow + swipeSign;
    } else {
      targetRow = currentRow + draggedRows.round();
    }
    final target = (targetRow * _rowSpacing).clamp(0.0, _vScrollMax).toDouble();
    _vSnapFrom = _vScroll;
    _vSnapTo = target;
    if ((_vSnapTo - _vSnapFrom).abs() < 0.5) return;
    _vSnap
      ..stop()
      ..forward(from: 0);
  }

  // 旧版上拉回弹逻辑已被底部手势区取代（保留 spring 基础设施以便日后复用）

  // ─────────────────────────────────────────────
  // 手势处理
  // ─────────────────────────────────────────────

  void _onPanDown(DragDownDetails d) {
    if (_actionMenuOpen) {
      // 菜单打开时不响应 pan
      return;
    }
    // 不在这里 stop() —— momentum 让它跑到 axis 确定再接续，
    // 避免轻触不滑时 deceleration 被无端中断。
    _axis = _Axis.none;
    _panLive = true;
    _panStartHScroll = _hScroll;
    _panStartVScroll = _vScroll;
    _panDeltaDx = 0.0;
    _panDeltaDy = 0.0;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_actionMenuOpen) return;
    if (!_panLive) return;

    // 径向菜单已打开 → 手指移动更新 hover 判定
    if (_radialMenuOpen) {
      _updateRadialFinger(d.localPosition);
      return;
    }

    _panDeltaDx += d.delta.dx;
    _panDeltaDy += d.delta.dy;

    if (_axis == _Axis.none) {
      final adx = d.delta.dx.abs();
      final ady = d.delta.dy.abs();
      if (adx < 0.2 && ady < 0.2) return;
      _axis = adx > ady ? _Axis.horizontal : _Axis.vertical;
      // axis 确定瞬间才接管 momentum，避免轻触时 deceleration 被误中断。
      if (_axis == _Axis.horizontal) {
        _hSnap.stop();
      } else {
        _vSpring.stop();
        _vSnap.stop();
      }
      if (_axis == _Axis.horizontal && _showHOnboarding) {
        _showHOnboarding = false;
        StorageService.instance.markHSwipeDone();
        HapticService.onboardingComplete();
      } else if (_axis == _Axis.vertical && _showVOnboarding) {
        _showVOnboarding = false;
        StorageService.instance.markVSwipeDone();
        HapticService.onboardingComplete();
      }
    }

    if (_axis == _Axis.horizontal) {
      _hScroll = (_hScroll - d.delta.dx).clamp(_hScrollMin, _hScrollMax);
      _maybeHaptic();
      setState(() {});
    } else {
      // 纵向：仅在内容超过视口时用于浏览多条自定义行。
      final dy = d.delta.dy;
      if (dy < 0) {
        final canScroll = _vScrollMax - _vScroll;
        if (canScroll > 0) {
          final use = min(canScroll, -dy);
          _vScroll += use;
        }
      } else {
        _vScroll = max(0.0, _vScroll - dy);
      }
      // 行切换触觉反馈：当 vScroll 跨越行间距边界时触发
      if (_vScrollMax > 0 && _rowSpacing > 0) {
        final currentRow = (_vScroll / _rowSpacing).round();
        if (currentRow != _lastVScrollRow) {
          _lastVScrollRow = currentRow;
          HapticService.verticalScrollTick();
        }
      }
      setState(() {});
    }
  }

  void _onPanEnd(DragEndDetails d) {
    _panLive = false;
    if (_radialMenuOpen) {
      _closeRadialMenu(haptic: true, executeHover: true);
      _axis = _Axis.none;
      return;
    }
    if (_axis == _Axis.horizontal) {
      _snapHorizontal(-d.velocity.pixelsPerSecond.dx);
    } else if (_axis == _Axis.vertical && _vScrollMax > 0) {
      // 纵向松手：惯性 + 行对齐 snap
      _snapVertical(-d.velocity.pixelsPerSecond.dy);
    }
    _axis = _Axis.none;
  }

  void _onPanCancel() {
    _panLive = false;
    if (_radialMenuOpen) {
      _closeRadialMenu();
      _axis = _Axis.none;
      return;
    }
    if (_axis == _Axis.horizontal) _snapHorizontal(0);
    if (_axis == _Axis.vertical && _vScrollMax > 0) _snapVertical(0);
    _axis = _Axis.none;
  }

  // ─────────────────────────────────────────────
  // 点击：切换今日节点 / 退出菜单 / 卫星备注
  // ─────────────────────────────────────────────

  void _onTapUp(TapUpDetails d) {
    final p = d.localPosition;

    // 1) 删除态（旧版） — 先消化
    if (_deleteModeLineId != null) {
      final hit = _hitTestDeleteButton(p);
      if (hit) {
        _performLegacyDelete(_deleteModeLineId!);
      } else {
        setState(() {
          _deleteModeLineId = null;
          _deleteButtonPos = null;
        });
      }
      return;
    }

    // 2) 卫星点（备注图标）— 今日可编辑，历史日期只读查看
    if (_newFeaturesEnabled) {
      final sat = _hitTestSatellite(p);
      if (sat != null) {
        final isToday = _isTodayColumn(sat.dayIndex);
        _showNoteDialog(sat.lineId, sat.dayIndex, readOnly: !isToday);
        return;
      }
    }

    // 3) 节点本体
    final hit = _hitTestNode(p);
    if (hit == null) {
      // 点击空白区域 → 长按才打开径向菜单（避免与滑动冲突）
      return;
    }
    if (!_isTodayColumn(hit.dayIndex)) {
      final line = _findCustomLine(hit.lineId);
      if (line != null) {
        final date = _startDate.add(Duration(days: hit.dayIndex));
        if ((line.notes[_dateKey(date)] ?? '').isNotEmpty) {
          HapticService.historicalNoteOpen();
          _showNoteDialog(hit.lineId, hit.dayIndex, readOnly: true);
        }
      }
      return;
    } // 仅今日节点可切换
    _toggleNode(hit.lineId);
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (_axis != _Axis.none) return;
    if (_actionMenuOpen) return;
    if (_radialMenuOpen) return;
    final pos = d.localPosition;
    final hit = _hitTestNode(pos);

    if (hit == null) {
      // 空白区域长按 → 打开径向菜单
      _openRadialMenu(pos);
      return;
    }

    if (hit.lineId == _aliveId) {
      // 基准线长按 → 打开径向菜单
      _openRadialMenu(pos);
      return;
    }
    if (_friendLineIds.contains(hit.lineId)) {
      // 好友行长按：径向菜单（改名 / Unfriend）留到下一个大版本。
      // 当前走 friend_discovery_page 的既有长按入口，这里不落 custom line action menu，
      // 避免"看得到但不能用"的错误入口。
      return;
    }
    if (!_isTodayColumn(hit.dayIndex)) return;

    if (_newFeaturesEnabled) {
      _openActionMenu(hit.lineId, hit.dayIndex, hit.center);
    } else {
      setState(() {
        _deleteModeLineId = hit.lineId;
        _deleteButtonPos = hit.center;
      });
      HapticService.longPressEnter();
      _shake.forward(from: 0).then((_) {
        if (!mounted) return;
        _shake.value = 0;
      });
    }
  }

  // ─────────────────────────────────────────────
  // 命中测试
  // ─────────────────────────────────────────────

  _NodeHit? _hitTestNode(Offset p) {
    final vw = _viewport.width;
    final vh = _viewport.height;
    if (vw <= 0 || vh <= 0) return null;

    final dayIndex =
        ((p.dx - vw / 2 + _hScroll) / _dayWidth).round() + _todayIndex;
    if (dayIndex < 0) return null;
    final centerX = _screenXForDay(dayIndex, vw);
    if ((p.dx - centerX).abs() > _nodeHitRadius) return null;

    final aliveY = _aliveY(vh);
    if ((p.dy - aliveY).abs() < _nodeHitRadius) {
      return _NodeHit(
        lineId: _aliveId,
        dayIndex: dayIndex,
        center: Offset(centerX, aliveY),
      );
    }
    for (int k = 0; k < _customLines.length; k++) {
      if (dayIndex < _lineStartDayIndex(_customLines[k].createdAt)) {
        continue;
      }
      final y = _customRowY(k, vh);
      if ((p.dy - y).abs() < _nodeHitRadius) {
        return _NodeHit(
          lineId: _customLines[k].id,
          dayIndex: dayIndex,
          center: Offset(centerX, y),
        );
      }
    }
    for (int j = 0; j < _friendLines.length; j++) {
      final line = _friendLines[j];
      if (dayIndex < _lineStartDayIndex(line.createdAt)) continue;
      final y = _customRowY(_customLines.length + j, vh);
      if ((p.dy - y).abs() < _nodeHitRadius) {
        return _NodeHit(
          lineId: line.id,
          dayIndex: dayIndex,
          center: Offset(centerX, y),
        );
      }
    }
    return null;
  }

  /// 卫星点命中测试：仅对有备注的节点生效
  _SatelliteHit? _hitTestSatellite(Offset p) {
    final vw = _viewport.width;
    final vh = _viewport.height;
    if (vw <= 0 || vh <= 0) return null;

    final maxIdx = _totalDays - 1 + _futureDays;
    final firstDay = max(
      0,
      ((_hScroll - vw / 2) / _dayWidth).floor() + _todayIndex - 1,
    );
    final lastDay = min(
      maxIdx,
      ((_hScroll + vw / 2) / _dayWidth).ceil() + _todayIndex + 1,
    );

    final angle = _satelliteRotationEnabled ? _satellite.value * 2 * pi : 0.0;

    for (int k = 0; k < _customLines.length; k++) {
      final line = _customLines[k];
      if (line.notes.isEmpty) continue;
      final y = _customRowY(k, vh);
      if (y < -40 || y > vh + 40) continue;
      for (int i = firstDay; i <= lastDay; i++) {
        if (i < 0) continue;
        final date = _startDate.add(Duration(days: i));
        final key = _dateKey(date);
        if (!line.notes.containsKey(key)) continue;
        final x = _screenXForDay(i, vw);
        // 卫星点位置
        final sx = x + cos(angle) * _satelliteRingRadius;
        final sy = y + sin(angle) * _satelliteRingRadius;
        if ((p - Offset(sx, sy)).distance <= 12.0) {
          return _SatelliteHit(lineId: line.id, dayIndex: i);
        }
      }
    }
    return null;
  }

  bool _hitTestDeleteButton(Offset p) {
    if (_deleteButtonPos == null) return false;
    final btnCenter = _deleteButtonPos! + const Offset(56, 0);
    return (p - btnCenter).distance <= 36;
  }

  // ─────────────────────────────────────────────
  // 节点状态切换
  // ─────────────────────────────────────────────

  Future<void> _toggleNode(String lineId) async {
    // 时间被篡改时阻止写入
    if (TimeIntegrityService.instance.tampered) {
      HapticFeedback.mediumImpact();
      return;
    }
    // 首次点击今日节点 → 结束 tap-today 引导
    if (_showTapTodayOnboarding) {
      _showTapTodayOnboarding = false;
      _showRadialMenuOnboarding = true;
      StorageService.instance.markTapTodayDone();
      HapticService.onboardingComplete();
    }
    final previousCheckedDates = _checkedDatesForLine(lineId);
    final previousDayIndex = _latestCheckedDayBeforeToday(previousCheckedDates);
    bool nowChecked;
    try {
      if (lineId == _aliveId) {
        nowChecked = await StorageService.instance.toggleAliveToday();
        if (!mounted) return;
        _aliveCheckIns = StorageService.instance.getCheckInDates();
        _computeGapData();
        _bounceKey = _aliveId;
      } else if (_friendLineIds.contains(lineId)) {
        final friend = _friendsById[lineId];
        if (friend == null) return;
        final todayKey = _dateKey(_today);
        // 仅当对方 BLE 在范围内才允许对今日打卡（过去节点不可修改）。
        // 若缓存未命中，启动一次短窗口主动探测（方案 B）；否则走快速路径。
        bool inRange = BleService.instance.isPeerInRange(friend.uid);
        debugPrint('[FRIEND_TAP] uid=${friend.uid} cacheHit=$inRange');
        if (!inRange) {
          inRange = await _probeFriendInRange(friend.uid);
          debugPrint('[FRIEND_TAP] probe result inRange=$inRange');
          if (!mounted) return;
          if (!inRange) {
            HapticFeedback.mediumImpact();
            return;
          }
        }
        if (friend.checkInDates.contains(todayKey)) {
          friend.checkInDates.remove(todayKey);
          nowChecked = false;
        } else {
          friend.checkInDates.add(todayKey);
          nowChecked = true;
        }
        await friend.save();
        if (!mounted) return;
        _friendLines = _buildFriendLines(
          await BleService.instance.listFriends(),
        );
        _bounceKey = lineId;
        _bleFlashKey = lineId;
        _bleFlash.forward(from: 0);
      } else {
        final line = _findCustomLine(lineId);
        if (line == null) {
          debugPrint('==== WARNING: toggleNode line not found: $lineId ====');
          return;
        }
        nowChecked = await StorageService.instance.toggleCustomTodayForLine(
          line,
        );
        if (!mounted) return;
        _customLines = StorageService.instance.getCustomLines();
        _bounceKey = lineId;
      }
    } on TimeTamperedException {
      // 前置检查和 _nowForWrite 之间若出现竞态（极罕见），也静默拒写
      HapticFeedback.mediumImpact();
      return;
    }
    HapticService.checkInToggle();
    _bounce.forward(from: 0);
    _startTodayNodeFx(
      lineId: lineId,
      fromDayIndex: previousDayIndex,
      appearing: nowChecked,
    );
    setState(() {});
  }

  Set<String> _checkedDatesForLine(String lineId) {
    if (lineId == _aliveId) return {..._aliveCheckIns};
    if (_friendLineIds.contains(lineId)) {
      final friend = _friendsById[lineId];
      if (friend == null) return <String>{};
      return {...friend.checkInDates};
    }
    final line = _findCustomLine(lineId);
    return line == null ? <String>{} : {...line.completedDates};
  }

  int? _latestCheckedDayBeforeToday(Set<String> checkedDates) {
    int? latest;
    for (final key in checkedDates) {
      final date = _parseDateKey(key);
      final diff = DateUtils.dateOnly(
        date,
      ).difference(DateUtils.dateOnly(_startDate)).inDays;
      if (diff >= _todayIndex) continue;
      if (latest == null || diff > latest) latest = diff;
    }
    return latest;
  }

  /// 返回给定 lineId 对应时间轴行的屏幕 Y；未知行返回 null。
  /// 仅用于把时间轴 today-node 的位置投影给顶部星图作为极罕见兜底 origin。
  double? _rowScreenYForLine(String lineId, double vh) {
    if (lineId == _aliveId) return _aliveY(vh);
    if (_friendLineIds.contains(lineId)) {
      final j = _friendLines.indexWhere((f) => f.id == lineId);
      if (j < 0) return null;
      return _customRowY(_customLines.length + j, vh);
    }
    final k = _customLines.indexWhere((l) => l.id == lineId);
    if (k < 0) return null;
    return _customRowY(k, vh);
  }

  DateTime _parseDateKey(String key) {
    final p = key.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  void _startTodayNodeFx({
    required String lineId,
    required int? fromDayIndex,
    required bool appearing,
  }) {
    _todayNodeFxLineId = lineId;
    _todayNodeFxFromDayIndex = fromDayIndex;
    _todayNodeFxAppearing = appearing;
    _todayNodeLinkAnim.forward(from: 0);
  }

  // ─────────────────────────────────────────────
  // 操作菜单（4 向）
  // ─────────────────────────────────────────────

  void _openActionMenu(String lineId, int dayIndex, Offset center) {
    if (_actionMenuOpen) return;
    HapticService.actionMenuOpen();
    setState(() {
      _actionMenuOpen = true;
      _actionMenuLineId = lineId;
      _actionMenuDayIndex = dayIndex;
      _actionMenuCenter = center;
    });
    _menuAnim.forward(from: 0);
  }

  Future<void> _closeActionMenu({bool haptic = false}) async {
    if (!_actionMenuOpen) return;
    if (haptic) HapticService.actionMenuSelect();
    await _menuAnim.reverse();
    if (!mounted) return;
    setState(() {
      _actionMenuOpen = false;
      _actionMenuLineId = null;
      _actionMenuDayIndex = null;
      _actionMenuCenter = null;
    });
  }

  Future<void> _onMenuIconTap(String which) async {
    final lineId = _actionMenuLineId;
    final dayIndex = _actionMenuDayIndex;
    if (lineId == null || dayIndex == null) return;
    HapticService.actionMenuSelect();
    await _closeActionMenu();
    if (!mounted) return;
    switch (which) {
      case 'rename':
        await _showRenameDialog(lineId);
        break;
      case 'delete':
        await _confirmDeleteLine(lineId);
        break;
      case 'note':
        await _showNoteDialog(lineId, dayIndex);
        break;
      case 'archive':
        await _archiveLine(lineId);
        break;
      case 'reorder':
        await _showReorderDialog();
        break;
    }
  }

  // ─────────────────────────────────────────────
  // 对话框 / 操作
  // ─────────────────────────────────────────────

  Future<void> _showAddLineDialog() async {
    if (TimeIntegrityService.instance.tampered) {
      HapticFeedback.mediumImpact();
      return;
    }
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(120),
      builder: (ctx) => const _AddLineSheet(),
    );
    if (!mounted) return;
    if (name == null || name.trim().isEmpty) return;
    try {
      await StorageService.instance.addCustomLine(name.trim());
    } on TimeTamperedException {
      // sheet 打开期间用户改了系统时间 → 不允许新增
      HapticFeedback.mediumImpact();
      return;
    }
    if (!mounted) return;
    _customLines = StorageService.instance.getCustomLines();
    HapticService.lineAdded();
    // 首次添加：标记完成并启动中央虚线下降动画（作为连线教学）。
    final wasFirst = !_hasFirstTrack;
    if (wasFirst) {
      _hasFirstTrack = true;
      StorageService.instance.markFirstTrackAdded();
      _centerLineAnim.forward(from: 0);
    }
    _recomputeBounds(_viewport);
    _lineAddAnim.forward(from: 0);
    setState(() {});
  }

  TrailLine? _findCustomLine(String lineId) {
    return _customLines.cast<TrailLine?>().firstWhere(
      (l) => l?.id == lineId,
      orElse: () => null,
    );
  }

  Future<void> _showRenameDialog(String lineId) async {
    // 重命名会往 nameHistory 写「生效日」键 — tampered 时拒绝
    if (TimeIntegrityService.instance.tampered) {
      HapticFeedback.mediumImpact();
      return;
    }
    final line = _findCustomLine(lineId);
    if (line == null) return;
    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(120),
      builder: (ctx) => _RenameSheet(initial: line.name),
    );
    if (!mounted) return;
    if (newName == null || newName.trim().isEmpty) return;
    try {
      await StorageService.instance.renameCustomLine(line, newName.trim());
    } on TimeTamperedException {
      // 保险：sheet 打开后用户改了系统时间 → 静默拒写
      HapticFeedback.mediumImpact();
      return;
    }
    if (!mounted) return;
    _customLines = StorageService.instance.getCustomLines();
    setState(() {});
  }

  Future<void> _showNoteDialog(
    String lineId,
    int dayIndex, {
    bool readOnly = false,
  }) async {
    final line = _findCustomLine(lineId);
    if (line == null) return;
    final date = _startDate.add(Duration(days: dayIndex));
    final existing = line.notes[_dateKey(date)] ?? '';
    final result = await showModalBottomSheet<_NoteSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(120),
      builder: (ctx) => _NoteSheet(
        initial: existing,
        date: date,
        lineName: line.displayNameOn(date),
        readOnly: readOnly,
      ),
    );
    if (readOnly) return; // 只读模式不处理结果
    if (!mounted) return;
    if (result == null) return;
    if (result.deleted) {
      await StorageService.instance.setNoteFor(line, date, null);
    } else {
      await StorageService.instance.setNoteFor(line, date, result.text);
    }
    if (!mounted) return;
    _customLines = StorageService.instance.getCustomLines();
    setState(() {});
  }

  Future<void> _confirmDeleteLine(String lineId) async {
    final line = _findCustomLine(lineId);
    if (line == null) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withAlpha(150),
      builder: (ctx) => _ConfirmDialog(
        title: '删除「${line.name}」？',
        subtitle: '行动线及其全部打卡 / 备注将被永久移除',
        confirmLabel: '删除',
        onCancel: () => Navigator.pop(ctx, false),
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    );
    if (!mounted) return;
    if (ok != true) return;
    await StorageService.instance.deleteCustomLine(line);
    if (!mounted) return;
    _customLines = StorageService.instance.getCustomLines();
    HapticService.lineDeleted();
    _recomputeBounds(_viewport);
    setState(() {});
  }

  /// 重排行序 — 弹出 ReorderableList 让用户拖拽行的纵向顺序
  Future<void> _showReorderDialog() async {
    if (_customLines.isEmpty) return;
    final initial = _customLines.map((l) => l.id).toList(growable: false);
    final names = {for (final l in _customLines) l.id: l.name};
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(160),
      builder: (ctx) => _ReorderSheet(initialOrder: initial, names: names),
    );
    if (!mounted) return;
    if (result == null) return;
    await StorageService.instance.setLineOrder(result);
    HapticService.actionMenuSelect();
    if (!mounted) return;
    _customLines = StorageService.instance.getCustomLines();
    _recomputeBounds(_viewport);
    setState(() {});
  }

  Future<void> _archiveLine(String lineId) async {
    // archivedAt 参与排序 — tampered 时拒绝
    if (TimeIntegrityService.instance.tampered) {
      HapticFeedback.mediumImpact();
      return;
    }
    final line = _findCustomLine(lineId);
    if (line == null) return;
    try {
      await StorageService.instance.archiveLine(line);
    } on TimeTamperedException {
      HapticFeedback.mediumImpact();
      return;
    }
    HapticService.lineArchived();
    if (!mounted) return;
    _customLines = StorageService.instance.getCustomLines();
    _recomputeBounds(_viewport);
    setState(() {});
  }

  /// 旧版：直接删除（无 dialog 二次确认）
  Future<void> _performLegacyDelete(String lineId) async {
    final target = _customLines.cast<TrailLine?>().firstWhere(
      (l) => l?.id == lineId,
      orElse: () => null,
    );
    if (target == null) {
      setState(() {
        _deletingLineId = null;
        _deleteModeLineId = null;
        _deleteButtonPos = null;
      });
      return;
    }
    setState(() {
      _deletingLineId = lineId;
      _deleteModeLineId = null;
      _deleteButtonPos = null;
    });
    HapticService.lineDeleted();
    await _lineDeleteAnim.reverse(from: 1.0);
    if (!mounted) return;
    await StorageService.instance.deleteCustomLine(target);
    if (!mounted) return;
    _customLines = StorageService.instance.getCustomLines();
    _deletingLineId = null;
    _lineDeleteAnim.value = 1.0;
    _recomputeBounds(_viewport);
    setState(() {});
  }

  // ─────────────────────────────────────────────
  // 设置入口
  // ─────────────────────────────────────────────

  Future<void> _openSettings() async {
    HapticService.actionMenuSelect();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    if (!mounted) return;
    _loadPrefs();
    _applySatelliteRotation();
    // 归档/恢复也可能在归档页中发生 → 重新拉取
    _customLines = StorageService.instance.getCustomLines();
    _recomputeBounds(_viewport);
    setState(() {});
  }

  // ─────────────────────────────────────────────
  // BLE 好友发现入口
  // ─────────────────────────────────────────────

  Future<void> _openFriendDiscovery() async {
    HapticService.actionMenuSelect();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FriendDiscoveryPage()));
    if (!mounted) return;
    await _loadFriendSummary();
    setState(() {});
  }

  Future<void> _loadFriendSummary() async {
    final friends = await BleService.instance.listFriends();
    if (!mounted) return;
    final friendLines = _buildFriendLines(friends);
    final friendsById = <String, Friend>{
      for (final f in friends)
        if (f.state == FriendState.confirmed) _friendLineId(f.uid): f,
    };
    setState(() {
      // "pending" 在主页小红点语义里涵盖我方正在等或对方正在等我 — 两者都算未完成互确认
      _pendingFriendCount = friends
          .where(
            (f) =>
                f.state == FriendState.pendingOutgoing ||
                f.state == FriendState.pendingIncoming,
          )
          .length;
      _confirmedFriendCount = friends
          .where((f) => f.state == FriendState.confirmed)
          .length;
      _friendLines = friendLines;
      _friendsById = friendsById;
      _friendLineIds = friendsById.keys.toSet();
    });
    if (_viewport != Size.zero) {
      _recomputeBounds(_viewport);
    }
  }

  // ─────────────────────────────────────────────
  // 全局径向菜单（长按触发）
  // ─────────────────────────────────────────────

  void _openRadialMenu(Offset anchor) {
    if (_radialMenuOpen) return;
    if (_showRadialMenuOnboarding) {
      _showRadialMenuOnboarding = false;
      StorageService.instance.markRadialMenuDone();
      HapticService.onboardingComplete();
    }
    _radialMenuOpen = true;
    _radialAnchor = anchor;
    _radialHover = null;
    HapticService.actionMenuOpen();
    _radialAnim.forward(from: 0.0);
    setState(() {});
  }

  void _updateRadialFinger(Offset finger) {
    if (!_radialMenuOpen) return;
    const iconDist = 56.0;
    final addCenter = Offset(_radialAnchor.dx, _radialAnchor.dy - iconDist);
    final settingsCenter = Offset(
      _radialAnchor.dx + iconDist,
      _radialAnchor.dy,
    );
    final friendCenter = Offset(_radialAnchor.dx - iconDist, _radialAnchor.dy);
    const hoverRadius = 32.0;
    String? hover;
    if ((finger - addCenter).distance < hoverRadius) {
      hover = 'add';
    } else if ((finger - settingsCenter).distance < hoverRadius) {
      hover = 'settings';
    } else if ((finger - friendCenter).distance < hoverRadius) {
      hover = 'friend';
    }
    if (hover != _radialHover) {
      _radialHover = hover;
      if (hover != null) HapticService.dateSlide();
    }
    setState(() {});
  }

  void _closeRadialMenu({bool haptic = false, bool executeHover = false}) {
    if (!_radialMenuOpen) return;
    final action = executeHover ? _radialHover : null;
    _radialMenuOpen = false;
    _radialHover = null;
    if (haptic) HapticService.actionMenuSelect();
    _radialAnim.reverse().then((_) {
      if (mounted) setState(() {});
    });
    setState(() {});
    if (action != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (action) {
          case 'add':
            _showAddLineDialog();
            break;
          case 'settings':
            _openSettings();
            break;
          case 'friend':
            _openFriendDiscovery();
            break;
        }
      });
    }
  }

  void _onRadialSelect(String action) {
    _closeRadialMenu(haptic: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (action) {
        case 'add':
          _showAddLineDialog();
          break;
        case 'settings':
          _openSettings();
          break;
        case 'friend':
          _openFriendDiscovery();
          break;
      }
    });
  }

  // ── 时间篡改警告横幅 ──────────────────────────────

  Widget _buildTamperWarning() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF8B0000).withAlpha(220),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF4444).withAlpha(80)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFF6B6B),
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '检测到系统时间异常，操作将被限制',
                  style: TextStyle(
                    color: Color(0xEEDDDDDD),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await TimeIntegrityService.instance.clearTamperAfterFix();
                  if (mounted) setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '已修正',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadialMenuOverlay({required double bottomInset}) {
    if (!_radialMenuOpen && _radialAnim.isDismissed) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _radialAnim,
      builder: (ctx, _) {
        // t=0..0.4：背景暗化（0→0.55）；t=0.4..1：图标弹出。
        final dimT = (_radialAnim.value / 0.4).clamp(0.0, 1.0);
        final iconT = ((_radialAnim.value - 0.4) / 0.6).clamp(0.0, 1.0);
        final dimOpacity = Curves.easeOut.transform(dimT) * 0.55;
        final t = Curves.easeOutBack.transform(iconT.clamp(0.0, 1.0));
        final anchorX = _radialAnchor.dx;
        final anchorY = _radialAnchor.dy;
        const iconDist = 56.0;
        final addHover = _radialHover == 'add';
        final settingsHover = _radialHover == 'settings';
        final friendHover = _radialHover == 'friend';
        final backdropIgnoring = _radialAnim.value > 0.85;
        final iconOpacity = iconT.clamp(0.0, 1.0);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _closeRadialMenu(haptic: true),
                child: IgnorePointer(
                  ignoring: backdropIgnoring,
                  child: Container(color: Color.fromRGBO(0, 0, 0, dimOpacity)),
                ),
              ),
            ),
            Positioned(
              left: anchorX - 22,
              top: anchorY - iconDist * t - 22,
              child: IgnorePointer(
                ignoring: iconT < 0.01,
                child: Opacity(
                  opacity: iconOpacity,
                  child: Transform.scale(
                    scale: addHover ? 1.18 : 1.0,
                    child: _RadialIcon(
                      icon: Icons.add_rounded,
                      label: '新增',
                      highlighted: addHover,
                      onTap: () => _onRadialSelect('add'),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: anchorX + iconDist * t - 22,
              top: anchorY - 22,
              child: IgnorePointer(
                ignoring: iconT < 0.01,
                child: Opacity(
                  opacity: iconOpacity,
                  child: Transform.scale(
                    scale: settingsHover ? 1.18 : 1.0,
                    child: _RadialIcon(
                      icon: Icons.settings_outlined,
                      label: '设置',
                      highlighted: settingsHover,
                      onTap: () => _onRadialSelect('settings'),
                    ),
                  ),
                ),
              ),
            ),
            // 左侧：BLE 加好友
            Positioned(
              left: anchorX - iconDist * t - 22,
              top: anchorY - 22,
              child: IgnorePointer(
                ignoring: iconT < 0.01,
                child: Opacity(
                  opacity: iconOpacity,
                  child: Transform.scale(
                    scale: friendHover ? 1.18 : 1.0,
                    child: _RadialIcon(
                      icon: Icons.people_outline_rounded,
                      label: _confirmedFriendCount > 0 ? '好友' : '配对',
                      highlighted: friendHover,
                      badgeCount: _pendingFriendCount,
                      onTap: () => _onRadialSelect('friend'),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: anchorX - 4,
              top: anchorY - 4,
              child: IgnorePointer(
                child: Opacity(
                  opacity: iconOpacity * 0.6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0x88FFFFFF),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // 构建
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mediaPad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (ctx, cons) {
          final size = Size(cons.maxWidth, cons.maxHeight);
          if (_viewport != size || _topInset != mediaPad.top) {
            _topInset = mediaPad.top;
            _recomputeBounds(size);
          }

          final headerCenter = _centerDayIndex;
          // 出生日虚拟索引 = -_survivalDays。在首日教学模式下，用户可左滑到达。
          final birthDayIndex = -_survivalDays;
          final isCenterBirth =
              _isFirstDayTutorial &&
              headerCenter <= birthDayIndex + 0; // 贴近出生日即视为 birth
          final safeCenterIdx = headerCenter.clamp(0, _totalDays - 1);
          final centerDate = _startDate.add(Duration(days: safeCenterIdx));
          final trailsUpTo = _trailCountUpTo(safeCenterIdx);

          final useNewHeader = _newFeaturesEnabled;
          final aliveYpx = _aliveY(cons.maxHeight);

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Alto 天空背景（透传横滑偏移驱动视差）──
              // AltoBackground 是 const，内部不使用任何 animation 值；
              // 旧版 AnimatedBuilder 包装会让它每帧都参与脏标记，纯浪费。
              const IgnorePointer(child: AltoBackground()),
              // ── 星图背景装饰（仅过去节点）──
              // 允许星点进入三行字下方区域，避免顶部版式过平。
              if (_constellationVisible)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _todayNodeLinkAnim,
                    builder: (context, _) {
                      Offset? timelineTodayNodePos;
                      final fxLineId = _todayNodeFxLineId;
                      if (fxLineId != null) {
                        final rowY = _rowScreenYForLine(
                          fxLineId,
                          cons.maxHeight,
                        );
                        if (rowY != null) {
                          timelineTodayNodePos = Offset(
                            _screenXForDay(_todayIndex, cons.maxWidth),
                            rowY,
                          );
                        }
                      }
                      return ConstellationBackground(
                        aliveCheckIns: _aliveCheckIns,
                        customLines: _customLines,
                        today: _today,
                        topInset: mediaPad.top,
                        bottomY: _constellationBottomY(aliveYpx),
                        visibleHeight: _constellationVisibleHeight(
                          aliveYpx,
                          mediaPad.top,
                        ),
                        todayFxValue: _todayNodeLinkAnim.value,
                        todayFxLineId: _todayNodeFxLineId,
                        todayFxFromDayIndex: _todayNodeFxFromDayIndex,
                        todayFxAppearing: _todayNodeFxAppearing,
                        timelineTodayNodeScreenPos: timelineTodayNodePos,
                      );
                    },
                  ),
                ),
              // ── 时间轴 ──
              _buildGestureLayer(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _glow,
                    _bounce,
                    _bleFlash,
                    _shake,
                    _arrowPulse,
                    _lineAddAnim,
                    _lineDeleteAnim,
                    _todayNodeLinkAnim,
                    _satellite,
                    _centerLineAnim,
                    _dayAxisReveal,
                    _radialAnim,
                    _vSnap,
                  ]),
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(cons.maxWidth, cons.maxHeight),
                      painter: _TimelinePainter(
                        startDate: _startDate,
                        today: _today,
                        totalDays: _totalDays,
                        futureDays: _futureDays,
                        todayIndex: _todayIndex,
                        aliveCheckIns: _aliveCheckIns,
                        customLines: _customLines,
                        friendLines: _friendLines,
                        friendLineIds: _friendLineIds,
                        survivalDays: _survivalDays,
                        dayWidth: _dayWidth,
                        hScroll: _hScroll,
                        vScroll: _vScroll,
                        pullUp: _pullUp,
                        rowSpacing: _rowSpacing,
                        aliveY: aliveYpx,
                        viewportWidth: cons.maxWidth,
                        viewportHeight: cons.maxHeight,
                        glowValue: _glow.value,
                        bounceValue: _bounce.value,
                        bounceKey: _bounceKey,
                        bleFlashValue: _bleFlash.value,
                        bleFlashKey: _bleFlashKey,
                        shakeValue: _shake.value,
                        arrowPulse: _arrowPulse.value,
                        lineAddValue: _lineAddAnim.value,
                        lineDeleteValue: _lineDeleteAnim.value,
                        todayNodeFxValue: _todayNodeLinkAnim.value,
                        todayNodeFxLineId: _todayNodeFxLineId,
                        todayNodeFxFromDayIndex: _todayNodeFxFromDayIndex,
                        todayNodeFxAppearing: _todayNodeFxAppearing,
                        deletingLineId: _deletingLineId,
                        deleteModeLineId: _deleteModeLineId,
                        gapData: _gapData,
                        showHOnboarding: _showHOnboarding,
                        showVOnboarding: _showVOnboarding,
                        pullThresholdLatched: _pullLatched,
                        pullUpThreshold: _pullUpThreshold,
                        // ── 新功能 ──
                        newFeaturesEnabled: _newFeaturesEnabled,
                        satelliteAngle: _satelliteRotationEnabled
                            ? _satellite.value * 2 * pi
                            : 0.0,
                        // ── 新引导 ──
                        showTapTodayOnboarding: _showTapTodayOnboarding,
                        showRadialMenuOnboarding: _showRadialMenuOnboarding,
                        centerLineProgress: _centerLineAnim.value,
                        dayAxisReveal: _dayAxisReveal.value,
                        hasFirstTrack: _hasFirstTrack,
                        isFirstDayTutorial: _isFirstDayTutorial,
                        birthday: _birthday,
                      ),
                    );
                  },
                ),
              ),

              // ── 3 行居中 Header（贴在「活着」基准节点上方，随今日节点同屏呼吸） ──
              if (useNewHeader)
                _buildInlineHeader(
                  survivalDays: _survivalDays,
                  trailsUpTo: trailsUpTo,
                  centerDate: centerDate,
                  isToday: safeCenterIdx == _todayIndex,
                  aliveYpx: aliveYpx,
                  isCenterBirth: isCenterBirth,
                ),

              // ── 旧版删除按钮浮层 ──
              if (!_newFeaturesEnabled &&
                  _deleteModeLineId != null &&
                  _deleteButtonPos != null)
                Positioned(
                  left: _deleteButtonPos!.dx + 28,
                  top: _deleteButtonPos!.dy - 14,
                  child: IgnorePointer(
                    ignoring: true,
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 160),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withAlpha(60),
                            width: 0.6,
                          ),
                        ),
                        child: const Text(
                          '删除',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 2,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── 节点操作菜单（新版） ──
              if (_actionMenuOpen && _actionMenuCenter != null)
                _buildActionMenuOverlay(_actionMenuCenter!),

              // ── 全局径向菜单（长按触发） ──
              _buildRadialMenuOverlay(bottomInset: mediaPad.bottom),

              // ── 时间篡改警告 ──
              if (TimeIntegrityService.instance.tampered) _buildTamperWarning(),
            ],
          );
        },
      ),
    );
  }

  /// 时间轴主手势层。用 RawGestureDetector 以便自定义长按时长（300 ms）。
  Widget _buildGestureLayer({required Widget child}) {
    return RawGestureDetector(
      key: ValueKey('rgd_$_newFeaturesEnabled'),
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(),
              (instance) {
                instance
                  ..onDown = _onPanDown
                  ..onUpdate = _onPanUpdate
                  ..onEnd = _onPanEnd
                  ..onCancel = _onPanCancel;
              },
            ),
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (instance) {
                instance.onTapUp = _onTapUp;
              },
            ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: const Duration(milliseconds: 300),
              ),
              (instance) {
                instance.onLongPressStart = _onLongPressStart;
              },
            ),
      },
      child: child,
    );
  }

  // ─────────────────────────────────────────────
  // 3 行内嵌 Header —— 像初版一样写在「活着」基准节点的上方。
  //   Line 1：YYYY年MM月DD日 星期X（最小，跟随滚动中心日更新）
  //   Line 2：你已在这个星球上暂居 X 天（强调色；绑定用户生日，滚动时不变）
  //   Line 3：截至今日已留下 N 个迹点（从起始累计到滚动中心日的已勾选节点数；随滚动更新）
  // ─────────────────────────────────────────────

  Widget _buildInlineHeader({
    required int survivalDays,
    required int trailsUpTo,
    required DateTime centerDate,
    required bool isToday,
    required double aliveYpx,
    required bool isCenterBirth,
  }) {
    const accent = Color(0xFFE0CFA8); // 淡暖金色
    final centeredSurvivalDay = max(
      1,
      DateUtils.dateOnly(
            centerDate,
          ).difference(DateUtils.dateOnly(_birthday)).inDays +
          1,
    );
    // 统一字号 12dp × 3 行 + 间距 6dp × 2 = 36+12=48 dp。
    const headerFontSize = 12.0;
    // 内容高 = 12×3 + 6×2 = 48dp
    // top = aliveYpx - 底部距节点 - 内容高 = aliveYpx - 44 - 48 = aliveYpx - 92
    // Header 底部距「活着」节点 44dp，与轴主节点文字到节点的距离一致。
    final top = (aliveYpx - 92.0).clamp(0.0, aliveYpx);
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: true,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Container(
              height: 92,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF000000),
                    Color(0xF2000000),
                    Color(0x00000000),
                  ],
                  stops: [0.0, 0.72, 1.0],
                ),
              ),
            ),
            isCenterBirth
                ? _buildBirthHeader(centerDate: centerDate)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildAnimatedDateLine(
                        centerDate: centerDate,
                        fontSize: headerFontSize,
                        textColor: isToday
                            ? const Color(0xAAFFFFFF)
                            : const Color(0x77FFFFFF),
                      ),
                      const SizedBox(height: 6),
                      _buildAnimatedHeaderMetricLine(
                        prefix: '您在这个星球暂居 ',
                        value: centeredSurvivalDay,
                        suffix: ' 天',
                        fontSize: headerFontSize,
                        baseColor: const Color(0xEEFFFFFF),
                        valueColor: accent,
                      ),
                      const SizedBox(height: 6),
                      _buildAnimatedHeaderMetricLine(
                        prefix: '截至此日留下 ',
                        value: trailsUpTo,
                        suffix: ' 个迹点',
                        fontSize: headerFontSize,
                        baseColor: const Color(0x99FFFFFF),
                        valueColor: const Color(0xCCFFFFFF),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedDateLine({
    required DateTime centerDate,
    required double fontSize,
    required Color textColor,
  }) {
    final dateLabel = _fmtDateZh(centerDate);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) {
        final slide =
            Tween<Offset>(
              begin: const Offset(0, 0.45),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return ClipRect(
          child: FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          ),
        );
      },
      child: Text(
        dateLabel,
        key: ValueKey<String>(dateLabel),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w300,
          letterSpacing: 1.0,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _buildAnimatedHeaderMetricLine({
    required String prefix,
    required int value,
    required String suffix,
    required double fontSize,
    required Color baseColor,
    required Color valueColor,
  }) {
    return DefaultTextStyle(
      style: TextStyle(
        color: baseColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.0,
        decoration: TextDecoration.none,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(prefix),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) {
              final slide =
                  Tween<Offset>(
                    begin: const Offset(0, 0.55),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  );
              final fade = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              );
              return ClipRect(
                child: FadeTransition(
                  opacity: fade,
                  child: SlideTransition(position: slide, child: child),
                ),
              );
            },
            child: Text(
              '$value',
              key: ValueKey<int>(value),
              style: TextStyle(
                color: valueColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Text(suffix),
        ],
      ),
    );
  }

  /// 出生日 3 行 Header（统一字号）
  ///   Line 1: YYYY年MM月DD日
  ///   Line 2: 出生日
  ///   Line 3: 截止目前 XXX天
  Widget _buildBirthHeader({required DateTime centerDate}) {
    const headerFontSize = 12.0;
    final mm = _birthday.month.toString().padLeft(2, '0');
    final dd = _birthday.day.toString().padLeft(2, '0');
    final line1 = '${_birthday.year}年$mm月$dd日';
    final days = DateUtils.dateOnly(
      centerDate,
    ).difference(DateUtils.dateOnly(_birthday)).inDays.abs();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          line1,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xAAFFFFFF),
            fontSize: headerFontSize,
            fontWeight: FontWeight.w300,
            letterSpacing: 1.0,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '出生日',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xEEFFFFFF),
            fontSize: headerFontSize,
            fontWeight: FontWeight.w500,
            letterSpacing: 2.4,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '截止目前 $days 天',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0x99FFFFFF),
            fontSize: headerFontSize,
            fontWeight: FontWeight.w400,
            letterSpacing: 1.0,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  String _fmtDateZh(DateTime d) {
    const wk = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}年$mm月$dd日 ${wk[d.weekday - 1]}';
  }

  // ─────────────────────────────────────────────
  // 操作菜单浮层
  // ─────────────────────────────────────────────

  /// 节点操作菜单浮层 —— 背景先暗化，再弹出 4 向图标。
  Widget _buildActionMenuOverlay(Offset center) {
    return AnimatedBuilder(
      animation: _menuAnim,
      builder: (ctx, _) {
        // t=0..0.4：背景暗化（0→0.55）；t=0.4..1：图标弹出。
        final dimT = (_menuAnim.value / 0.4).clamp(0.0, 1.0);
        final iconT = ((_menuAnim.value - 0.4) / 0.6).clamp(0.0, 1.0);
        final dimOpacity = Curves.easeOut.transform(dimT) * 0.55;

        return Stack(
          children: [
            // 暗化背景（点击关闭菜单）
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _closeActionMenu(haptic: true),
                child: IgnorePointer(
                  ignoring: dimOpacity < 0.01,
                  child: Container(color: Color.fromRGBO(0, 0, 0, dimOpacity)),
                ),
              ),
            ),
            // 环 + 加深节点（跟随图标进度）
            IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: _ActionMenuPainter(
                  center: center,
                  progress: Curves.easeOutBack.transform(iconT),
                ),
              ),
            ),
            // 4 图标
            ..._buildMenuIcons(center, iconT),
          ],
        );
      },
    );
  }

  List<Widget> _buildMenuIcons(Offset center, double masterT) {
    // 45° 对角菱形排布（避开上下水平时间线）：TR / BR / BL / TL。
    // 删除操作已迁移到「归档页」，此处 4 位以「重排行序」替代「删除」。
    const diag = 0.70710678; // cos(π/4)
    const items = [
      _MenuIconSpec(
        which: 'rename',
        icon: Icons.edit_outlined,
        dx: diag,
        dy: -diag,
        stagger: 0.0,
      ), // 右上：重命名
      _MenuIconSpec(
        which: 'note',
        icon: Icons.chat_bubble_outline,
        dx: diag,
        dy: diag,
        stagger: 0.1,
      ), // 右下：备注
      _MenuIconSpec(
        which: 'archive',
        icon: Icons.archive_outlined,
        dx: -diag,
        dy: diag,
        stagger: 0.2,
      ), // 左下：归档
      _MenuIconSpec(
        which: 'reorder',
        icon: Icons.swap_vert,
        dx: -diag,
        dy: -diag,
        stagger: 0.3,
      ), // 左上：重排行序
    ];
    final widgets = <Widget>[];
    for (final spec in items) {
      final localTraw = ((masterT - spec.stagger) / (1.0 - spec.stagger)).clamp(
        0.0,
        1.0,
      );
      final eased = Curves.easeOutBack.transform(localTraw);
      final dx = spec.dx * _menuIconRadius * eased;
      final dy = spec.dy * _menuIconRadius * eased;
      final iconCenter = center + Offset(dx, dy);
      widgets.add(
        Positioned(
          left: iconCenter.dx - _menuIconHitSize / 2,
          top: iconCenter.dy - _menuIconHitSize / 2,
          width: _menuIconHitSize,
          height: _menuIconHitSize,
          child: Opacity(
            opacity: localTraw,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onMenuIconTap(spec.which),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0x18FFFFFF),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0x44FFFFFF),
                    width: 0.6,
                  ),
                ),
                child: Icon(spec.icon, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}

// ═══════════════════════════════════════════════════
// 命中信息
// ═══════════════════════════════════════════════════

class _NodeHit {
  final String lineId;
  final int dayIndex;
  final Offset center;
  _NodeHit({
    required this.lineId,
    required this.dayIndex,
    required this.center,
  });
}

class _SatelliteHit {
  final String lineId;
  final int dayIndex;
  _SatelliteHit({required this.lineId, required this.dayIndex});
}

class _MenuIconSpec {
  final String which;
  final IconData icon;
  final double dx;
  final double dy;
  final double stagger;
  const _MenuIconSpec({
    required this.which,
    required this.icon,
    required this.dx,
    required this.dy,
    required this.stagger,
  });
}

// ═══════════════════════════════════════════════════
// 径向菜单图标按钮
// ═══════════════════════════════════════════════════

class _RadialIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;
  final int badgeCount;
  final VoidCallback onTap;
  const _RadialIcon({
    required this.icon,
    required this.label,
    this.highlighted = false,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgAlpha = highlighted ? 0.38 : 0.22;
    final borderAlpha = highlighted ? 0.7 : 0.44;
    final iconColor = highlighted ? Colors.white : const Color(0xCCFFFFFF);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.fromRGBO(255, 255, 255, bgAlpha),
                    border: Border.all(
                      color: Color.fromRGBO(255, 255, 255, borderAlpha),
                      width: highlighted ? 1.0 : 0.6,
                    ),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE09A62),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 新增行动线输入面板（极简）
// ═══════════════════════════════════════════════════

class _AddLineSheet extends StatefulWidget {
  const _AddLineSheet();

  @override
  State<_AddLineSheet> createState() => _AddLineSheetState();
}

class _AddLineSheetState extends State<_AddLineSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.unfocus();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    _submitted = true;
    final txt = _controller.text.trim();
    _focus.unfocus();
    Navigator.of(context).pop(txt);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {},
        child: Container(
          color: Colors.black.withAlpha(180),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '新增一条行动线',
                style: TextStyle(
                  color: Color(0xAAFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                cursorColor: Colors.white,
                cursorWidth: 1.0,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.8,
                ),
                decoration: const InputDecoration(
                  hintText: '起个名字 …',
                  hintStyle: TextStyle(
                    color: Color(0x55FFFFFF),
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                  ),
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0x33FFFFFF),
                      width: 0.6,
                    ),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0x33FFFFFF),
                      width: 0.6,
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0xAAFFFFFF),
                      width: 0.8,
                    ),
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                maxLength: 12,
                buildCounter:
                    (
                      _, {
                      required int currentLength,
                      required bool isFocused,
                      required int? maxLength,
                    }) => null,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_submitted) return;
                      _submitted = true;
                      _focus.unfocus();
                      Navigator.of(context).pop(null);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          color: Color(0x77FFFFFF),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _submit,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        '确认',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 重命名输入面板
// ═══════════════════════════════════════════════════

class _RenameSheet extends StatefulWidget {
  final String initial;
  const _RenameSheet({required this.initial});

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.unfocus();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    _submitted = true;
    final txt = _controller.text.trim();
    _focus.unfocus();
    Navigator.of(context).pop(txt.isEmpty ? null : txt);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {},
        child: Container(
          color: Colors.black.withAlpha(180),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '重命名',
                style: TextStyle(
                  color: Color(0xAAFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                cursorColor: Colors.white,
                cursorWidth: 1.0,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.8,
                ),
                decoration: const InputDecoration(
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0x33FFFFFF),
                      width: 0.6,
                    ),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0x33FFFFFF),
                      width: 0.6,
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: Color(0xAAFFFFFF),
                      width: 0.8,
                    ),
                  ),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                maxLength: 12,
                buildCounter:
                    (
                      _, {
                      required int currentLength,
                      required bool isFocused,
                      required int? maxLength,
                    }) => null,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_submitted) return;
                      _submitted = true;
                      _focus.unfocus();
                      Navigator.of(context).pop(null);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          color: Color(0x77FFFFFF),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _submit,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        '保存',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 备注输入面板
// ═══════════════════════════════════════════════════

class _NoteSheetResult {
  final String text;
  final bool deleted;
  _NoteSheetResult.save(this.text) : deleted = false;
  _NoteSheetResult.delete() : text = '', deleted = true;
}

class _NoteSheet extends StatefulWidget {
  final String initial;
  final DateTime date;
  final String lineName;
  final bool readOnly;
  const _NoteSheet({
    required this.initial,
    required this.date,
    required this.lineName,
    this.readOnly = false,
  });

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.unfocus();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_submitted) return;
    _submitted = true;
    final txt = _controller.text.trim();
    _focus.unfocus();
    if (txt.isEmpty && widget.initial.isNotEmpty) {
      Navigator.of(context).pop(_NoteSheetResult.delete());
    } else if (txt.isEmpty) {
      Navigator.of(context).pop(null);
    } else {
      Navigator.of(context).pop(_NoteSheetResult.save(txt));
    }
  }

  void _cancel() {
    if (_submitted) return;
    _submitted = true;
    _focus.unfocus();
    Navigator.of(context).pop(null);
  }

  void _delete() {
    if (_submitted) return;
    _submitted = true;
    _focus.unfocus();
    Navigator.of(context).pop(_NoteSheetResult.delete());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasExisting = widget.initial.isNotEmpty;
    final isReadOnly = widget.readOnly;
    final dateStr =
        '${widget.date.year}/${widget.date.month}/${widget.date.day}';
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => Navigator.of(context).pop(null),
        child: Container(
          color: Colors.black.withAlpha(180),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.lineName,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 2,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      color: Color(0x77FFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (isReadOnly) ...[
                    const SizedBox(width: 10),
                    const Text(
                      '只读查看',
                      style: TextStyle(
                        color: Color(0x55FFFFFF),
                        fontSize: 10,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 70,
                  maxHeight: 200,
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: !isReadOnly,
                  enabled: !isReadOnly,
                  maxLines: null,
                  cursorColor: Colors.white,
                  cursorWidth: 1.0,
                  style: TextStyle(
                    color: isReadOnly ? const Color(0xAAFFFFFF) : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: isReadOnly ? '（无备注）' : '记一笔吧 …',
                    hintStyle: TextStyle(
                      color: const Color(0x44FFFFFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              if (!isReadOnly) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (hasExisting)
                      GestureDetector(
                        onTap: _delete,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            '删除',
                            style: TextStyle(
                              color: Color(0x77FFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 2,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _cancel,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          '取消',
                          style: TextStyle(
                            color: Color(0x77FFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 2,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _save,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          '保存',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 2,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ], // end if (!isReadOnly)
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 通用二次确认对话框
// ═══════════════════════════════════════════════════

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x22FFFFFF), width: 0.6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0x77FFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.6,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: onCancel,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: Color(0x77FFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onConfirm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 重排行序面板 —— 拖拽调整自定义行动线的纵向顺序
// ═══════════════════════════════════════════════════

class _ReorderSheet extends StatefulWidget {
  final List<String> initialOrder;
  final Map<String, String> names;
  const _ReorderSheet({required this.initialOrder, required this.names});

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    _order = List<String>.from(widget.initialOrder);
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final id = _order.removeAt(oldIndex);
      _order.insert(newIndex, id);
    });
    HapticService.actionMenuSelect();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.7;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        color: Colors.black.withAlpha(200),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '重排行序',
                  style: TextStyle(
                    color: Color(0xEEFFFFFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(null),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: Color(0x77FFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(_order),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      '完成',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '长按拖拽以调整行动线顺序',
              style: TextStyle(
                color: Color(0x66FFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w300,
                letterSpacing: 1,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                ),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, index, anim) =>
                      Material(color: Colors.transparent, child: child),
                  itemCount: _order.length,
                  onReorder: _onReorder,
                  itemBuilder: (ctx, i) {
                    final id = _order[i];
                    final name = widget.names[id] ?? '';
                    return ReorderableDragStartListener(
                      key: ValueKey(id),
                      index: i,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x10FFFFFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0x22FFFFFF),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.drag_handle,
                              color: Color(0x77FFFFFF),
                              size: 18,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  color: Color(0xEEFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 1,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 操作菜单 — 环 + 加深节点
// ═══════════════════════════════════════════════════

class _ActionMenuPainter extends CustomPainter {
  final Offset center;
  final double progress;
  _ActionMenuPainter({required this.center, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    // 环
    final ringRadius = 24.0 * (0.6 + 0.4 * eased);
    final ringPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.15 * eased)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, ringRadius, ringPaint);

    // 加深的主节点：8 → 14
    final r = 8.0 + 6.0 * eased;
    final node = Paint()..color = Color.fromRGBO(255, 255, 255, 0.95);
    canvas.drawCircle(center, r, node);
  }

  @override
  bool shouldRepaint(covariant _ActionMenuPainter old) =>
      old.center != center || old.progress != progress;
}

// ═══════════════════════════════════════════════════
// 时间轴 CustomPainter — 纯黑白灰
// ═══════════════════════════════════════════════════

class _TimelinePainter extends CustomPainter {
  final DateTime startDate;
  final DateTime today;
  final int totalDays;
  final int futureDays;
  final int todayIndex;
  final Set<String> aliveCheckIns;
  final List<TrailLine> customLines;
  final List<TrailLine> friendLines;
  final Set<String> friendLineIds;
  final int survivalDays;
  final double dayWidth;
  final double hScroll;
  final double vScroll;
  final double pullUp;
  final double rowSpacing;
  final double aliveY;
  final double viewportWidth;
  final double viewportHeight;
  final double glowValue;
  final double bounceValue;
  final String? bounceKey;
  final double bleFlashValue; // 0..1；BLE 验证成功的一次性亮度脉冲
  final String? bleFlashKey;
  final double shakeValue;
  final double arrowPulse;
  final double lineAddValue;
  final double lineDeleteValue;
  final double todayNodeFxValue;
  final String? todayNodeFxLineId;
  final int? todayNodeFxFromDayIndex;
  final bool todayNodeFxAppearing;
  final String? deletingLineId;
  final String? deleteModeLineId;
  final Map<int, int> gapData;
  final bool showHOnboarding;
  final bool showVOnboarding;
  final bool pullThresholdLatched;
  final double pullUpThreshold;

  // 新增
  final bool newFeaturesEnabled;
  final double satelliteAngle;

  // 新引导
  final bool showTapTodayOnboarding;
  final bool showRadialMenuOnboarding;
  final double centerLineProgress; // 0..1
  final double dayAxisReveal; // 0..1
  final bool hasFirstTrack;
  final bool isFirstDayTutorial;
  final DateTime birthday;

  _TimelinePainter({
    required this.startDate,
    required this.today,
    required this.totalDays,
    required this.futureDays,
    required this.todayIndex,
    required this.aliveCheckIns,
    required this.customLines,
    required this.friendLines,
    required this.friendLineIds,
    required this.survivalDays,
    required this.dayWidth,
    required this.hScroll,
    required this.vScroll,
    required this.pullUp,
    required this.rowSpacing,
    required this.aliveY,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.glowValue,
    required this.bounceValue,
    required this.bounceKey,
    required this.bleFlashValue,
    required this.bleFlashKey,
    required this.shakeValue,
    required this.arrowPulse,
    required this.lineAddValue,
    required this.lineDeleteValue,
    required this.todayNodeFxValue,
    required this.todayNodeFxLineId,
    required this.todayNodeFxFromDayIndex,
    required this.todayNodeFxAppearing,
    required this.deletingLineId,
    required this.deleteModeLineId,
    required this.gapData,
    required this.showHOnboarding,
    required this.showVOnboarding,
    required this.pullThresholdLatched,
    required this.pullUpThreshold,
    required this.newFeaturesEnabled,
    required this.satelliteAngle,
    required this.showTapTodayOnboarding,
    required this.showRadialMenuOnboarding,
    required this.centerLineProgress,
    required this.dayAxisReveal,
    required this.hasFirstTrack,
    required this.isFirstDayTutorial,
    required this.birthday,
  });

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _screenX(int dayIndex) =>
      viewportWidth / 2 + (dayIndex - todayIndex) * dayWidth - hScroll;

  double _customY(int k) => aliveY + (k + 1) * rowSpacing - vScroll;

  int _lineStartIndex(DateTime createdAt) {
    final created = DateUtils.dateOnly(createdAt);
    final diff = created.difference(DateUtils.dateOnly(startDate)).inDays;
    return diff.clamp(0, totalDays - 1 + futureDays);
  }

  int _firstCheckedDayIndex(Set<String> checkedDates, int fallbackStartDay) {
    final upper = min(todayIndex, totalDays - 1);
    for (int i = fallbackStartDay; i <= upper; i++) {
      final date = startDate.add(Duration(days: i));
      if (checkedDates.contains(_dateKey(date))) return i;
    }
    return fallbackStartDay;
  }

  int? _latestCheckedDayBeforeToday(Set<String> checkedDates) {
    final upper = min(todayIndex - 1, totalDays - 1);
    for (int i = upper; i >= 0; i--) {
      final date = startDate.add(Duration(days: i));
      if (checkedDates.contains(_dateKey(date))) return i;
    }
    return null;
  }

  int get _firstVisible {
    final x = ((hScroll - viewportWidth / 2) / dayWidth).floor() - 1;
    return todayIndex + x;
  }

  int get _lastVisible {
    final x = ((hScroll + viewportWidth / 2) / dayWidth).ceil() + 1;
    return todayIndex + x;
  }

  int get _centerVisibleDay {
    return todayIndex + (hScroll / dayWidth).round();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final firstDay = max(0, _firstVisible);
    final lastDay = min(totalDays - 1 + futureDays, _lastVisible);

    // ── 中心磁吸轴 ──
    // 今天：保留教学式出现动画
    // 非今天：只要下方已经有轴，直接完整连到底
    final hasAnyTrackedRow =
        customLines.isNotEmpty || friendLines.isNotEmpty || hasFirstTrack;
    if (newFeaturesEnabled && hasAnyTrackedRow) {
      _paintCenterAxis(canvas);
    }
    if (newFeaturesEnabled) {
      _paintSideDayAxes(canvas, firstDay, lastDay);
    }

    // ── 基准线：活着 ──
    _paintRow(
      canvas: canvas,
      y: aliveY,
      lineId: '__alive__',
      lineName: '活着',
      isAlive: true,
      checkedDates: aliveCheckIns,
      notes: const {},
      firstDay: firstDay,
      lastDay: lastDay,
      rowAlpha: 1.0,
    );

    // ── 旧版（关闭新功能）：保留今日节点上方的暂居文本 ──
    if (!newFeaturesEnabled) {
      final todayX = _screenX(todayIndex);
      if (todayX > -40 && todayX < viewportWidth + 40) {
        _drawText(
          canvas,
          '你已在这个星球上暂居 $survivalDays 天',
          Offset(todayX, aliveY - 44),
          const Color(0x99FFFFFF),
          12.0,
          FontWeight.w300,
          letterSpacing: 1.2,
        );
      }
    }

    // ── 自定义行动线 ──
    for (int k = 0; k < customLines.length; k++) {
      final line = customLines[k];
      final lineFirstDay = max(firstDay, _lineStartIndex(line.createdAt));
      final checkedDates = line.completedDates.toSet();
      final centerDate = startDate.add(
        Duration(days: _centerVisibleDay.clamp(0, totalDays - 1)),
      );
      final visibleName = line.displayNameOn(centerDate);
      final currentEffectiveKey = line.currentNameEffectiveFromKey();
      final centerKey = _dateKey(centerDate);
      final ghostCurrentName =
          currentEffectiveKey != null &&
              currentEffectiveKey.compareTo(centerKey) > 0 &&
              visibleName != line.name
          ? line.name
          : null;
      double alpha = 1.0;
      if (line.id == deletingLineId) alpha = lineDeleteValue;
      if (k == customLines.length - 1 && lineAddValue < 1.0) {
        alpha *= lineAddValue;
      }

      final baseY = _customY(k);
      final yOffset = (line.id == deletingLineId)
          ? (1 - lineDeleteValue) * 16.0
          : (k == customLines.length - 1 && lineAddValue < 1.0)
          ? (1 - lineAddValue) * -10.0
          : 0.0;

      _paintRow(
        canvas: canvas,
        y: baseY + yOffset,
        lineId: line.id,
        lineName: visibleName,
        isAlive: false,
        checkedDates: checkedDates,
        notes: line.notes,
        firstDay: lineFirstDay,
        lastDay: lastDay,
        rowAlpha: alpha,
        revealProgress: k == customLines.length - 1 ? lineAddValue : 1.0,
        revealFromDay: k == customLines.length - 1
            ? _firstCheckedDayIndex(
                checkedDates,
                _lineStartIndex(line.createdAt),
              )
            : null,
        revealToDay: k == customLines.length - 1 ? todayIndex : null,
        showLabel: _centerVisibleDay >= _lineStartIndex(line.createdAt),
        ghostLabel: ghostCurrentName,
      );
    }

    for (int j = 0; j < friendLines.length; j++) {
      final line = friendLines[j];
      final lineFirstDay = max(firstDay, _lineStartIndex(line.createdAt));
      _paintRow(
        canvas: canvas,
        y: _customY(customLines.length + j),
        lineId: line.id,
        lineName: line.name,
        isAlive: false,
        isFriendRow: true,
        checkedDates: line.completedDates.toSet(),
        notes: const {},
        firstDay: lineFirstDay,
        lastDay: lastDay,
        rowAlpha: 0.78,
        showLabel: _centerVisibleDay >= _lineStartIndex(line.createdAt),
      );
    }

    // ── 引导：横向箭头（旧版） ──
    if (showHOnboarding) {
      _paintHOnboarding(canvas);
    }
    // ── 引导：向上箭头（旧版） ──
    if (showVOnboarding) {
      _paintVOnboarding(canvas);
    }

    // ── 首日教学：出生日标记（左侧锚点，可通过左滑到达） ──
    if (isFirstDayTutorial) {
      _paintBirthMarker(canvas);
    }

    // ── 点击今日节点引导：节点外圈脉动环 + 轻触引导文字 ──
    if (showTapTodayOnboarding) {
      _paintTapTodayHint(canvas);
    }

    if (showRadialMenuOnboarding) {
      _paintRadialMenuHint(canvas);
    }
  }

  // ─────────────────────────────────────────────
  // 中心磁吸轴 —— 永远位于屏幕水平中线，贯穿 Header 底部到视口底部。
  // 取代原先的「今日专属虚线」。
  // ─────────────────────────────────────────────

  void _paintCenterAxis(Canvas canvas) {
    final x = viewportWidth / 2;
    final top = aliveY;
    final targetBottom = _bottomYForDay(_centerVisibleDay);
    if (targetBottom == null || targetBottom - top < 1) return;

    final axisProgress = _centerVisibleDay == todayIndex
        ? Curves.easeOutCubic.transform(centerLineProgress.clamp(0.0, 1.0))
        : 1.0;
    final reveal = Curves.easeOutCubic.transform(dayAxisReveal.clamp(0.0, 1.0));
    final bottom = top + (targetBottom - top) * (axisProgress * reveal);
    if (bottom - top < 1) return;
    _drawDashedLine(
      canvas,
      Offset(x, top),
      Offset(x, bottom),
      const Color(0x33FFFFFF),
      dashWidth: 4,
      gapWidth: 4,
      strokeWidth: 1.0,
    );
  }

  void _paintSideDayAxes(Canvas canvas, int firstDay, int lastDay) {
    for (int dayIndex = firstDay; dayIndex <= lastDay; dayIndex++) {
      if (dayIndex == _centerVisibleDay) continue;

      final bottomY = _bottomYForDay(dayIndex);
      if (bottomY == null || bottomY - aliveY < 1) continue;

      final x = _screenX(dayIndex);
      if (x < -dayWidth || x > viewportWidth + dayWidth) continue;
      final reveal = Curves.easeOutCubic.transform(
        dayAxisReveal.clamp(0.0, 1.0),
      );
      final animatedBottom = aliveY + (bottomY - aliveY) * reveal;
      if (animatedBottom - aliveY < 1) continue;

      _drawDashedLine(
        canvas,
        Offset(x, aliveY),
        Offset(x, animatedBottom),
        const Color(0x24FFFFFF),
        dashWidth: 4,
        gapWidth: 4,
        strokeWidth: 0.9,
      );
    }
  }

  double? _bottomYForDay(int dayIndex) {
    if (dayIndex < 0 || dayIndex > totalDays - 1 + futureDays) return null;

    final date = startDate.add(Duration(days: dayIndex));
    final key = _dateKey(date);
    double? bottomY;

    if (aliveCheckIns.contains(key)) {
      bottomY = aliveY;
    }

    for (int i = 0; i < customLines.length; i++) {
      if (customLines[i].completedDates.contains(key)) {
        bottomY = _customY(i);
      }
    }

    for (int j = 0; j < friendLines.length; j++) {
      if (friendLines[j].completedDates.contains(key)) {
        bottomY = _customY(customLines.length + j);
      }
    }

    return bottomY;
  }

  // ─────────────────────────────────────────────
  // 行渲染
  // ─────────────────────────────────────────────

  void _paintRow({
    required Canvas canvas,
    required double y,
    required String lineId,
    required String lineName,
    required bool isAlive,
    required Set<String> checkedDates,
    required Map<String, String> notes,
    required int firstDay,
    required int lastDay,
    required double rowAlpha,
    double revealProgress = 1.0,
    int? revealFromDay,
    int? revealToDay,
    bool showLabel = true,
    String? ghostLabel,
    bool isFriendRow = false,
  }) {
    if (y < -40 || y > viewportHeight + 40) return;

    final clippedReveal = revealProgress.clamp(0.0, 1.0);
    final revealT = Curves.easeOutCubic.transform(clippedReveal);
    final todayKey = _dateKey(startDate.add(Duration(days: todayIndex)));
    final todayChecked = checkedDates.contains(todayKey);
    final isActiveTodayFx = todayNodeFxLineId == lineId;
    final todayBridgeFrom = todayChecked
        ? _latestCheckedDayBeforeToday(checkedDates)
        : (!todayNodeFxAppearing && isActiveTodayFx
              ? todayNodeFxFromDayIndex
              : null);
    if (!isAlive &&
        clippedReveal < 1.0 &&
        revealFromDay != null &&
        revealToDay != null) {
      final startX = _screenX(revealFromDay);
      final targetX = _screenX(revealToDay);
      final progressX = ui.lerpDouble(startX, targetX, revealT)!;
      final progressPaint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, 0.42 * rowAlpha)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(startX, y), Offset(progressX, y), progressPaint);

      if (!checkedDates.contains(todayKey) && revealToDay == todayIndex) {
        _drawHollowNode(
          canvas,
          targetX,
          y,
          (0.22 + 0.12 * revealT) * rowAlpha,
          scale: 1.04,
        );
      }

      final headPaint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, 0.45 * rowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawCircle(Offset(progressX, y), 4.5, headPaint);
    }
    if (clippedReveal < 1.0) {
      final revealStartX = revealFromDay != null
          ? _screenX(revealFromDay) - dayWidth * 0.5
          : -dayWidth;
      final revealEndX = revealToDay != null
          ? _screenX(revealToDay) + dayWidth * 0.5
          : viewportWidth + dayWidth;
      final revealRight = ui.lerpDouble(revealStartX, revealEndX, revealT)!;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          revealStartX,
          -viewportHeight,
          revealRight,
          viewportHeight * 2,
        ),
      );
    }

    // ── 行级渐隐 ──
    const fadeZone = 36.0; // 视口边缘渐隐区域高度
    double edgeAlpha = 1.0;
    if (y < fadeZone) {
      edgeAlpha = (y / fadeZone).clamp(0.0, 1.0);
    }
    if (y > viewportHeight - fadeZone) {
      edgeAlpha = ((viewportHeight - y) / fadeZone).clamp(0.0, 1.0);
    }
    // ── 自定义行防穿模：靠近上方基准行时渐隐 ──
    // 基准行（活着）节点在上方，下方自定义行上滑接近时，
    // 自定义行的节点/标题应渐隐，避免与基准行节点+文字重叠
    double overlapAlpha = 1.0;
    if (!isAlive) {
      // 从低于日期轴约半档的位置开始渐隐，越贴近日期轴透明度越低。
      final anchorY = aliveY;
      final fadeStart = anchorY + rowSpacing * 0.55;
      final fadeEnd = anchorY + 10.0;
      if (y <= fadeStart) {
        final t = ((y - fadeEnd) / (fadeStart - fadeEnd)).clamp(0.0, 1.0);
        overlapAlpha = Curves.easeOut.transform(t);
      }
    }
    final effRowAlpha = rowAlpha * edgeAlpha * overlapAlpha;

    double shakeDx = 0;
    if (deleteModeLineId == lineId && shakeValue > 0) {
      shakeDx = sin(shakeValue * pi * 4) * 2.4;
    }

    final int maxIdx = totalDays - 1 + futureDays;
    final int endDay = min(lastDay, maxIdx);

    // ── 连线 ──
    for (int i = firstDay; i <= endDay; i++) {
      if (i >= maxIdx) continue;
      final x1 = _screenX(i);
      final x2 = _screenX(i + 1);
      if (x2 < -dayWidth || x1 > viewportWidth + dayWidth) continue;

      final date1 = startDate.add(Duration(days: i));
      final date2 = startDate.add(Duration(days: i + 1));
      final c1 = checkedDates.contains(_dateKey(date1));
      final c2 = checkedDates.contains(_dateKey(date2));
      final isFocusSegment =
          i == _centerVisibleDay || i + 1 == _centerVisibleDay;
      final segmentAlpha = (effRowAlpha * (isFocusSegment ? 1.28 : 1.0)).clamp(
        0.0,
        1.0,
      );

      final bothChecked = c1 && c2;
      final isTodayBridgeSegment =
          i + 1 == todayIndex &&
          todayChecked &&
          todayBridgeFrom == i &&
          isActiveTodayFx &&
          todayNodeFxAppearing;
      if (bothChecked) {
        if (isTodayBridgeSegment) {
          continue;
        }
        final paint = Paint()
          ..color = Colors.white.withAlpha((255 * segmentAlpha).round())
          ..strokeWidth = isFocusSegment ? 1.35 : 1.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(x1 + shakeDx, y),
          Offset(x2 + shakeDx, y),
          paint,
        );
      } else {
        _drawDashedLine(
          canvas,
          Offset(x1 + shakeDx, y),
          Offset(x2 + shakeDx, y),
          Color.fromRGBO(
            255,
            255,
            255,
            (0.18 * segmentAlpha * (isFocusSegment ? 1.2 : 1.0)).clamp(
              0.0,
              1.0,
            ),
          ),
          dashWidth: 3,
          gapWidth: 3,
          strokeWidth: isFocusSegment ? 1.0 : 0.8,
        );
      }
    }

    if (todayBridgeFrom != null) {
      final startX = _screenX(todayBridgeFrom) + shakeDx;
      final endX = _screenX(todayIndex) + shakeDx;
      final isGapBridge = todayIndex - todayBridgeFrom > 1;
      final isFocusBridge =
          todayBridgeFrom == _centerVisibleDay ||
          todayIndex == _centerVisibleDay;
      final bridgeAlpha = (effRowAlpha * (isFocusBridge ? 1.28 : 1.0)).clamp(
        0.0,
        1.0,
      );
      final bridgeProgress = isActiveTodayFx
          ? (todayNodeFxAppearing
                ? Curves.easeOutCubic.transform(
                    todayNodeFxValue.clamp(0.0, 1.0),
                  )
                : 1.0 -
                      Curves.easeOutCubic.transform(
                        todayNodeFxValue.clamp(0.0, 1.0),
                      ))
          : (todayChecked ? 1.0 : 0.0);
      if (bridgeProgress > 0.0) {
        final bridgePaint = Paint()
          ..color = Colors.white.withAlpha((255 * bridgeAlpha).round())
          ..strokeWidth = isFocusBridge ? 1.35 : 1.0
          ..strokeCap = StrokeCap.round;
        final bridgeX = ui.lerpDouble(startX, endX, bridgeProgress)!;
        if (isGapBridge) {
          _drawDashedLine(
            canvas,
            Offset(startX, y),
            Offset(bridgeX, y),
            Color.fromRGBO(255, 255, 255, bridgeAlpha),
            dashWidth: 3,
            gapWidth: 3,
            strokeWidth: isFocusBridge ? 1.15 : 1.0,
          );
        } else {
          canvas.drawLine(Offset(startX, y), Offset(bridgeX, y), bridgePaint);
        }
      }
    }

    // ── 节点 ──
    for (int i = firstDay; i <= endDay; i++) {
      final x = _screenX(i) + shakeDx;
      if (x < -dayWidth * 2 || x > viewportWidth + dayWidth * 2) continue;

      final isTodayCol = (i == todayIndex);
      final isFuture = i > todayIndex;
      final date = startDate.add(Duration(days: i));
      final dKey = _dateKey(date);
      final checked = checkedDates.contains(dKey);
      final isFocusCol = i == _centerVisibleDay;
      final isTodayNodeFxActive = todayNodeFxLineId == lineId && isTodayCol;
      final suppressStaticTodayNode = isTodayNodeFxActive;

      final futureFade = isFuture ? 0.35 : 1.0;
      double effAlpha = (effRowAlpha * futureFade * (isFocusCol ? 1.25 : 1.0))
          .clamp(0.0, 1.0);

      double bounceScale = isFocusCol ? 1.05 : 1.0;
      if (bounceKey == lineId && isTodayCol && bounceValue > 0) {
        final t = bounceValue;
        if (t < 0.4) {
          bounceScale *= 1.0 + t / 0.4 * 0.25;
        } else {
          bounceScale *= 1.25 - (t - 0.4) / 0.6 * 0.25;
        }
      }
      final todayNodeScale = isTodayNodeFxActive
          ? (isFocusCol ? 1.05 : 1.0)
          : bounceScale;

      // BLE 验证成功的一次性亮度脉冲（仅朋友行今日节点）。
      // 轨迹：alpha *= 1 + 0.7 * sin(π * t)，t∈(0,1)。t=0/1 时为 1x，t=0.5 时峰值 1.7x。
      // 由 clamp(0, 1) 兜底，不会越界。350ms 后自止。
      if (bleFlashKey == lineId &&
          isTodayCol &&
          bleFlashValue > 0 &&
          bleFlashValue < 1) {
        final pulse = sin(bleFlashValue * pi);
        effAlpha = (effAlpha * (1.0 + 0.7 * pulse)).clamp(0.0, 1.0);
      }

      final hasRevealFinishAccent =
          !isAlive &&
          revealToDay == todayIndex &&
          isTodayCol &&
          clippedReveal < 1.0 &&
          clippedReveal > 0.72;
      if (hasRevealFinishAccent) {
        final t = ((clippedReveal - 0.72) / 0.28).clamp(0.0, 1.0);
        final accent = sin(Curves.easeOutCubic.transform(t) * pi);
        effAlpha = (effAlpha + 0.18 * accent).clamp(0.0, 1.0);
        bounceScale *= 1.0 + 0.10 * accent;

        final glowPaint = Paint()
          ..color = Color.fromRGBO(255, 255, 255, 0.12 * accent * effAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7.0 + 4.0 * accent);
        canvas.drawCircle(Offset(x, y), 11.0 + 2.0 * accent, glowPaint);
      }

      if (suppressStaticTodayNode) {
        // today FX 期间保留终点位的大节点占位，避免“小点滑过去，末端再突然变大”。
        _drawTodayHollow(canvas, x, y, todayNodeScale, effAlpha);
      } else if (isTodayCol && isAlive) {
        if (checked) {
          _drawTodayAliveSolid(canvas, x, y, todayNodeScale, effAlpha);
        } else {
          _drawTodayHollow(canvas, x, y, todayNodeScale, effAlpha);
        }
      } else if (isTodayCol && !isAlive) {
        if (checked) {
          _drawTodayCustomSolid(canvas, x, y, todayNodeScale, effAlpha);
        } else {
          _drawTodayHollow(canvas, x, y, todayNodeScale, effAlpha);
        }
      } else if (checked) {
        _drawSolidNode(canvas, x, y, effAlpha);
      } else if (isFriendRow) {
        _drawDashedHollowNode(canvas, x, y, effAlpha);
      } else {
        _drawHollowNode(canvas, x, y, effAlpha);
      }

      // BLE 验证成功的一次性扩散环（仅朋友行今日节点）。
      // 语义：A 能画出这个环 = A 真的从 BLE 读到了 B。路径 A（tapper 侧视觉），
      // 两台手机"同时亮"不在 scope 内。
      // 轨迹：半径 4 → 36（easeOutCubic），alpha 0.55 → 0，350ms 内自止。
      if (bleFlashKey == lineId &&
          isTodayCol &&
          isFriendRow &&
          bleFlashValue > 0 &&
          bleFlashValue < 1) {
        final t = bleFlashValue;
        final easeOut = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
        final r = 4.0 + easeOut * 32.0;
        final ringAlpha = ((1.0 - t) * 0.55 * effAlpha).clamp(0.0, 1.0);
        final ringPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Color.fromRGBO(255, 255, 255, ringAlpha);
        canvas.drawCircle(Offset(x, y), r, ringPaint);
      }

      // 卫星点 — 仅新功能 + 节点有备注
      if (newFeaturesEnabled && notes.containsKey(dKey)) {
        _drawSatellite(canvas, x, y, effAlpha, isTodayCol);
      }

      // 间隔文字 — 从 v3 起：在所有时间轴上显示（不只是「活着」基准线），
      // 并且放到节点+日期标签的下方（而不是夹在中间），让读序与视觉分组一致：
      //   节点 → 日期标签（仅基准线） → 间隔文字
      // `gapMap` 是传入的基准线 gap 表；非基准线由 `_computeRowGapMap` 按当前行
      // checkedDates 现场计算。
      final Map<int, int> rowGap = isAlive
          ? gapData
          : _computeRowGapMap(checkedDates, totalDays, startDate);
      if (rowGap.containsKey(i)) {
        // 基准线：位于日期标签（y+24）下方 → y+44
        // 非基准线：行名标签在 y+22、ghost 标签在 y+38，需要避开这两者；
        // 放到 ghost 标签（约 y+43 底）之下 → y+54，保持与下一行节点（默认 y+64）
        // 也有呼吸空间。
        final gapY = isAlive ? (y + 44) : (y + 54);
        _drawText(
          canvas,
          '间隔 ${rowGap[i]} 天',
          Offset(x, gapY),
          Color.fromRGBO(255, 255, 255, 0.35 * effAlpha),
          10.0,
          FontWeight.w300,
        );
      }

      // 日期标签（仅基准行）
      // 今天 / 昨天 / 前天 → 高亮；更早 → M月D日；每月 1 日额外显示 YYYY.MM
      if (isAlive) {
        // 日期标签始终固定在 y+24（紧贴节点下方）；gap 文字移到 y+44（标签下方）
        final labelY = y + 24;
        final delta = todayIndex - i;
        String? primary;
        double primaryAlpha = 0.55;
        double primaryFontSize = 10.0;
        FontWeight primaryWeight = FontWeight.w400;
        if (delta == 0) {
          primary = '今天';
        } else if (delta == 1) {
          primary = '昨天';
          primaryAlpha = 0.45;
        } else if (delta == 2) {
          primary = '前天';
          primaryAlpha = 0.40;
        } else if (delta > 2) {
          primary = '${date.month}月${date.day}日';
          primaryAlpha = 0.30;
          primaryFontSize = 9.5;
          primaryWeight = FontWeight.w300;
        }
        if (primary != null) {
          _drawText(
            canvas,
            primary,
            Offset(x, labelY),
            Color.fromRGBO(255, 255, 255, primaryAlpha * effAlpha),
            primaryFontSize,
            primaryWeight,
          );
        }
        // 每月 1 日附加年月标记（叠加在主标签下方，仅非今昨前天时）
        if (date.day == 1 && delta > 2) {
          _drawText(
            canvas,
            '${date.year}.${date.month}',
            Offset(x, labelY + 12),
            Color.fromRGBO(255, 255, 255, 0.20 * effAlpha),
            8.5,
            FontWeight.w300,
          );
        }
      }

      if (isTodayNodeFxActive) {
        _paintTodayNodeToggleFx(
          canvas: canvas,
          x: x,
          y: y,
          rowAlpha: effAlpha,
          isAlive: isAlive,
          scale: todayNodeScale,
          fromDayIndex: todayNodeFxFromDayIndex,
        );
      }
    }

    // ── 行名标签 ──
    if (!isAlive && showLabel) {
      if (newFeaturesEnabled) {
        // 新版：永远钉在中心磁吸轴正下方，横向滚动时不移动。
        _drawText(
          canvas,
          lineName,
          Offset(viewportWidth / 2, y + 22),
          Color.fromRGBO(255, 255, 255, 0.55 * effRowAlpha),
          11.0,
          FontWeight.w400,
          letterSpacing: 1.2,
        );
        if (ghostLabel != null) {
          _drawText(
            canvas,
            ghostLabel,
            Offset(viewportWidth / 2, y + 38),
            Color.fromRGBO(255, 255, 255, 0.12 * effRowAlpha),
            10.0,
            FontWeight.w300,
            letterSpacing: 1.0,
          );
        }
      } else if (customLines.isNotEmpty) {
        // 旧版：屏幕中央上方
        _drawText(
          canvas,
          lineName,
          Offset(viewportWidth / 2, y - 16),
          Color.fromRGBO(255, 255, 255, 0.45 * effRowAlpha),
          10.0,
          FontWeight.w300,
          letterSpacing: 1.2,
        );
      }
    }

    if (clippedReveal < 1.0) {
      canvas.restore();
    }
  }

  void _paintTodayNodeToggleFx({
    required Canvas canvas,
    required double x,
    required double y,
    required double rowAlpha,
    required bool isAlive,
    required double scale,
    required int? fromDayIndex,
  }) {
    final v = todayNodeFxValue.clamp(0.0, 1.0);
    // 按 spec「今天增量语法」：appearing = easeOutCubic，取消 = easeInCubic，
    // 使 progress = 1 - easeInCubic(v) 与 appearing 的几何完全时间对称（慢离→快归）。
    final eased = todayNodeFxAppearing
        ? Curves.easeOutCubic.transform(v)
        : Curves.easeInCubic.transform(v);
    final progress = todayNodeFxAppearing ? eased : (1.0 - eased);
    if (progress <= 0.0) return;

    final fromDay = todayNodeFxFromDayIndex;
    final startX = fromDay == null ? x : _screenX(fromDay);
    final headX = ui.lerpDouble(startX, x, progress)!;
    final linePaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, (0.92 * rowAlpha).clamp(0.0, 1.0))
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final isGapBridge = fromDayIndex != null && todayIndex - fromDayIndex > 1;
    if (isGapBridge) {
      _drawDashedLine(
        canvas,
        Offset(startX, y),
        Offset(headX, y),
        Color.fromRGBO(255, 255, 255, (0.48 * rowAlpha).clamp(0.0, 1.0)),
        dashWidth: 2.5,
        gapWidth: 3.5,
        strokeWidth: 0.8,
      );
    } else {
      canvas.drawLine(Offset(startX, y), Offset(headX, y), linePaint);
    }

    final sourceRadius = 3.6;
    final targetRadius = (isAlive ? 6.0 : 5.0) * scale;
    final currentRadius = ui.lerpDouble(sourceRadius, targetRadius, progress)!;
    final glowRadius = currentRadius + (isAlive ? 2.0 : 1.8);
    final glowAlpha = ((isAlive ? 0.08 : 0.05) * rowAlpha).clamp(0.0, 1.0);
    final glowPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, glowAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);
    canvas.drawCircle(Offset(headX, y), currentRadius + 1.2, glowPaint);

    final headPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, rowAlpha.clamp(0.0, 1.0));
    canvas.drawCircle(Offset(headX, y), currentRadius, headPaint);
  }

  // ─────────────────────────────────────────────
  // 节点绘制
  // ─────────────────────────────────────────────

  void _drawTodayAliveSolid(
    Canvas canvas,
    double x,
    double y,
    double scale,
    double alpha,
  ) {
    final glowRadius = 8.0 + glowValue * 4.0;
    final glowAlpha = ((0.10 + glowValue * 0.14) * alpha).clamp(0.0, 1.0);
    final glowPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, glowAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);
    canvas.drawCircle(Offset(x, y), 8.0 * scale, glowPaint);
    final node = Paint()..color = Color.fromRGBO(255, 255, 255, alpha);
    canvas.drawCircle(Offset(x, y), 6.0 * scale, node);
  }

  void _drawTodayCustomSolid(
    Canvas canvas,
    double x,
    double y,
    double scale,
    double alpha,
  ) {
    final glowRadius = 6.0 + glowValue * 3.0;
    final glowAlpha = ((0.06 + glowValue * 0.08) * alpha).clamp(0.0, 1.0);
    final glowPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, glowAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);
    canvas.drawCircle(Offset(x, y), 7.0 * scale, glowPaint);
    final node = Paint()..color = Color.fromRGBO(255, 255, 255, alpha);
    canvas.drawCircle(Offset(x, y), 5.0 * scale, node);
  }

  void _drawTodayHollow(
    Canvas canvas,
    double x,
    double y,
    double scale,
    double alpha,
  ) {
    final paint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.55 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(x, y), 5.6 * scale, paint);
  }

  void _drawSolidNode(Canvas canvas, double x, double y, double alpha) {
    final paint = Paint()..color = Color.fromRGBO(255, 255, 255, alpha);
    canvas.drawCircle(Offset(x, y), 3.6, paint);
  }

  void _drawHollowNode(
    Canvas canvas,
    double x,
    double y,
    double alpha, {
    double scale = 1.0,
  }) {
    final paint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.28 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(Offset(x, y), 3.6 * scale, paint);
  }

  /// 朋友节点未打卡态：虚线空心圆，区别于普通 hollow。
  /// 达到"需要对方在场才能落地"的视觉暗示。
  void _drawDashedHollowNode(
    Canvas canvas,
    double x,
    double y,
    double alpha, {
    double scale = 1.0,
  }) {
    final r = 3.6 * scale;
    final paint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.32 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.butt;
    // 10 段圆周 → 5 段可见、5 段空（棋盘式虚线环）
    const int segments = 10;
    for (int i = 0; i < segments; i++) {
      if (i.isOdd) continue;
      final startAngle = (i / segments) * 2 * pi;
      final sweep = (1 / segments) * 2 * pi;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(x, y), radius: r),
        startAngle,
        sweep,
        false,
        paint,
      );
    }
  }

  // 卫星点 + 环
  void _drawSatellite(
    Canvas canvas,
    double x,
    double y,
    double alpha,
    bool isToday,
  ) {
    const ringRadius = 11.0;
    final ringPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.10 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas.drawCircle(Offset(x, y), ringRadius, ringPaint);

    final sx = x + cos(satelliteAngle) * ringRadius;
    final sy = y + sin(satelliteAngle) * ringRadius;
    final dotPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.85 * alpha);
    canvas.drawCircle(Offset(sx, sy), 2.0, dotPaint);
  }

  /// 给任意一行（非基准线）现场计算 gap 表。
  /// 输出格式与 `_computeGapData()` 一致：`Map<int resumeDayIdx, int gapDays>`。
  /// 基准线沿用 State 侧预计算的 [gapData] 避免重复工作。
  Map<int, int> _computeRowGapMap(
    Set<String> checkedDates,
    int totalDays,
    DateTime startDate,
  ) {
    if (checkedDates.isEmpty) return const {};
    final map = <int, int>{};
    int? lastIdx;
    for (int i = 0; i < totalDays; i++) {
      final date = startDate.add(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      if (checkedDates.contains(key)) {
        if (lastIdx != null) {
          final gap = i - lastIdx - 1;
          if (gap > 0) map[i] = gap;
        }
        lastIdx = i;
      }
    }
    return map;
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color, {
    double dashWidth = 4,
    double gapWidth = 3,
    double strokeWidth = 1.0,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final total = (to - from).distance;
    if (total <= 0) return;
    final dir = (to - from) / total;
    double cur = 0;
    while (cur < total) {
      final next = min(cur + dashWidth, total);
      final p1 = from + dir * cur;
      final p2 = from + dir * next;
      canvas.drawLine(p1, p2, paint);
      cur = next + gapWidth;
    }
  }

  // ─────────────────────────────────────────────
  // 引导绘制
  // ─────────────────────────────────────────────

  void _paintHOnboarding(Canvas canvas) {
    final x = _screenX(todayIndex);
    final y = aliveY;
    final pulse = (sin(arrowPulse * pi * 2) + 1) / 2;
    final drift = 4.0 + pulse * 3.0;
    final arrowColor = Color.fromRGBO(255, 255, 255, 0.18 + pulse * 0.22);

    _drawChevron(
      canvas,
      Offset(x - 28 - drift, y),
      size: 5.0,
      color: arrowColor,
      pointLeft: true,
    );
    _drawChevron(
      canvas,
      Offset(x + 28 + drift, y),
      size: 5.0,
      color: arrowColor,
      pointLeft: false,
    );

    _drawText(
      canvas,
      '左右滑动，查看你的人生轨迹',
      Offset(x, y + 58),
      const Color(0x66FFFFFF),
      11.0,
      FontWeight.w300,
      letterSpacing: 1.4,
    );
  }

  void _paintVOnboarding(Canvas canvas) {
    final x = _screenX(todayIndex);
    final y = aliveY;
    final pulse = (sin(arrowPulse * pi * 2) + 1) / 2;
    final drift = 6.0 + pulse * 4.0;
    final arrowColor = Color.fromRGBO(255, 255, 255, 0.18 + pulse * 0.22);

    _drawChevronUp(
      canvas,
      Offset(x, y + 86 + drift),
      size: 5.0,
      color: arrowColor,
    );
    _drawText(
      canvas,
      '向上滑动，添加专属迹点',
      Offset(x, y + 110),
      const Color(0x66FFFFFF),
      11.0,
      FontWeight.w300,
      letterSpacing: 1.4,
    );
  }

  // ─────────────────────────────────────────────
  // 首日「出生日」标记 —— 作为左滑目标锚点
  // ─────────────────────────────────────────────

  void _paintBirthMarker(Canvas canvas) {
    // 出生日在虚拟 dayIndex = -survivalDays 的位置。
    final birthDayIndex = -survivalDays;
    final x = _screenX(birthDayIndex);
    if (x < -40 || x > viewportWidth + 40) return;
    final y = aliveY;

    // 空心节点 + 外圈呼吸
    final pulse = (sin(arrowPulse * pi * 2) + 1) / 2;
    final ringPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.12 + pulse * 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(Offset(x, y), 12.0 + pulse * 2.0, ringPaint);

    final hollow = Paint()
      ..color = const Color(0x88FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(x, y), 5.0, hollow);
  }

  // ─────────────────────────────────────────────
  // 点击「今日」节点的引导 —— 外圈涟漪 + 指示文本
  // ─────────────────────────────────────────────

  void _paintTapTodayHint(Canvas canvas) {
    final x = _screenX(todayIndex);
    // 仅当今日节点仍在视野内时才绘制引导
    if (x < -40 || x > viewportWidth + 40) return;
    final y = aliveY;
    final t = arrowPulse; // 0..1..0 (反复)
    final phase = (sin(t * pi * 2) + 1) / 2; // 0..1
    // 多层涟漪：2 圈以错位相位
    for (int i = 0; i < 2; i++) {
      final p = ((phase + i * 0.5) % 1.0);
      final r = 12.0 + p * 20.0;
      final a = (1.0 - p) * 0.22;
      final paint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
    _drawText(
      canvas,
      '轻点今日，开启你的第一条迹点',
      Offset(x, y + 58),
      const Color(0x88FFFFFF),
      11.0,
      FontWeight.w300,
      letterSpacing: 1.4,
    );
  }

  void _paintRadialMenuHint(Canvas canvas) {
    final x = viewportWidth / 2;
    final y = (viewportHeight * 0.68).clamp(aliveY + 72, viewportHeight - 96);
    final phase = (sin(arrowPulse * pi * 2) + 1) / 2;

    for (int i = 0; i < 2; i++) {
      final p = ((phase + i * 0.45) % 1.0);
      final r = 18.0 + p * 24.0;
      final a = (1.0 - p) * 0.16;
      final paint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      canvas.drawCircle(Offset(x, y), r, paint);
    }

    final centerPaint = Paint()
      ..color = Color.fromRGBO(255, 255, 255, 0.14 + phase * 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 10.0, centerPaint);

    _drawText(
      canvas,
      '长按空白处，新增新的轴或进入设置',
      Offset(x, y + 54),
      const Color(0x88FFFFFF),
      11.0,
      FontWeight.w300,
      letterSpacing: 1.2,
    );
  }

  // 旧版上拉「+」按钮已被底部手势区取代 —— 不再绘制。

  void _drawChevron(
    Canvas canvas,
    Offset c, {
    required double size,
    required Color color,
    required bool pointLeft,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final s = size;
    if (pointLeft) {
      canvas.drawLine(
        Offset(c.dx + s, c.dy - s),
        Offset(c.dx - s, c.dy),
        paint,
      );
      canvas.drawLine(
        Offset(c.dx - s, c.dy),
        Offset(c.dx + s, c.dy + s),
        paint,
      );
    } else {
      canvas.drawLine(
        Offset(c.dx - s, c.dy - s),
        Offset(c.dx + s, c.dy),
        paint,
      );
      canvas.drawLine(
        Offset(c.dx + s, c.dy),
        Offset(c.dx - s, c.dy + s),
        paint,
      );
    }
  }

  void _drawChevronUp(
    Canvas canvas,
    Offset c, {
    required double size,
    required Color color,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final s = size;
    canvas.drawLine(Offset(c.dx - s, c.dy + s), Offset(c.dx, c.dy - s), paint);
    canvas.drawLine(Offset(c.dx, c.dy - s), Offset(c.dx + s, c.dy + s), paint);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double fontSize,
    FontWeight fontWeight, {
    double letterSpacing = 0.5,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) {
    // 以前是 `=> true`，每次 AnimatedBuilder 重建都会触发完整 repaint。
    // 这里改成逐字段比较 —— Listenable.merge 的 11 个动画值里只要有一个
    // 仍然在变（例如 glow/bounce/shake 的持续脉冲），`true` 仍然会返回；
    // 否则（例如手势静止、动画 dismissed）可以直接 skip repaint。
    //
    // 字段顺序和构造函数保持一致，方便以后新增字段时一并在这里更新。
    return old.startDate != startDate ||
        old.today != today ||
        old.totalDays != totalDays ||
        old.futureDays != futureDays ||
        old.todayIndex != todayIndex ||
        !identical(old.aliveCheckIns, aliveCheckIns) ||
        !identical(old.customLines, customLines) ||
        !identical(old.friendLines, friendLines) ||
        !identical(old.friendLineIds, friendLineIds) ||
        old.survivalDays != survivalDays ||
        old.dayWidth != dayWidth ||
        old.hScroll != hScroll ||
        old.vScroll != vScroll ||
        old.pullUp != pullUp ||
        old.rowSpacing != rowSpacing ||
        old.aliveY != aliveY ||
        old.viewportWidth != viewportWidth ||
        old.viewportHeight != viewportHeight ||
        old.glowValue != glowValue ||
        old.bounceValue != bounceValue ||
        old.bleFlashValue != bleFlashValue ||
        old.bleFlashKey != bleFlashKey ||
        old.bounceKey != bounceKey ||
        old.shakeValue != shakeValue ||
        old.arrowPulse != arrowPulse ||
        old.lineAddValue != lineAddValue ||
        old.lineDeleteValue != lineDeleteValue ||
        old.todayNodeFxValue != todayNodeFxValue ||
        old.todayNodeFxLineId != todayNodeFxLineId ||
        old.todayNodeFxFromDayIndex != todayNodeFxFromDayIndex ||
        old.todayNodeFxAppearing != todayNodeFxAppearing ||
        old.deletingLineId != deletingLineId ||
        old.deleteModeLineId != deleteModeLineId ||
        !identical(old.gapData, gapData) ||
        old.showHOnboarding != showHOnboarding ||
        old.showVOnboarding != showVOnboarding ||
        old.pullThresholdLatched != pullThresholdLatched ||
        old.pullUpThreshold != pullUpThreshold ||
        old.newFeaturesEnabled != newFeaturesEnabled ||
        old.satelliteAngle != satelliteAngle ||
        old.showTapTodayOnboarding != showTapTodayOnboarding ||
        old.showRadialMenuOnboarding != showRadialMenuOnboarding ||
        old.centerLineProgress != centerLineProgress ||
        old.dayAxisReveal != dayAxisReveal ||
        old.hasFirstTrack != hasFirstTrack ||
        old.isFirstDayTutorial != isFirstDayTutorial ||
        old.birthday != birthday;
  }
}
