// ─────────────────────────────────────────────────────────────────────────────
// time_integrity_service.dart
//
// 模块定位（CORE REQ 2）：
//   提供「可信的离线时间戳」。
//
//   「迹点」全量离线，不能依赖 NTP，所以任何时间戳都基于 `DateTime.now()` —
//   但我们要在这基础上加两层防线：
//     (1) 签名：对 `{payload, timestamp}` 用 HMAC-SHA256(签名密钥) 签名，
//         得到一个「信封」(SignedEnvelope)；导入备份或校验历史记录时必须验签。
//     (2) 防回拨：把「已见过的最大时间戳」持久化到 Keychain/Keystore。
//         下次启动时，如果 `DateTime.now()` 比已知最大时间还要小，
//         超过 5 分钟容差（容纳 NTP 正常漂移），就标记 `tampered = true`，
//         UI 层可据此提示用户「检测到系统时间被回拨」。
//
//   与 REQ 3（备份文件签名）是同一套签名密钥；和 Hive AES 主密钥是**不同**的密钥
//   （见 crypto_utils.dart 中的域分离盐）。
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto_utils.dart';
import 'uid_service.dart';

/// 被签名的信封结构 — 用于持久化任何「需要事后校验来源」的数据片段
class SignedEnvelope {
  /// 记录创建时的毫秒时间戳（UTC，epoch ms）
  final int timestampMs;

  /// 被签名的明文载荷（通常是 JSON 字符串）
  final String body;

  /// HMAC-SHA256(sigKey, "$timestampMs|$body") 的 hex 字符串
  final String signatureHex;

  const SignedEnvelope({
    required this.timestampMs,
    required this.body,
    required this.signatureHex,
  });

  Map<String, dynamic> toJson() => {
        'ts': timestampMs,
        'body': body,
        'sig': signatureHex,
      };

  factory SignedEnvelope.fromJson(Map<String, dynamic> j) => SignedEnvelope(
        timestampMs: (j['ts'] as num).toInt(),
        body: j['body'] as String,
        signatureHex: j['sig'] as String,
      );

  String encodeJson() => jsonEncode(toJson());

  static SignedEnvelope decodeJson(String s) =>
      SignedEnvelope.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// 数据写入时发现系统时间被篡改 — 调用方应 abort 本次写入。
///
/// 不是所有写路径都必须拒绝（例如 UI 偏好），只有「与时间挂钩的关键数据」
/// （打卡、笔记、归档时间）才走 [TimeIntegrityService.nowForWrite]，从而在
/// tampered 状态下被这个异常阻挡。
class TimeTamperedException implements Exception {
  final String operation;
  const TimeTamperedException(this.operation);

  @override
  String toString() =>
      'TimeTamperedException: refusing "$operation" while system clock is tampered.';
}

/// 可信离线时间戳 + 签名 + 时钟回拨检测
///
/// 四层防线：
///   1. 启动时检测：与持久化的历史最大时间戳比较（回拨）
///   2. 前后台切换时检测：App 进入后台时记录时间，回到前台时校验（回拨）
///   3. 每次 now() 调用时检测：运行中如果系统时间回拨也能捕获（回拨）
///   4. 进程内 Stopwatch 基线检测：系统时间「往前跳」超过容差也会被抓（前跳）
///      — 这一层专门解决「用户把系统时间调到未来」这种历史防御盲点。
///
/// tampered 状态下：
///   - `now()` 返回的是单调时钟推算值（而非系统时间），防止用假时间写入数据
///   - `nowForWrite()` 直接抛 [TimeTamperedException]，阻断关键写入
///   - UI 层可通过 `tampered` getter 展示警告
class TimeIntegrityService {
  TimeIntegrityService._();

  static final TimeIntegrityService instance = TimeIntegrityService._();

  /// Secure storage key：上次见过的最大时间戳（epoch ms）
  static const String _kLastSeenKey = 'trail.core.lastSeenEpochMs.v1';

  /// Secure storage key：App 进入后台时的时间戳
  static const String _kBackgroundKey = 'trail.core.backgroundEpochMs.v1';

