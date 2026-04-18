import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/date_guard.dart';
import '../core/secure_box_service.dart';
import '../core/time_integrity_service.dart';
import '../models/birthday.dart';
import '../models/friend.dart';
import '../models/trail_line.dart';

/// 本地 Hive 盒子打开失败。
///
/// 关键契约：抛出此异常时，**物理数据文件从未被删除**。
/// 上层（main.dart / 恢复页）可以让用户选择重试、恢复备份或联系支持，
/// 但绝对不能把它当成“空档”继续往下走——那会在下次写入时覆盖用户数据。
class HiveOpenFailure implements Exception {
  final String boxName;
  final Object cause;
  final StackTrace? causeStack;
  const HiveOpenFailure(this.boxName, this.cause, [this.causeStack]);

  @override
  String toString() => 'HiveOpenFailure(box="$boxName", cause=$cause)';
}

/// Header 布局模式
enum HeaderLayoutMode {
  centeredLayered, // 层叠居中（新默认）
  sideMinimal, // 极简侧边
  original, // 原始（上抛在今日节点上方）
}

extension HeaderLayoutModeX on HeaderLayoutMode {
  int get storageValue {
    switch (this) {
      case HeaderLayoutMode.centeredLayered:
        return 0;
      case HeaderLayoutMode.sideMinimal:
        return 1;
      case HeaderLayoutMode.original:
        return 2;
    }
  }

  static HeaderLayoutMode fromStorage(int? v) {
    switch (v) {
      case 1:
        return HeaderLayoutMode.sideMinimal;
      case 2:
        return HeaderLayoutMode.original;
      case 0:
      default:
        return HeaderLayoutMode.centeredLayered;
    }
  }
}

/// 本地存储服务 — Hive 纯本地，零网络
class StorageService {
  static StorageService? _instance;
  static StorageService get instance => _instance!;

  late Box<Birthday> _birthdayBox;
  late Box<TrailLine> _customLinesBox;
  late Box _dataBox;

  static const String _checkInKey = 'checkin_dates'; // 「活着」基准线打卡集合
  static const String _startDateKey = 'start_date';
  static const String _onboardHSwipeKey = 'onboard_h_done'; // 横向滑动引导
  static const String _onboardVSwipeKey = 'onboard_v_done'; // 纵向滑动引导
  static const String _onboardTapTodayKey =
      'onboard_tap_today_done'; // 点击今日节点引导
  static const String _onboardRadialMenuKey =
      'onboard_radial_menu_done'; // 长按空白区域引导
  static const String _firstTrackAddedKey = 'first_track_added'; // 已添加过第一条行动线

  // ── 偏好 (v2 UI 升级) ─────────────────────────
  static const String _prefHeaderLayoutKey = 'pref_header_layout';
  static const String _prefNewFeaturesKey = 'pref_new_features_enabled';
  static const String _prefNodeSpacingKey = 'pref_node_spacing';
  static const String _prefSatelliteRotationKey = 'pref_satellite_rotation';
  static const String _prefLineOrderKey = 'pref_line_order'; // 自定义行动线的手动排序

  // 默认值
  static const double defaultNodeSpacing = 64.0;
  static const double minNodeSpacing = 48.0;
  static const double maxNodeSpacing = 80.0;

  StorageService._();

  static Future<void> init() async {
    // `Hive.initFlutter()` 已在 CoreBootstrap.initialize() 中调用（必须在
    // SecureBoxService 之前）。此处不再重复调用，避免 iOS 26 上偶发的启动
    // 阻塞，也让“Hive 初始化”只保留一个真理点。
    assert(
      Hive.isAdapterRegistered(10),
      'CoreBootstrap must run before StorageService.init()',
    );

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(BirthdayAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TrailLineAdapter());
    }

    final service = StorageService._();
    final cipher = SecureBoxService.instance.cipher;

