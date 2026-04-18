// ─────────────────────────────────────────────────────────────────────────────
// friend_discovery_page.dart
//
// BLE 近场好友发现页面：
//   - 扫描附近设备，并在用户手动开启时短暂广播本机 UID
//   - 实时展示扫描到的候选好友列表（按 RSSI 排序，信号强的在前）
//   - 用户点击候选 → 确认添加到本地好友名册
//   - 底部展示已配对好友列表，可移除
//
// 页面退出时自动停止广播 + 扫描。
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/ble_service.dart';
import '../models/friend.dart';
import '../services/haptic_service.dart';

class FriendDiscoveryPage extends StatefulWidget {
  const FriendDiscoveryPage({super.key});

  @override
  State<FriendDiscoveryPage> createState() => _FriendDiscoveryPageState();
}

class _FriendDiscoveryPageState extends State<FriendDiscoveryPage> {
  final BleService _ble = BleService.instance;
  // 扫描窗口 20s — 与 BleService.startScan 的默认值对齐，避免两边不一致。
  static const Duration _scanDuration = Duration(seconds: 20);

  /// 扫描到的候选
  List<DiscoveredPeer> _peers = [];

  /// 已配对好友
  List<Friend> _friends = [];

  /// 状态
  bool _scanning = false;
  bool _advertising = false;
  bool _requestingPerm = false;
  bool _permanentlyDenied = false;
  String? _error;
  DateTime? _discoverableUntil;

  StreamSubscription<DiscoveredPeer>? _peerSub;
  StreamSubscription<String>? _incomingSub;
  Timer? _discoverabilityTicker;

