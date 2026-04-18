import 'package:hive/hive.dart';

part 'trail_line.g.dart';

/// 轨迹线类型
enum TrailLineType {
  alive, // 「活着」基准线
  custom, // 自定义行动线
}

/// 轨迹线模型
@HiveType(typeId: 1)
class TrailLine extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final int typeIndex; // 0=alive, 1=custom

  @HiveField(2)
  String name;

  @HiveField(3)
  final DateTime createdAt;

  /// 已完成日期的字符串集合（格式: YYYY-MM-DD）
  @HiveField(4)
  List<String> completedDates;

  /// 节点备注 — dateKey (YYYY-MM-DD) → 备注文本
  /// 仅对已存在的节点有意义；没有 key 即无备注。
  @HiveField(5)
  Map<String, String> notes;

  /// 是否已归档（从主时间轴移出到归档页）
  @HiveField(6)
  bool archived;

  /// 归档时间（用于归档页排序；未归档时为 null）
  @HiveField(7)
  DateTime? archivedAt;

  /// 线名历史：生效日期（YYYY-MM-DD） -> 从该日开始使用的名称
  @HiveField(8)
  Map<String, String> nameHistory;

  TrailLine({
    required this.id,
    required this.typeIndex,
    required this.name,
    required this.createdAt,
    List<String>? completedDates,
    Map<String, String>? notes,
    bool? archived,
    this.archivedAt,
    Map<String, String>? nameHistory,
  }) : completedDates = completedDates ?? [],
       notes = notes ?? {},
       archived = archived ?? false,
       nameHistory = nameHistory ?? {_dateKeyStatic(createdAt): name};

  /// 便利构造：使用 TrailLineType
  factory TrailLine.fromType({
    required String id,
    required TrailLineType type,
    required String name,
    required DateTime createdAt,
    List<String>? completedDates,
    Map<String, String>? notes,
    bool? archived,
    DateTime? archivedAt,
    Map<String, String>? nameHistory,
  }) {
    return TrailLine(
      id: id,
      typeIndex: type.index,
      name: name,
      createdAt: createdAt,
      completedDates: completedDates,
      notes: notes,
      archived: archived,
      archivedAt: archivedAt,
      nameHistory: nameHistory,
    );
  }

  /// 获取轨迹线类型
  TrailLineType get type => TrailLineType.values[typeIndex];

  String displayNameOn(DateTime date) {
    final dayKey = _dateKey(date);
    String resolved = name;
    String? bestKey;
    for (final entry in nameHistory.entries) {
      if (entry.key.compareTo(dayKey) <= 0 &&
          (bestKey == null || entry.key.compareTo(bestKey) > 0)) {
        bestKey = entry.key;
        resolved = entry.value;
      }
    }
    return resolved;
  }

  String? currentNameEffectiveFromKey() {
    String? bestKey;
    for (final entry in nameHistory.entries) {
      if (entry.value == name &&
          (bestKey == null || entry.key.compareTo(bestKey) > 0)) {
        bestKey = entry.key;
      }
    }
    return bestKey;
  }

  Future<void> renameEffectiveToday(String newName, DateTime today) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final key = _dateKey(today);
    name = trimmed;
    nameHistory[key] = trimmed;
    await save();
  }

  /// 检查某天是否已完成
  bool isCompletedOn(DateTime date) {
    final key = _dateKey(date);
    return completedDates.contains(key);
  }

  /// 标记某天完成
  void markCompleted(DateTime date) {
    final key = _dateKey(date);
    if (!completedDates.contains(key)) {
      completedDates.add(key);
      save();
    }
  }

  /// 取消某天完成
  void unmarkCompleted(DateTime date) {
    final key = _dateKey(date);
    completedDates.remove(key);
    save();
  }

  /// 获取某天备注；没有则返回 null
  String? noteOn(DateTime date) => notes[_dateKey(date)];

  /// 写入/更新某天备注；传空字符串或 null 表示删除。
  void setNote(DateTime date, String? text) {
    final key = _dateKey(date);
    if (text == null || text.trim().isEmpty) {
      notes.remove(key);
    } else {
      notes[key] = text.trim();
    }
    save();
  }

  String _dateKey(DateTime date) {
    return _dateKeyStatic(date);
  }

  static String _dateKeyStatic(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