  /// 允许系统时钟「略微倒退」的容差（5 分钟）—
  /// NTP 校准后可能会把时间往回校几秒到几分钟，属正常；超过这个就判为异常。
  static const int _toleranceMs = 5 * 60 * 1000;

  /// 前跳容差 — 允许「现实 elapsed ≤ 宣称 elapsed + 此值」。
  /// 比回拨容差宽一点（10 min），因为跨时区手动切换时 wall clock 会瞬跳。
  static const int _forwardToleranceMs = 10 * 60 * 1000;

  final FlutterSecureStorage _store = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Uint8List? _sigKey;
  int _lastSeenMs = 0;
  bool _tampered = false;
  bool _ready = false;

  /// 单调时钟基线 — 用于前跳检测。Stopwatch 基于 OS 单调时钟，
  /// 不受用户改系统时间影响；跨 app 被系统 kill 后会重置，但每次 initialize
  /// 都会重新 anchor，所以仍然有效（被 kill 时也就是下次启动走 lastSeen 分支）。
  final Stopwatch _mono = Stopwatch();

  /// 上次 anchor 时的系统 wall-clock ms
  int _anchorWallMs = 0;

  /// 上次 anchor 时的单调时钟 ms（通常 0，除非中途 re-anchor）
  int _anchorMonoMs = 0;

  /// UI 可订阅：tampered 状态变化时通知
  final StreamController<bool> _tamperedCtrl = StreamController<bool>.broadcast();
  Stream<bool> get onTamperedChanged => _tamperedCtrl.stream;

  /// 最近一次启动时是否检测到系统时钟「显著回拨」
  bool get tampered => _tampered;

  /// 本次启动时从 secure storage 读到的「历史最大时间戳」
  int get lastSeenEpochMs => _lastSeenMs;

  /// 是否已 initialize()
  bool get isReady => _ready;

  /// 内部：拿签名密钥；未 initialize() 时抛错
  Uint8List get _keyOrThrow {
    final k = _sigKey;
    if (k == null) {
      throw StateError(
        'TimeIntegrityService used before initialize(). '
        'Call TimeIntegrityService.instance.initialize() during bootstrap.',
      );
    }
    return k;
  }

  /// 必须在 UidService.initialize() 完成后调用。
  /// 读取/更新「历史最大时间戳」并派生签名密钥。
  Future<void> initialize() async {
    if (_ready) return;
    final uid = UidService.instance.uid;
    _sigKey = CryptoUtils.deriveSigKey(uid);

    int lastSeen = 0;
    try {
      final raw = await _store.read(key: _kLastSeenKey);
      if (raw != null && raw.isNotEmpty) {
        lastSeen = int.tryParse(raw) ?? 0;
      }
    } catch (e) {
      debugPrint('[TimeIntegrity] failed to read last-seen: $e');
    }

    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;

    if (lastSeen > 0 && nowMs + _toleranceMs < lastSeen) {
      _tampered = true;
      debugPrint(
        '[TimeIntegrity] TAMPER DETECTED: now=$nowMs < lastSeen=$lastSeen (tol=${_toleranceMs}ms)',
      );
    } else {
      _tampered = false;
    }

    // 无论是否 tampered，都把 max(lastSeen, nowMs) 写回去
    final newMax = nowMs > lastSeen ? nowMs : lastSeen;
    if (newMax != lastSeen) {
      try {
        await _store.write(key: _kLastSeenKey, value: newMax.toString());
      } catch (e) {
        debugPrint('[TimeIntegrity] failed to write last-seen: $e');
      }
    }
    _lastSeenMs = newMax;
    _anchorWallMs = nowMs;
    _anchorMonoMs = 0;
    if (!_mono.isRunning) _mono.start();
    _ready = true;
  }

  /// 重新校准单调基线 — 在 onAppResumed 时调用，因为后台期间系统可能
  /// 暂停 Stopwatch 或我们需要把"后台时长"纳入 anchor。
  void _reanchor(int currentWallMs) {
    _anchorWallMs = currentWallMs;
    _anchorMonoMs = _mono.elapsedMilliseconds;
  }

  // ── App 生命周期集成 ───────────────────────────────

