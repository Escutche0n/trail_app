// ─────────────────────────────────────────────────────────────────────────────
// secure_box_service.dart
//
// 模块定位（CORE REQ 3）：
//   1. 提供所有 Hive 盒子使用的 AES-256 密钥 / HiveAesCipher。
//      → 每个盒子物理上加密在磁盘上（SQLite/文件被外部拿到也无法读）。
//   2. 提供 `.trail` 本地备份的导出 / 导入：
//      - 导出：读取 birthday / custom_lines / trail_data / friends 的明文 JSON，
//              打包成 `{v:1, magic, body, sig}` 信封（signature = HMAC-SHA256）。
//      - 导入：验签 → 任何一字节被篡改都会失败 → 失败直接拒绝。
//      - 整个过程 100% 本地；文件选择用 file_picker（Android SAF / iOS DocumentPicker）。
//
// 设计决定：
//   - 备份文件用 UTF-8 JSON（而非二进制），内容可审计、跨版本升级友好。
//   - 备份文件本身**不**加密 — 因为签名就足以保证「完整性 + 来自本设备」。
//     如果用户想要加密，可以把 .trail 再放进 iCloud/Google Drive 的加密区（系统级）。
//     （若未来产品决策要加密，切入口是 `_wrapEnvelope` / `_unwrapEnvelope`。）
//   - Hive box 的密钥与备份签名密钥**不同**（域分离），防止横向破解。
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/birthday.dart';
import '../models/friend.dart';
import '../models/trail_line.dart';
import 'crypto_utils.dart';
import 'time_integrity_service.dart';
import 'uid_service.dart';

/// 备份导入结果
enum BackupImportResult {
  ok,
  fileNotFound,
  badMagic,
  badVersion,
  signatureMismatch,
  corruptJson,
  ioError,
}

/// 统一管理 Hive 加密密钥 + 备份导入导出
class SecureBoxService {
  SecureBoxService._();

  static final SecureBoxService instance = SecureBoxService._();

  // ── 备份文件格式常量 ───────────────────────────────
  static const String backupMagic = 'TRAIL_BACKUP';
  static const int backupVersion = 1;
  static const String backupFileExt = 'trail';

  HiveAesCipher? _cipher;
  bool _ready = false;

  bool get isReady => _ready;

  /// Hive 专用密码器；给 `Hive.openBox(encryptionCipher: ...)` 用
  HiveAesCipher get cipher {
    final c = _cipher;
    if (c == null) {
      throw StateError(
        'SecureBoxService used before initialize(). '
        'Call SecureBoxService.instance.initialize() during bootstrap.',
      );
    }
    return c;
  }

  /// 必须在 UidService.initialize() 之后调用
  Future<void> initialize() async {
    if (_ready) return;
    final uid = UidService.instance.uid;
    final aesKey = CryptoUtils.deriveAesKey(uid); // 32 bytes → AES-256
    _cipher = HiveAesCipher(aesKey);
    _ready = true;
  }

  /// 便捷：打开一个带 AES 加密的 Hive Box
  Future<Box<T>> openEncryptedBox<T>(String name) {
    return Hive.openBox<T>(name, encryptionCipher: cipher);
  }

  /// 便捷：打开一个不带类型参数的加密 Box
  Future<Box> openEncryptedRawBox(String name) {
    return Hive.openBox(name, encryptionCipher: cipher);
  }

  // ── 导出 ────────────────────────────────────────────

