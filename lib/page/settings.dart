import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

import '../main.dart';

// ======================= SETTINGS PAGE =========================
class SettingsPage extends StatefulWidget {
  final Function(bool) onToggleTheme;
  final ThemeMode themeMode;
  const SettingsPage({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final Box settings = Hive.box('settings');

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeMode == ThemeMode.dark;

    final recurringEnabled =
        settings.get('recurring_enabled', defaultValue: false) as bool;
    final recurringAmount =
        (settings.get('recurring_amount', defaultValue: 0.0) as num).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: isDark,
            onChanged: (v) => widget.onToggleTheme(v),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Daily Auto Reduction Time'),
            subtitle: Text('Tap to change'),
            onTap: () => _pickAutoReduceTime(context),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Auto reduce runs once per UTC day at this time.\nIf the app was closed, missed days are applied on next launch.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const Divider(),
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
                      icon: const Icon(Icons.edit),
                      tooltip: 'Set recurring salary',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}




Future<void> _pickAutoReduceTime(BuildContext context) async {
  final settings = Hive.box('settings');
  final currentHour = settings.get('auto_reduce_hour', defaultValue: 23) as int;
  final currentMinute = settings.get('auto_reduce_minute', defaultValue: 55) as int;

  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: currentHour, minute: currentMinute),
    helpText: 'Select Local Time for Daily Reduction',
  );

  if (picked != null) {
    await settings.put('auto_reduce_hour', picked.hour);
    await settings.put('auto_reduce_minute', picked.minute);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reduction time set to ${picked.format(context)} (Local Time)'),
      ),
    );

    await scheduleDailyReduction(); // reschedule immediately
  }
}

/// Global dialog for Recurring Salary (used from Settings)
Future<void> showRecurringSalaryDialog(BuildContext context) async {
  final settings = Hive.box('settings');
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
                  validator: (v) =>
                      v == null || double.tryParse(v) == null ? 'Invalid' : null,
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
