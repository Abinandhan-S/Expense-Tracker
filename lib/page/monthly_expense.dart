import 'dart:io';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:expense_tracker/page/common_expense.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart';
import '../models/earning_expense.dart';


// ======================= MONTHLY PAGE ===========================
class MonthlyPage extends StatefulWidget {
  final Function(bool) onToggleTheme;
  final ThemeMode themeMode;
  final DateTime selectedMonth;
  final ValueChanged<DateTime> onMonthChanged;

  const MonthlyPage({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
    required this.selectedMonth,
    required this.onMonthChanged,
  });

  @override
  State<MonthlyPage> createState() => _MonthlyPageState();
}

class _MonthlyPageState extends State<MonthlyPage> {
  final Box<Expense> expenseBox = Hive.box<Expense>('expenses_box');
  final Box<Earning> earningBox = Hive.box<Earning>('earnings_box');

  late DateTime selectedMonth;
  MonthlyFilter _filter = MonthlyFilter.all;
  ExpenseStatusFilter _expenseStatusFilter = ExpenseStatusFilter.all;

  @override
  void initState() {
    super.initState();
    selectedMonth = widget.selectedMonth;
  }

  @override
  void didUpdateWidget(covariant MonthlyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedMonth != widget.selectedMonth) {
      setState(() => selectedMonth = widget.selectedMonth);
    }
  }

  double get totalExpensesForMonth {
    return expenseBox.values
        .where(
          (e) =>
              e.date.year == selectedMonth.year &&
              e.date.month == selectedMonth.month,
        )
        .fold(0.0, (s, e) => s + e.amount);
  }

  double get totalEarningsForMonth {
    return earningBox.values
        .where(
          (e) =>
              e.date.year == selectedMonth.year &&
              e.date.month == selectedMonth.month,
        )
        .fold(0.0, (s, e) => s + e.amount);
  }

  double displayedExpensesTotal(List<Expense> expenses) {
    return expenses.fold(0.0, (s, e) => s + e.amount);
  }

  double displayedEarningsTotal(List<Earning> earnings) {
    return earnings.fold(0.0, (s, e) => s + e.amount);
  }

  double get remainingBalance => totalEarningsForMonth - totalExpensesForMonth;

  void previousMonth() {
    final m = DateTime(selectedMonth.year, selectedMonth.month - 1);
    setState(() => selectedMonth = m);
    widget.onMonthChanged(selectedMonth);
  }

  void nextMonth() {
    final m = DateTime(selectedMonth.year, selectedMonth.month + 1);
    setState(() => selectedMonth = m);
    widget.onMonthChanged(selectedMonth);
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        selectedMonth = DateTime(picked.year, picked.month);
      });
      widget.onMonthChanged(selectedMonth);
    }
  }

  Future<void> exportCSV() async {
    final rows = <List<dynamic>>[];
    rows.add([
      'Type',
      'ID',
      'Title',
      'Amount',
      'Category/Source',
      'Date',
      'Note',
    ]);
    for (final e in expenseBox.values) {
      rows.add([
        'Expense',
        e.id,
        e.title,
        e.amount.toStringAsFixed(2),
        e.category,
        DateFormat.yMd().format(e.date),
        e.note,
      ]);
    }
    for (final e in earningBox.values) {
      rows.add([
        'Earning',
        e.id,
        e.title,
        e.amount.toStringAsFixed(2),
        e.source,
        DateFormat.yMd().format(e.date),
        e.note,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/transactions_export_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csv);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exported CSV to: ${file.path}')));
    }
  }

  void openAddEditSheet({
    Expense? expense,
    Earning? earning,
    bool isEarning = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AddEditSheet(
            expense: expense,
            earning: earning,
            isEarning: isEarning,
            onSaved: () {
              setState(() {});
            },
          ),
        ),
      ),
    );
  }

  void showAddChoiceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add, color: Colors.teal),
              title: const Text('Add Expense'),
              onTap: () {
                Navigator.pop(ctx);
                openAddEditSheet(isEarning: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments, color: Colors.green),
              title: const Text('Add Earning'),
              onTap: () {
                Navigator.pop(ctx);
                openAddEditSheet(isEarning: true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<Expense> _applyExpenseFilter(List<Expense> expenses) {
    switch (_filter) {
      case MonthlyFilter.all:
        return expenses;
      case MonthlyFilter.income:
        return [];
      case MonthlyFilter.expense:
        switch (_expenseStatusFilter) {
          case ExpenseStatusFilter.all:
            return expenses;
          case ExpenseStatusFilter.paid:
            return expenses.where((e) => e.isPaid).toList();
          case ExpenseStatusFilter.unpaid:
            return expenses.where((e) => !e.isPaid).toList();
        }
    }
  }

  List<Earning> _applyEarningFilter(List<Earning> earnings) {
    switch (_filter) {
      case MonthlyFilter.all:
        return earnings;
      case MonthlyFilter.income:
        return earnings;
      case MonthlyFilter.expense:
        return [];
    }
  }

  /// Use Common Expense (multi-select) from Monthly tab
  Future<void> _showCommonApplySheet() async {
    final box = Hive.box<CommonExpense>('common_expenses_box');
    final items = box.values.toList();

    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No Common Expenses found')));
      return;
    }

    final Set<CommonExpense> selected = {};

    final result = await showModalBottomSheet<List<CommonExpense>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final height = min(450.0, MediaQuery.of(ctx).size.height * 0.7);
        return SafeArea(
          child: SizedBox(
            height: height,
            child: StatefulBuilder(
              builder: (ctx2, setSt) {
                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Select Common Expenses to apply',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (c, i) {
                          final ce = items[i];
                          final isSel = selected.contains(ce);
                          return CheckboxListTile(
                            value: isSel,
                            title: Text(ce.title),
                            subtitle: Text(
                              '${ce.category} • ₹${ce.amount.toStringAsFixed(2)}',
                            ),
                            onChanged: (v) {
                              setSt(() {
                                if (v == true) {
                                  selected.add(ce);
                                } else {
                                  selected.remove(ce);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx2),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx2, selected.toList());
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (result == null || result.isEmpty) return;

    final expensesBox = Hive.box<Expense>('expenses_box');
    int added = 0;

    for (final ce in result) {
      final alreadyExists = expensesBox.values.any(
        (e) =>
            e.date.year == selectedMonth.year &&
            e.date.month == selectedMonth.month &&
            e.title == ce.title &&
            e.category == ce.category &&
            (e.amount - ce.amount).abs() < 0.01,
      );
      if (alreadyExists) continue;

      final id = DateTime.now().millisecondsSinceEpoch.toString() + '_' + ce.id;
      final dateToUse = DateTime(selectedMonth.year, selectedMonth.month, 1);

      expensesBox.add(
        Expense(
          id: id,
          title: ce.title,
          amount: ce.amount,
          category: ce.category,
          date: dateToUse,
          note: ce.note,
          isPaid: false,
        ),
      );
      added++;
    }

    if (!mounted) return;

    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Applied $added common expense(s) for ${DateFormat.yMMMM().format(selectedMonth)}',
          ),
        ),
      );
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No new expenses added (already exist in this month)'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeMode == ThemeMode.dark;
    final theme = Theme.of(context);

    Widget buildFilterButton(MonthlyFilter f, IconData icon, String label) {
      final selected = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _filter = f;
              if (f == MonthlyFilter.expense) {
                _expenseStatusFilter = ExpenseStatusFilter.all;
              }
            });
          },
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(0, 36),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withOpacity(0.6),
            ),
            backgroundColor: selected
                ? theme.colorScheme.primary
                : Colors.transparent,
            foregroundColor: selected ? theme.colorScheme.onPrimary : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      );
    }

    Widget buildExpenseStatusButton(
      ExpenseStatusFilter status,
      IconData icon,
      String label,
    ) {
      final selected = _expenseStatusFilter == status;
      final colorBase = isDark ? Colors.cyanAccent : theme.colorScheme.primary;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _expenseStatusFilter = status;
            });
          },
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(0, 34),
            side: BorderSide(
              color: selected ? colorBase : colorBase.withOpacity(0.4),
            ),
            backgroundColor: selected
                ? colorBase.withOpacity(0.18)
                : Colors.transparent,
            foregroundColor: selected ? colorBase : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: [
          Row(
            children: [
              Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              Switch(value: isDark, onChanged: (v) => widget.onToggleTheme(v)),
            ],
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _showCommonApplySheet,
            icon: const Icon(Icons.repeat, size: 18),
            label: const Text("Use Common"),
            style: TextButton.styleFrom(
              foregroundColor: isDark
                  ? Colors.cyanAccent
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: expenseBox.listenable(),
        builder: (context, Box<Expense> b, _) {
          final allExpenses =
              b.values
                  .where(
                    (e) =>
                        e.date.year == selectedMonth.year &&
                        e.date.month == selectedMonth.month,
                  )
                  .toList()
                ..sort((a, b) => b.date.compareTo(a.date));

          return ValueListenableBuilder(
            valueListenable: earningBox.listenable(),
            builder: (context, Box<Earning> eb, __) {
              final allEarnings =
                  eb.values
                      .where(
                        (e) =>
                            e.date.year == selectedMonth.year &&
                            e.date.month == selectedMonth.month,
                      )
                      .toList()
                    ..sort((a, b) => b.date.compareTo(a.date));

              final visibleExpenses = _applyExpenseFilter(allExpenses);
              final visibleEarnings = _applyEarningFilter(allEarnings);

              final displayedExpenses = displayedExpensesTotal(visibleExpenses);
              final displayedEarnings = displayedEarningsTotal(visibleEarnings);

              final paidCount = allExpenses.where((e) => e.isPaid).length;
              final progress = allExpenses.isEmpty
                  ? 0.0
                  : (paidCount / allExpenses.length);

              return SingleChildScrollView(
                child: Column(
                  children: [
                    // Month selector
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: previousMonth,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: _pickMonth,
                              child: Text(
                                DateFormat.yMMMM().format(selectedMonth),
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: nextMonth,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),

                    // Main filter buttons row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            buildFilterButton(
                              MonthlyFilter.all,
                              Icons.all_inclusive,
                              'All',
                            ),
                            buildFilterButton(
                              MonthlyFilter.income,
                              Icons.trending_up,
                              'Income',
                            ),
                            buildFilterButton(
                              MonthlyFilter.expense,
                              Icons.shopping_bag,
                              'Expense',
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Animated Paid/Unpaid row (only when Expense selected)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) {
                        return SizeTransition(
                          sizeFactor: animation,
                          axisAlignment: -1.0,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: _filter == MonthlyFilter.expense
                          ? Padding(
                              key: const ValueKey('subFilterRow'),
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                              child: Center(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      buildExpenseStatusButton(
                                        ExpenseStatusFilter.paid,
                                        Icons.check_circle,
                                        'Paid',
                                      ),
                                      buildExpenseStatusButton(
                                        ExpenseStatusFilter.unpaid,
                                        Icons.pending_actions,
                                        'Unpaid',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('subFilterEmpty'),
                              height: 0,
                            ),
                    ),

                    // Remaining Balance Card
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Remaining Balance',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '₹${remainingBalance.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: remainingBalance >= 0
                                        ? Colors.green
                                        : Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text('Earnings - Expenses'),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: showAddChoiceSheet,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add'),
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Earnings Card
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Earnings',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '₹${displayedEarnings.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text('Displayed earnings for this month'),
                              ],
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                openAddEditSheet(isEarning: true);
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Earn'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Expenses Card
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text('Expenses'),
                                Text(
                                  '₹${displayedExpenses.toStringAsFixed(2)}',
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                const Text('Pending'),
                                Text(
                                  '₹${pendingTotalForVisible(allExpenses).toStringAsFixed(2)}',
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                Text('${allExpenses.length} items'),
                                SizedBox(
                                  width: 100,
                                  child: LinearProgressIndicator(
                                    value: progress,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Category Summary
                    if (allExpenses.isNotEmpty)
                      Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Category Summary',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              ...defaultCategories.map((cat) {
                                final catItems = allExpenses
                                    .where((e) => e.category == cat)
                                    .toList();
                                if (catItems.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final total = catItems.fold(
                                  0.0,
                                  (s, e) => s + e.amount,
                                );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        color:
                                            categoryColors[cat] ?? Colors.black,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(cat)),
                                      Text('₹${total.toStringAsFixed(2)}'),
                                      const SizedBox(width: 8),
                                      Text('(${catItems.length} items)'),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Expenses',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Expenses List (filtered)
                    if (visibleExpenses.isNotEmpty)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visibleExpenses.length,
                        itemBuilder: (ctx, i) {
                          final e = visibleExpenses[i];

                          return Dismissible(
                            key: Key(
                              'expense_${e.id}_${e.date.millisecondsSinceEpoch}',
                            ),
                            background: Container(
                              color: Colors.green,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                              ),
                            ),
                            secondaryBackground: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                openAddEditSheet(expense: e, isEarning: false);
                                return false;
                              } else {
                                final shouldDelete = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("Delete Expense?"),
                                    content: const Text(
                                      "Do you want to delete this item?",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text("Cancel"),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text("Delete"),
                                      ),
                                    ],
                                  ),
                                );
                                return shouldDelete ?? false;
                              }
                            },
                            onDismissed: (direction) async {
                              final deletedCopy = e.copyWith();
                              await e.delete();
                              if (mounted) {
                                ScaffoldMessenger.of(
                                  context,
                                ).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Expense deleted'),
                                    action: SnackBarAction(
                                      label: 'UNDO',
                                      onPressed: () async {
                                        final box = Hive.box<Expense>(
                                          'expenses_box',
                                        );
                                        await box.add(deletedCopy);
                                        setState(() {});
                                      },
                                    ),
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            },
                            child: Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                onTap: () => openAddEditSheet(
                                  expense: e,
                                  isEarning: false,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      categoryColors[e.category] ??
                                      Colors.blueGrey,
                                  child: Icon(
                                    categoryIcons[e.category] ?? Icons.money,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  e.title.isNotEmpty ? e.title : e.category,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${DateFormat.yMMMd().format(e.date)} • ${e.note}'
                                      '${(e.autoReduceEnabled && e.totalBudget != null && e.totalBudget! > 0) ? ' • Budget: ₹${e.totalBudget!.toStringAsFixed(0)}' : ''}',
                                    ),
                                    if (e.autoReduceEnabled &&
                                        (e.dailyReduce ?? 0) > 0)
                                      Text(
                                        'Auto reducing ₹${e.dailyReduce!.toStringAsFixed(0)}/day (UTC)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.orangeAccent,
                                            ),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('₹${e.amount.toStringAsFixed(2)}'),
                                    const SizedBox(width: 8),
                                    Checkbox(
                                      value: e.isPaid,
                                      onChanged: (val) {
                                        setState(() {
                                          e.isPaid = val ?? false;
                                          e.save();
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                              "Delete Expense?",
                                            ),
                                            content: const Text(
                                              "This action cannot be undone.",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text("Cancel"),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text("Delete"),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed ?? false) {
                                          final deletedCopy = e.copyWith();
                                          await e.delete();
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).hideCurrentSnackBar();
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: const Text(
                                                  'Expense deleted',
                                                ),
                                                action: SnackBarAction(
                                                  label: 'UNDO',
                                                  onPressed: () async {
                                                    final box =
                                                        Hive.box<Expense>(
                                                          'expenses_box',
                                                        );
                                                    await box.add(deletedCopy);
                                                    setState(() {});
                                                  },
                                                ),
                                                duration: const Duration(
                                                  seconds: 4,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 12),

                    // Earnings Section
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Earnings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (visibleEarnings.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'No earnings for this month',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),

                    if (visibleEarnings.isNotEmpty)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: visibleEarnings.length,
                        itemBuilder: (ctx, i) {
                          final ent = visibleEarnings[i];

                          return Dismissible(
                            key: Key(
                              'earning_${ent.id}_${ent.date.millisecondsSinceEpoch}',
                            ),
                            background: Container(
                              color: Colors.green,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                              ),
                            ),
                            secondaryBackground: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                openAddEditSheet(earning: ent, isEarning: true);
                                return false;
                              } else {
                                final shouldDelete = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("Delete Earning?"),
                                    content: const Text(
                                      "Do you want to delete this earning?",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text("Cancel"),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text("Delete"),
                                      ),
                                    ],
                                  ),
                                );
                                return shouldDelete ?? false;
                              }
                            },
                            onDismissed: (direction) async {
                              final deletedCopy = ent.copyWith();
                              await ent.delete();
                              if (mounted) {
                                ScaffoldMessenger.of(
                                  context,
                                ).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Earning deleted'),
                                    action: SnackBarAction(
                                      label: 'UNDO',
                                      onPressed: () async {
                                        final box = Hive.box<Earning>(
                                          'earnings_box',
                                        );
                                        await box.add(deletedCopy);
                                        setState(() {});
                                      },
                                    ),
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            },
                            child: Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                onTap: () => openAddEditSheet(
                                  earning: ent,
                                  isEarning: true,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green,
                                  child: const Icon(
                                    Icons.payments,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  ent.title.isNotEmpty ? ent.title : ent.source,
                                ),
                                subtitle: Text(
                                  '${DateFormat.yMMMd().format(ent.date)} • ${ent.note}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('₹${ent.amount.toStringAsFixed(2)}'),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () async {
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                              "Delete Earning?",
                                            ),
                                            content: const Text(
                                              "This action cannot be undone.",
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text("Cancel"),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text("Delete"),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed ?? false) {
                                          final deletedCopy = ent.copyWith();
                                          await ent.delete();
                                          if (mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).hideCurrentSnackBar();
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: const Text(
                                                  'Earning deleted',
                                                ),
                                                action: SnackBarAction(
                                                  label: 'UNDO',
                                                  onPressed: () async {
                                                    final box =
                                                        Hive.box<Earning>(
                                                          'earnings_box',
                                                        );
                                                    await box.add(deletedCopy);
                                                    setState(() {});
                                                  },
                                                ),
                                                duration: const Duration(
                                                  seconds: 4,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showAddChoiceSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  double pendingTotalForVisible(List<Expense> allExpenses) {
    final unpaid = allExpenses
        .where((e) => !e.isPaid)
        .fold(0.0, (s, e) => s + e.amount);
    return unpaid;
  }
}


class MonthlyExpensesPage extends StatefulWidget {
  const MonthlyExpensesPage({Key? key}) : super(key: key);

  @override
  State<MonthlyExpensesPage> createState() => _MonthlyExpensesPageState();
}

class _MonthlyExpensesPageState extends State<MonthlyExpensesPage> {
  late Box<Expense> _expenseBox;
  List<Expense> _expenses = [];

  @override
  void initState() {
    super.initState();
    _expenseBox = Hive.box<Expense>('expenses_box');
    _loadExpenses();
  }

  void _loadExpenses() {
    _expenses = _expenseBox.values.toList();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Expenses')),
      body: _expenses.isEmpty
          ? const Center(child: Text('No expenses yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _expenses.length,
              itemBuilder: (context, index) {
                final e = _expenses[index];
                return LongPressDraggable(
                  data: e,
                  feedback: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.9,
                      child: ExpenseCard(expense: e, isDragging: true),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: ExpenseCard(expense: e),
                  ),
                  onDragStarted: () => HapticFeedback.lightImpact(),
                  child: ExpenseCard(expense: e),
                );
              },
            ),
    );
  }
}
