// ─────────────────────────────────────────────────────────────────────────────
// friend.dart
//
// 模块定位（支撑 CORE REQ 4 — BLE 配对）：
//   已配对好友的本地记录。
//   仅存在于本机 Hive（加密盒）中，永不上云。
//
//   字段设计：
//     - uid        : 对方设备的 UUID v4（通过 BLE 广播交换）
//     - displayName: 本地昵称（用户自行设置；默认用 uid 前 8 位）
//     - pairedAt   : 本机记录时间（由 TimeIntegrityService 决定）
//     - rssi       : 最近一次扫描到的信号强度（dBm，可选；方便排序「附近的人」）
//
// 为什么手写 TypeAdapter 而不是用 build_runner：
//   1. 避免每次 schema 微调都跑 codegen，节省 CI 时间。
//   2. 让二进制格式对维护者完全可控 — 未来 v2 升级时我们知道每个字节的来历。
//   3. 此类字段少且稳定，手写成本低。
//
// typeId 分配：
//   Birthday=0 / TrailLine=1 / Friend=10（中间保留给未来其他核心模型）
// ─────────────────────────────────────────────────────────────────────────────

import 'package:hive/hive.dart';

/// 本地好友状态机（PRD v1.0.2 §4.2 / §6）
///
/// 语义：
///   · pendingOutgoing — 我已发起添加，正在广播 request 等对方确认
///   · pendingIncoming — 对方已发起添加（我扫到了对方的 request），等我确认
///   · confirmed       — 双方已完成本次会面内的互相确认
///
/// 磁盘 index（持久化顺序，**不可重排**；新增值只能追加在末尾）：
///   0 = pendingOutgoing
///   1 = confirmed
///   2 = pendingIncoming ← 新增
///
/// 旧版本（只写过 0/1）的数据经 [FriendAdapter._decodeState] 映射：
///   缺字段/非法 index → confirmed（保守：不让用户看到幽灵 pending）
enum FriendState { pendingOutgoing, confirmed, pendingIncoming }

/// 已配对好友（本地）
class Friend extends HiveObject {
  /// 对方设备 UUID v4（小写，36 字符）
  final String uid;

  /// 本地昵称 — 用户可改，默认 uid 前 8 位
  String displayName;

  /// 本机记录的配对时间
  final DateTime pairedAt;

  /// 最近一次扫描时的 RSSI（dBm）；未扫描过为 null
  int? rssi;

  /// 本地好友状态：
  ///   - pendingOutgoing: 我已发起添加，等待对方确认
  ///   - confirmed: 双方已完成本次会面内的互相确认
  FriendState state;

  /// 本机打卡日集合（dateKey `YYYY-MM-DD`）
  ///
  /// 仅当对方 BLE 在范围内时允许在今日节点上登记一次。
  /// 过去的打卡不可撤销 —— 见 constellation.md "反游戏化" 决策。
  List<String> checkInDates;

  Friend({
    required this.uid,
    required this.displayName,
    required this.pairedAt,
    this.rssi,
    this.state = FriendState.confirmed,
    List<String>? checkInDates,
  }) : checkInDates = checkInDates ?? <String>[];
}

/// 手写 TypeAdapter（不依赖 build_runner）
///
/// 二进制布局（按 writeByte 顺序）：
///   field 0 : String  uid
///   field 1 : String  displayName
///   field 2 : int     pairedAt.millisecondsSinceEpoch (UTC)
///   field 3 : int?    rssi
///   field 4 : int     state.index
///   field 5 : `List<String>` checkInDates  (v2 新增；旧数据缺字段 → 空列表)
class FriendAdapter extends TypeAdapter<Friend> {
  @override
  final int typeId = 10;

  @override
  Friend read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return Friend(
      uid: fields[0] as String,
      displayName: fields[1] as String,
      pairedAt: DateTime.fromMillisecondsSinceEpoch(
        fields[2] as int,
        isUtc: true,
      ).toLocal(),
      rssi: fields[3] as int?,
      state: _decodeState(fields[4]),
      checkInDates: (fields[5] as List?)?.whereType<String>().toList(),
    );
  }

  /// 把磁盘上的 int 解回 [FriendState]。
  /// 防御三种情况：
  ///   · 缺字段（旧版本）→ confirmed
  ///   · 非 int 类型      → confirmed
  ///   · 索引超界（未来版本新增了枚举值 + 用户降级回旧 App）→ confirmed
  /// 绝不 `values[...]` 直接取，避免 RangeError 把整个盒子的读取带崩。
  static FriendState _decodeState(dynamic raw) {
    if (raw is int && raw >= 0 && raw < FriendState.values.length) {
      return FriendState.values[raw];
    }
    return FriendState.confirmed;
  }

  @override
  void write(BinaryWriter writer, Friend obj) {
    writer
      ..writeByte(6) // 6 个字段
      ..writeByte(0)
      ..write(obj.uid)
      ..writeByte(1)
      ..write(obj.displayName)
      ..writeByte(2)
      ..write(obj.pairedAt.toUtc().millisecondsSinceEpoch)
      ..writeByte(3)
      ..write(obj.rssi)
      ..writeByte(4)
      ..write(obj.state.index)
      ..writeByte(5)
      ..write(obj.checkInDates);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
