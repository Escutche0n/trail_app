// ─────────────────────────────────────────────────────────────────────────────
// crypto_utils.dart
//
// 模块定位：
//   整个本地核心架构共用的「纯算法」工具层。
//   仅提供 SHA-256 / HMAC-SHA256 / 基于 UID 的密钥派生 — 不涉及 I/O、不涉及状态。
//
// 设计原则：
//   1. 所有密钥派生都使用域分离盐（domain-separation salt），
//      确保「加密密钥」、「签名密钥」、「其它未来用途」互相独立，
//      即使一把被破译也不会横向污染其它用途。
//   2. AES 密钥固定 32 字节（AES-256），签名密钥固定 32 字节（HMAC-SHA256）。
//   3. 本文件不持有任何密钥，不读写 secure storage；调用方负责传入 UID。
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart' show hex;
import 'package:crypto/crypto.dart';

/// 加密 / 签名相关纯函数工具
class CryptoUtils {
  CryptoUtils._();

  // ── 域分离盐（domain-separation salts） ────────────
  // 任何新用途都应追加新的 salt，不要复用现有 salt。
  static const String _aesSaltV1 = 'trail.aes.v1';
  static const String _sigSaltV1 = 'trail.sig.v1';

  // ── Hash ────────────────────────────────────────────

  /// 对任意字节做 SHA-256，返回 32 字节摘要
  static Uint8List sha256Bytes(List<int> data) {
    return Uint8List.fromList(sha256.convert(data).bytes);
  }

  /// SHA-256 的十六进制字符串（64 个字符）
  static String sha256Hex(List<int> data) {
    return hex.encode(sha256.convert(data).bytes);
  }

  // ── HMAC ────────────────────────────────────────────

  /// HMAC-SHA256 原始字节
  static Uint8List hmacSha256(List<int> key, List<int> data) {
    return Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);
  }

  /// HMAC-SHA256 十六进制字符串
  static String hmacSha256Hex(List<int> key, List<int> data) {
    return hex.encode(Hmac(sha256, key).convert(data).bytes);
  }

  // ── 基于 UID 的密钥派生 ────────────────────────────
  //
  // 派生公式：key = SHA-256( utf8(salt) || utf8(uid) )
  // 说明：使用 SHA-256 而非 HKDF 是因为输入熵已足够（UUID v4 有 122 bit），
  //   并且我们只需要单把 32 字节密钥，不需要多段 OKM。

  /// 派生 Hive AES-256 主密钥（32 字节）
  static Uint8List deriveAesKey(String uid) {
    final material = utf8.encode('$_aesSaltV1|$uid');
    return sha256Bytes(material);
  }

  /// 派生 HMAC 签名密钥（32 字节）
  static Uint8List deriveSigKey(String uid) {
    final material = utf8.encode('$_sigSaltV1|$uid');
    return sha256Bytes(material);
  }

  // ── 编码辅助 ───────────────────────────────────────

  /// 将字节转为十六进制字符串（小写）
  static String toHex(List<int> bytes) => hex.encode(bytes);

  /// 从十六进制字符串还原字节；格式错误返回空列表
  static Uint8List fromHex(String s) {
    try {
      return Uint8List.fromList(hex.decode(s));
    } catch (_) {
      return Uint8List(0);
    }
  }

  /// 常数时间字节比较（防止计时攻击）—
  /// 验证签名时必须使用此函数而不是 `==`。
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
