import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/core_bootstrap.dart';
import 'core/uid_service.dart';
import 'services/storage_service.dart';
import 'app.dart';

/// debug-only 日志；release 包完全剥除（避免泄露路径/状态信息）。
void _devLog(String msg) {
  assert(() {
    debugPrint('[boot] $msg');
    return true;
  }());
}

void main() {
  // 全局错误捕获 — 防止未处理异常直接闪退
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    assert(() {
      debugPrint('[FlutterError] ${details.exceptionAsString()}');
      debugPrint('${details.stack}');
      return true;
    }());
  };

  runZonedGuarded(
    () async {
      _devLog('main() started');
      WidgetsFlutterBinding.ensureInitialized();

      // 全屏沉浸式，无系统 UI 干扰
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
      _devLog('SystemChrome configured');

      // 初始化本地存储（加保护 + 超时）
      // 超时保护：Hive 在 iOS 26 / 某些机型偶发卡死；超过 5 秒直接按失败处理，
      // 保证至少能看到界面或错误页，不会停在白屏。
      bool storageOk = false;
      _BootFailure? fatal;
      try {
        _devLog('CoreBootstrap (UID / time / AES)');
        // 先初始化：UID → TimeIntegrity → SecureBox
        // 这三者是 Hive 加密盒的前置条件，必须在 StorageService.init() 之前完成。
        await CoreBootstrap.initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('CoreBootstrap timed out after 5s');
          },
        );
        _devLog('calling StorageService.init');
        await StorageService.init().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('StorageService.init timed out after 5s');
          },
        );
        storageOk = true;
        _devLog('StorageService initialized OK');
      } on UidSecureStorageException catch (e, st) {
        _devLog('UID secure storage failed: $e\n$st');
        fatal = _BootFailure.uid(e);
      } on HiveOpenFailure catch (e, st) {
        _devLog('Hive open failure (data preserved): $e\n$st');
        fatal = _BootFailure.hive(e);
      } on TimeoutException catch (e, st) {
        _devLog('bootstrap timed out: $e\n$st');
        fatal = _BootFailure.timeout(e);
      } catch (e, st) {
        _devLog('bootstrap unknown failure: $e\n$st');
        fatal = _BootFailure.unknown(e);
      }

      if (!storageOk) {
        runApp(_ErrorApp(failure: fatal));
        return;
      }

      runApp(const TrailApp());
    },
    (error, stack) {
      assert(() {
        debugPrint('[unhandled-async] $error\n$stack');
        return true;
      }());
    },
  );
}

/// 启动失败的类型 — 决定错误页展示哪段文案。
/// 关键点：**所有类型都不会触发抹档**；UI 只是呈现不同的恢复提示。
enum _BootFailureKind { uid, hive, timeout, unknown }

class _BootFailure {
  final _BootFailureKind kind;
  final Object cause;
  const _BootFailure._(this.kind, this.cause);
  factory _BootFailure.uid(Object e) => _BootFailure._(_BootFailureKind.uid, e);
  factory _BootFailure.hive(Object e) =>
      _BootFailure._(_BootFailureKind.hive, e);
  factory _BootFailure.timeout(Object e) =>
      _BootFailure._(_BootFailureKind.timeout, e);
  factory _BootFailure.unknown(Object e) =>
      _BootFailure._(_BootFailureKind.unknown, e);
}

/// 存储初始化彻底失败时展示的错误页面。
///
/// 文案原则（PRD §4.3 / §7）：
///   · 明确告知“数据仍然保留”，不要让用户以为需要重装/重置。
///   · UID 失败 vs 数据盒失败 的提示不同（前者是权限/Keychain 问题，后者是文件问题）。
///   · debug 模式下显示原始错误辅助排查；release 模式只给用户可操作信息。
class _ErrorApp extends StatelessWidget {
  final _BootFailure? failure;

  const _ErrorApp({this.failure});

  String get _title {
    switch (failure?.kind) {
      case _BootFailureKind.uid:
        return '无法读取安全身份';
      case _BootFailureKind.hive:
        return '本地数据读取失败';
      case _BootFailureKind.timeout:
        return '启动超时';
      case _BootFailureKind.unknown:
      case null:
        return '初始化失败';
    }
  }

  String get _body {
    switch (failure?.kind) {
      case _BootFailureKind.uid:
        return '系统安全存储暂时不可用。你的数据和身份都没有被修改，'
            '请尝试重启设备后再打开应用。';
      case _BootFailureKind.hive:
        return '本地加密数据无法解开。为保护你的现有记录，'
            '应用不会自动重置数据。可以尝试重启应用，或从备份恢复。';
      case _BootFailureKind.timeout:
        return '启动在 5 秒内未能完成。你的数据保持原样，'
            '请重新打开应用重试。';
      case _BootFailureKind.unknown:
      case null:
        return '遇到未知错误。你的数据没有被清除，请尝试重启应用。';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 仅在 debug 模式暴露原始异常字符串
    String? debugReason;
    assert(() {
      debugReason = failure?.cause.toString();
      return true;
    }());

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, color: Color(0x88FFFFFF), size: 48),
                const SizedBox(height: 20),
                Text(
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _body,
                  style: const TextStyle(
                    color: Color(0x77FFFFFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (debugReason != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    debugReason!,
                    style: const TextStyle(
                      color: Color(0x55FFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w300,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
