// lib/main.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'models/earning_expense.dart';
import 'page/overview.dart';
import 'page/monthly_expense.dart';
import 'page/common_expense.dart';
import 'page/settings.dart';

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

  // Defaults for auto-reduction time (UTC)
  final settings = Hive.box('settings');
  if (!settings.containsKey('auto_reduce_hour')) {
    settings.put('auto_reduce_hour', 23); // 23:55 UTC by default
  }
  if (!settings.containsKey('auto_reduce_minute')) {
    settings.put('auto_reduce_minute', 55);
  }

  await ensureRecurringSalaryFilled();
  await applyDailyReductions(); // catch-up for missed days
  scheduleDailyReduction(); // schedule daily auto-reduce at configured UTC time

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
// HELPER: AUTO DAILY REDUCTION FOR EXPENSES (UTC-BASED)
// =============================================================
DateTime _stripUtcDate(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);

Future<void> applyDailyReductions() async {
  final expenseBox = Hive.box<Expense>('expenses_box');
  final todayUtcDate = _stripUtcDate(DateTime.now().toUtc());

  for (final e in expenseBox.values) {
    if (!(e.autoReduceEnabled == true &&
        (e.dailyReduce ?? 0) > 0 &&
        e.amount > 0)) {
      continue;
    }

    final last = e.lastReducedDateUtc != null
        ? _stripUtcDate(e.lastReducedDateUtc!)
        : _stripUtcDate(e.date.toUtc());

    final daysSince = todayUtcDate.difference(last).inDays;
    if (daysSince <= 0) continue;

    e.amount = max(0, e.amount - (e.dailyReduce! * daysSince));;
    e.lastReducedDateUtc = todayUtcDate;
    e.reducedDaysCount = (e.reducedDaysCount ?? 0) + 1;

    await e.save();
  }
}

/// Schedules the next daily auto reduction at the configured UTC time.
/// Safe to call multiple times; extra calls do no harm.
Future<void> scheduleDailyReduction() async {
  final settings = Hive.box('settings');
  final userHour = settings.get('auto_reduce_hour', defaultValue: 23) as int;
  final userMinute = settings.get('auto_reduce_minute', defaultValue: 55) as int;

  // ✅ Pure local-time scheduling
  final now = DateTime.now(); // local device time
  final next = DateTime(now.year, now.month, now.day, userHour, userMinute);
  final nextTrigger = next.isBefore(now)
      ? next.add(const Duration(days: 1))
      : next;
  final duration = nextTrigger.difference(now);

  debugPrint('Next auto reduction scheduled at (Local): $nextTrigger');

  Future.delayed(duration, () async {
    await applyDailyReductions();
    await scheduleDailyReduction(); // re-run for next day
  });
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
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.teal.shade50,
          selectedItemColor: Colors.teal.shade700,
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.grey.shade900,
          selectedItemColor: Colors.cyanAccent,
          unselectedItemColor: Colors.grey,
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
            _selectedIndex = 0; // switch to Monthly tab
          });
        },
      ),
      const CommonExpensePage(),
      SettingsPage(
        onToggleTheme: widget.onToggleTheme,
        themeMode: widget.themeMode,
      ),
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
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// ======================= FILTER ENUMS ===========================
enum MonthlyFilter { all, income, expense }
enum ExpenseStatusFilter { all, paid, unpaid }
enum EarningStatusFilter { all, received, pending }


