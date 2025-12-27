import 'package:flutter/material.dart';

import '../../../data/services/break_reminder_service.dart';
import '../../../data/services/daily_usage_service.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';
import 'daily_usage_screen.dart';

class TimeManagementScreen extends StatefulWidget {
  const TimeManagementScreen({super.key});

  @override
  State<TimeManagementScreen> createState() => _TimeManagementScreenState();
}

class _TimeManagementScreenState extends State<TimeManagementScreen> {
  bool _breakReminderEnabled = false;
  int _intervalMinutes = 60;
  bool _loading = true;

  final List<int> _intervalOptions = [15, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await BreakReminderService.instance.ensureInitialized();
    if (!mounted) return;
    setState(() {
      _breakReminderEnabled = BreakReminderService.instance.enabled;
      _intervalMinutes = BreakReminderService.instance.intervalMinutes;
      _loading = false;
    });
  }

  Future<void> _toggleBreakReminder(bool value) async {
    setState(() {
      _breakReminderEnabled = value;
    });

    await BreakReminderService.instance.setEnabled(value);

    if (!mounted) return;
    final strings = AppLocalizations.of(context);
    final message = value
        ? strings?.timeMgmtEnabled ?? 'Đã bật nhắc nhở nghỉ giải lao'
        : strings?.timeMgmtDisabled ?? 'Đã tắt nhắc nhở nghỉ giải lao';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeInterval(int? minutes) async {
    if (minutes == null) return;
    setState(() {
      _intervalMinutes = minutes;
    });

    await BreakReminderService.instance.setIntervalMinutes(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings?.timeMgmtTitle ?? 'Quản lý thời gian'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.timer_outlined),
                  title: Text(
                    strings?.timeMgmtBreakReminder ?? 'Nhắc nhở nghỉ giải lao',
                  ),
                  subtitle: Text(
                    strings?.timeMgmtBreakReminderDesc ??
                        'Nhắc bạn nghỉ giải lao sau một khoảng thời gian',
                  ),
                  value: _breakReminderEnabled,
                  onChanged: _toggleBreakReminder,
                ),
                if (_breakReminderEnabled)
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(
                      strings?.timeMgmtIntervalLabel ?? 'Khoảng thời gian nhắc',
                    ),
                    subtitle: Text(
                      'Cứ mỗi $_intervalMinutes phút sẽ nhắc bạn nghỉ ngơi',
                    ),
                    trailing: DropdownButton<int>(
                      value: _intervalMinutes,
                      items: _intervalOptions
                          .map(
                            (m) => DropdownMenuItem<int>(
                              value: m,
                              child: Text('$m phút'),
                            ),
                          )
                          .toList(),
                      onChanged: _changeInterval,
                    ),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.access_time),
                  title: Text(
                    strings?.timeUsageTitle ?? 'Thời gian sử dụng hàng ngày',
                  ),
                  subtitle: const Text('Xem thời gian bạn dùng ứng dụng'),
                  onTap: () async {
                    // Đảm bảo đã lưu session hiện tại trước khi xem thống kê
                    await DailyUsageService.instance.getTodayUsage();
                    if (!mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DailyUsageScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}
