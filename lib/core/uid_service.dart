// ─────────────────────────────────────────────────────────────────────────────
// uid_service.dart
//
// 模块定位（CORE REQ 1）：
//   应用首次启动时生成一枚**加密强随机 UUID v4**，
//   并写入原生安全存储（iOS Keychain / Android Keystore-backed EncryptedSharedPreferences）。
//   此 UID 是「迹点」整个本地架构的根：
//     - 作为根密钥材料（派生 Hive AES 主密钥 + 签名密钥）
//     - 作为用户身份（BLE 配对时交换）
//
// 关键性质：
//   * 绝不落盘到 Hive / SharedPreferences / 文件 — 只存 Keychain/Keystore。
//   * 卸载后不会自动删除（依赖平台策略：iOS Keychain accessibility 为 first_unlock_this_device，
//     Android 使用 EncryptedSharedPreferences）；即便 App 数据清空，UID 仍会保留直到用户手动清除。
//   * 单例：全局只有一份 UID，一次启动派生所有密钥。
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// 安全存储可用性异常。
///
/// 这是高风险错误：如果把它当作“UID 不存在”处理，就可能生成新 UID，
/// 进一步导致 Hive 派生出不同的加密密钥，使旧数据看起来像“损坏”。
class UidSecureStorageException implements Exception {
  final String message;
  final Object? cause;

  const UidSecureStorageException(this.message, [this.cause]);

  @override
  String toString() => cause == null
      ? 'UidSecureStorageException: $message'
      : 'UidSecureStorageException: $message ($cause)';
}

/// 统一的安全存储实例（iOS Keychain / Android EncryptedSharedPreferences）
class _SecureStoreFactory {
  static const IOSOptions _iosOpts = IOSOptions(
    // 首次解锁后方可访问；不随 iCloud Keychain 同步。
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  static const AndroidOptions _androidOpts = AndroidOptions(
    encryptedSharedPreferences: true,
    // 使用 Android Keystore-backed 加密（由 flutter_secure_storage 默认实现）
    resetOnError: false,
  );

  static FlutterSecureStorage create() =>
      const FlutterSecureStorage(iOptions: _iosOpts, aOptions: _androidOpts);
}

/// UID 读写 + 生成服务。
/// 全 App 使用单例，首次启动后 UID 即永久固定。
class UidService {
  UidService._();

  static final UidService instance = UidService._();

  /// Keychain/Keystore 中存 UID 的键名。
  /// 带 `trail.` 前缀避免与其它 App 冲突（iOS Keychain 是按 bundle-id 隔离的，
  /// 但加前缀保留未来可读性）。
  static const String _kUidKey = 'trail.core.uid.v1';
  static const String _kHandleKey = 'trail.core.handle.v1';
  static const int _handleLength = 6;
  static final RegExp _handleRe = RegExp(r'^[A-Za-z_]{6}$');
  static const String _handleAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_';

  /// UUID v4 正则（严格 — 版本位必须是 4，variant 位必须是 8/9/a/b）
  static final RegExp _uuidV4Re = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final FlutterSecureStorage _store = _SecureStoreFactory.create();
  String? _cachedUid;
  String? _cachedHandle;

  /// 是否已初始化完成（UID 已在内存中）
  bool get isReady => _cachedUid != null;
  String get pairingHandle {
    final v = _cachedHandle;
    if (v == null) {
      throw StateError(
        'UidService.pairingHandle accessed before initialize(). '
        'Call UidService.instance.initialize() during app bootstrap.',
      );
    }
    return v;
  }

  /// 当前设备 UID；必须先调用 [initialize]。
  String get uid {
    final v = _cachedUid;
    if (v == null) {
      throw StateError(
        'UidService.uid accessed before initialize(). '
        'Call UidService.instance.initialize() during app bootstrap.',
      );
    }
    return v;
  }

  /// 读取（或在首次启动时生成并写入）UID。
  /// 幂等：多次调用不会覆盖已有 UID。
  Future<String> initialize() async {
    if (_cachedUid != null) return _cachedUid!;

    // 1) 尝试读取已存在的 UID
    String? existing;
    try {
      existing = await _store.read(key: _kUidKey);
    } catch (e) {
      debugPrint('[UidService] secure storage read failed: $e');
      throw UidSecureStorageException(
        'failed to read uid from secure storage',
        e,
      );
    }

    if (existing != null && _uuidV4Re.hasMatch(existing.trim())) {
      _cachedUid = existing.trim().toLowerCase();
      _cachedHandle = await _loadOrCreateHandle();
      debugPrint('[UidService] existing UID loaded');
      return _cachedUid!;
    }

    if (existing != null && existing.trim().isNotEmpty) {
      throw UidSecureStorageException('uid in secure storage is malformed');
    }

    // 2) 不存在或格式不合法 → 生成新 UID
    //    仅在“确实没有旧 UID”时允许生成。
    final fresh = const Uuid().v4();
    assert(_uuidV4Re.hasMatch(fresh), 'uuid.v4() produced non-v4 value');

    try {
      await _store.write(key: _kUidKey, value: fresh);
    } catch (e) {
      debugPrint('[UidService] secure storage write failed: $e');
      throw UidSecureStorageException('failed to persist generated uid', e);
    }
    _cachedUid = fresh;
    _cachedHandle = await _loadOrCreateHandle();
    debugPrint('[UidService] new UID generated & stored');
    return _cachedUid!;
  }

  Future<String> _loadOrCreateHandle() async {
    try {
      final existing = await _store.read(key: _kHandleKey);
      if (existing != null && _handleRe.hasMatch(existing.trim())) {
        return existing.trim();
      }
    } catch (e) {
      debugPrint('[UidService] secure storage handle read failed: $e');
      throw UidSecureStorageException(
        'failed to read pairing handle from secure storage',
        e,
      );
    }

    final random = Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < _handleLength; i++) {
      buffer.write(_handleAlphabet[random.nextInt(_handleAlphabet.length)]);
    }
    final handle = buffer.toString();

    try {
      await _store.write(key: _kHandleKey, value: handle);
    } catch (e) {
      debugPrint('[UidService] secure storage handle write failed: $e');
      throw UidSecureStorageException('failed to persist pairing handle', e);
    }
    return handle;
  }

  /// 仅供调试/自测使用；生产代码不应调用。
  @visibleForTesting
  Future<void> debugReset() async {
    _cachedUid = null;
    _cachedHandle = null;
    await _store.delete(key: _kUidKey);
    await _store.delete(key: _kHandleKey);
  }

  Future<void> resetForWipe() async {
    await debugReset();
  }
}
