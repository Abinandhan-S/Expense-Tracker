import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/earning_expense.dart';

class OverviewPage extends StatefulWidget {
  final DateTime selectedMonth;
  final void Function(DateTime) onMonthSelected;
  const OverviewPage({
    super.key,
    required this.selectedMonth,
    required this.onMonthSelected,
  });

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  final Box<Expense> expenseBox = Hive.box<Expense>('expenses_box');
  final Box<Earning> earningBox = Hive.box<Earning>('earnings_box');

  Map<String, Map<String, double>> computeMonthTotals() {
    final Map<String, Map<String, double>> totals = {};
    for (final e in expenseBox.values) {
      final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      totals.putIfAbsent(key, () => {'expenses': 0.0, 'earnings': 0.0});
      totals[key]!['expenses'] = totals[key]!['expenses']! + e.amount;
    }
    for (final e in earningBox.values) {
      final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      totals.putIfAbsent(key, () => {'expenses': 0.0, 'earnings': 0.0});
      totals[key]!['earnings'] = totals[key]!['earnings']! + e.amount;
    }
    return totals;
  }

  List<String> sortedMonthKeysDesc(Map<String, Map<String, double>> totals) {
    final keys = totals.keys.toList();
    keys.sort((a, b) => b.compareTo(a)); // yyyy-MM descending
    return keys;
  }

  Color _bgForBalance(double balance, BuildContext context) {
    if (balance > 0) {
      return Theme.of(context).brightness == Brightness.dark
          ? Colors.green.shade900.withOpacity(0.18)
          : Colors.green.shade50;
    } else if (balance < 0) {
      return Theme.of(context).brightness == Brightness.dark
          ? Colors.red.shade900.withOpacity(0.12)
          : Colors.red.shade50;
    }
    return Theme.of(context).cardColor;
  }

  List<double> computeDailySampledBalance(
    int year,
    int month, {
    int maxPoints = 12,
  }) {
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    if (daysInMonth <= 0) return [0.0];
    final step = max(1, (daysInMonth / maxPoints).floor());
    final points = <double>[];
    for (int d = 1; d <= daysInMonth; d += step) {
      final endDate = DateTime(
        year,
        month,
        min(d + step - 1, daysInMonth),
        23,
        59,
        59,
      );
      final earnings = earningBox.values
          .where(
            (e) =>
                e.date.year == year &&
                e.date.month == month &&
                (e.date.isBefore(endDate) || isSameDate(e.date, endDate)),
          )
          .fold(0.0, (s, e) => s + e.amount);
      final expenses = expenseBox.values
          .where(
            (ex) =>
                ex.date.year == year &&
                ex.date.month == month &&
                (ex.date.isBefore(endDate) || isSameDate(ex.date, endDate)),
          )
          .fold(0.0, (s, ex) => s + ex.amount);
      points.add(earnings - expenses);
    }
    final lastEnd = DateTime(year, month, daysInMonth, 23, 59, 59);
    final earningsLast = earningBox.values
        .where(
          (e) =>
              e.date.year == year &&
              e.date.month == month &&
              (e.date.isBefore(lastEnd) || isSameDate(e.date, lastEnd)),
        )
        .fold(0.0, (s, e) => s + e.amount);
    final expensesLast = expenseBox.values
        .where(
          (ex) =>
              ex.date.year == year &&
              ex.date.month == month &&
              (ex.date.isBefore(lastEnd) || isSameDate(ex.date, lastEnd)),
          )
        .fold(0.0, (s, ex) => s + ex.amount);
    final lastBalance = earningsLast - expensesLast;
    if (points.isEmpty || (points.isNotEmpty && points.last != lastBalance)) {
      points.add(lastBalance);
    }
    return points;
  }

  static bool isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final totals = computeMonthTotals();
    final keys = sortedMonthKeysDesc(totals);

    if (keys.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Overview')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.calendar_month, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'No transactions yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('Add expenses or earnings to see month-wise summary.'),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Overview')),
      body: RefreshIndicator(
        onRefresh: () async {
          await ensureRecurringSalaryFilled();
          await applyDailyReductions();
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            ...keys.map((key) {
              final parts = key.split('-');
              final year = int.parse(parts[0]);
              final month = int.parse(parts[1]);
              final displayDate = DateTime(year, month);
              final map = totals[key]!;
              final earnings = map['earnings'] ?? 0.0;
              final expenses = map['expenses'] ?? 0.0;
              final balance = earnings - expenses;
              final bg = _bgForBalance(balance, context);
              final balanceLabel =
                  (balance >= 0 ? '+' : '') + '₹${balance.toStringAsFixed(2)}';

              final points = computeDailySampledBalance(
                year,
                month,
                maxPoints: 12,
              );
              final maxAbs = points
                  .map((e) => e.abs())
                  .fold<double>(0.0, (p, n) => max(p, n));
              final norm = maxAbs == 0 ? 1.0 : maxAbs;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Card(
                  clipBehavior: Clip.hardEdge,
                  child: InkWell(
                    onTap: () => widget.onMonthSelected(displayDate),
                    child: Container(
                      color: bg,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat.yMMMM().format(displayDate),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Earnings',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₹${earnings.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 24),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Expenses',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₹${expenses.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 36,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: points.map((val) {
                                      final height = (val.abs() / norm) * 34;
                                      final color = val >= 0
                                          ? Colors.green.shade400
                                          : Colors.red.shade400;
                                      return Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          child: Container(
                                            height: max(2.0, height),
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Balance',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                balanceLabel,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: balance >= 0
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
