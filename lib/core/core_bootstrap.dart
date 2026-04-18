// ─────────────────────────────────────────────────────────────────────────────
// core_bootstrap.dart
//
// 模块定位：
//   应用启动时必须按顺序初始化的核心服务的编排入口。
//   在 `main.dart` 的 `StorageService.init()` **之前**调用，
//   因为 Hive box 的打开依赖 SecureBoxService 产出的 AES cipher。
//
// 顺序依赖：
//   UidService          → 必须最先，后续所有密钥都派生自 UID
//   TimeIntegrityService → 依赖 UID 派生签名密钥；并做时钟回拨检测
//   SecureBoxService    → 依赖 UID 派生 AES 密钥；为后续 Hive 打开提供 cipher
//
// 只读 / 无副作用（除了 Keychain 写一次 UID 和更新 last-seen-epoch）。
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/friend.dart';
import 'secure_box_service.dart';
import 'time_integrity_service.dart';
import 'uid_service.dart';

class CoreBootstrap {
  CoreBootstrap._();

  static void _log(String msg) {
    assert(() {
      debugPrint('[CoreBootstrap] $msg');
      return true;
    }());
  }

  /// 幂等；main() 里 await 一次即可。
  ///
  /// 顺序（不可交换）：
  ///   1. Hive.initFlutter              — 绑定 Hive 到 app 文档目录
  ///   2. 注册 FriendAdapter (typeId 10) — SecureBoxService 内部会用到 friends 盒
  ///   3. UidService                    — 后续所有密钥的根
  ///   4. TimeIntegrityService          — 依赖 UID 派生签名密钥 & 时钟回拨检测
  ///   5. SecureBoxService              — 为后续 Hive 打开提供 AES cipher
  static Future<void> initialize() async {
    _log('begin');

    // Hive 初始化（幂等）— 唯一真理点：本文件负责 Hive.initFlutter，
    // StorageService.init() 不再重复调用。这样做避免 iOS 26 上偶发的启动
    // 阻塞，也让“谁在初始化 Hive”一眼可见。
    await Hive.initFlutter();
    _log('Hive.initFlutter done');

    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(FriendAdapter());
    }

    await UidService.instance.initialize();
    _log('UidService ready');

    await TimeIntegrityService.instance.initialize();
    _log('TimeIntegrityService ready (tampered=${TimeIntegrityService.instance.tampered})');

    await SecureBoxService.instance.initialize();
    _log('SecureBoxService ready');
  }
}
