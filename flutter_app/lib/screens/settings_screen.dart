import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../data/cloud.dart';
import 'cloud_section.dart';
import 'staff_screen.dart';

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
      _say('${t('Could not export', 'Lama soo saari karo')}: $e');
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
        title: Text(t('Restore from backup', 'Ka soo celi kayd')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(
                'Paste the contents of a backup below. This replaces everything '
                    'on this device. Export a backup first if you are unsure.',
                'Hoos ku dhaji nuxurka kaydka. Tani waxay beddeshaa wax walba oo '
                    'qalabkan ku jira. Marka hore kaydka soo saar haddii aadan '
                    'hubin.')),
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
              child: Text(t('Cancel', 'Jooji'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Restore', 'Soo celi'))),
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
        _say(t('Backup restored', 'Kaydka waa la soo celiyay'));
        setState(() {});
      }
    } catch (e) {
      _say('${t('Could not import', 'Lama soo deji karo')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = store.biz;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(t('Settings', 'Dejinta'))),
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
          _SectionLabel(t('Language', 'Luqadda')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                _LangBtn('English', store.lang == 'en',
                    () => setState(() => store.setLang('en'))),
                const SizedBox(width: 8),
                _LangBtn('Soomaali', store.lang == 'so',
                    () => setState(() => store.setLang('so'))),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          _SectionLabel(t('Cloud & business', 'Cloud & ganacsi')),
          const CloudSection(),
          const SizedBox(height: 14),
          _SectionLabel(t('People who sign in', 'Dadka gala')),
          Card(
            child: ListTile(
              leading: const Icon(Icons.group_outlined, color: kBlue),
              title: Text(t('People who sign in', 'Dadka gala')),
              // How many tills are in use, said on the way in rather than
              // after somebody presses Add and is turned away.
              subtitle: Text(store.registerLimit == 0
                  ? '${store.bizStaff.length} ${t('accounts', 'akoon')}'
                  : '${store.registersUsed}/${store.registerLimit} '
                      '${t('cash registers used', 'rijistar la isticmaalay')}'
                      ' · ${store.bizStaff.length} ${t('accounts', 'akoon')}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const StaffScreen()));
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: 14),
          _SectionLabel(t('Backup & restore', 'Kaydinta & soo celinta')),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text(
                    t(
                        'Everything is stored on THIS device. Export a backup '
                            'regularly — if the phone is lost or reset, it is the '
                            'only way to get your sales and products back.',
                        'Wax walba waxay ku kaydsan yihiin qalabkan. Had iyo jeer '
                            'kaydka soo saar — haddii telefoonku lumo ama dib loo '
                            'dejiyo, sidaas keliya ayaad iibkaaga iyo alaabtaada '
                            'ku soo celin kartaa.'),
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF5C6B82)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined, color: kBlue),
                  title: Text(t('Export backup', 'Soo saar kaydka')),
                  subtitle: Text(
                      t('Save or share a .json file', 'Kaydi ama wadaag file')),
                  onTap: _busy ? null : _export,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.upload_outlined, color: kBlue),
                  title: Text(t('Import backup', 'Soo deji kaydka')),
                  subtitle: Text(t('Also reads backups from the old app',
                      'Waxay sidoo kale akhrida kaydka appka hore')),
                  onTap: _busy ? null : _import,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionLabel(t('Account', 'Akoonka')),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFD63B3B)),
              title: Text(t('Sign out', 'Ka bax'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFFD63B3B))),
              onTap: () async {
                store.signOut(); // local first, then cloud (no screen flash)
                await cloud.signOut();
              },
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

class _LangBtn extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _LangBtn(this.label, this.on, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: on ? kBlue : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? kBlue : const Color(0xFFD8E0EA)),
            ),
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: on ? Colors.white : const Color(0xFF44536B))),
          ),
        ),
      );
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
