// ─────────────────────────────────────────────────────────────────────────────
// ble_service.dart
//
// 模块定位（CORE REQ 4）：
//   BLE 近场「扫一扫」配对 — 不走任何服务器 / 互联网 / 账号体系。
//
//   做法（零协议、零 GATT 连接）：
//     - 广播：把本机 UID 的 16 字节原始 GUID 塞进 BLE 广播包的
//             Manufacturer Specific Data（Company ID = 0xFFF1，属厂商测试段）。
//     - 扫描：开 Scan → 过滤出含该 Manufacturer Data 的包 →
//             从 16 字节还原 UUID → 去重 → 回调「发现好友候选」。
//
//   之所以用 Manufacturer Data 而不是 GATT Service UUID：
//     iOS 在后台/锁屏状态只会广播「overflow area」(Apple 会擦掉 service UUID)，
//     Manufacturer Data 在前台扫描场景是最稳、跨平台最一致的载体。
//
//   好友一旦「被发现 + 确认」→ 通过 `addFriend(uid, displayName)` 写入 `friends` 盒。
//   不做自动配对 — UI 层必须展示候选列表让用户手动确认。
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:hive/hive.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/friend.dart';
import 'secure_box_service.dart';
import 'time_integrity_service.dart';
import 'uid_service.dart';

/// 扫描到的候选好友（未确认）
class DiscoveredPeer {
  final String uid;
  final int rssi;
  final DateTime discoveredAt;
  final PeerHandshakeState handshakeState;
  final String? targetUidPrefix;
  final String? displayTag;

  /// 对方广播里携带的 1-byte "presence nonce" —— 对方每次确认感知到我们时会轮转。
  /// 旧版本广播（9-byte payload / iOS 旧 localName）会给出 0。
  /// 应用层可据此做：
  ///   · 判断对方刚刚是否也在线
  ///   · 检测新鲜度（同一 peer 连续多次给出同一个值 = payload 没更新）
  ///   · 未来同步合打卡时作为 "双方都在" 的依据
  final int presenceByte;

  const DiscoveredPeer({
    required this.uid,
    required this.rssi,
    required this.discoveredAt,
    required this.handshakeState,
    this.targetUidPrefix,
    this.displayTag,
    this.presenceByte = 0,
  });
}

enum PeerHandshakeState { discoverable, request, confirm }

/// 权限申请结果
enum BlePermissionResult { granted, denied, permanentlyDenied }

/// BLE 近场配对服务（单例）
class BleService {
  BleService._();

  static final BleService instance = BleService._();

  /// 迹点自定义 Service UUID — 广播和扫描都靠它识别「迹点」设备
  /// 128-bit UUID 格式，iOS 和 Android 都支持
  static const String _trailServiceUuid =
      '0000fff1-0000-1000-8000-00805f9b34fb';

  /// 自定义的 Manufacturer Company ID — 仅 Android 广播使用
  static const int _manufacturerId = 0xFFF1;
  static const Duration discoverableDuration = Duration(minutes: 5);
  static const int _payloadStateDiscoverable = 0;
  static const int _payloadStateRequest = 1;
  static const int _payloadStateConfirm = 2;
  static const String _iosNamePrefix = 'tr@';

  /// 广播周期 — 上层可在 UI「查找朋友」页面手动调用 start/stop
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  StreamSubscription<List<ScanResult>>? _scanSub;
  final StreamController<DiscoveredPeer> _peerCtrl =
      StreamController<DiscoveredPeer>.broadcast();

  /// 最近扫描到的 uid → peer 缓存（去重 + 更新 RSSI）
  final Map<String, DiscoveredPeer> _seen = {};

  /// 超过 [_peerTtl] 没再被扫到就清理掉 — 避免 UI 上显示已离开的设备
  /// 20s 窗口同时覆盖"朋友打卡 15s 在场门槛"的判定，保留若干 buffer。
  static const Duration _peerTtl = Duration(seconds: 20);
  Timer? _ageOutTimer;

  Timer? _discoverableTimer;
  DateTime? _discoverableUntil;

  bool _advertising = false;
  bool _scanning = false;
  PeerHandshakeState _currentHandshakeState = PeerHandshakeState.discoverable;
  String? _currentTargetPrefix;

  /// 本机广播里附带的 1-byte "presence nonce"。
  /// - 每次我们感知到某个好友靠近、想要给对方一个"我也在这"的信号时，
  ///   调用 [bumpPresence] 让它轮转（mod 256）并重新广播一次。
  /// - 对方扫描到后会在 [DiscoveredPeer.presenceByte] 上读到新的值。
  /// - **不**承载任何位置/身份细节；仅是一个递增计数器，泄露面最小。
  int _currentPresenceByte = 0;
  int get currentPresenceByte => _currentPresenceByte;