    // ── 明文 → 加密 自动迁移 ──────────────────────
    // 旧版本的 Hive 盒子是明文写的。加密打开明文盒子会抛异常。
    // 策略：
    //   1. 先尝试加密打开 → 成功 = 已经是加密盒（正常路径）。
    //   2. 失败 → 改用明文打开 → 读出全部数据 → 关盒 → 删物理文件 →
    //           重新用加密打开（新空盒）→ 把数据写回。
    // 一台设备只会迁移一次；以后每次都走正常路径。
    service._birthdayBox = await _openWithMigration<Birthday>(
      'birthday',
      cipher,
    );
    service._customLinesBox = await _openWithMigration<TrailLine>(
      'custom_lines',
      cipher,
    );
    service._dataBox = await _openRawWithMigration('trail_data', cipher);
    _instance = service;
  }

  /// 尝试加密打开 typed box；失败则从明文迁移。
  ///
  /// 与旧版本的关键差异（PRD §4.3.1 / §7）：
  ///   · 加密打开失败 + 明文打开失败 → 抛 [HiveOpenFailure]，**不删文件**。
  ///   · 用户层面会看到错误页，可以重试或恢复备份，但数据文件保持原样。
  static Future<Box<T>> _openWithMigration<T>(
    String name,
    HiveAesCipher cipher,
  ) async {
    try {
      return await Hive.openBox<T>(name, encryptionCipher: cipher);
    } catch (e) {
      assert(() {
        debugPrint('[Hive] encrypted open "$name" failed, trying plain: $e');
        return true;
      }());
      // 走到这里表示可能是旧明文盒 → 尝试明文打开做一次性迁移。
      // 如果明文打开也失败，则认为文件已损坏/被篡改/用错密钥 →
      // 保留原文件，抛 HiveOpenFailure，交给上层决定。
      final List<T> items;
      try {
        final plain = await Hive.openBox<T>(name);
        items = plain.values.toList();
        await plain.close();
      } catch (e2, st2) {
        assert(() {
          debugPrint('[Hive] plain open "$name" also failed: $e2');
          return true;
        }());
        throw HiveOpenFailure(name, e2, st2);
      }

      // 明文能打开 → 这是合法的一次性迁移。
      // 这里 *可以* 安全删除明文文件，因为 items 已在内存中备份，
      // 且随后立即写回加密盒；若写回失败，我们仍然抛错而不是静默丢数据。
      try {
        await Hive.deleteBoxFromDisk(name);
        final encrypted = await Hive.openBox<T>(name, encryptionCipher: cipher);
        for (final item in items) {
          await encrypted.add(item);
        }
        assert(() {
          debugPrint('[Hive] migrated "$name": ${items.length} items');
          return true;
        }());
        return encrypted;
      } catch (e3, st3) {
        throw HiveOpenFailure(name, e3, st3);
      }
    }
  }

  /// 尝试加密打开 raw box（无类型参数）；失败则从明文迁移。
  ///
  /// 语义等同 [_openWithMigration]：损坏时只抛错，不删盘。
  static Future<Box> _openRawWithMigration(
    String name,
    HiveAesCipher cipher,
  ) async {
    try {
      return await Hive.openBox(name, encryptionCipher: cipher);
    } catch (e) {
      assert(() {
        debugPrint('[Hive] encrypted open "$name" failed, trying plain: $e');
        return true;
      }());
      final Map<dynamic, dynamic> entries;
      try {
        final plain = await Hive.openBox(name);
        entries = plain.toMap();
        await plain.close();
      } catch (e2, st2) {
        assert(() {
          debugPrint('[Hive] plain open "$name" also failed: $e2');
          return true;
        }());
        throw HiveOpenFailure(name, e2, st2);
      }

      try {
        await Hive.deleteBoxFromDisk(name);
        final encrypted = await Hive.openBox(name, encryptionCipher: cipher);
        for (final e in entries.entries) {
          await encrypted.put(e.key, e.value);
        }
        assert(() {
          debugPrint('[Hive] migrated "$name": ${entries.length} entries');
          return true;
        }());
        return encrypted;
      } catch (e3, st3) {
        throw HiveOpenFailure(name, e3, st3);
      }
    }
  }

  // ── 生日 ──────────────────────────────────────

  bool get hasBirthday => _birthdayBox.isNotEmpty;

  DateTime? getBirthday() {
    if (_birthdayBox.isEmpty) return null;
    return _birthdayBox.values.first.date;
  }

  Future<void> saveBirthday(DateTime date) async {
    if (_birthdayBox.isNotEmpty) return;
    await _birthdayBox.add(Birthday(date: date));
    // 起始日期就是"注册当天"。走 nowForWrite — 若系统时间被篡改，宁可让
    // 用户先修正时间再重试，也不要把一个错误的起点永久写进去。
    final key = _fmtDate(_nowForWrite('saveBirthday'));
    await _dataBox.put(_startDateKey, key);
  }

  // ── 「活着」基准线打卡 ────────────────────────

  Set<String> getCheckInDates() {
    final raw = _dataBox.get(_checkInKey);
    if (raw == null) return {};
    return _safeStringList(raw).toSet();
  }

  /// 今日自动打卡（打开 App 自动标记「活着」为实心）
  ///
  /// 系统时间被篡改时静默跳过 — 不抛异常（启动路径不应因此崩），
  /// 但也**不**写入假日期。等用户修正时间后下一次启动会正常打卡。
  void checkInToday() {
    if (TimeIntegrityService.instance.tampered) return;
    final key = _fmtDate(TimeIntegrityService.instance.now());
    final raw = _dataBox.get(_checkInKey, defaultValue: <String>[]);
    final list = _safeStringList(raw);
    if (!list.contains(key)) {
      list.add(key);
      _dataBox.put(_checkInKey, list);
    }
  }

  /// 切换今日「活着」基准线的打卡状态
  Future<bool> toggleAliveToday() async {
    // 用户主动操作 → tampered 时抛异常，让 UI 明确提示
    final key = _fmtDate(_nowForWrite('toggleAliveToday'));
    final raw = _dataBox.get(_checkInKey, defaultValue: <String>[]);
    final list = _safeStringList(raw);
    final bool nowChecked;
    if (list.contains(key)) {
      list.remove(key);
      nowChecked = false;
    } else {
      list.add(key);
      nowChecked = true;
    }
    await _dataBox.put(_checkInKey, list);
    return nowChecked;
  }

  DateTime getStartDate() {
    final String? key = _dataBox.get(_startDateKey);
    // tampered 时 now() 返回的是 clamp 后的安全值 — 仍然比假系统时间好。
    if (key == null) return TimeIntegrityService.instance.now();
    return _parseDate(key);
  }

  // ── 自定义行动线 ──────────────────────────────

  /// 返回活跃（未归档）自定义线。若用户设置了手动排序 → 按手动顺序；否则按 createdAt。
  List<TrailLine> getCustomLines() {
    final list = _customLinesBox.values
        .where((l) => l.type == TrailLineType.custom && !l.archived)
        .toList();
    final order = _lineOrder;
    if (order.isEmpty) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else {
      final orderMap = <String, int>{
        for (int i = 0; i < order.length; i++) order[i]: i,
      };
      list.sort((a, b) {
        final ai = orderMap[a.id];
        final bi = orderMap[b.id];
        if (ai != null && bi != null) return ai.compareTo(bi);
        if (ai != null) return -1; // 已排序的在前
        if (bi != null) return 1;
        return a.createdAt.compareTo(b.createdAt);
      });
    }
    return list;
  }

  /// 手动排序（用户拖拽完成后调用）
  List<String> get _lineOrder =>
      _safeStringList(_dataBox.get(_prefLineOrderKey));

  Future<void> setLineOrder(List<String> ids) =>
      _dataBox.put(_prefLineOrderKey, ids);

  /// 返回归档的自定义线（按归档时间倒序）
  List<TrailLine> getArchivedLines() {
    final list = _customLinesBox.values
        .where((l) => l.type == TrailLineType.custom && l.archived)
        .toList();
    list.sort((a, b) {
      final aa = a.archivedAt ?? a.createdAt;
      final bb = b.archivedAt ?? b.createdAt;
      return bb.compareTo(aa);
    });
    return list;
  }

  /// 用于生成线 id 的 UUID 生成器（v4，基于 `Random.secure()`）。
  static const Uuid _uuid = Uuid();

  Future<TrailLine> addCustomLine(String name) async {
    // createdAt 是整条线的「历史原点」— tampered 时一旦写错，后续所有
    // 日期对比都会歪。用 nowForWrite 强制失败，让用户先修正系统时间。
    final today = _nowForWrite('addCustomLine');
    // 旧版本用 microsecondsSinceEpoch.toString() 作 id —— 在同一毫秒内连调两次
    // （或从备份批量导入时）会产生冲突。UUID v4 解决这个问题，且与 Friend uid
    // 的格式保持一致，方便未来所有模型用同一种 id 风格。
    final line = TrailLine.fromType(
      id: _uuid.v4(),
      type: TrailLineType.custom,
      name: name,
      createdAt: today,
      nameHistory: {_fmtDate(today): name},
    );
    await _customLinesBox.add(line);
    return line;
  }

  Future<void> deleteCustomLine(TrailLine line) async {
    await line.delete();
  }

  /// 重命名一条自定义线
  Future<void> renameCustomLine(TrailLine line, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    // 重命名会往 nameHistory 里写一条「生效日」，生效日错了就是历史伪造
    await line.renameEffectiveToday(trimmed, _nowForWrite('renameCustomLine'));
  }

  /// 归档
  Future<void> archiveLine(TrailLine line) async {
    // archivedAt 参与归档列表排序；写错会让归档顺序错乱
    line.archived = true;
    line.archivedAt = _nowForWrite('archiveLine');
    await line.save();
  }

  /// 恢复（归档 → 活跃）
  Future<void> restoreLine(TrailLine line) async {
    line.archived = false;
    line.archivedAt = null;
    await line.save();
  }

  /// 写入/删除节点备注（date 为该节点所属日期）
  ///
  /// 受 [DateGuard] 保护：只有「今天」的节点可以写备注，
  /// 历史 / 未来节点一律 READ-ONLY。
  /// 违反时抛出 [ReadOnlyPastException]（UI 层 catch 后提示）。
  Future<void> setNoteFor(TrailLine line, DateTime date, String? text) async {
    DateGuard.assertEditableToday(date);
    line.setNote(date, text);
    // setNote 已 save()
  }

  /// 切换自定义行动线今日状态
  Future<bool> toggleCustomTodayForLine(TrailLine line) async {
    // 打卡 key 是行动线数据正确性的核心。tampered 时抛异常。
    final today = _nowForWrite('toggleCustomTodayForLine');
    final key = _fmtDate(today);
    // 确保 completedDates 是可变 List<String>
    final dates = List<String>.from(line.completedDates.whereType<String>());
    final bool nowChecked;
    if (dates.contains(key)) {
      dates.remove(key);
      nowChecked = false;
    } else {
      dates.add(key);
      nowChecked = true;
    }
    line.completedDates
      ..clear()
      ..addAll(dates);
    await line.save();
    return nowChecked;
  }

  // ── 引导状态 ──────────────────────────────────

  bool get hSwipeOnboardingDone =>
      _dataBox.get(_onboardHSwipeKey, defaultValue: false) as bool;

  bool get vSwipeOnboardingDone =>
      _dataBox.get(_onboardVSwipeKey, defaultValue: false) as bool;

  Future<void> markHSwipeDone() => _dataBox.put(_onboardHSwipeKey, true);
  Future<void> markVSwipeDone() => _dataBox.put(_onboardVSwipeKey, true);

  bool get tapTodayOnboardingDone =>
      _dataBox.get(_onboardTapTodayKey, defaultValue: false) as bool;
  Future<void> markTapTodayDone() => _dataBox.put(_onboardTapTodayKey, true);

  bool get radialMenuOnboardingDone =>
      _dataBox.get(_onboardRadialMenuKey, defaultValue: false) as bool;
  Future<void> markRadialMenuDone() =>
      _dataBox.put(_onboardRadialMenuKey, true);

  bool get firstTrackAdded =>
      _dataBox.get(_firstTrackAddedKey, defaultValue: false) as bool;
  Future<void> markFirstTrackAdded() => _dataBox.put(_firstTrackAddedKey, true);

  // ── UI 偏好（v2 升级） ────────────────────────

  /// 新功能总开关（false = 还原成最原始的纯点+连线时间轴）
  bool get newFeaturesEnabled =>
      _dataBox.get(_prefNewFeaturesKey, defaultValue: true) as bool;

  Future<void> setNewFeaturesEnabled(bool v) =>
      _dataBox.put(_prefNewFeaturesKey, v);

  HeaderLayoutMode get headerLayoutMode {
    final raw = _dataBox.get(_prefHeaderLayoutKey);
    return HeaderLayoutModeX.fromStorage(raw is int ? raw : null);
  }

  Future<void> setHeaderLayoutMode(HeaderLayoutMode m) =>
      _dataBox.put(_prefHeaderLayoutKey, m.storageValue);

  double get nodeSpacing {
    final raw = _dataBox.get(_prefNodeSpacingKey);
    if (raw is num) {
      return raw.toDouble().clamp(minNodeSpacing, maxNodeSpacing);
    }
    return defaultNodeSpacing;
  }

  Future<void> setNodeSpacing(double v) => _dataBox.put(
    _prefNodeSpacingKey,
    v.clamp(minNodeSpacing, maxNodeSpacing),
  );

  /// 卫星点是否旋转（false = 固定在环右侧）
  bool get satelliteRotationEnabled =>
      _dataBox.get(_prefSatelliteRotationKey, defaultValue: true) as bool;

  Future<void> setSatelliteRotationEnabled(bool v) =>
      _dataBox.put(_prefSatelliteRotationKey, v);

  /// 危险操作：清除所有本地业务数据，并删除对应的 Hive 物理文件。
  ///
  /// 这会把 app 恢复到“首次启动”状态：
  /// - birthday
  /// - custom_lines
  /// - trail_data
  /// - friends
  ///
  /// 不负责清理 UID / 时间完整性签名状态；调用方需自行重置相应服务。
  Future<void> resetAllData() async {
    final openBoxes = <Box>[
      _birthdayBox,
      _customLinesBox,
      _dataBox,
      if (Hive.isBoxOpen('friends')) Hive.box<Friend>('friends'),
    ];

    for (final box in openBoxes) {
      if (box.isOpen) {
        await box.close();
      }
    }

    for (final name in const [
      'birthday',
      'custom_lines',
      'trail_data',
      'friends',
    ]) {
      await Hive.deleteBoxFromDisk(name);
    }

    _instance = null;
  }

  // ── 工具方法 ──────────────────────────────────

  /// 关键写入路径统一入口 —— 系统时间被篡改时直接抛 [TimeTamperedException]。
  /// 若 TimeIntegrityService 还没初始化完（极端边界），回落到系统时间（仅限启动期）。
  DateTime _nowForWrite(String op) {
    if (!TimeIntegrityService.instance.isReady) return DateTime.now();
    return TimeIntegrityService.instance.nowForWrite(op);
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _parseDate(String s) {
    final p = s.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// 安全地将动态值转为 `List<String>`，过滤掉非 String 元素
  List<String> _safeStringList(dynamic raw) {
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return [];
  }
}