  /// 最近一次把扫描结果同步到 _friends 的时刻 — 避免每个 peer 事件都读一次 Hive。
  DateTime _lastFriendsReload = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _friendsReloadMinInterval = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _initBle();
  }

  Future<void> _initBle() async {
    setState(() {
      _requestingPerm = true;
      _error = null;
      _permanentlyDenied = false;
    });

    final result = await _ble.requestPermissions();

    if (!mounted) return;
    setState(() => _requestingPerm = false);

    if (result == BlePermissionResult.denied ||
        result == BlePermissionResult.permanentlyDenied) {
      // Android 12+ 第二次拒绝后系统会自动当永久拒绝处理 ——
      // 这种情况下"重试"不会再弹窗，必须把用户引到系统设置。
      // 因此 UI 上对 denied 和 permanentlyDenied 都展示"打开设置"入口，
      // 只是文案略不同。
      setState(() {
        _permanentlyDenied = result == BlePermissionResult.permanentlyDenied;
        _error = _permanentlyDenied
            ? '蓝牙权限已被永久拒绝，请到系统设置中重新开启蓝牙 / 附近设备权限'
            : '需要蓝牙权限才能发现附近好友。\n如果点重试没有弹窗，请打开系统设置手动开启。';
      });
      return;
    }

    // 加载已有好友
    await _loadFriends();
    if (!mounted) return;

    // 默认只扫描。是否可被附近设备发现由用户手动开启。
    await _startDiscovery();
  }

  Future<void> _loadFriends() async {
    final friends = await _ble.listFriends();
    if (!mounted) return;
    setState(() => _friends = friends);
  }

  Future<void> _startDiscovery() async {
    // 扫描
    final scanOk = await _ble.startScan(timeout: _scanDuration);

    if (!mounted) return;
    setState(() {
      _advertising = _ble.isDiscoverable;
      _scanning = scanOk;
      _discoverableUntil = _ble.discoverableUntil;
    });

    if (!scanOk) {
      setState(() => _error = '无法启动蓝牙扫描');
      return;
    }

    // 监听扫描结果（_loadFriends 节流到 800ms，避免每个 RSSI 变化都打 Hive）
    await _peerSub?.cancel();
    _peerSub = _ble.discoveredPeers.listen((peer) {
      if (!mounted) return;
      setState(() {
        _peers = _ble.currentDiscovered;
      });
      final now = DateTime.now();
      if (now.difference(_lastFriendsReload) >= _friendsReloadMinInterval) {
        _lastFriendsReload = now;
        unawaited(_loadFriends());
      }
    });

    // 陌生 peer 主动 request → 写入本地 pendingIncoming 占位并 reload
    await _incomingSub?.cancel();
    _incomingSub = _ble.incomingRequests.listen((uid) async {
      if (!mounted) return;
      // 如果本地已有这条 friend 记录，ble_service 层已经更新了状态；
      // 这里只需刷新 UI。
      final existing = await _ble.findFriendByUid(uid);
      if (existing == null) {
        // 新陌生请求 — 作为 pendingIncoming 占位写入，但 displayName 用前 8 位
        // 作为默认；用户在 UI 上可以改名后确认（或直接删除）。
        await _ble.addFriend(
          uid: uid,
          displayName: uid.substring(0, 8),
          state: FriendState.pendingIncoming,
        );
      }
      await _loadFriends();
    });

    if (_advertising && _discoverableUntil != null) {
      _armDiscoverabilityTicker();
    }

    // 初始快照
    setState(() {
      _peers = _ble.currentDiscovered;
    });
  }

  Future<void> _toggleDiscoverability() async {
    HapticService.actionMenuSelect();

    if (_advertising) {
      await _ble.disableDiscoverability();
      _discoverabilityTicker?.cancel();
      _discoverabilityTicker = null;
      if (!mounted) return;
      setState(() {
        _advertising = false;
        _discoverableUntil = null;
      });
      _showToast('已关闭可被发现');
      return;
    }

    final ok = await _ble.setDiscoverable();
    if (!mounted) return;
    if (!ok) {
      _showToast('开启可被发现失败');
      return;
    }

    setState(() {
      _advertising = true;
      _discoverableUntil = _ble.discoverableUntil;
    });
    _armDiscoverabilityTicker();
    _showToast('已开启可被发现，5 分钟后自动关闭');
  }

  void _armDiscoverabilityTicker() {
    _discoverabilityTicker?.cancel();
    _discoverabilityTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final until = _ble.discoverableUntil;
      final active = _ble.isDiscoverable && until != null;
      if (!active) {
        _discoverabilityTicker?.cancel();
        _discoverabilityTicker = null;
        final wasAdvertising = _advertising;
        setState(() {
          _advertising = false;
          _discoverableUntil = null;
        });
        if (wasAdvertising) {
          _showToast('可被发现已自动关闭');
        }
        return;
      }

      setState(() {
        _advertising = true;
        _discoverableUntil = until;
      });
    });
  }

  Duration? get _discoverableRemaining {
    final until = _discoverableUntil;
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative) return Duration.zero;
    return remaining;
  }

  Future<void> _addPeer(DiscoveredPeer peer) async {
    HapticService.actionMenuSelect();

    final existingFriend = _friends.cast<Friend?>().firstWhere(
      (f) => f?.uid == peer.uid,
      orElse: () => null,
    );

    // 只有已完成互相确认时，才阻止再次添加
    if (existingFriend?.state == FriendState.confirmed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已经是好友了', style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF333333),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    // 确认对话框
    final displayName = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withAlpha(120),
      builder: (ctx) => _ConfirmAddDialog(
        uid: peer.uid,
        initialName: peer.displayTag?.replaceFirst('@', ''),
      ),
    );
    if (displayName == null || !mounted) return;
    final trimmedName = displayName.trim().isEmpty
        ? peer.uid.substring(0, 8)
        : displayName.trim();

    if (peer.handshakeState == PeerHandshakeState.request) {
      await _ble.confirmFriendRequest(
        uid: peer.uid,
        displayName: trimmedName,
        rssi: peer.rssi,
      );
      HapticService.lineAdded();
      _showToast('已确认 $trimmedName，等待对方完成同步');
    } else {
      await _ble.addFriend(
        uid: peer.uid,
        displayName: trimmedName,
        rssi: peer.rssi,
        state: FriendState.pendingOutgoing,
      );
      // 先确保正在广播（若用户没手动开启），再切换 payload 成 request。
      if (!_ble.isDiscoverable) {
        await _ble.setDiscoverable();
      }
      await _ble.updateBroadcastHandshake(
        state: PeerHandshakeState.request,
        targetUidPrefix: peer.uid.substring(0, 8).toLowerCase(),
      );
      HapticService.lineAdded();
      _showToast('已向 $trimmedName 发送好友请求');
    }

    await _loadFriends();
    if (!mounted) return;

    // 从候选列表移除
    setState(() {
      _peers = _peers.where((p) => p.uid != peer.uid).toList();
    });
    if (!mounted) return;
    setState(() {
      _advertising = _ble.isDiscoverable;
      _discoverableUntil = _ble.discoverableUntil;
    });
    if (_advertising) {
      _armDiscoverabilityTicker();
    }
  }

  Future<void> _removeFriend(Friend friend) async {
    HapticService.actionMenuOpen();
    await _ble.removeFriend(friend);
    await _loadFriends();
    if (!mounted) return;
    _showToast('已移除好友 ${friend.displayName}');
  }

  /// 长按好友卡 → 本地重命名（只改本机备注，不广播、不上传）
  Future<void> _renameFriend(Friend friend) async {
    HapticService.actionMenuOpen();
    final newName = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withAlpha(180),
      builder: (ctx) => _RenameFriendDialog(initial: friend.displayName),
    );
    if (!mounted) return;
    if (newName == null) return; // 用户取消
    await _ble.renameFriend(friend, newName);
    await _loadFriends();
    if (!mounted) return;
    HapticService.lineAdded();
    _showToast('已重命名为 ${friend.displayName}');
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF222222),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  void dispose() {
    _discoverabilityTicker?.cancel();
    _peerSub?.cancel();
    _incomingSub?.cancel();
    _ble.stopScan();
    _ble.disableDiscoverability();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white70,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '发现好友',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w400,
            letterSpacing: 1,
          ),
        ),
        actions: [
          if (_scanning || _advertising)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _PulseDot(active: _scanning),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_requestingPerm) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
            SizedBox(height: 16),
            Text(
              '正在请求蓝牙权限 …',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.bluetooth_disabled,
                color: Colors.white24,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white38, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: _initBle,
                    child: const Text(
                      '重试',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  // Android 12+ 第二次拒绝后就自动永久拒绝，重试不会再弹窗。
                  // 因此"打开设置"无论是否 permanentlyDenied 都提供 —— 保证
                  // 用户不会卡在"点重试没反应"的状态。
                  TextButton(
                    onPressed: openAppSettings,
                    child: const Text(
                      '打开设置',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      backgroundColor: const Color(0xFF222222),
      color: Colors.white54,
      onRefresh: () async {
        await _ble.stopScan();
        await _startDiscovery();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // ── 状态提示 ──
          _buildStatusHint(),
          const SizedBox(height: 24),
          _buildDiscoverabilityCard(),
          const SizedBox(height: 24),

          // ── 附近的人 ──
          if (_peers.isNotEmpty) ...[
            const Text(
              '附近的人',
              style: TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            ..._peers.map((p) => _PeerCard(peer: p, onTap: () => _addPeer(p))),
            const SizedBox(height: 28),
          ] else if (_scanning) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 32),
                child: Column(
                  children: [
                    _ScanningWave(),
                    SizedBox(height: 16),
                    Text(
                      '正在扫描附近 …',
                      style: TextStyle(color: Colors.white24, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const _DiscoveryHint(),
          ],

          // ── 已配对好友 ──
          if (_friends.isNotEmpty) ...[
            const Text(
              '已配对',
              style: TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            // 目前扫描到的 uid 集合 — 用来给"近场"好友卡片亮起柔和的脉动灯。
            // 每次 build 都重新计算，开销极小（_peers 长度通常 < 20）。
            ...(() {
              final nearbyUids = <String>{for (final p in _peers) p.uid};
              return _friends.map(
                (f) => _FriendCard(
                  friend: f,
                  isNearby: nearbyUids.contains(f.uid),
                  onRemove: () => _removeFriend(f),
                  onRename: () => _renameFriend(f),
                ),
              );
            })(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusHint() {
    String text;
    if (_advertising && _scanning) {
      final remaining = _discoverableRemaining;
      final mm = remaining == null
          ? '--'
          : remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
      final ss = remaining == null
          ? '--'
          : remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
      text = '正在扫描，且本机可被发现（$mm:$ss 后自动关闭）';
    } else if (_scanning) {
      text = '正在扫描附近。默认不会广播自己，需要时请手动开启“可被发现”';
    } else if (_advertising) {
      text = '本机可被发现，但扫描未启动';
    } else {
      text = '下拉刷新重新扫描';
    }
    return Text(
      text,
      style: const TextStyle(
        color: Color(0x44FFFFFF),
        fontSize: 12,
        fontWeight: FontWeight.w300,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildDiscoverabilityCard() {
    final remaining = _discoverableRemaining;
    final countdown = remaining == null
        ? '默认关闭'
        : '${remaining.inMinutes.remainder(60).toString().padLeft(2, '0')}:${remaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _advertising
              ? const Color(0x334CD964)
              : const Color(0x18FFFFFF),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _advertising ? '本机可被附近好友发现' : '本机当前不可被发现',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _advertising
                      ? '倒计时 $countdown，结束后会自动关闭'
                      : '需要时手动开启 5 分钟，避免长期广播',
                  style: const TextStyle(
                    color: Color(0x77FFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: _toggleDiscoverability,
            style: FilledButton.styleFrom(
              backgroundColor: _advertising
                  ? const Color(0x224CD964)
                  : const Color(0x22FFFFFF),
              foregroundColor: Colors.white,
              minimumSize: const Size(92, 40),
            ),
            child: Text(_advertising ? '关闭' : '开启'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 子组件
// ═══════════════════════════════════════════════════

class _PeerCard extends StatelessWidget {
  final DiscoveredPeer peer;
  final VoidCallback onTap;

  const _PeerCard({required this.peer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIncomingRequest = peer.handshakeState == PeerHandshakeState.request;
    // RSSI 信号强度指示
    final signal = peer.rssi > -50
        ? '强'
        : peer.rssi > -70
        ? '中'
        : '弱';
    final signalColor = peer.rssi > -50
        ? const Color(0xFF4CD964)
        : peer.rssi > -70
        ? const Color(0xFFFFCC00)
        : const Color(0xFFFF3B30);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Row(
          children: [
            // 头像占位（取 uid 前 1 位做颜色种子）
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Color.fromRGBO(
                  (peer.uid.hashCode & 0xFF),
                  ((peer.uid.hashCode >> 8) & 0xFF),
                  ((peer.uid.hashCode >> 16) & 0xFF),
                  0.6,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  peer.uid.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peer.displayTag ?? peer.uid.substring(0, 8),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: signalColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '信号 $signal  (${peer.rssi} dBm)',
                            style: TextStyle(
                              color: signalColor.withAlpha(180),
                              fontSize: 11,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ],
                      ),
                      if (isIncomingRequest) ...[
                        const SizedBox(height: 4),
                        const Text(
                          '对方已请求添加你，点按确认',
                          style: TextStyle(
                            color: Color(0xFF9CD67A),
                            fontSize: 11,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              isIncomingRequest
                  ? Icons.verified_outlined
                  : Icons.add_circle_outline,
              color: isIncomingRequest
                  ? const Color(0xAA9CD67A)
                  : const Color(0x66FFFFFF),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendCard extends StatefulWidget {
  final Friend friend;

  /// 当前是否在 BLE 扫描的近场列表里 —— 控制状态灯是否脉动
  final bool isNearby;
  final VoidCallback onRemove;

  /// 长按卡片 → 本地重命名（可选；测试或旧调用路径可不传）
  final VoidCallback? onRename;

  const _FriendCard({
    required this.friend,
    required this.onRemove,
    this.isNearby = false,
    this.onRename,
  });

  @override
  State<_FriendCard> createState() => _FriendCardState();
}

class _FriendCardState extends State<_FriendCard>
    with SingleTickerProviderStateMixin {
  /// 柔和脉动 — 2 秒一周期，reverse，只在 `isNearby=true` 时 repeat。
  /// 动画振幅控制在 alpha 0.35 ↔ 0.95，避免扎眼。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isNearby) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _FriendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isNearby != oldWidget.isNearby) {
      if (widget.isNearby) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 状态灯颜色：已确认好友 = 柔白；未确认态 = 暖黄提示。
    final baseLedColor = widget.friend.state == FriendState.confirmed
        ? const Color(0xFFEAEAEA)
        : const Color(0xFFE6C77A);

    return GestureDetector(
      // 长按只在卡片区域生效；子级的「关闭」按钮保留原 onTap。
      onLongPress: widget.onRename,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x11FFFFFF)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Color.fromRGBO(
                  (widget.friend.uid.hashCode & 0xFF),
                  ((widget.friend.uid.hashCode >> 8) & 0xFF),
                  ((widget.friend.uid.hashCode >> 16) & 0xFF),
                  0.4,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.friend.displayName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.friend.displayName,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    switch (widget.friend.state) {
                      FriendState.confirmed =>
                        '已互相确认 · ${widget.friend.pairedAt.month}/${widget.friend.pairedAt.day}',
                      FriendState.pendingOutgoing => '等待对方确认',
                      FriendState.pendingIncoming => '对方请求你确认',
                    },
                    style: const TextStyle(
                      color: Color(0x44FFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
            // 近场指示灯 — 在范围内缓慢脉动；不在范围内保持静态暗点
            _NearbyPulseDot(
              controller: _pulse,
              isNearby: widget.isNearby,
              baseColor: baseLedColor,
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: widget.onRemove,
              child:
                  const Icon(Icons.close, color: Color(0x44FFFFFF), size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// 好友卡片右侧的近场脉动小灯（8×8）。
/// - `isNearby=false`：静态、低亮度（alpha ~0.18），和整体灰度界面融为一体
/// - `isNearby=true` ：在 alpha 0.35 ↔ 0.95 之间缓慢呼吸，周期 2s reverse
class _NearbyPulseDot extends StatelessWidget {
  final AnimationController controller;
  final bool isNearby;
  final Color baseColor;

  const _NearbyPulseDot({
    required this.controller,
    required this.isNearby,
    required this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!isNearby) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: baseColor.withAlpha(46), // ~0.18
          shape: BoxShape.circle,
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        // Curves.easeInOut 让呼吸节奏更柔和
        final t = Curves.easeInOut.transform(controller.value);
        final alpha = (0.35 + 0.60 * t).clamp(0.0, 1.0);
        final glowAlpha = (0.10 + 0.22 * t).clamp(0.0, 1.0);
        return SizedBox(
          width: 16,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 外层柔和光晕
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: baseColor.withValues(alpha: glowAlpha * 0.35),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: baseColor.withValues(alpha: alpha),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 本地重命名好友对话框 —— 极简风格，与其他 sheet 一致。
class _RenameFriendDialog extends StatefulWidget {
  final String initial;
  const _RenameFriendDialog({required this.initial});

  @override
  State<_RenameFriendDialog> createState() => _RenameFriendDialogState();
}

class _RenameFriendDialogState extends State<_RenameFriendDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A0A0A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '本地备注名',
              style: TextStyle(
                color: Color(0xDDFFFFFF),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '仅保存在本机，不会同步',
              style: TextStyle(
                color: Color(0x55FFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 24,
              cursorColor: const Color(0xCCFFFFFF),
              style: const TextStyle(
                color: Color(0xEEFFFFFF),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0x22FFFFFF)),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0x66FFFFFF)),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Color(0x88FFFFFF), fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, _controller.text),
                  child: const Text(
                    '保存',
                    style: TextStyle(color: Color(0xFFEAEAEA), fontSize: 13),
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

class _ConfirmAddDialog extends StatefulWidget {
  final String uid;
  final String? initialName;
  const _ConfirmAddDialog({required this.uid, this.initialName});

  @override
  State<_ConfirmAddDialog> createState() => _ConfirmAddDialogState();
}

class _ConfirmAddDialogState extends State<_ConfirmAddDialog> {
  late final TextEditingController _controller;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialName ?? widget.uid.substring(0, 8),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    _submitted = true;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        width: 304,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '添加好友',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.uid.substring(0, 8),
              style: const TextStyle(
                color: Color(0xAAFFFFFF),
                fontSize: 18,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '给对方起个你一眼就认得出的名字',
              style: TextStyle(
                color: Color(0x77FFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              cursorColor: Colors.white,
              textInputAction: TextInputAction.done,
              maxLength: 12,
              buildCounter:
                  (
                    _, {
                    required int currentLength,
                    required bool isFocused,
                    required int? maxLength,
                  }) => null,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w300,
              ),
              decoration: const InputDecoration(
                hintText: '输入好友名称',
                hintStyle: TextStyle(
                  color: Color(0x44FFFFFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w300,
                ),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0x33FFFFFF), width: 0.8),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0x33FFFFFF), width: 0.8),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Color(0xAAFFFFFF), width: 1.0),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text(
                    '取消',
                    style: TextStyle(color: Color(0x66FFFFFF)),
                  ),
                ),
                TextButton(
                  onPressed: _submit,
                  child: const Text(
                    '添加',
                    style: TextStyle(color: Colors.white),
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

/// 顶部脉冲指示灯
class _PulseDot extends StatefulWidget {
  final bool active;
  const _PulseDot({required this.active});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final alpha = 0.3 + _ctrl.value * 0.7;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Color.fromRGBO(76, 217, 100, alpha),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

/// 扫描波纹动画
class _ScanningWave extends StatefulWidget {
  const _ScanningWave();

  @override
  State<_ScanningWave> createState() => _ScanningWaveState();
}

class _ScanningWaveState extends State<_ScanningWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 三层波纹
              for (int i = 0; i < 3; i++)
                _Ring(progress: (_ctrl.value + i * 0.33) % 1.0),
              // 中心点
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0x88FFFFFF),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiscoveryHint extends StatelessWidget {
  const _DiscoveryHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E0E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: const Text(
        '如果暂时没看到对方，请确认双方都打开了此页面，并至少有一台设备已开启“可被发现”。',
        style: TextStyle(
          color: Color(0x66FFFFFF),
          fontSize: 12,
          fontWeight: FontWeight.w300,
          height: 1.45,
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final double progress;
  const _Ring({required this.progress});

  @override
  Widget build(BuildContext context) {
    final scale = 0.3 + progress * 0.7;
    final alpha = (1.0 - progress) * 0.4;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Color.fromRGBO(255, 255, 255, alpha),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