  /// 收集当前所有盒子的明文快照，返回 UTF-8 编码的 `.trail` 文件内容。
  /// 调用方把返回值写到用户选定的位置即可。
  Future<List<int>> buildBackupBytes() async {
    final body = await _collectSnapshot();
    final bodyJson = jsonEncode(body);
    final sigKey = CryptoUtils.deriveSigKey(UidService.instance.uid);
    final sig = CryptoUtils.hmacSha256Hex(sigKey, utf8.encode(bodyJson));
    // exportedAt 走 TimeIntegrityService — tampered 时记录 clamp 后的时间，
    // 保证备份里的时间戳不会因用户当下改了系统时间而失真。
    final exportedAtMs = TimeIntegrityService.instance.isReady
        ? TimeIntegrityService.instance.now().toUtc().millisecondsSinceEpoch
        : DateTime.now().toUtc().millisecondsSinceEpoch;
    final envelope = {
      'magic': backupMagic,
      'v': backupVersion,
      'exportedAt': exportedAtMs,
      'uid': UidService.instance.uid, // 不敏感（UID 本身不是密钥，只是身份标识）
      'body': body,
      'sig': sig,
    };
    return utf8.encode(jsonEncode(envelope));
  }

  /// 便捷：把备份写到 App 文档目录的默认路径，返回文件对象。
  /// 用户想分享时再用 file_picker / share_plus 导出到外部。
  Future<File> writeDefaultBackupFile() async {
    final bytes = await buildBackupBytes();
    final dir = await getApplicationDocumentsDirectory();
    // 文件名里的时间戳也用 TimeIntegrity — 避免篡改时文件名对不上 exportedAt。
    final stampSource = TimeIntegrityService.instance.isReady
        ? TimeIntegrityService.instance.now()
        : DateTime.now();
    final stamp = stampSource.toIso8601String().replaceAll(':', '-');
    final f = File('${dir.path}/trail-backup-$stamp.$backupFileExt');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// 采集四个盒子的全量明文快照
  Future<Map<String, dynamic>> _collectSnapshot() async {
    final birthdayBox = Hive.box<Birthday>('birthday');
    final linesBox = Hive.box<TrailLine>('custom_lines');
    final dataBox = Hive.box('trail_data');
    final friendsBox = Hive.isBoxOpen('friends')
        ? Hive.box<Friend>('friends')
        : await openEncryptedBox<Friend>('friends');

    return {
      'birthday': birthdayBox.values
          .map((b) => {'date': b.date.toUtc().millisecondsSinceEpoch})
          .toList(),
      'custom_lines': linesBox.values
          .map(
            (l) => {
              'id': l.id,
              'typeIndex': l.typeIndex,
              'name': l.name,
              'createdAt': l.createdAt.toUtc().millisecondsSinceEpoch,
              'completedDates': l.completedDates,
              'notes': l.notes,
              'archived': l.archived,
              'archivedAt': l.archivedAt?.toUtc().millisecondsSinceEpoch,
            },
          )
          .toList(),
      'trail_data': {
        for (final k in dataBox.keys) k.toString(): _jsonSafe(dataBox.get(k)),
      },
      'friends': friendsBox.values
          .map(
            (f) => {
              'uid': f.uid,
              'displayName': f.displayName,
              'pairedAt': f.pairedAt.toUtc().millisecondsSinceEpoch,
              'rssi': f.rssi,
              'stateIndex': f.state.index,
            },
          )
          .toList(),
    };
  }

  /// 将 Hive 中可能出现的非 JSON 原生类型（DateTime 等）转换为 JSON-safe
  dynamic _jsonSafe(dynamic v) {
    if (v == null || v is num || v is bool || v is String) return v;
    if (v is DateTime) return v.toUtc().millisecondsSinceEpoch;
    if (v is List) return v.map(_jsonSafe).toList();
    if (v is Map) {
      return {for (final e in v.entries) e.key.toString(): _jsonSafe(e.value)};
    }
    return v.toString();
  }

  // ── 导入 ────────────────────────────────────────────

  /// 从 `.trail` 文件字节导入（先验签，再覆盖本地 Hive）。
  /// 任何一字节被篡改 → 返回 [BackupImportResult.signatureMismatch]，不会写入数据。
  Future<BackupImportResult> importBackupBytes(List<int> bytes) async {
    // 1) 解包
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return BackupImportResult.corruptJson;
    }

    if (envelope['magic'] != backupMagic) return BackupImportResult.badMagic;
    if (envelope['v'] is! num ||
        (envelope['v'] as num).toInt() != backupVersion) {
      return BackupImportResult.badVersion;
    }

    final body = envelope['body'];
    final sig = envelope['sig'];
    if (body is! Map || sig is! String) return BackupImportResult.corruptJson;

    // 2) 验签（用当前设备 UID 派生的签名密钥 — 所以备份只能在同一设备恢复）
    final bodyJson = jsonEncode(body);
    final sigKey = CryptoUtils.deriveSigKey(UidService.instance.uid);
    final expected = CryptoUtils.hmacSha256(sigKey, utf8.encode(bodyJson));
    final given = CryptoUtils.fromHex(sig);
    if (given.isEmpty || !CryptoUtils.constantTimeEquals(expected, given)) {
      return BackupImportResult.signatureMismatch;
    }

    // 3) 写入 — 先清空各盒子再写，保证幂等
    try {
      await _restoreSnapshot(body.cast<String, dynamic>());
      return BackupImportResult.ok;
    } catch (e, st) {
      debugPrint('[SecureBox] restore failed: $e\n$st');
      return BackupImportResult.ioError;
    }
  }

