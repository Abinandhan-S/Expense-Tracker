import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

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

  /// ✅ Compute raw totals for each month (no reduction)
  Map<String, Map<String, double>> computeMonthTotals() {
    final Map<String, Map<String, double>> totals = {};

    // ✅ EXPENSES (consider auto-reduce totalBudget if enabled)
    for (final e in expenseBox.values) {
      final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      totals.putIfAbsent(key, () => {'expenses': 0.0, 'earnings': 0.0});

      // Use totalBudget if auto-reduction is active and valid
      final amountToUse = (e.autoReduceEnabled && (e.totalBudget ?? 0) > 0)
          ? e.totalBudget!
          : e.amount;

      totals[key]!['expenses'] = totals[key]!['expenses']! + amountToUse;
    }

    // ✅ EARNINGS (no reduction logic, full exact total)
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

  @override
  Widget build(BuildContext context) {
    final totals = computeMonthTotals();
    final keys = sortedMonthKeysDesc(totals);

    if (keys.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Overview')),
        body: const Center(
          child: Text('No transactions yet. Add some expenses or earnings!'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Overview')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {}); // Just refresh UI (no reduction logic)
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
                  '${balance >= 0 ? '+' : ''}₹${balance.toStringAsFixed(2)}';

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
                                const SizedBox(height: 8),
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
