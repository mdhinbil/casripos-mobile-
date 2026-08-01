import 'package:flutter/material.dart';
import '../main.dart';

/// A real activity log: the newest events (sales, saves) the app has recorded
/// on this device, newest first.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});
  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('Clear log', 'Tirtir diiwaanka')),
        content: Text(t('Remove all log entries on this device?',
            'Ka tirtir dhammaan diiwaanka qalabkan?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel', 'Jooji'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Clear', 'Tirtir'))),
        ],
      ),
    );
    if (ok == true) setState(() => store.clearLog());
  }

  @override
  Widget build(BuildContext context) {
    final logs = store.logs;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Log', 'Diiwaanka')),
        actions: [
          if (logs.isNotEmpty)
            IconButton(
                onPressed: _clear,
                tooltip: t('Clear', 'Tirtir'),
                icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Text(t('No activity yet', 'Weli dhaqdhaqaaq ma jiro'),
                  style: const TextStyle(color: Color(0xFF6B7688))))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = logs[i];
                final d = e.when;
                final stamp =
                    '${d.day}/${d.month} ${_two(d.hour)}:${_two(d.minute)}';
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.circle, size: 8, color: kBlue),
                  title: Text(e.msg, style: const TextStyle(fontSize: 13)),
                  trailing: Text(stamp,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF8B97A8))),
                );
              },
            ),
    );
  }
}
