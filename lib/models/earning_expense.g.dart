// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'earning_expense.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  final int typeId = 0;

  @override
  Expense read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Expense(
      id: fields[0] as String,
      title: fields[1] as String,
      amount: fields[2] as double,
      category: fields[3] as String,
      date: fields[4] as DateTime,
      isPaid: fields[5] as bool,
      note: fields[6] as String?,
      sortIndex: fields[7] as int,
      autoReduceEnabled: fields[8] as bool?,
      dailyReduce: fields[9] as double?,
      totalBudget: fields[10] as double?,
      lastReducedDateUtc: fields[11] as DateTime?,
      reducedDaysCount: fields[12] as int,
      isExtra: fields[13] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, Expense obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.category)
      ..writeByte(4)
      ..write(obj.date)
      ..writeByte(5)
      ..write(obj.isPaid)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.sortIndex)
      ..writeByte(8)
      ..write(obj.autoReduceEnabled)
      ..writeByte(9)
      ..write(obj.dailyReduce)
      ..writeByte(10)
      ..write(obj.totalBudget)
      ..writeByte(11)
      ..write(obj.lastReducedDateUtc)
      ..writeByte(12)
      ..write(obj.reducedDaysCount)
      ..writeByte(13)
      ..write(obj.isExtra);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class EarningAdapter extends TypeAdapter<Earning> {
  @override
  final int typeId = 1;

  @override
  Earning read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Earning(
      id: fields[0] as String,
      title: fields[1] as String,
      amount: fields[2] as double,
      source: fields[3] as String,
      date: fields[4] as DateTime,
      isReceived: fields[5] as bool,
      note: fields[6] as String?,
      sortIndex: fields[7] as int,
    );
  }

  @override
  void write(BinaryWriter writer, Earning obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.source)
      ..writeByte(4)
      ..write(obj.date)
      ..writeByte(5)
      ..write(obj.isReceived)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.sortIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EarningAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
