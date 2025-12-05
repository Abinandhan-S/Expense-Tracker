import 'package:hive_flutter/hive_flutter.dart';

// ======================= EXPENSE & EARNING MODELS ===========================
@HiveType(typeId: 0) // or your current typeId
class Expense extends HiveObject {
  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.note,
    required this.isPaid,
    this.totalBudget,
    this.dailyReduce,
    this.autoReduceEnabled = false,
    this.lastReducedDateUtc,
    this.sortOrder,
    this.autoReduceStartDate,
    this.reducedDaysCount,
  });

  // =========================
  // 🧩 Core fields
  // =========================
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  double amount;

  @HiveField(3)
  String category;

  @HiveField(4)
  DateTime date;

  @HiveField(5)
  String note;

  @HiveField(6)
  bool isPaid;

  // =========================
  // 🧮 Auto-reduce fields
  // =========================
  @HiveField(7)
  double? totalBudget; // total initial budget (e.g., ₹5500)

  @HiveField(8)
  double? dailyReduce; // daily reduction amount (e.g., ₹180)

  @HiveField(9)
  bool autoReduceEnabled; // toggle

  @HiveField(10)
  DateTime? lastReducedDateUtc; // old field — may stay null now

  @HiveField(11)
  int? sortOrder; // (optional for drag sorting)

  @HiveField(12)
  DateTime? autoReduceStartDate; // 👈 when auto reduction began

  @HiveField(13)
  int? reducedDaysCount; // 👈 how many days reduced so far

  // =========================
  // 🔁 Copy helper
  // =========================
  Expense copyWith({
    String? id,
    String? title,
    double? amount,
    String? category,
    DateTime? date,
    String? note,
    bool? isPaid,
    double? totalBudget,
    double? dailyReduce,
    bool? autoReduceEnabled,
    DateTime? lastReducedDateUtc,
    int? sortOrder,
    DateTime? autoReduceStartDate,
    int? reducedDaysCount,
  }) {
    return Expense(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      note: note ?? this.note,
      isPaid: isPaid ?? this.isPaid,
      totalBudget: totalBudget ?? this.totalBudget,
      dailyReduce: dailyReduce ?? this.dailyReduce,
      autoReduceEnabled: autoReduceEnabled ?? this.autoReduceEnabled,
      lastReducedDateUtc: lastReducedDateUtc ?? this.lastReducedDateUtc,
      sortOrder: sortOrder ?? this.sortOrder,
      autoReduceStartDate: autoReduceStartDate ?? this.autoReduceStartDate,
      reducedDaysCount: reducedDaysCount ?? this.reducedDaysCount,
    );
  }
}

class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  final int typeId = 0;

  @override
  Expense read(BinaryReader reader) {
    final id = reader.readString();
    final title = reader.readString();
    final amount = reader.readDouble();
    final category = reader.readString();
    final dateMillis = reader.readInt();
    final note = reader.readString();
    final isPaid = reader.readBool();

    bool autoReduceEnabled = false;
    double? totalBudget;
    double? dailyReduce;
    DateTime? lastReducedDateUtc;

    // Try reading new fields (for backward compatibility)
    try {
      autoReduceEnabled = reader.readBool();
      totalBudget = reader.readDouble();
      dailyReduce = reader.readDouble();
      final lastMs = reader.readInt();
      if (lastMs != 0) {
        lastReducedDateUtc =
            DateTime.fromMillisecondsSinceEpoch(lastMs, isUtc: true);
      }
    } catch (_) {
      // Old entries won't have these fields.
    }

    return Expense(
      id: id,
      title: title,
      amount: amount,
      category: category,
      date: DateTime.fromMillisecondsSinceEpoch(dateMillis),
      note: note,
      isPaid: isPaid,
      totalBudget: totalBudget,
      dailyReduce: dailyReduce,
      autoReduceEnabled: autoReduceEnabled,
      lastReducedDateUtc: lastReducedDateUtc,
    );
  }

  @override
  void write(BinaryWriter writer, Expense obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeDouble(obj.amount);
    writer.writeString(obj.category);
    writer.writeInt(obj.date.millisecondsSinceEpoch);
    writer.writeString(obj.note);
    writer.writeBool(obj.isPaid);

    // New fields
    writer.writeBool(obj.autoReduceEnabled);
    writer.writeDouble(obj.totalBudget ?? 0);
    writer.writeDouble(obj.dailyReduce ?? 0);
    writer.writeInt(obj.lastReducedDateUtc?.millisecondsSinceEpoch ?? 0);
  }
}

/// Earning model - separate box
class Earning extends HiveObject {
  Earning({
    required this.id,
    required this.title,
    required this.amount,
    required this.source,
    required this.date,
    required this.note,
  });

  String id;
  String title;
  double amount;
  String source;
  DateTime date;
  String note;

  Earning copyWith({
    String? id,
    String? title,
    double? amount,
    String? source,
    DateTime? date,
    String? note,
  }) {
    return Earning(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      source: source ?? this.source,
      date: date ?? this.date,
      note: note ?? this.note,
    );
  }
}

class EarningAdapter extends TypeAdapter<Earning> {
  @override
  final int typeId = 1;

  @override
  Earning read(BinaryReader reader) {
    return Earning(
      id: reader.readString(),
      title: reader.readString(),
      amount: reader.readDouble(),
      source: reader.readString(),
      date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      note: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, Earning obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeDouble(obj.amount);
    writer.writeString(obj.source);
    writer.writeInt(obj.date.millisecondsSinceEpoch);
    writer.writeString(obj.note);
  }
}
