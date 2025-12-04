// lib/main.dart
import 'dart:io';
import 'dart:math';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

// =============================================================
// MAIN INITIALIZATION
// =============================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(ExpenseAdapter());
  Hive.registerAdapter(EarningAdapter());
  Hive.registerAdapter(CommonExpenseAdapter());

  await Hive.openBox<Expense>('expenses_box');
  await Hive.openBox<Earning>('earnings_box');
  await Hive.openBox<CommonExpense>('common_expenses_box');
  await Hive.openBox('settings');

  await ensureRecurringSalaryFilled();

  runApp(const ExpenseTrackerApp());
}

// =============================================================
// HELPER: RECURRING SALARY
// =============================================================
Future<void> ensureRecurringSalaryFilled() async {
  final settings = Hive.box('settings');
  final enabled =
      settings.get('recurring_enabled', defaultValue: false) as bool;
  final amount = (settings.get('recurring_amount', defaultValue: 0.0) as num)
      .toDouble();
  final lastAddedStr =
      settings.get('recurring_last_added', defaultValue: '') as String;

  if (!enabled || amount <= 0) return;

  DateTime now = DateTime.now();
  DateTime lastAdded;
  if (lastAddedStr.isEmpty) {
    lastAdded = DateTime(1970, 1);
  } else {
    final parts = lastAddedStr.split('-');
    lastAdded = DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  DateTime cursor = DateTime(lastAdded.year, lastAdded.month + 1);
  final earningsBox = Hive.box<Earning>('earnings_box');
  while (!isSameMonthOrAfter(cursor, now.add(const Duration(days: 1)))) {
    final exists = earningsBox.values.any(
      (e) =>
          e.source == 'Salary' &&
          e.date.year == cursor.year &&
          e.date.month == cursor.month,
    );
    if (!exists) {
      final id =
          DateTime.now().millisecondsSinceEpoch.toString() +
          '_' +
          cursor.toIso8601String();
      earningsBox.add(
        Earning(
          id: id,
          title: 'Salary',
          amount: amount,
          source: 'Salary',
          date: DateTime(cursor.year, cursor.month, 1),
          note: 'Recurring Salary',
        ),
      );
    }
    settings.put(
      'recurring_last_added',
      '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}',
    );
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
}

bool isSameMonthOrAfter(DateTime a, DateTime b) {
  if (a.year > b.year) return true;
  if (a.year == b.year && a.month >= b.month) return true;
  return false;
}

// =============================================================
// MAIN APP SHELL
// =============================================================
class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});
  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void toggleTheme(bool dark) {
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: MainShell(onToggleTheme: toggleTheme, themeMode: _themeMode),
    );
  }
}

// =============================================================
// MAIN NAVIGATION SHELL
// =============================================================
class MainShell extends StatefulWidget {
  final Function(bool) onToggleTheme;
  final ThemeMode themeMode;
  const MainShell({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  DateTime selectedMonth = DateTime.now();

  void _onItemTapped(int idx) => setState(() => _selectedIndex = idx);
  void _setSelectedMonth(DateTime month) =>
      setState(() => selectedMonth = DateTime(month.year, month.month));

  @override
  Widget build(BuildContext context) {
    final pages = [
      MonthlyPage(
        onToggleTheme: widget.onToggleTheme,
        themeMode: widget.themeMode,
        selectedMonth: selectedMonth,
        onMonthChanged: (dt) => setState(() => selectedMonth = dt),
      ),
      OverviewPage(
        selectedMonth: selectedMonth,
        onMonthSelected: (dt) {
          setState(() {
            selectedMonth = dt;
            _selectedIndex = 0; // 🔥 switch to Monthly tab
          });
        },

      ),
      const CommonExpensePage(),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: 'Monthly',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Common'),
        ],
      ),
    );
  }
}

// =============================================================
// COMMON EXPENSE MODEL + PAGE
// =============================================================
class CommonExpense extends HiveObject {
  CommonExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.note,
  });

  String id;
  String title;
  double amount;
  String category;
  String note;
}

