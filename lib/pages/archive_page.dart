import 'package:flutter/material.dart';
import '../models/trail_line.dart';
import '../services/storage_service.dart';
import '../services/haptic_service.dart';

/// 归档页 — 展示被归档的行动线，支持恢复 / 彻底删除
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  late List<TrailLine> _lines;

  @override
  void initState() {
    super.initState();
    _lines = StorageService.instance.getArchivedLines();
  }

  Future<void> _restore(TrailLine l) async {
    await StorageService.instance.restoreLine(l);
    HapticService.lineArchived();
    if (!mounted) return;
    setState(() => _lines = StorageService.instance.getArchivedLines());
  }

  Future<void> _delete(TrailLine l) async {
    await StorageService.instance.deleteCustomLine(l);
    HapticService.lineDeleted();
    if (!mounted) return;
    setState(() => _lines = StorageService.instance.getArchivedLines());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Icon(
                        Icons.chevron_left,
                        color: Color(0xCCFFFFFF),
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '归档',
                    style: TextStyle(
                      color: Color(0xEEFFFFFF),
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_lines.length}',
                    style: const TextStyle(
                      color: Color(0x77FFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: _lines.isEmpty ? _emptyState() : _buildList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => const Center(
        child: Text(
          '这里空空如也',
          style: TextStyle(
            color: Color(0x44FFFFFF),
            fontSize: 14,
            fontWeight: FontWeight.w300,
            letterSpacing: 4,
            decoration: TextDecoration.none,
          ),
        ),
      );

  Widget _buildList() => ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _lines.length,
        separatorBuilder: (_, _) => const Divider(
          color: Color(0x11FFFFFF),
          height: 1,
          thickness: 0.5,
        ),
        itemBuilder: (ctx, i) {
          final l = _lines[i];
          return _ArchiveRow(
            line: l,
            onRestore: () => _restore(l),
            onDelete: () => _confirmDelete(l),
          );
        },
      );

  Future<void> _confirmDelete(TrailLine l) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withAlpha(150),
      builder: (ctx) => _ConfirmDialog(
        title: '彻底删除「${l.name}」？',
        subtitle: '该操作不可撤销',
        confirmLabel: '删除',
        onCancel: () => Navigator.pop(ctx, false),
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    );
    if (ok == true) await _delete(l);
  }
}

class _ArchiveRow extends StatelessWidget {
  final TrailLine line;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _ArchiveRow({
    required this.line,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final when = line.archivedAt;
    final when1 = when == null
        ? ''
        : '${when.year}/${when.month}/${when.day}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0x55FFFFFF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  style: const TextStyle(
                    color: Color(0xDDFFFFFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  when.isNotEmpty ? '归档于 $when1' : '',
                  style: const TextStyle(
                    color: Color(0x55FFFFFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 0.6,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SmallPill(
            label: '恢复',
            onTap: onRestore,
            bright: true,
          ),
          const SizedBox(width: 8),
          _SmallPill(
            label: '删除',
            onTap: onDelete,
            bright: false,
          ),
        ],
      ),
    );
  }
}

extension on DateTime? {
  bool get isNotEmpty => this != null;
}

class _SmallPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool bright;

  const _SmallPill({
    required this.label,
    required this.onTap,
    required this.bright,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bright
              ? const Color(0x18FFFFFF)
              : const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Color.fromRGBO(
                255, 255, 255, bright ? 0.35 : 0.15),
            width: 0.6,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: bright
                ? Colors.white
                : const Color(0x88FFFFFF),
            fontSize: 11,
            fontWeight: FontWeight.w400,
            letterSpacing: 1,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// 通用二次确认对话框
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0B0B0B),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x22FFFFFF), width: 0.6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0x77FFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.6,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: onCancel,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: Color(0x77FFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onConfirm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2,
                        decoration: TextDecoration.none,
                      ),
                    ),
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