// ======================= ADD/EDIT SHEET =========================
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

  late double totalBudget;
  late double dailyReduce;
  late bool autoReduceEnabled;

  Timer? _countdownTimer;
  Duration? _timeToNextReduction;
  DateTime? _nextReductionTime; // ✅ local next trigger time

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
      category = defaultCategories.first;
      isPaid = false;
      totalBudget = 0;
      dailyReduce = 0;
      autoReduceEnabled = false;
    } else {
      final e = widget.expense;
      title = e?.title ?? '';
      amount = e?.amount ?? 0;
      category = e?.category ?? defaultCategories.first;
      date = e?.date ?? DateTime.now();
      note = e?.note ?? '';
      isPaid = e?.isPaid ?? false;
      totalBudget = e?.totalBudget ?? (e?.amount ?? 0);
      dailyReduce = e?.dailyReduce ?? 0;
      autoReduceEnabled = e?.autoReduceEnabled ?? false;

      source = 'Salary';
      _dateController = TextEditingController(
        text: DateFormat.yMd().format(date),
      );

      if (autoReduceEnabled) _startCountdownTimer();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _dateController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final totalMinutes = d.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  /// 🔁 Update countdown based on local device time
  void _updateCountdown() {
    final settings = Hive.box('settings');
    final hour = settings.get('auto_reduce_hour', defaultValue: 23) as int;
    final minute = settings.get('auto_reduce_minute', defaultValue: 55) as int;

    final now = DateTime.now(); // ✅ local time
    DateTime nextLocal = DateTime(now.year, now.month, now.day, hour, minute);

    if (!nextLocal.isAfter(now)) {
      nextLocal = nextLocal.add(const Duration(days: 1));
    }

    setState(() {
      _nextReductionTime = nextLocal;
      _timeToNextReduction = nextLocal.difference(now);
    });
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateCountdown();
    });
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

  void save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState?.save();

    if (widget.isEarning) {
      final box = Hive.box<Earning>('earnings_box');
      if (widget.earning != null) {
        final e = widget.earning!;
        e
          ..title = title
          ..amount = amount
          ..source = source
          ..date = date
          ..note = note;
        e.save();
      } else {
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        box.add(Earning(
          id: id,
          title: title,
          amount: amount,
          source: source,
          date: date,
          note: note,
        ));
      }
    } else {
      final box = Hive.box<Expense>('expenses_box');

      // =============================
      // 🧩 EXISTING EXPENSE (Edit)
      // =============================
      if (widget.expense != null) {
        final e = widget.expense!;
        e
          ..title = title
          ..amount = amount
          ..category = category
          ..date = date
          ..note = note
          ..isPaid = isPaid
          ..autoReduceEnabled = autoReduceEnabled;

        if (autoReduceEnabled) {
          if (totalBudget <= 0 && amount > 0) totalBudget = amount;

          e
            ..totalBudget = totalBudget
            ..dailyReduce = dailyReduce > 0 ? dailyReduce : null
            ..lastReducedDateUtc = null; // ✅ no UTC now

          // ✅ NEW CODE — Track start and progress
          e.autoReduceStartDate ??= DateTime.now();
          e.reducedDaysCount ??= 0;
        } else {
          e
            ..totalBudget = null
            ..dailyReduce = null
            ..lastReducedDateUtc = null
            ..autoReduceStartDate = null
            ..reducedDaysCount = null;
        }

        e.save();
      } 
      // =============================
      // 🧩 NEW EXPENSE (Add)
      // =============================
      else {
        if (autoReduceEnabled) {
          if (totalBudget <= 0 && amount > 0) {
            totalBudget = amount;
          } else if (totalBudget > 0 && amount <= 0) {
            amount = totalBudget;
          }
        }

        final id = DateTime.now().millisecondsSinceEpoch.toString();

        box.add(Expense(
          id: id,
          title: title,
          amount: amount,
          category: category,
          date: date,
          note: note,
          isPaid: isPaid,
          totalBudget: autoReduceEnabled ? totalBudget : null,
          dailyReduce: autoReduceEnabled && dailyReduce > 0 ? dailyReduce : null,
          autoReduceEnabled: autoReduceEnabled,
          lastReducedDateUtc: null, // removed UTC
          // ✅ NEW FIELDS
          autoReduceStartDate: autoReduceEnabled ? DateTime.now() : null,
          reducedDaysCount: autoReduceEnabled ? 0 : null,
        ));
      }
    }

    widget.onSaved?.call();
    Navigator.pop(context);
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

            if (!isE)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final selected = await showModalBottomSheet<CommonExpense>(
                      context: context,
                      builder: (ctx) => const SelectCommonExpenseSheet(),
                    );
                    if (selected != null) applyCommonExpense(selected);
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
              validator: (v) =>
                  (!isE && (v == null || v.isEmpty)) ? 'Required' : null,
              onSaved: (v) => title = v ?? '',
            ),
            const SizedBox(height: 10),

            TextFormField(
              initialValue: amount > 0 ? amount.toString() : '',
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
                    labelText: 'Source (e.g., Salary, Bonus)'),
                onSaved: (v) => source = v ?? '',
              ),

            const SizedBox(height: 10),

            if (!isE) ...[
              SwitchListTile(
                value: autoReduceEnabled,
                title: const Text('Enable Daily Auto Reduce'),
                subtitle: const Text(
                  'Automatically deduct a fixed amount every day from this expense.',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (v) {
                  setState(() {
                    autoReduceEnabled = v;
                  });
                  if (v) {
                    _startCountdownTimer();
                  } else {
                    _countdownTimer?.cancel();
                    setState(() {
                      _timeToNextReduction = null;
                      _nextReductionTime = null;
                    });
                  }
                },
              ),
              if (autoReduceEnabled) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _nextReductionTime != null
                        ? Text(
                            'Next auto reduce at ${DateFormat('hh:mm a').format(_nextReductionTime!)} '
                            '(${_formatDuration(_timeToNextReduction!)} remaining)',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : const Text('Calculating next auto reduce…'),
                  ),
                ),
                TextFormField(
                  initialValue: totalBudget > 0
                      ? totalBudget.toString()
                      : (amount > 0 ? amount.toString() : ''),
                  decoration:
                      const InputDecoration(labelText: 'Total Budget (e.g., 5500)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onSaved: (v) =>
                      totalBudget = double.tryParse(v ?? '0') ?? 0,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: dailyReduce > 0 ? dailyReduce.toString() : '',
                  decoration: const InputDecoration(
                      labelText: 'Daily Deduct Amount (e.g., 180)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onSaved: (v) =>
                      dailyReduce = double.tryParse(v ?? '0') ?? 0,
                ),
              ],
              const SizedBox(height: 8),
            ],

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
