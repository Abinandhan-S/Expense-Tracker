import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models/earning_expense.dart';
import '../services/category_service.dart';

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

  /// ✅ Compute raw totals for each month (earnings + expenses)
  Map<String, Map<String, double>> computeMonthTotals() {
    final Map<String, Map<String, double>> totals = {};

    // -----------------------------
    // ✅ EARNINGS
    // -----------------------------
    for (final e in earningBox.values) {
      final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';

      totals.putIfAbsent(key, () => {'expenses': 0.0, 'earnings': 0.0});

      totals[key]!['earnings'] = totals[key]!['earnings']! + e.amount;
    }

    // -----------------------------
    // ✅ EXPENSES
    // -----------------------------
    for (final e in expenseBox.values) {
      final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';

      totals.putIfAbsent(key, () => {'expenses': 0.0, 'earnings': 0.0});

      totals[key]!['expenses'] = totals[key]!['expenses']! + e.amount;
    }

    return totals;
  }

  List<String> sortedMonthKeysDesc(Map<String, Map<String, double>> totals) {
    final keys = totals.keys.toList();
    keys.sort((a, b) => b.compareTo(a)); // yyyy-MM descending
    return keys;
  }

  List<String> sortedMonthKeysAsc(Map<String, Map<String, double>> totals) {
    final keys = totals.keys.toList();
    keys.sort((a, b) => a.compareTo(b)); // yyyy-MM ascending
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

  /// 📊 BAR CHART: Last 6 months Income vs Expense
  Widget _buildBarChart(Map<String, Map<String, double>> totals) {
    // Get last 6 months (ascending)
    final allKeys = sortedMonthKeysAsc(totals);
    final recentKeys = allKeys.length > 6
        ? allKeys.sublist(allKeys.length - 6)
        : allKeys;

    if (recentKeys.isEmpty) return const SizedBox.shrink();

    // Find max value for Y-axis scaling
    double maxY = 0;
    for (final k in recentKeys) {
      maxY = max(maxY, totals[k]!['earnings']!);
      maxY = max(maxY, totals[k]!['expenses']!);
    }
    if (maxY == 0) maxY = 100;

    return AspectRatio(
      aspectRatio: 1.6,
      child: Card(
        margin: const EdgeInsets.all(12),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Income vs Expense (Last 6 Months)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY * 1.2,
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value < 0 || value >= recentKeys.length) {
                              return const SizedBox.shrink();
                            }
                            final parts = recentKeys[value.toInt()].split('-');
                            final date = DateTime(
                              int.parse(parts[0]),
                              int.parse(parts[1]),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                DateFormat.MMM().format(date),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: recentKeys.asMap().entries.map((entry) {
                      final index = entry.key;
                      final key = entry.value;
                      final earnings = totals[key]!['earnings']!;
                      final expenses = totals[key]!['expenses']!;

                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: earnings,
                            color: Colors.green,
                            width: 12,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            ),
                          ),
                          BarChartRodData(
                            toY: expenses,
                            color: Colors.redAccent,
                            width: 12,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🥧 PIE CHART: Expense Breakdown for Selected Month
  Widget _buildPieChart(DateTime month) {
    // Filter expenses for this month
    final expenses = expenseBox.values.where(
      (e) => e.date.year == month.year && e.date.month == month.month,
    );

    if (expenses.isEmpty) {
      // Only show if there's data, otherwise maybe user hasn't selected a month with data
      return const SizedBox.shrink();
    }

    // Group by category
    final Map<String, double> categoryTotals = {};
    for (final e in expenses) {
      categoryTotals.update(
        e.category,
        (v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }

    final totalExp = categoryTotals.values.fold(0.0, (s, e) => s + e);
    if (totalExp <= 0) return const SizedBox.shrink();

    final sections = categoryTotals.entries.map((e) {
      final percentage = (e.value / totalExp) * 100;
      final color = CategoryService.getColor(e.key);

      return PieChartSectionData(
        color: color,
        value: e.value,
        title: '${percentage.toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return AspectRatio(
      aspectRatio: 1.3,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'Expenses: ${DateFormat.yMMMM().format(month)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: PieChart(
                        PieChartData(
                          sections: sections,
                          centerSpaceRadius: 40,
                          sectionsSpace: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: categoryTotals.keys.map((cat) {
                          final color = CategoryService.getColor(cat);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Container(width: 12, height: 12, color: color),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    cat,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totals = computeMonthTotals();
    final keys = sortedMonthKeysDesc(totals);

    if (keys.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Overview')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.receipt_long, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No transactions yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Add some expenses or earnings!',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Overview')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {}); // Just refresh UI
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            // 📊 Charts Section
            _buildBarChart(totals),
            _buildPieChart(widget.selectedMonth),

            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'History',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),

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
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
