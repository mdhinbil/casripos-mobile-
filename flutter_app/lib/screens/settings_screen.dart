import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import 'cloud_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Writes the backup to a file and hands it to the share sheet, so it can go
  /// to WhatsApp, Drive, or a cable — whatever the shop actually uses.
  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final json = store.exportBackup();
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final f = File('${dir.path}/casripos-backup-$stamp.json');
      await f.writeAsString(json);
      await Share.shareXFiles([XFile(f.path)], subject: 'Casri POS backup');
    } catch (e) {
      _say('Could not export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Imports a backup — including one exported from the old web version, since
  /// both write the same format. The backup text is pasted in directly (from a
  /// shared file opened in any app, or from the web export), which keeps restore
  /// dependency-free and works the same on every device.
  Future<void> _import() async {
    final ctrl = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore from backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Paste the contents of a backup below. This replaces everything '
                'on this device. Export a backup first if you are unsure.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '{ "biz": … }',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (go != true) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _busy = true);
    try {
      final err = await store.importBackup(text);
      if (err != null) {
        _say(err);
      } else {
        _say('Backup restored');
        setState(() {});
      }
    } catch (e) {
      _say('Could not import: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = store.biz;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 30),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: kBlue,
                      child: Icon(Icons.storefront, color: Colors.white)),
                  title: Text(b.name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${b.type} · ${b.currency}'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(store.user?.name ?? 'Admin'),
                  subtitle: Text(store.user?.role ?? 'admin'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _SectionLabel('Cloud & workspace'),
          const CloudSection(),
          const SizedBox(height: 14),
          const _SectionLabel('Backup & restore'),
          Card(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    'Everything is stored on THIS device. Export a backup '
                    'regularly — if the phone is lost or reset, it is the only '
                    'way to get your sales and products back.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF5C6B82)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined, color: kBlue),
                  title: const Text('Export backup'),
                  subtitle: const Text('Save or share a .json file'),
                  onTap: _busy ? null : _export,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.upload_outlined, color: kBlue),
                  title: const Text('Import backup'),
                  subtitle:
                      const Text('Also reads backups from the old app'),
                  onTap: _busy ? null : _import,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _SectionLabel('Account'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFD63B3B)),
              title: const Text('Sign out',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFFD63B3B))),
              onTap: () => store.signOut(),
            ),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text('Casri POS 2.0',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF98A2B3))),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 7),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: .7,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7688))),
      );
}