  /// App 进入后台时调用（从 WidgetsBindingObserver.didChangeAppLifecycleState）
  ///
  /// 记录当前时间到 secure storage。回到前台时会与这个值比较，
  /// 防止用户在后台改系统时间再回来。
  Future<void> onAppPaused() async {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch;
    // 只在时间可信时记录
    if (ms >= _lastSeenMs) {
      try {
        await _store.write(key: _kBackgroundKey, value: ms.toString());
      } catch (e) {
        debugPrint('[TimeIntegrity] failed to write background time: $e');
      }
    }
  }

  /// App 回到前台时调用（从 WidgetsBindingObserver.didChangeAppLifecycleState）
  ///
  /// 检测：如果当前时间比「进入后台时的时间」还早（超过容差），
  /// 说明用户在后台修改了系统时间。
  Future<void> onAppResumed() async {
    if (!_ready) return;

    int bgMs = 0;
    try {
      final raw = await _store.read(key: _kBackgroundKey);
      if (raw != null && raw.isNotEmpty) {
        bgMs = int.tryParse(raw) ?? 0;
      }
    } catch (e) {
      debugPrint('[TimeIntegrity] failed to read background time: $e');
    }

    if (bgMs <= 0) return; // 没有记录，跳过

    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;

    // 当前时间不能比「进入后台时」还早（含容差）
    if (nowMs + _toleranceMs < bgMs) {
      _setTampered(true);
      debugPrint(
        '[TimeIntegrity] TAMPER on resume: now=$nowMs < bgTime=$bgMs',
      );
    }

    // 同时检查历史最大值
    _checkAndUpdateLastSeen(nowMs);

    // 重新校准单调基线 — 后台期间可能系统休眠导致 Stopwatch 滞后；
    // 这里把 wall-clock 重新 anchor 到当前，后续的前跳检测以此为起点。
    if (!_tampered) _reanchor(nowMs);
  }

  // ── 核心时间获取 ──────────────────────────────────

  /// 获取「现在」时间戳。
  ///
  /// - 正常情况：返回 DateTime.now()
  /// - tampered 时：返回从单调时钟推算的 DateTime（而非系统时间）
  ///   这样即使系统时间被改了，写入数据的时间戳也不会被污染
  /// - 每次调用都会顺便检测回拨 / 前跳 并更新 `_lastSeenMs`
  DateTime now() {
    final dt = DateTime.now();
    final ms = dt.toUtc().millisecondsSinceEpoch;

    // 1) 回拨检测（旧）
    if (ms + _toleranceMs < _lastSeenMs) {
      _setTampered(true);
      debugPrint(
        '[TimeIntegrity] TAMPER(back) in now(): sysMs=$ms < lastSeen=$_lastSeenMs',
      );
    }

    // 2) 前跳检测（新）— 基于单调时钟：wall 的增长应 ≈ mono 的增长
    if (_ready && _anchorWallMs > 0) {
      final monoElapsed = _mono.elapsedMilliseconds - _anchorMonoMs;
      final expected = _anchorWallMs + monoElapsed;
      // 只有当 wall 跑得比 mono 快很多时才是「前跳」
      if (ms - expected > _forwardToleranceMs) {
        _setTampered(true);
        debugPrint(
          '[TimeIntegrity] TAMPER(fwd) in now(): sysMs=$ms expected=$expected '
          '(mono=$monoElapsed, anchor=$_anchorWallMs)',
        );
      }
    }

    // 非篡改时，更新 lastSeen（只向前推进）
    if (!_tampered && ms > _lastSeenMs) {
      _lastSeenMs = ms;
      _store
          .write(key: _kLastSeenKey, value: ms.toString())
          .catchError(
            (e) => debugPrint('[TimeIntegrity] persist now() failed: $e'),
          );
    }

    // tampered 时：用单调时钟推算的时间，而非系统时间
    if (_tampered) {
      final monoElapsed = _mono.elapsedMilliseconds - _anchorMonoMs;
      final safeMs = _anchorWallMs > 0
          ? _anchorWallMs + monoElapsed
          : _lastSeenMs;
      // 取 max(safeMs, lastSeenMs) 确保不会后退
      final clampMs = safeMs > _lastSeenMs ? safeMs : _lastSeenMs;
      return DateTime.fromMillisecondsSinceEpoch(clampMs, isUtc: true).toLocal();
    }
    return dt;
  }

