import 'package:hive_flutter/hive_flutter.dart';

part 'earning_expense.g.dart';

@HiveType(typeId: 0)
class Expense extends HiveObject {
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
  bool isPaid;
  
  @HiveField(6)
  String? note;
  
  @HiveField(7)
  int sortIndex;
  
  @HiveField(8)
  bool? autoReduceEnabled;
  
  @HiveField(9)
  double? dailyReduce;
  
  @HiveField(10)
  double? totalBudget;
  
  @HiveField(11)
  DateTime? lastReducedDateUtc;
  
  @HiveField(12)
  int reducedDaysCount;
  
  @HiveField(13)
  bool? isExtra;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    this.isPaid = false,
    this.note,
    this.sortIndex = 0,
    this.autoReduceEnabled,
    this.dailyReduce,
    this.totalBudget,
    this.lastReducedDateUtc,
    this.reducedDaysCount = 0,
    this.isExtra = false,
  });

  Expense copyWith({
    String? id,
    String? title,
    double? amount,
    String? category,
    DateTime? date,
    bool? isPaid,
    String? note,
    int? sortIndex,
    bool? autoReduceEnabled,
    double? dailyReduce,
    double? totalBudget,
    DateTime? lastReducedDateUtc,
    int? reducedDaysCount,
    bool? isExtra,
  }) {
    return Expense(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      isPaid: isPaid ?? this.isPaid,
      note: note ?? this.note,
      sortIndex: sortIndex ?? this.sortIndex,
      autoReduceEnabled: autoReduceEnabled ?? this.autoReduceEnabled,
      dailyReduce: dailyReduce ?? this.dailyReduce,
      totalBudget: totalBudget ?? this.totalBudget,
      lastReducedDateUtc: lastReducedDateUtc ?? this.lastReducedDateUtc,
      reducedDaysCount: reducedDaysCount ?? this.reducedDaysCount,
      isExtra: isExtra ?? this.isExtra,
    );
  }
}

@HiveType(typeId: 1)
class Earning extends HiveObject {
  @HiveField(0)
  String id;
  
  @HiveField(1)
  String title;
  
  @HiveField(2)
  double amount;
  
  @HiveField(3)
  String source;
  
  @HiveField(4)
  DateTime date;
  
  @HiveField(5)
  bool isReceived;
  
  @HiveField(6)
  String? note;
  
  @HiveField(7)
  int sortIndex;

  Earning({
    required this.id,
    required this.title,
    required this.amount,
    required this.source,
    required this.date,
    this.isReceived = false,
    this.note,
    this.sortIndex = 0,
  });

  Earning copyWith({
    String? id,
    String? title,
    double? amount,
    String? source,
    DateTime? date,
    bool? isReceived,
    String? note,
    int? sortIndex,
  }) {
    return Earning(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      source: source ?? this.source,
      date: date ?? this.date,
      isReceived: isReceived ?? this.isReceived,
      note: note ?? this.note,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }
}