  /// 获取某个已知 peer 最近一次携带的 presenceByte（未见过 → null）
  int? presenceByteFor(String peerUid) => _seen[peerUid]?.presenceByte;

  /// 判定某 peer 是否在近场（默认 15s 内被扫到过）。
  /// 供朋友节点打卡门禁使用：只有 peer 在范围内，今日节点才可 tap。
  bool isPeerInRange(
    String peerUid, {
    Duration window = const Duration(seconds: 15),
  }) {
    final peer = _seen[peerUid];
    if (peer == null) return false;
    return DateTime.now().difference(peer.discoveredAt) <= window;
  }

  /// 轮转本机 presence nonce 并立即 refresh 广播。
  /// UI / 合打卡逻辑在感知到对方在附近时调用；每次调用改一次 payload。
  /// 如果当前没在广播，只更新内部值不报错（等下次 startAdvertising 自动生效）。
  Future<void> bumpPresence() async {
    _currentPresenceByte = (_currentPresenceByte + 1) & 0xFF;
    // 已在广播时刷新 payload（updateBroadcastHandshake 会 stop→start）。
    // 未广播 → 只更新内部字段；下一次 startAdvertising 会自动带上新值。
    if (_advertising) {
      await updateBroadcastHandshake(
        state: _currentHandshakeState,
        targetUidPrefix: _currentTargetPrefix,
      );
    }
  }

  /// 节流：同一时间段内多次看到多个好友时，合并成一次 bumpPresence，
  /// 避免每个扫描批都重启一次 advertising。
  DateTime? _lastAutoBumpAt;
  static const Duration _autoBumpMinInterval = Duration(seconds: 8);

  Future<void> _maybeBumpPresenceForConfirmedFriend() async {
    final now = DateTime.now();
    final last = _lastAutoBumpAt;
    if (last != null && now.difference(last) < _autoBumpMinInterval) return;
    _lastAutoBumpAt = now;
    await bumpPresence();
  }

  /// 扫描到新 peer / RSSI 更新时发事件 — UI 订阅此流
  Stream<DiscoveredPeer> get discoveredPeers => _peerCtrl.stream;

  bool get isAdvertising => _advertising;
  bool get isScanning => _scanning;
  bool get isDiscoverable => _advertising;
  DateTime? get discoverableUntil => _discoverableUntil;
  String get myUidPrefix =>
      UidService.instance.uid.replaceAll('-', '').substring(0, 8).toLowerCase();

  Box<Friend>? _friendsBox;

  /// 打开 friends 盒（加密）。幂等。
  Future<Box<Friend>> ensureFriendsBox() async {
    if (_friendsBox != null && _friendsBox!.isOpen) return _friendsBox!;
    if (Hive.isBoxOpen('friends')) {
      _friendsBox = Hive.box<Friend>('friends');
    } else {
      _friendsBox = await SecureBoxService.instance.openEncryptedBox<Friend>(
        'friends',
      );
    }
    return _friendsBox!;
  }

  /// 请求必要的运行时权限。
  ///
  /// 关键规则（AndroidManifest 声明了 BLUETOOTH_SCAN + neverForLocation）：
  ///   · iOS：权限由系统首次使用时自动弹窗，Info.plist 已声明即可。
  ///   · Android 12+（API 31+）：只要 bluetoothScan / advertise / connect 授了就够；
  ///     **不需要定位**（neverForLocation 让 BLUETOOTH_SCAN 不暗含定位能力）。
  ///   · Android ≤ 11：bluetoothScan 是"编译时权限"，permission_handler 上总是回
  ///     `granted`；真正需要的是 fine/coarse location。
  ///
  /// 判定策略（不引新依赖）：
  ///   1. 顺带请求 `locationWhenInUse` —— Android ≤ 11 的用户会看到提示；
  ///      12+ 的用户因 manifest 已 `maxSdkVersion=30` 请求即时返回 denied，不显示弹窗。
  ///   2. 合格条件：bluetoothScan + advertise + connect 都 granted。
  ///      locationWhenInUse 只是信息性——它被拒不代表 BLE 不能用。
  Future<BlePermissionResult> requestPermissions() async {
    if (kIsWeb) return BlePermissionResult.denied;

    if (Platform.isIOS) {
      return BlePermissionResult.granted;
    }

    const required = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ];