  /// 从磁盘文件读取并导入
  Future<BackupImportResult> importBackupFile(File file) async {
    if (!await file.exists()) return BackupImportResult.fileNotFound;
    final bytes = await file.readAsBytes();
    return importBackupBytes(bytes);
  }

  Future<void> _restoreSnapshot(Map<String, dynamic> body) async {
    final birthdayBox = Hive.box<Birthday>('birthday');
    final linesBox = Hive.box<TrailLine>('custom_lines');
    final dataBox = Hive.box('trail_data');
    final friendsBox = Hive.isBoxOpen('friends')
        ? Hive.box<Friend>('friends')
        : await openEncryptedBox<Friend>('friends');

    // birthday
    await birthdayBox.clear();
    for (final b in (body['birthday'] as List? ?? const [])) {
      final m = b as Map;
      final ms = (m['date'] as num).toInt();
      await birthdayBox.add(
        Birthday(
          date: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal(),
        ),
      );
    }

    // custom_lines
    await linesBox.clear();
    for (final l in (body['custom_lines'] as List? ?? const [])) {
      final m = l as Map;
      final line = TrailLine(
        id: m['id'] as String,
        typeIndex: (m['typeIndex'] as num).toInt(),
        name: m['name'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (m['createdAt'] as num).toInt(),
          isUtc: true,
        ).toLocal(),
        completedDates: (m['completedDates'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        notes: ((m['notes'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
        archived: (m['archived'] as bool?) ?? false,
        archivedAt: m['archivedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (m['archivedAt'] as num).toInt(),
                isUtc: true,
              ).toLocal(),
      );
      await linesBox.add(line);
    }

    // trail_data
    await dataBox.clear();
    final data = (body['trail_data'] as Map?) ?? const {};
    for (final e in data.entries) {
      await dataBox.put(e.key.toString(), e.value);
    }

    // friends
    await friendsBox.clear();
    for (final f in (body['friends'] as List? ?? const [])) {
      final m = f as Map;
      await friendsBox.add(
        Friend(
          uid: m['uid'] as String,
          displayName: (m['displayName'] as String?) ?? '',
          pairedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['pairedAt'] as num).toInt(),
            isUtc: true,
          ).toLocal(),
          rssi: m['rssi'] == null ? null : (m['rssi'] as num).toInt(),
          state: _decodeFriendState(m['stateIndex']),
        ),
      );
    }
  }

  @visibleForTesting
  Future<void> debugReset() async {
    _cipher = null;
    _ready = false;
  }

  /// 导入流程里解回 FriendState — 与 [FriendAdapter._decodeState] 对齐。
  /// 越界/缺字段一律回落到 confirmed，避免跨版本备份导入时抛 RangeError。
  static FriendState _decodeFriendState(dynamic raw) {
    final int? idx = raw is num ? raw.toInt() : null;
    if (idx != null && idx >= 0 && idx < FriendState.values.length) {
      return FriendState.values[idx];
    }
    return FriendState.confirmed;
  }
}
