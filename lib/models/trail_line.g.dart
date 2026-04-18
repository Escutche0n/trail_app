// GENERATED CODE - DO NOT MODIFY BY HAND
// Hand-maintained to match trail_line.dart (see comments below).
//
// Backwards compatibility: older records written before HiveField(5..7) existed
// or before HiveField(8) existed will have fewer fields. The TrailLine
// constructor provides defaults for
// the missing fields so those records load cleanly.

part of 'trail_line.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TrailLineAdapter extends TypeAdapter<TrailLine> {
  @override
  final int typeId = 1;

  @override
  TrailLine read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TrailLine(
      id: fields[0] as String,
      typeIndex: fields[1] as int,
      name: fields[2] as String,
      createdAt: fields[3] as DateTime,
      completedDates: (fields[4] as List?)?.cast<String>(),
      notes: (fields[5] as Map?)?.cast<String, String>(),
      archived: fields[6] as bool?,
      archivedAt: fields[7] as DateTime?,
      nameHistory: (fields[8] as Map?)?.cast<String, String>(),
    );
  }

  @override
  void write(BinaryWriter writer, TrailLine obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.typeIndex)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.completedDates)
      ..writeByte(5)
      ..write(obj.notes)
      ..writeByte(6)
      ..write(obj.archived)
      ..writeByte(7)
      ..write(obj.archivedAt)
      ..writeByte(8)
      ..write(obj.nameHistory);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrailLineAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
