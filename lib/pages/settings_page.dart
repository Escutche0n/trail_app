import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../core/ble_service.dart';
import '../core/core_bootstrap.dart';
import '../core/secure_box_service.dart';
import '../core/time_integrity_service.dart';
import '../core/uid_service.dart';
import '../services/storage_service.dart';
import '../services/haptic_service.dart';
import 'archive_page.dart';
import 'birthday_setup_page.dart';
import 'home_page.dart';

/// 设置页 — 极简深色风格
/// 提供:
///   • UID 显示 + 复制
///   • 备份 / 恢复（.trail 文件）
///   • 个性化入口
///   • 归档页入口
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late double _nodeSpacing;
  late bool _constellationVisible;
  late ConstellationHeightMode _constellationHeightMode;
  late bool _satelliteRotation;
  bool _backupBusy = false;
  bool _restoreBusy = false;
  bool _resetBusy = false;

  @override
  void initState() {
    super.initState();
    _reloadPersonalizationSummary();
  }

  void _reloadPersonalizationSummary() {
    final s = StorageService.instance;
    _nodeSpacing = s.nodeSpacing;
    _constellationVisible = s.constellationVisible;
    _constellationHeightMode = s.constellationHeightMode;
    _satelliteRotation = s.satelliteRotationEnabled;
  }

  String _constellationHeightLabel(ConstellationHeightMode mode) {
    switch (mode) {
      case ConstellationHeightMode.compact:
        return '紧凑';
      case ConstellationHeightMode.standard:
        return '标准';
      case ConstellationHeightMode.expansive:
        return '开阔';
    }
  }

  String get _personalizationSubtitle {
    final constellationSummary = _constellationVisible
        ? '星图${_constellationHeightLabel(_constellationHeightMode)}'
        : '星图关闭';
    final satelliteSummary = _satelliteRotation ? '卫星旋转开' : '卫星旋转关';
    return '行间距 ${_nodeSpacing.round()} dp · $constellationSummary · $satelliteSummary';
  }

  Future<void> _openPersonalization() async {
    HapticService.actionMenuSelect();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PersonalizationPage()));
    if (!mounted) return;
    setState(_reloadPersonalizationSummary);
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 8,
            bottom: padding.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(title: '设置', onBack: () => Navigator.of(context).pop()),
              const SizedBox(height: 22),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    // ── 身份 UID ──
                    _sectionLabel('身份标识'),
                    _UidTile(uid: UidService.instance.uid),
                    const SizedBox(height: 28),

                    // ── 备份 & 恢复 ──
                    _sectionLabel('数据安全'),
                    _ActionTile(
                      title: '导出备份',
                      subtitle: '将所有数据导出为 .trail 文件',
                      icon: Icons.upload_outlined,
                      busy: _backupBusy,
                      onTap: _doBackup,
                    ),
                    const SizedBox(height: 4),
                    _ActionTile(
                      title: '导入恢复',
                      subtitle: '从 .trail 文件恢复数据（需验签）',
                      icon: Icons.download_outlined,
                      busy: _restoreBusy,
                      onTap: _doRestore,
                    ),
                    const SizedBox(height: 4),
                    _DangerTile(
                      title: '清除所有数据',
                      subtitle: '删除本机全部记录并回到首次启动状态',
                      busy: _resetBusy,
                      onTap: _doResetAllData,
                    ),
                    const SizedBox(height: 28),

                    // ── 个性化 ──
                    _sectionLabel('个性化'),
                    _NavTile(
                      title: '时间轴与星图',
                      subtitle: _personalizationSubtitle,
                      onTap: _openPersonalization,
                    ),
                    const SizedBox(height: 28),

                    // ── 归档 ──
                    _sectionLabel('归档'),
                    _NavTile(
                      title: '查看归档',
                      subtitle: '被归档的行动线可以在这里恢复',
                      onTap: () async {
                        HapticService.actionMenuSelect();
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ArchivePage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                    _footerText(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 备份 ─────────────────────────────────────
  //
  // 注：Android 11+ (API 30+) 使用 SAF（Storage Access Framework），
  //     file_picker / FilePicker.saveFile 自动走 SAF，
  //     不需要 READ/WRITE_EXTERNAL_STORAGE 权限。
  //     Android 10 及以下：file_picker 内部自行处理权限请求。
  //     所以这里不需要手动请求存储权限。

  Future<void> _doBackup() async {
    if (_backupBusy) return;
    HapticService.actionMenuSelect();

    // 先生成备份文件内容
    setState(() => _backupBusy = true);
    List<int> bytes;
    try {
      bytes = await SecureBoxService.instance.buildBackupBytes();
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupBusy = false);
      _showToast('备份失败: $e');
      return;
    }

    try {
      final payload = Uint8List.fromList(bytes);
      // 备份文件名走 TimeIntegrityService — 与 envelope 内的 exportedAt 对齐
      final stampSource = TimeIntegrityService.instance.isReady
          ? TimeIntegrityService.instance.now()
          : DateTime.now();
      final stamp = stampSource.toIso8601String().replaceAll(':', '-');
      final fileName = 'trail-backup-$stamp.trail';

      String? savePath;
      try {
        savePath = await FilePicker.saveFile(
          dialogTitle: '选择备份保存位置',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['trail'],
          bytes: payload,
        );
      } catch (e) {
        savePath = null;
      }

      if (savePath != null) {
        if (!mounted) return;
        _showToast('备份成功\n${savePath.split('/').last}');
        return;
      }

      // 移动端保存对话框被取消或平台回退时，至少仍然生成一个本地文件，
      // 然后再交给系统分享/存储面板继续处理。
      final file = await SecureBoxService.instance.writeDefaultBackupFile();
      if (Platform.isIOS) {
        if (!mounted) return;
        await Share.shareXFiles([
          XFile(file.path, mimeType: 'application/octet-stream'),
        ], text: '迹点备份文件');
        if (!mounted) return;
        _showToast('备份已分享');
      } else {
        if (!mounted) return;
        _showToast('备份成功（已保存到应用文档目录）\n${file.path.split('/').last}');
      }
    } catch (e) {
      if (!mounted) return;
      _showToast('备份失败: $e');
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _doRestore() async {
    if (_restoreBusy) return;
    HapticService.actionMenuSelect();

    // 用 file_picker 选取 .trail 文件
    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['trail'],
        allowMultiple: false,
        withData: true,
      );
    } catch (e) {
      if (!mounted) return;
      _showToast('无法打开文件选择器');
      return;
    }
    if (picked == null || picked.files.isEmpty) return;

    final selectedFile = picked.files.single;

    setState(() => _restoreBusy = true);
    try {
      BackupImportResult result;
      if (selectedFile.path != null) {
        result = await SecureBoxService.instance.importBackupFile(
          File(selectedFile.path!),
        );
      } else if (selectedFile.bytes != null) {
        result = await SecureBoxService.instance.importBackupBytes(
          selectedFile.bytes!,
        );
      } else {
        if (!mounted) return;
        _showToast('无法读取备份文件内容');
        return;
      }
      if (!mounted) return;
      switch (result) {
        case BackupImportResult.ok:
          _showToast('恢复成功');
          break;
        case BackupImportResult.signatureMismatch:
          _showToast('验签失败 — 文件可能被篡改或来自其他设备');
          break;
        case BackupImportResult.badMagic:
        case BackupImportResult.badVersion:
        case BackupImportResult.corruptJson:
          _showToast('文件格式无效 — 不是有效的 .trail 备份');
          break;
        case BackupImportResult.fileNotFound:
          _showToast('文件不存在');
          break;
        case BackupImportResult.ioError:
          _showToast('恢复时发生 I/O 错误');
          break;
      }
    } catch (e) {
      if (!mounted) return;
      _showToast('恢复失败: $e');
    } finally {
      if (mounted) setState(() => _restoreBusy = false);
    }
  }

  Future<void> _doResetAllData() async {
    if (_resetBusy) return;
    HapticService.actionMenuSelect();

    final confirmFirst = await _showResetDialog(
      title: '清除所有数据',
      body: '这会删除本机上的生日、时间线、朋友记录、设置与备份索引。此操作不可撤销。',
      confirmText: '继续',
    );
    if (confirmFirst != true || !mounted) return;

    final confirmSecond = await _showResetDialog(
      title: '最后确认',
      body: '清除后应用会回到首次启动状态。若你没有可用备份，这些数据将永久丢失。',
      confirmText: '立即清除',
      destructive: true,
    );
    if (confirmSecond != true || !mounted) return;

    setState(() => _resetBusy = true);
    try {
      await BleService.instance.resetRuntimeState();
      await StorageService.instance.resetAllData();
      await SecureBoxService.instance.resetForWipe();
      await TimeIntegrityService.instance.resetForWipe();
      await UidService.instance.resetForWipe();
      await CoreBootstrap.initialize();
      await StorageService.init();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (pageContext) => BirthdaySetupPage(
            onConfirmed: () {
              Navigator.of(pageContext).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomePage()),
                (route) => false,
              );
            },
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _resetBusy = false);
      _showToast('清除失败: $e');
    }
  }

  Future<bool?> _showResetDialog({
    required String title,
    required String body,
    required String confirmText,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: Text(
          body,
          style: const TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消', style: TextStyle(color: Color(0x88FFFFFF))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmText,
              style: TextStyle(
                color: destructive ? const Color(0xFFFF6B6B) : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
        backgroundColor: const Color(0xDD1A1A1A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
  }

  Widget _sectionLabel(String text, {bool dim = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10, top: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Color.fromRGBO(255, 255, 255, dim ? 0.22 : 0.42),
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 2,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _footerText() => const Center(
    child: Text(
      '迹点 · Trail',
      style: TextStyle(
        color: Color(0x33FFFFFF),
        fontSize: 10,
        fontWeight: FontWeight.w300,
        letterSpacing: 4,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

class PersonalizationPage extends StatefulWidget {
  const PersonalizationPage({super.key});

  @override
  State<PersonalizationPage> createState() => _PersonalizationPageState();
}

class _PersonalizationPageState extends State<PersonalizationPage> {
  late double _nodeSpacing;
  late bool _constellationVisible;
  late ConstellationHeightMode _constellationHeightMode;
  late bool _satelliteRotation;

  @override
  void initState() {
    super.initState();
    final s = StorageService.instance;
    _nodeSpacing = s.nodeSpacing;
    _constellationVisible = s.constellationVisible;
    _constellationHeightMode = s.constellationHeightMode;
    _satelliteRotation = s.satelliteRotationEnabled;
  }

  String _constellationHeightSubtitle(ConstellationHeightMode mode) {
    switch (mode) {
      case ConstellationHeightMode.compact:
        return '只保留一条更克制的顶部星带';
      case ConstellationHeightMode.standard:
        return '保持当前推荐的呼吸空间';
      case ConstellationHeightMode.expansive:
        return '让顶部星图占据更完整的抬头区域';
    }
  }

  Widget _sectionLabel(String text, {bool dim = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10, top: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Color.fromRGBO(255, 255, 255, dim ? 0.22 : 0.42),
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 2,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _footerText() => const Center(
    child: Text(
      '个性化',
      style: TextStyle(
        color: Color(0x33FFFFFF),
        fontSize: 10,
        fontWeight: FontWeight.w300,
        letterSpacing: 4,
        decoration: TextDecoration.none,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 8,
            bottom: padding.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(title: '个性化', onBack: () => Navigator.of(context).pop()),
              const SizedBox(height: 22),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    _sectionLabel('主时间轴'),
                    _SpacingTile(
                      value: _nodeSpacing,
                      min: StorageService.minNodeSpacing,
                      max: StorageService.maxNodeSpacing,
                      enabled: true,
                      onChanged: (v) {
                        setState(() => _nodeSpacing = v);
                      },
                      onChangeEnd: (v) {
                        StorageService.instance.setNodeSpacing(v);
                        HapticService.actionMenuSelect();
                      },
                    ),
                    const SizedBox(height: 28),
                    _sectionLabel('顶部星图'),
                    _ToggleTile(
                      title: '显示头上的星图',
                      subtitle: '关闭后，顶部回到纯黑背景',
                      value: _constellationVisible,
                      onChanged: (v) {
                        setState(() => _constellationVisible = v);
                        StorageService.instance.setConstellationVisible(v);
                        HapticService.actionMenuSelect();
                      },
                    ),
                    const SizedBox(height: 8),
                    _ChoiceTile<ConstellationHeightMode>(
                      title: '星图高度',
                      subtitle: _constellationVisible
                          ? _constellationHeightSubtitle(
                              _constellationHeightMode,
                            )
                          : '先打开顶部星图，才需要调整占据高度',
                      value: _constellationHeightMode,
                      enabled: _constellationVisible,
                      options: const [
                        _ChoiceOption(
                          value: ConstellationHeightMode.compact,
                          label: '紧凑',
                        ),
                        _ChoiceOption(
                          value: ConstellationHeightMode.standard,
                          label: '标准',
                        ),
                        _ChoiceOption(
                          value: ConstellationHeightMode.expansive,
                          label: '开阔',
                        ),
                      ],
                      onChanged: (mode) {
                        setState(() => _constellationHeightMode = mode);
                        StorageService.instance.setConstellationHeightMode(
                          mode,
                        );
                        HapticService.actionMenuSelect();
                      },
                    ),
                    const SizedBox(height: 28),
                    _sectionLabel('节点备注'),
                    _ToggleTile(
                      title: '卫星点旋转动画',
                      subtitle: '关闭后，备注图标固定在环右侧',
                      value: _satelliteRotation,
                      onChanged: (v) {
                        setState(() => _satelliteRotation = v);
                        StorageService.instance.setSatelliteRotationEnabled(v);
                        HapticService.actionMenuSelect();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '注：本次例外仅针对 icon 级卫星点动画，不扩展为常驻系统背景动画。',
                      style: const TextStyle(
                        color: Color(0x55FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w300,
                        height: 1.45,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _footerText(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// 顶栏：返回 + 标题
// ─────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBack,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Icon(Icons.chevron_left, color: Color(0xCCFFFFFF), size: 22),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xEEFFFFFF),
            fontSize: 17,
            fontWeight: FontWeight.w500,
            letterSpacing: 2,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────
// UID 显示 Tile（点击可复制）
// ─────────────────────────────────────────────────────

class _UidTile extends StatelessWidget {
  final String uid;
  const _UidTile({required this.uid});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Clipboard.setData(ClipboardData(text: uid));
        HapticService.actionMenuSelect();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '已复制到剪贴板',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
            backgroundColor: const Color(0xDD1A1A1A),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '设备 UID',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              uid,
              style: const TextStyle(
                color: Color(0xAAFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w300,
                fontFamily: 'Courier',
                letterSpacing: 0.6,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '点击复制 · 此 ID 用于加密和配对',
              style: TextStyle(
                color: Color(0x55FFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.8,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// 操作按钮 Tile（备份/恢复）
// ─────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;

  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: Opacity(
        opacity: busy ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xBBFFFFFF), size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 1,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0x77FFFFFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.8,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0x88FFFFFF),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right,
                  color: Color(0x55FFFFFF),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DangerTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;

  const _DangerTile({
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: Opacity(
        opacity: busy ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline,
                color: Color(0xCCFF6B6B),
                size: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '清除所有数据',
                      style: TextStyle(
                        color: Color(0xFFFF6B6B),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 1,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0x88FFFFFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.8,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Color(0x88FFFFFF),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right,
                  color: Color(0x55FFFFFF),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// 通用 Toggle Tile
// ─────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0x77FFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 0.8,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _SoftSwitch(value: value),
          ],
        ),
      ),
    );
  }
}

class _SoftSwitch extends StatelessWidget {
  final bool value;
  const _SoftSwitch({required this.value});

  @override
  Widget build(BuildContext context) {
    final trackColor = value
        ? const Color(0xAAFFFFFF)
        : const Color(0x22FFFFFF);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 42,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color.fromRGBO(255, 255, 255, value ? 0.35 : 0.12),
          width: 0.6,
        ),
      ),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: value ? Colors.black : Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// 节点间距滑块
// ─────────────────────────────────────────────────────

class _SpacingTile extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SpacingTile({
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final text = enabled ? Colors.white : const Color(0x55FFFFFF);
    final sub = enabled ? const Color(0x77FFFFFF) : const Color(0x33FFFFFF);
    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '行间距',
                        style: TextStyle(
                          color: text,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 1,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '主节点之间的纵向距离',
                        style: TextStyle(
                          color: sub,
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0.8,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${value.round()} dp',
                  style: TextStyle(
                    color: text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.6,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: Color.fromRGBO(
                  255,
                  255,
                  255,
                  enabled ? 0.85 : 0.3,
                ),
                inactiveTrackColor: const Color(0x22FFFFFF),
                thumbColor: enabled ? Colors.white : const Color(0x66FFFFFF),
                overlayColor: const Color(0x11FFFFFF),
                trackHeight: 1.4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: (max - min).round(),
                onChanged: enabled ? onChanged : null,
                onChangeEnd: enabled ? onChangeEnd : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceOption<T> {
  final T value;
  final String label;

  const _ChoiceOption({required this.value, required this.label});
}

class _ChoiceTile<T> extends StatelessWidget {
  final String title;
  final String subtitle;
  final T value;
  final bool enabled;
  final List<_ChoiceOption<T>> options;
  final ValueChanged<T> onChanged;

  const _ChoiceTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = enabled ? Colors.white : const Color(0x55FFFFFF);
    final subColor = enabled
        ? const Color(0x77FFFFFF)
        : const Color(0x33FFFFFF);
    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: subColor,
                fontSize: 12,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.8,
                height: 1.35,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final option in options)
                  _ChoiceChip(
                    label: option.label,
                    selected: value == option.value,
                    enabled: enabled,
                    onTap: () => onChanged(option.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : Colors.white;
    final bg = selected ? const Color(0xE6FFFFFF) : const Color(0x12FFFFFF);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0x55FFFFFF) : const Color(0x22FFFFFF),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? fg : const Color(0x55FFFFFF),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w300,
            letterSpacing: 0.8,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// 导航跳转 Tile
// ─────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0x77FFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 0.8,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.chevron_right, color: Color(0x77FFFFFF), size: 20),
          ],
        ),
      ),
    );
  }
}