    final statuses = await [
      ...required,
      Permission.locationWhenInUse, // 为 Android ≤ 11 顺带请求；不计入合格判定
    ].request();

    // 只用"必需三项"判断通过/不通过
    bool anyPermanentlyDenied = false;
    bool allGranted = true;
    for (final perm in required) {
      final s = statuses[perm] ?? PermissionStatus.denied;
      if (s.isPermanentlyDenied) anyPermanentlyDenied = true;
      if (!s.isGranted) allGranted = false;
    }

    assert(() {
      debugPrint(
        '[BLE] permission result: scan=${statuses[Permission.bluetoothScan]}, '
        'advertise=${statuses[Permission.bluetoothAdvertise]}, '
        'connect=${statuses[Permission.bluetoothConnect]}, '
        'loc=${statuses[Permission.locationWhenInUse]}',
      );
      return true;
    }());

    if (allGranted) return BlePermissionResult.granted;
    if (anyPermanentlyDenied) return BlePermissionResult.permanentlyDenied;
    return BlePermissionResult.denied;
  }

  // ── 广播 ────────────────────────────────────────────

  /// 开始广播本机 UID。
  ///
  /// 跨平台策略：
  ///   - 两侧都广播自定义 Service UUID（0xFFF1）→ 扫描端靠它识别「迹点」设备
  ///   - Android：用紧凑的 4-byte 前缀广播，保证落在 legacy advertisement 的 31-byte 限制内，
  ///             提高被 iPhone 扫到的概率
  ///   - iOS：用 localName 传 UID 前 8 位 hex（iOS CoreBluetooth 不支持 Manufacturer Data 广播）
  ///
  /// 扫描端优先从 Manufacturer Data / Service Data 取，fallback 从设备名取前 8 位。
  Future<bool> startAdvertising() async {
    if (_advertising) return true;
    final uidPrefix = myUidPrefix;
    final pairingHandle = UidService.instance.pairingHandle;
    final targetPrefix = (_currentTargetPrefix ?? '00000000').toLowerCase();
    final payloadBytes = _buildHandshakePayload(
      selfPrefix: uidPrefix,
      state: _currentHandshakeState,
      targetPrefix: targetPrefix,
      presenceByte: _currentPresenceByte,
    );
    final localName = _buildIosLocalName(
      pairingHandle: pairingHandle,
      selfPrefix: uidPrefix,
      state: _currentHandshakeState,
      targetPrefix: targetPrefix,
      presenceByte: _currentPresenceByte,
    );

    AdvertiseData data;
    AdvertiseSettings? settings;
    if (Platform.isIOS) {
      // iOS：Service UUID + LocalName（前 8 位 hex = 4 字节）
      data = AdvertiseData(
        serviceUuid: _trailServiceUuid,
        localName: localName,
        includeDeviceName: false,
      );
    } else {
      // Android：同时带 serviceUuid + manufacturerData。
      // serviceUuid 让 iPhone 端的带过滤扫描 (`withServices`) 能命中我们，
      // manufacturerData 仍承载握手 payload（9 bytes，在 legacy 31-byte 限制内）。
      data = AdvertiseData(
        serviceUuid: _trailServiceUuid,
        manufacturerId: _manufacturerId,
        manufacturerData: Uint8List.fromList(payloadBytes),
        includeDeviceName: false,
      );
      settings = AdvertiseSettings(
        advertiseSet: false,
        advertiseMode: AdvertiseMode.advertiseModeLowLatency,
        connectable: true,
        timeout: 0,
        txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
      );
    }

    try {
      await _peripheral.start(advertiseData: data, advertiseSettings: settings);
      _advertising = true;
      return true;
    } catch (e) {
      debugPrint('[BLE] startAdvertising failed: $e');
      return false;
    }
  }

  Future<void> stopAdvertising() async {
    _discoverableTimer?.cancel();
    _discoverableTimer = null;
    _discoverableUntil = null;
    _currentHandshakeState = PeerHandshakeState.discoverable;
    _currentTargetPrefix = null;
    if (!_advertising) return;
    try {
      await _peripheral.stop();
    } catch (e) {
      debugPrint('[BLE] stopAdvertising failed: $e');
    }
    _advertising = false;
  }

  /// 打开「可被发现」状态（用户手动触发）。
  ///
  /// 契约（PRD §4.1）：
  ///   · 每次调用都明确给出 [duration]；内部用单一 Timer 在到期时 stopAdvertising。
  ///   · 如果已经可被发现，本调用**不会续期** — 除非传入 [renew]=true。
  ///     这样连续的 UI 点按不会让用户不知道自己其实已经在广播。
  ///   · 握手状态与目标 prefix 由后续 [updateBroadcastHandshake] 更新，
  ///     **不再触碰本计时器**（旧版本会因每次握手变化 renew 5 分钟，违反 PRD §4.1.3）。
  Future<bool> setDiscoverable({
    Duration duration = discoverableDuration,
    bool renew = false,
  }) async {
    // 首次开启 → 设置 default 握手状态 & 清空目标
    _currentHandshakeState = PeerHandshakeState.discoverable;
    _currentTargetPrefix = null;

    if (_advertising) {
      if (renew) {
        // 用户主动续期：重启广播并重置计时器
        await stopAdvertising();
      } else {
        // 已在广播 — 什么都不做；返回当前计时是否仍然有效
        return _discoverableUntil != null &&
            _discoverableUntil!.isAfter(DateTime.now());
      }
    }

    final ok = await startAdvertising();
    if (!ok) return false;

    _discoverableUntil = DateTime.now().add(duration);
    _discoverableTimer?.cancel();
    _discoverableTimer = Timer(duration, () {
      // 到时强制关广播（PRD §4.1.4）
      stopAdvertising();
    });
    return true;
  }

  /// 更新广播内的握手状态/目标，不改动可被发现计时器。
  ///
  /// 触发场景：
  ///   · 用户点「添加」→ switch to [PeerHandshakeState.request] with target
  ///   · 本机确认请求    → switch to [PeerHandshakeState.confirm] with target
  /// 在不是 advertising 的状态下调用会被忽略 — 上层应先 [setDiscoverable]。
  Future<bool> updateBroadcastHandshake({
    required PeerHandshakeState state,
    String? targetUidPrefix,
  }) async {
    _currentHandshakeState = state;
    _currentTargetPrefix = targetUidPrefix;
    if (!_advertising) {
      // 没在广播 — 由调用者决定是否要 setDiscoverable 再更新
      return false;
    }
    // 重启广播以刷新 payload，不碰计时器
    try {
      await _peripheral.stop();
      _advertising = false;
    } catch (e) {
      debugPrint('[BLE] updateBroadcastHandshake stop failed: $e');
    }
    return startAdvertising();
  }

  /// 兼容旧调用点的 shim（一次性；后续统一迁移到 [setDiscoverable]）。
  @Deprecated('Use setDiscoverable / updateBroadcastHandshake instead')
  Future<bool> enableDiscoverability({
    Duration duration = discoverableDuration,
    PeerHandshakeState state = PeerHandshakeState.discoverable,
    String? targetUidPrefix,
  }) async {
    final ok = await setDiscoverable(duration: duration, renew: true);
    if (!ok) return false;
    if (state != PeerHandshakeState.discoverable || targetUidPrefix != null) {
      await updateBroadcastHandshake(
        state: state,
        targetUidPrefix: targetUidPrefix,
      );
    }
    return true;
  }

  Future<void> disableDiscoverability() async {
    await stopAdvertising();
  }

  // ── 扫描 ────────────────────────────────────────────

  /// 开始扫描附近在广播「迹点 Service UUID」的设备
  ///
  /// 扫描过滤策略：
  ///   · 首选：`withServices = [迹点 UUID]` —— iOS 后台也会返回命中，
  ///          且 CoreBluetooth 不会对无过滤扫描做激进节流。
  ///   · 万一 withServices 过滤在某些 Android 机型上识别不到
  ///     legacy advertising，回退到不带过滤扫描。
  Future<bool> startScan({Duration? timeout}) async {
    if (_scanning) return true;
    _seen.clear();
    final timeoutToUse = timeout ?? const Duration(seconds: 20);
    final trailGuid = Guid(_trailServiceUuid);
    _startAgeOutTimer();
    try {
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen(_onScanBatch);
      await FlutterBluePlus.startScan(
        withServices: [trailGuid],
        timeout: timeoutToUse,
        androidScanMode: AndroidScanMode.lowLatency,
      );
      _scanning = true;
      return true;
    } catch (e) {
      debugPrint(
        '[BLE] filtered startScan failed, retrying without filter: $e',
      );
      // fallback：不带过滤的全量扫描（_onScanBatch 仍会按 serviceUuid 过滤）
      try {
        _scanSub = FlutterBluePlus.scanResults.listen(_onScanBatch);
        await FlutterBluePlus.startScan(
          timeout: timeoutToUse,
          androidScanMode: AndroidScanMode.lowLatency,
        );
        _scanning = true;
        return true;
      } catch (e2) {
        debugPrint('[BLE] startScan fallback also failed: $e2');
        await _scanSub?.cancel();
        _scanSub = null;
        return false;
      }
    }
  }

  Future<void> stopScan() async {
    _ageOutTimer?.cancel();
    _ageOutTimer = null;
    if (!_scanning) return;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('[BLE] stopScan failed: $e');
    }
    await _scanSub?.cancel();
    _scanSub = null;
    _scanning = false;
  }

  /// 周期性清理过期 peer。每 4s 一跳：超过 [_peerTtl] 没再被扫到就从 _seen 里剔除。
  /// 不发 remove 事件（Stream 契约只承诺「新/更新」），上层靠 [currentDiscovered] 刷新。
  void _startAgeOutTimer() {
    _ageOutTimer?.cancel();
    _ageOutTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      final cutoff = DateTime.now().subtract(_peerTtl);
      final stale = _seen.entries
          .where((e) => e.value.discoveredAt.isBefore(cutoff))
          .map((e) => e.key)
          .toList();
      if (stale.isEmpty) return;
      for (final uid in stale) {
        _seen.remove(uid);
      }
    });
  }

  void _onScanBatch(List<ScanResult> results) {
    for (final r in results) {
      final adv = r.advertisementData;
      final hasTrailService = adv.serviceUuids.any(
        (uuid) => uuid.toString().toLowerCase() == _trailServiceUuid,
      );

      // 策略 1：从 Manufacturer Data 取握手 payload（Android 广播的）
      //   v1 = 9 bytes: selfPrefix(4)+state(1)+targetPrefix(4)
      //   v2 = 10 bytes: v1 + presenceByte(1)
      //   解析器接受两种长度以兼容旧版本设备。
      final md = adv.manufacturerData;
      String? uid;
      PeerHandshakeState handshakeState = PeerHandshakeState.discoverable;
      String? targetUidPrefix;
      String? displayTag;
      int presenceByte = 0;
      final manuBytes = md[_manufacturerId];
      if (manuBytes != null &&
          (manuBytes.length == 9 || manuBytes.length == 10)) {
        final parsed = _parseHandshakePayload(manuBytes);
        uid = _prefixToPartialUid(parsed.selfPrefix);
        handshakeState = parsed.state;
        targetUidPrefix = parsed.targetPrefix;
        presenceByte = parsed.presenceByte;
      }

      // 策略 3：从带 Trail 前缀的 localName 解析（iOS 广播的）
      if (uid == null) {
        final name = adv.advName.trim();
        if (name.isNotEmpty) {
          final parsed = _parseIosLocalName(name);
          if (parsed != null) {
            uid = _prefixToPartialUid(parsed.selfPrefix);
            handshakeState = parsed.state;
            targetUidPrefix = parsed.targetPrefix;
            displayTag = '@${parsed.pairingHandle}';
            presenceByte = parsed.presenceByte;
          }
        }
      }

      if (uid == null && !hasTrailService) continue; // 不是迹点设备
      if (uid == null) continue;
      if (uid == UidService.instance.uid) continue; // 过滤自己

      unawaited(
        _handleHandshakeIfNeeded(
          remoteUid: uid,
          handshakeState: handshakeState,
          targetUidPrefix: targetUidPrefix,
        ),
      );

      final prev = _seen[uid];
      final now = TimeIntegrityService.instance.isReady
          ? TimeIntegrityService.instance.now()
          : DateTime.now();
      final peer = DiscoveredPeer(
        uid: uid,
        rssi: r.rssi,
        discoveredAt: now,
        handshakeState: handshakeState,
        targetUidPrefix: targetUidPrefix,
        displayTag: displayTag,
        presenceByte: presenceByte,
      );
      _seen[uid] = peer;
      final handshakeChanged =
          prev == null ||
          prev.handshakeState != peer.handshakeState ||
          prev.targetUidPrefix != peer.targetUidPrefix ||
          prev.presenceByte != peer.presenceByte;
      if (handshakeChanged || (prev.rssi - peer.rssi).abs() > 6) {
        if (!_peerCtrl.isClosed) _peerCtrl.add(peer);
      }
    }
  }

  /// 检查字符串是否是合法 hex
  static bool _isValidHex(String s) {
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
  }

  /// 将 UID 前 8 位 hex（4 bytes）扩展为部分 UID
  /// 格式：xxxxxxxx-0000-0000-0000-000000000000
  /// 注意：只有 Android 广播完整 UID 时才能完整识别；
  /// iOS 只广播前 8 位，两端都是 iOS 时只能用前缀匹配。
  static String _prefixToPartialUid(String prefix8hex) {
    // 补齐到 32 hex = 16 bytes
    final padded = prefix8hex.padRight(32, '0');
    // 格式化为 UUID：8-4-4-4-12
    return '${padded.substring(0, 8)}-${padded.substring(8, 12)}-${padded.substring(12, 16)}-${padded.substring(16, 20)}-${padded.substring(20, 32)}';
  }

  /// 当前扫描结果快照（UI 可直接取来建列表）
  List<DiscoveredPeer> get currentDiscovered =>
      _seen.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

  /// 处理扫描到的握手信号。
  ///
  /// 关键规则（PRD §4.2 / §6）：
  ///   · **不会自动创建好友**。对方一个 request 最多把「我方已存在的 pendingOutgoing」
  ///     升级为 confirmed（即「双边同时请求 → 自动收口」路径），
  ///     或者在没有好友记录时通过回调把信号抛到 UI 让用户确认。
  ///   · 对方 confirm + target 指向我 → 我方 pendingOutgoing → confirmed。
  ///
  /// 旧版本里 confirmFriendRequest 会隐式 addFriend，相当于「A 点一次就直接加上」，
  /// 违反 PRD §4.2.1。这里改成只 save state，不调用 addFriend。
  Future<void> _handleHandshakeIfNeeded({
    required String remoteUid,
    required PeerHandshakeState handshakeState,
    required String? targetUidPrefix,
  }) async {
    final friend = await findFriendByUid(remoteUid);

    // 目标前缀如果存在且不是我（也不是通配 0000...），直接忽略 —— 别人在对别人握手
    final bool addressedToMe =
        targetUidPrefix == null ||
        targetUidPrefix == '00000000' ||
        targetUidPrefix.toLowerCase() == myUidPrefix;
    if (!addressedToMe) return;

    // 我没记录这个 peer —— 本层不写任何持久化。UI 层会订阅
    // [incomingRequests] 展示「对方请求你确认」条目，由用户点同意/命名后再写盒。
    if (friend == null) {
      if (handshakeState == PeerHandshakeState.request) {
        if (!_incomingCtrl.isClosed) _incomingCtrl.add(remoteUid);
      }
      return;
    }

    if (handshakeState == PeerHandshakeState.request) {
      // 双边同时添加：我在 pendingOutgoing，对方也在 request →
      // 直接 confirmed，并切广播到 confirm 通知对方。
      if (friend.state == FriendState.pendingOutgoing) {
        friend.state = FriendState.confirmed;
        await friend.save();
        await updateBroadcastHandshake(
          state: PeerHandshakeState.confirm,
          targetUidPrefix: _uidPrefixOf(remoteUid),
        );
        return;
      }
      // 我方还没发过请求 —— 标为 pendingIncoming（等 UI 弹出确认）。
      if (friend.state != FriendState.pendingIncoming &&
          friend.state != FriendState.confirmed) {
        friend.state = FriendState.pendingIncoming;
        await friend.save();
      }
      return;
    }

    if (handshakeState == PeerHandshakeState.confirm) {
      if (friend.state == FriendState.confirmed) {
        // 已确认好友重新被扫到 → 轮转 presence nonce 作为 "我也在" 的回执
        unawaited(_maybeBumpPresenceForConfirmedFriend());
        return;
      }
      // 对方已 confirm 我们 → 我方也 confirmed
      friend.state = FriendState.confirmed;
      await friend.save();
      unawaited(_maybeBumpPresenceForConfirmedFriend());
      return;
    }

    // 稳态 discoverable：如果对方是我已确认的好友，也轮转一次 presence。
    if (handshakeState == PeerHandshakeState.discoverable &&
        friend.state == FriendState.confirmed) {
      unawaited(_maybeBumpPresenceForConfirmedFriend());
    }
  }

  /// UI 订阅：有陌生 peer 发来 [PeerHandshakeState.request] 时推送其 uid。
  /// 由好友发现页去重、显示「对方请求你确认」条目。
  final StreamController<String> _incomingCtrl =
      StreamController<String>.broadcast();
  Stream<String> get incomingRequests => _incomingCtrl.stream;

  // ── 好友名册（本地） ───────────────────────────────

  /// 确认添加一个扫描到的候选 peer → 写入 friends 盒
  Future<Friend> addFriend({
    required String uid,
    String? displayName,
    int? rssi,
    FriendState state = FriendState.pendingOutgoing,
  }) async {
    final box = await ensureFriendsBox();
    // 去重
    final existing = box.values.where((f) => f.uid == uid).toList();
    if (existing.isNotEmpty) {
      final f = existing.first;
      if (displayName != null && displayName.trim().isNotEmpty) {
        f.displayName = displayName.trim();
        await f.save();
      }
      if (rssi != null) {
        f.rssi = rssi;
        await f.save();
      }
      if (f.state != state) {
        f.state = state;
        await f.save();
      }
      return f;
    }
    final now = TimeIntegrityService.instance.isReady
        ? TimeIntegrityService.instance.now()
        : DateTime.now();
    final friend = Friend(
      uid: uid,
      displayName: (displayName == null || displayName.trim().isEmpty)
          ? uid.substring(0, 8)
          : displayName.trim(),
      pairedAt: now,
      rssi: rssi,
      state: state,
    );
    await box.add(friend);
    return friend;
  }

  Future<Friend?> findFriendByUid(String uid) async {
    final box = await ensureFriendsBox();
    try {
      return box.values.firstWhere((f) => f.uid == uid);
    } catch (_) {
      return null;
    }
  }

  /// 用户在 UI 上点「确认添加」时调用。
  ///
  /// 契约：
  ///   · 只在用户主动触发时执行 —— 握手层不会自己调它。
  ///   · 把本机状态置为 confirmed，并把广播切到 confirm 通知对方。
  ///   · 不重置可被发现计时器（PRD §4.1.3）；若广播已关，则重新打开。
  Future<void> confirmFriendRequest({
    required String uid,
    String? displayName,
    int? rssi,
  }) async {
    await addFriend(
      uid: uid,
      displayName: displayName,
      rssi: rssi,
      state: FriendState.confirmed,
    );
    if (!_advertising) {
      await setDiscoverable();
    }
    await updateBroadcastHandshake(
      state: PeerHandshakeState.confirm,
      targetUidPrefix: _uidPrefixOf(uid),
    );
  }

  /// 当前已配对好友（按 pairedAt 倒序）
  Future<List<Friend>> listFriends() async {
    final box = await ensureFriendsBox();
    final list = box.values.toList()
      ..sort((a, b) {
        if (a.state != b.state) {
          return a.state.index.compareTo(b.state.index);
        }
        return b.pairedAt.compareTo(a.pairedAt);
      });
    return list;
  }

  Future<void> removeFriend(Friend f) async {
    await f.delete();
  }

  /// 本地重命名好友（仅写本机 Hive，不走任何网络 / BLE 同步）。
  /// 空或全空白名字视为"恢复默认"（uid 前 8 位），与 addFriend 的默认值一致。
  Future<void> renameFriend(Friend f, String newName) async {
    final trimmed = newName.trim();
    f.displayName = trimmed.isEmpty ? f.uid.substring(0, 8) : trimmed;
    await f.save();
  }

  /// 服务清理（App 退出 / 页面销毁时调用）
  Future<void> dispose() async {
    _ageOutTimer?.cancel();
    _ageOutTimer = null;
    await stopScan();
    await stopAdvertising();
    await _peerCtrl.close();
    await _incomingCtrl.close();
  }

  /// 仅供调试 / 设置页清档使用：停止 BLE 活动并清空内存态。
  Future<void> resetRuntimeState() async {
    await stopScan();
    await stopAdvertising();
    _seen.clear();
    _friendsBox = null;
    _currentPresenceByte = 0;
    _lastAutoBumpAt = null;
    _currentHandshakeState = PeerHandshakeState.discoverable;
    _currentTargetPrefix = null;
  }

  // ── UUID <-> 16 bytes ──────────────────────────────

  static String _uidPrefixOf(String uid) =>
      uid.replaceAll('-', '').substring(0, 8).toLowerCase();

  /// 构造握手 payload。
  ///
  /// 布局（v2，10 bytes；v1 是 9 bytes 没有 presenceByte）：
  ///   [0..4)  selfPrefix   (4 bytes, 本机 UID 前 8 位 hex)
  ///   [4]     state        (1 byte)
  ///   [5..9)  targetPrefix (4 bytes)
  ///   [9]     presenceByte (1 byte, 轮转 nonce, 旧版本设为 0)
  ///
  /// 31-byte legacy advertisement 限制：Company ID 2B + 10B payload = 12B，
  /// 加上 serviceUuid 后总长仍在 31B 以内，OK。
  static List<int> _buildHandshakePayload({
    required String selfPrefix,
    required PeerHandshakeState state,
    required String targetPrefix,
    int presenceByte = 0,
  }) {
    return [
      ..._hexToBytes(selfPrefix),
      switch (state) {
        PeerHandshakeState.discoverable => _payloadStateDiscoverable,
        PeerHandshakeState.request => _payloadStateRequest,
        PeerHandshakeState.confirm => _payloadStateConfirm,
      },
      ..._hexToBytes(targetPrefix),
      presenceByte & 0xFF,
    ];
  }

  /// iOS localName 布局：
  ///   v1（legacy）：`tr@` + pairingHandle(6) + selfPrefix(8) + stateChar(1)  = 18 chars
  ///   v2（当前） ：上述 + presence(2 hex chars)                              = 20 chars
  /// 解析时两种长度都接受。
  static String _buildIosLocalName({
    required String pairingHandle,
    required String selfPrefix,
    required PeerHandshakeState state,
    required String targetPrefix,
    int presenceByte = 0,
  }) {
    final stateChar = switch (state) {
      PeerHandshakeState.discoverable => '0',
      PeerHandshakeState.request => '1',
      PeerHandshakeState.confirm => '2',
    };
    final presenceHex = (presenceByte & 0xFF).toRadixString(16).padLeft(2, '0');
    return '$_iosNamePrefix$pairingHandle${selfPrefix.toLowerCase()}$stateChar$presenceHex';
  }

  /// 解析握手 payload。向后兼容：9-byte（v1 旧版）和 10-byte（v2 当前）都接受。
  static ({
    String selfPrefix,
    PeerHandshakeState state,
    String targetPrefix,
    int presenceByte,
  })
  _parseHandshakePayload(List<int> payload) {
    final selfPrefix = _bytesToHex(payload.sublist(0, 4));
    final state = switch (payload[4]) {
      _payloadStateRequest => PeerHandshakeState.request,
      _payloadStateConfirm => PeerHandshakeState.confirm,
      _ => PeerHandshakeState.discoverable,
    };
    final targetPrefix = _bytesToHex(payload.sublist(5, 9));
    final presenceByte = payload.length >= 10 ? (payload[9] & 0xFF) : 0;
    return (
      selfPrefix: selfPrefix,
      state: state,
      targetPrefix: targetPrefix,
      presenceByte: presenceByte,
    );
  }

  static ({
    String pairingHandle,
    String selfPrefix,
    PeerHandshakeState state,
    String targetPrefix,
    int presenceByte,
  })?
  _parseIosLocalName(String name) {
    final normalized = name.trim().toLowerCase();
    if (!normalized.startsWith(_iosNamePrefix)) return null;
    // v1 = prefix + 6 + 8 + 1 = 18 chars after prefix-stripping
    // v2 = v1 + 2 presence hex = 20 chars after prefix-stripping
    final v1Len = _iosNamePrefix.length + 6 + 8 + 1;
    final v2Len = v1Len + 2;
    if (name.length != v1Len && name.length != v2Len) return null;
    final pairingHandle = name.substring(
      _iosNamePrefix.length,
      _iosNamePrefix.length + 6,
    );
    final selfPrefix = normalized.substring(
      _iosNamePrefix.length + 6,
      _iosNamePrefix.length + 14,
    );
    final stateChar = normalized.substring(
      _iosNamePrefix.length + 14,
      _iosNamePrefix.length + 15,
    );
    if (!_isValidHex(selfPrefix)) return null;
    if (!RegExp(r'^[A-Za-z_]{6}$').hasMatch(pairingHandle)) return null;
    final state = switch (stateChar) {
      '1' => PeerHandshakeState.request,
      '2' => PeerHandshakeState.confirm,
      _ => PeerHandshakeState.discoverable,
    };
    int presenceByte = 0;
    if (name.length == v2Len) {
      final presenceHex = normalized.substring(
        _iosNamePrefix.length + 15,
        _iosNamePrefix.length + 17,
      );
      if (_isValidHex(presenceHex)) {
        presenceByte = int.parse(presenceHex, radix: 16);
      }
    }
    return (
      pairingHandle: pairingHandle,
      selfPrefix: selfPrefix,
      state: state,
      targetPrefix: '00000000',
      presenceByte: presenceByte,
    );
  }

  static List<int> _hexToBytes(String hex) {
    final normalized = hex.replaceAll('-', '');
    if (normalized.length.isOdd) {
      throw ArgumentError.value(
        hex,
        'hex',
        'must have an even number of chars',
      );
    }
    return List<int>.generate(
      normalized.length ~/ 2,
      (i) => int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16),
    );
  }

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