  /// 纯日期（00:00:00）版本的 [now]，供 storage 层生成「今日 key」使用。
  /// 这样所有 day-key 都经过 tamper 防护。
  DateTime todayDateOnly() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }

  /// 用于**关键数据写入**的 now —— tampered 时直接抛异常，而不是返回 clamp 值。
  ///
  /// 场景：打卡 / 笔记 / 归档等写入会永久留痕的操作，宁可失败也不要写脏数据。
  /// UI 层 catch 到这个异常后，应提示用户「请先修正系统时间」。
  DateTime nowForWrite(String operation) {
    if (_tampered) {
      throw TimeTamperedException(operation);
    }
    return now();
  }

  /// 格式化 yyyy-MM-dd（供 day-key 使用）
  String todayKey() {
    final d = todayDateOnly();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// 格式化 yyyy-MM-dd（写入版：tampered 时抛）
  String todayKeyForWrite(String operation) {
    if (_tampered) {
      throw TimeTamperedException(operation);
    }
    return todayKey();
  }

  // ── 状态管理 ──────────────────────────────────────

  void _setTampered(bool value) {
    if (_tampered != value) {
      _tampered = value;
      if (!_tamperedCtrl.isClosed) _tamperedCtrl.add(value);
    }
  }

  void _checkAndUpdateLastSeen(int nowMs) {
    if (nowMs > _lastSeenMs) {
      _lastSeenMs = nowMs;
      _store
          .write(key: _kLastSeenKey, value: nowMs.toString())
          .catchError((e) => debugPrint('[TimeIntegrity] persist failed: $e'));
    }
  }

  /// 用户确认已修正系统时间后调用。
  /// 会重新读取系统时间，如果不再回拨则清除 tampered 标记。
  Future<void> clearTamperAfterFix() async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (nowMs + _toleranceMs >= _lastSeenMs) {
      _setTampered(false);
      _lastSeenMs = nowMs;
      await _store.write(key: _kLastSeenKey, value: nowMs.toString());
      debugPrint('[TimeIntegrity] Tamper cleared, time is valid again.');
    } else {
      debugPrint('[TimeIntegrity] Cannot clear tamper: time still behind.');
    }
  }

  // ── 签名 / 验签 ────────────────────────────────────

  /// 对任意载荷生成 SignedEnvelope（timestamp = 经防篡改校正的 now UTC ms）
  ///
  /// 注意：用 [now] 而非 `DateTime.now()` — tampered 时签的是 clamp 值，
  /// 避免把假时间签进信封里。
  SignedEnvelope sign(String body) {
    final key = _keyOrThrow;
    final tsMs = now().toUtc().millisecondsSinceEpoch;
    final msg = utf8.encode('$tsMs|$body');
    final sig = CryptoUtils.hmacSha256Hex(key, msg);
    return SignedEnvelope(timestampMs: tsMs, body: body, signatureHex: sig);
  }

  /// 对外部提供的 (body, timestamp, signature) 三元组验签（常数时间比较）
  bool verify({
    required String body,
    required int timestampMs,
    required String signatureHex,
  }) {
    final key = _keyOrThrow;
    final expected = CryptoUtils.hmacSha256(
      key,
      utf8.encode('$timestampMs|$body'),
    );
    final given = CryptoUtils.fromHex(signatureHex);
    if (given.isEmpty) return false;
    return CryptoUtils.constantTimeEquals(expected, given);
  }

  /// 验签整个信封（便捷方法）
  bool verifyEnvelope(SignedEnvelope env) => verify(
        body: env.body,
        timestampMs: env.timestampMs,
        signatureHex: env.signatureHex,
      );

  @visibleForTesting
  Future<void> debugReset() async {
    _sigKey = null;
    _lastSeenMs = 0;
    _tampered = false;
    _ready = false;
    _anchorWallMs = 0;
    _anchorMonoMs = 0;
    _mono.stop();
    _mono.reset();
    await _store.delete(key: _kLastSeenKey);
    await _store.delete(key: _kBackgroundKey);
  }
}