class CommonExpenseAdapter extends TypeAdapter<CommonExpense> {
  @override
  final int typeId = 99;
  @override
  CommonExpense read(BinaryReader reader) {
    return CommonExpense(
      id: reader.readString(),
      title: reader.readString(),
      amount: reader.readDouble(),
      category: reader.readString(),
      note: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, CommonExpense obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeDouble(obj.amount);
    writer.writeString(obj.category);
    writer.writeString(obj.note);
  }
}

class CommonExpensePage extends StatefulWidget {
  const CommonExpensePage({super.key});
  @override
  State<CommonExpensePage> createState() => _CommonExpensePageState();
}

class _CommonExpensePageState extends State<CommonExpensePage> {
  final Box<CommonExpense> commonBox = Hive.box<CommonExpense>(
    'common_expenses_box',
  );

  void openAddEdit({CommonExpense? item}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: AddCommonExpenseSheet(
          item: item,
          onSaved: () => setState(() {}),
        ),
      ),
    );
  }

  double get total => commonBox.values.fold(0.0, (s, e) => s + e.amount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Common Expenses')),
      body: ValueListenableBuilder(
        valueListenable: commonBox.listenable(),
        builder: (context, Box<CommonExpense> box, _) {
          final items = box.values.toList();
          if (items.isEmpty) {
            return const Center(child: Text("No common expenses yet"));
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Total: ₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              ...items.map(
                (e) => Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.repeat),
                    title: Text(e.title),
                    subtitle: Text('${e.category} • ${e.note}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('₹${e.amount.toStringAsFixed(2)}'),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await e.delete();
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    onTap: () => openAddEdit(item: e),
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openAddEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// =============================================================
// CONSTANTS & MODELS
// =============================================================
const List<String> defaultCategories = [
  'Food',
  'Travel',
  'Shopping',
  'Bills',
  'Fuel',
  'Rent',
  'Life',
  'Others',
];

const Map<String, IconData> categoryIcons = {
  'Food': Icons.restaurant,
  'Travel': Icons.flight,
  'Shopping': Icons.shopping_cart,
  'Bills': Icons.receipt_long,
  'Fuel': Icons.local_gas_station,
  'Rent': Icons.home,
  'Life': Icons.favorite,
  'Others': Icons.more_horiz,
};

const Map<String, Color> categoryColors = {
  'Food': Colors.orange,
  'Travel': Colors.blue,
  'Shopping': Colors.purple,
  'Bills': Colors.grey,
  'Fuel': Colors.red,
  'Rent': Colors.teal,
  'Life': Colors.pink,
  'Others': Colors.green,
};

class AddCommonExpenseSheet extends StatefulWidget {
  final CommonExpense? item;
  final VoidCallback onSaved;
  const AddCommonExpenseSheet({super.key, this.item, required this.onSaved});

  @override
  State<AddCommonExpenseSheet> createState() => _AddCommonExpenseSheetState();
}

class _AddCommonExpenseSheetState extends State<AddCommonExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  late String title;
  late double amount;
  late String category;
  late String note;

  @override
  void initState() {
    super.initState();
    title = widget.item?.title ?? '';
    amount = widget.item?.amount ?? 0;
    category = widget.item?.category ?? defaultCategories.first;
    note = widget.item?.note ?? '';
  }

  void save() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final box = Hive.box<CommonExpense>('common_expenses_box');
    if (widget.item != null) {
      final e = widget.item!;
      e.title = title;
      e.amount = amount;
      e.category = category;
      e.note = note;
      e.save();
    } else {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      box.add(
        CommonExpense(
          id: id,
          title: title,
          amount: amount,
          category: category,
          note: note,
        ),
      );
    }
    widget.onSaved();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Text(
                "Add / Edit Common Expense",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                onSaved: (v) => title = v ?? '',
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: amount > 0 ? amount.toString() : '',
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) =>
                    v == null || double.tryParse(v) == null ? 'Invalid' : null,
                onSaved: (v) => amount = double.tryParse(v ?? '0') ?? 0,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: category,
                items: defaultCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => category = v!),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: note,
                decoration: const InputDecoration(labelText: 'Note'),
                onSaved: (v) => note = v ?? '',
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}

class Expense extends HiveObject {
  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.note,
    required this.isPaid,
  });

  String id;
  String title;
  double amount;
  String category;
  DateTime date;
  String note;
  bool isPaid;

  Expense copyWith({
    String? id,
    String? title,
    double? amount,
    String? category,
    DateTime? date,
    String? note,
    bool? isPaid,
  }) {
    return Expense(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      note: note ?? this.note,
      isPaid: isPaid ?? this.isPaid,
    );
  }
}

class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  final int typeId = 0;

  @override
  Expense read(BinaryReader reader) {
    return Expense(
      id: reader.readString(),
      title: reader.readString(),
      amount: reader.readDouble(),
      category: reader.readString(),
      date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      note: reader.readString(),
      isPaid: reader.readBool(),
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

/// ===== FILTER ENUMS for Monthly Page =====
enum MonthlyFilter { all, income, expense }

enum ExpenseStatusFilter { all, paid, unpaid }

/// ===== MONTHLY PAGE =====
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

  // Quick sheet where FAB lets user choose add Expense / Earning
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

  /// Apply filter to expenses
  List<Expense> _applyExpenseFilter(List<Expense> expenses) {
    switch (_filter) {
      case MonthlyFilter.all:
        return expenses; // show all
      case MonthlyFilter.income:
        return []; // no expenses in income view
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

  /// Apply filter to earnings
  List<Earning> _applyEarningFilter(List<Earning> earnings) {
    switch (_filter) {
      case MonthlyFilter.all:
        return earnings; // show earnings
      case MonthlyFilter.income:
        return earnings; // all earnings
      case MonthlyFilter.expense:
        return []; // focus on expenses only
    }
  }

  /// 👉 Use Common Expense (multi-select) from Monthly tab
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
          isPaid: false, // keep as Unpaid as requested
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

    // Helper for main filter buttons (Style B: Outlined buttons with icons)
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

    // Helper for expense sub-filter buttons (Paid / Unpaid)
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
          // Theme Toggle Switch
          Row(
            children: [
              Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              Switch(value: isDark, onChanged: (v) => widget.onToggleTheme(v)),
            ],
          ),
          const SizedBox(width: 8),

          // Common Expense Quick Button
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
                                subtitle: Text(
                                  '${DateFormat.yMMMd().format(e.date)} • ${e.note}',
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
                                        final confirmed = await showDialog<bool>(
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

                    // ------------------ Earnings Section (filtered) ------------------
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
                                        final confirmed = await showDialog<bool>(
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
    // pending: all unpaid expenses for this month
    final unpaid = allExpenses
        .where((e) => !e.isPaid)
        .fold(0.0, (s, e) => s + e.amount);
    return unpaid;
  }
}

/// ===== OVERVIEW PAGE =====
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
  final Box settings = Hive.box('settings');

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
    keys.sort(
      (a, b) => b.compareTo(a),
    ); // descending lexicographic yyyy-MM works
    return keys;
  }

  Color _bgForBalance(double balance, BuildContext context) {
    if (balance > 0) {
      // soft green background for positive
      return Theme.of(context).brightness == Brightness.dark
          ? Colors.green.shade900.withOpacity(0.18)
          : Colors.green.shade50;
    } else if (balance < 0) {
      // soft red for negative
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
    // ensure last point is end of month
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

    final recurringEnabled =
        settings.get('recurring_enabled', defaultValue: false) as bool;
    final recurringAmount =
        (settings.get('recurring_amount', defaultValue: 0.0) as num).toDouble();

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
          setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            // Recurring salary control header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Recurring Salary',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              recurringEnabled
                                  ? 'Enabled — ₹${recurringAmount.toStringAsFixed(2)} / month'
                                  : 'Disabled',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await showRecurringSalaryDialog(context);
                          await ensureRecurringSalaryFilled();
                          setState(() {});
                        },
                        icon: const Icon(Icons.repeat),
                        tooltip: 'Set recurring salary',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Month cards list
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
                          // Left: Month + metrics + sparkline
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
                                // Sparkline as mini bars (daily-sampled balance)
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

                          // Right: Balance
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

  /// Shows a dialog to set recurring salary options (amount + enabled)
  Future<void> showRecurringSalaryDialog(BuildContext context) async {
    final enabled =
        settings.get('recurring_enabled', defaultValue: false) as bool;
    final amount = (settings.get('recurring_amount', defaultValue: 0.0) as num)
        .toDouble();

    bool _enabled = enabled;
    double _amount = amount;
    final formKey = GlobalKey<FormState>();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recurring Salary'),
        content: StatefulBuilder(
          builder: (ctx2, setSt) {
            return Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: _enabled,
                    title: const Text('Enable recurring salary'),
                    onChanged: (v) => setSt(() => _enabled = v),
                  ),
                  TextFormField(
                    initialValue: _amount > 0 ? _amount.toString() : '',
                    decoration: const InputDecoration(
                      labelText: 'Amount (monthly)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) => v == null || double.tryParse(v) == null
                        ? 'Invalid'
                        : null,
                    onSaved: (v) => _amount = double.tryParse(v ?? '0') ?? 0,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'When enabled, salary is added on 1st of month if missing.',
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final form = formKey.currentState;
              form?.save();
              if (_enabled && _amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter valid amount')),
                );
                return;
              }
              settings.put('recurring_enabled', _enabled);
              settings.put('recurring_amount', _amount);
              if (_enabled) {
                final now = DateTime.now();
                final prev = DateTime(now.year, now.month - 1);
                settings.put(
                  'recurring_last_added',
                  '${prev.year}-${prev.month.toString().padLeft(2, '0')}',
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// ===== ADD/EDIT SHEET =====
class AddEditSheet extends StatefulWidget {
  final Expense? expense;
  final Earning? earning;
  final bool isEarning;
  final VoidCallback? onSaved;

  const AddEditSheet({
    super.key,
    this.expense,
    this.earning,
    this.isEarning = false,
    this.onSaved,
  });

  @override
  State<AddEditSheet> createState() => _AddEditSheetState();
}

class _AddEditSheetState extends State<AddEditSheet> {
  final _formKey = GlobalKey<FormState>();

  late String title;
  late double amount;
  late DateTime date;
  late String note;
  late TextEditingController _dateController;

  late String category;
  late bool isPaid;

  late String source;

  @override
  void initState() {
    super.initState();
    if (widget.isEarning) {
      final e = widget.earning;
      title = e?.title ?? '';
      amount = e?.amount ?? 0;
      source = e?.source ?? 'Salary';
      date = e?.date ?? DateTime.now();
      note = e?.note ?? '';
      _dateController = TextEditingController(
        text: DateFormat.yMd().format(date),
      );
    } else {
      final e = widget.expense;
      title = e?.title ?? '';
      amount = e?.amount ?? 0;
      category = e?.category ?? defaultCategories.first;
      date = e?.date ?? DateTime.now();
      note = e?.note ?? '';
      isPaid = e?.isPaid ?? false;
      _dateController = TextEditingController(
        text: DateFormat.yMd().format(date),
      );
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  /// Prefill fields when a CommonExpense is chosen
  void applyCommonExpense(CommonExpense ce) {
    setState(() {
      title = ce.title;
      amount = ce.amount;
      category = ce.category;
      note = ce.note;
    });
  }

  /// Save current form
  void save() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

      if (widget.isEarning) {
        final box = Hive.box<Earning>('earnings_box');
        if (widget.earning != null) {
          final e = widget.earning!;
          e.title = title;
          e.amount = amount;
          e.source = source;
          e.date = date;
          e.note = note;
          e.save();
        } else {
          final id = DateTime.now().millisecondsSinceEpoch.toString();
          box.add(
            Earning(
              id: id,
              title: title,
              amount: amount,
              source: source,
              date: date,
              note: note,
            ),
          );
        }
      } else {
        final box = Hive.box<Expense>('expenses_box');
        if (widget.expense != null) {
          final e = widget.expense!;
          e.title = title;
          e.amount = amount;
          e.category = category;
          e.date = date;
          e.note = note;
          e.isPaid = isPaid;
          e.save();
        } else {
          final id = DateTime.now().millisecondsSinceEpoch.toString();
          box.add(
            Expense(
              id: id,
              title: title,
              amount: amount,
              category: category,
              date: date,
              note: note,
              isPaid: isPaid,
            ),
          );
        }
      }

      widget.onSaved?.call();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isE = widget.isEarning;
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isE ? 'Add / Edit Earning' : 'Add / Edit Expense',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // “Use Common Expense” button (only for Expense mode)
            if (!isE)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final selected = await showModalBottomSheet<CommonExpense>(
                      context: context,
                      builder: (ctx) => const SelectCommonExpenseSheet(),
                    );
                    if (selected != null) {
                      applyCommonExpense(selected);
                    }
                  },
                  icon: const Icon(Icons.library_books_outlined),
                  label: const Text("Use Common Expense"),
                ),
              ),

            TextFormField(
              initialValue: title,
              decoration: InputDecoration(
                labelText: isE ? 'Title (optional)' : 'Title',
              ),
              validator: (v) {
                if (!isE) return v == null || v.isEmpty ? 'Required' : null;
                return null;
              },
              onSaved: (v) => title = v ?? '',
            ),
            const SizedBox(height: 10),

            TextFormField(
              initialValue: amount > 0 ? amount.toString() : '',
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) =>
                  v == null || double.tryParse(v) == null ? 'Invalid' : null,
              onSaved: (v) => amount = double.tryParse(v ?? '0') ?? 0,
            ),
            const SizedBox(height: 10),

            if (!isE)
              DropdownButtonFormField<String>(
                value: category,
                items: defaultCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => category = v!),
                decoration: const InputDecoration(labelText: 'Category'),
              ),

            if (isE)
              TextFormField(
                initialValue: source,
                decoration: const InputDecoration(
                  labelText: 'Source (e.g., Salary, Bonus)',
                ),
                onSaved: (v) => source = v ?? '',
              ),

            const SizedBox(height: 10),

            TextFormField(
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Date',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              controller: _dateController,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() {
                    date = picked;
                    _dateController.text = DateFormat.yMd().format(date);
                  });
                }
              },
            ),

            const SizedBox(height: 10),

            TextFormField(
              initialValue: note,
              decoration: const InputDecoration(labelText: 'Note'),
              onSaved: (v) => note = v ?? '',
            ),

            const SizedBox(height: 10),

            if (!isE)
              SwitchListTile(
                value: isPaid,
                title: const Text('Paid'),
                onChanged: (v) => setState(() => isPaid = v),
              ),

            const SizedBox(height: 20),
            ElevatedButton(onPressed: save, child: const Text('Save')),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet selector for Common Expenses (single-select for Add/Edit)
class SelectCommonExpenseSheet extends StatelessWidget {
  const SelectCommonExpenseSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<CommonExpense>('common_expenses_box');
    final items = box.values.toList();

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "No Common Expenses available. Add some in the Common tab.",
        ),
      );
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              "Select a Common Expense to reuse",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...items.map(
            (e) => ListTile(
              leading: const Icon(Icons.repeat),
              title: Text(e.title),
              subtitle: Text('${e.category} • ₹${e.amount.toStringAsFixed(2)}'),
              onTap: () => Navigator.pop(context, e),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
