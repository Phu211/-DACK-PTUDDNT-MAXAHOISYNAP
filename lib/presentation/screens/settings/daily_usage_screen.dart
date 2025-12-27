import 'package:flutter/material.dart';

import '../../../data/services/daily_usage_service.dart';
import '../../../flutter_gen/gen_l10n/app_localizations.dart';

class DailyUsageScreen extends StatelessWidget {
  const DailyUsageScreen({super.key});

  String _formatDuration(Duration d) {
    final totalMinutes = d.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '$minutes phút';
    return '${hours}h ${minutes}p';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings?.timeUsageTitle ?? 'Thời gian sử dụng hàng ngày'),
      ),
      body: FutureBuilder<Map<String, Duration>>(
        future: DailyUsageService.instance.getUsageForLastDays(7),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data ?? {};
          if (data.isEmpty) {
            return Center(
              child: Text(
                strings?.timeUsageNoData ?? 'Chưa có dữ liệu thời gian sử dụng',
                style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                textAlign: TextAlign.center,
              ),
            );
          }

          final todayKey = DateTime.now();
          final todayString =
              '${todayKey.year.toString().padLeft(4, '0')}-${todayKey.month.toString().padLeft(2, '0')}-${todayKey.day.toString().padLeft(2, '0')}';
          final todayUsage = data[todayString] ?? Duration.zero;

          final sortedKeys = data.keys.toList()
            ..sort((a, b) => b.compareTo(a)); // mới nhất trước

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.today),
                  title: Text(strings?.timeUsageToday ?? 'Hôm nay'),
                  subtitle: Text(_formatDuration(todayUsage)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                strings?.timeUsageLast7Days ?? '7 ngày gần đây',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...sortedKeys.map((key) {
                final usage = data[key] ?? Duration.zero;
                return ListTile(
                  leading: const Icon(Icons.calendar_today_outlined, size: 20),
                  title: Text(key),
                  trailing: Text(_formatDuration(usage)),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }
}


