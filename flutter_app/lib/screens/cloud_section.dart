import 'package:flutter/material.dart';
import '../main.dart';
import '../data/cloud.dart';
import 'workspaces_admin_screen.dart';

/// The Settings card for cloud sync + workspace registration/approval. Talks to
/// the same Firebase backend as the web app, so a shop's data follows it across.
class CloudSection extends StatefulWidget {
  const CloudSection({super.key});
  @override
  State<CloudSection> createState() => _CloudSectionState();
}

class _CloudSectionState extends State<CloudSection> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    cloud.addListener(_onCloud);
    // Pull the latest approval state; cloud notifies listeners when it lands.
    cloud.refreshWorkspace();
  }

  @override
  void dispose() {
    cloud.removeListener(_onCloud);
    super.dispose();
  }

  void _onCloud() {
    if (mounted) setState(() {});
  }

  void _say(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ── sign-in flow ────────────────────────────────────────────────────────────
  Future<void> _link() async {
    final creds = await _askCredentials();
    if (creds == null) return;

    setState(() => _busy = true);
    try {
      final remote = await cloud.signIn(creds.email, creds.password,
          isNew: creds.isNew);
      final local = await cloud.localInfo();

      // Master account skips workspaces/direction entirely — it manages others.
      if (cloud.master) {
        _say(t('Signed in as MareegTech admin',
            'Waxaad u gashay sida maamulaha MareegTech'));
        return; // `finally` clears _busy
      }

      // Choose which side's data to keep.
      if (remote.has && (local.products > 0 || local.sales > 0)) {
        if (!mounted) return;
        final keep = await _askDirection(local, remote);
        if (keep == 'cloud') {
          await store.adoptCloudData();
          _say(t('Using cloud data', 'La isticmaalayo xogta cloud-ka'));
        } else if (keep == 'local') {
          await store.uploadLocalData();
          _say(t('This device\'s data uploaded',
              'Xogta qalabkan waa la soo geliyay'));
        }
      } else if (remote.has) {
        await store.adoptCloudData();
        _say(t('Cloud data restored', 'Xogta cloud-ka waa la soo celiyay'));
      } else {
        await store.uploadLocalData();
        _say(t('Data uploaded to cloud', 'Xogta waa la geliyay cloud-ka'));
      }

      // Register the workspace for approval if it isn't already.
      await cloud.refreshWorkspace();
      if (!cloud.wsRegistered && mounted) {
        final reg = await _askRegister();
        if (reg != null) {
          store.applyBusinessProfile(reg.name, reg.industry);
          store.seedIndustryProducts(reg.industry);
          await cloud.registerWorkspace(reg.name, reg.plan);
          store.planId = reg.plan;
          await cloud.refreshWorkspace();
          _say(t('Business submitted for approval',
              'Ganacsiga waa loo gudbiyay ansixin'));
        }
      }
    } catch (e) {
      _say(Cloud.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      await cloud.pull(force: false);
      await cloud.pushAll();
      store.reload();
      _say(t('Synced', 'La isku waafajiyay'));
    } catch (e) {
      _say(Cloud.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink() async {
    await cloud.signOut();
    if (!mounted) return;
    setState(() {});
  }

  // ── dialogs ─────────────────────────────────────────────────────────────────
  Future<_Creds?> _askCredentials() {
    final e = TextEditingController();
    final p = TextEditingController();
    var isNew = false;
    return showDialog<_Creds>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(isNew
              ? t('Create business account', 'Samee akoon ganacsi')
              : t('Link to cloud', 'Ku xir cloud-ka')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: e,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: t('Email', 'Iimayl')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: p,
                obscureText: true,
                decoration:
                    InputDecoration(labelText: t('Password', 'Furaha')),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(t('Create a new account', 'Samee akoon cusub')),
                value: isNew,
                onChanged: (v) => setD(() => isNew = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('Cancel', 'Jooji'))),
            FilledButton(
              onPressed: () {
                if (e.text.trim().isEmpty || p.text.isEmpty) return;
                Navigator.pop(
                    ctx, _Creds(e.text.trim(), p.text, isNew));
              },
              child: Text(isNew ? t('Create', 'Samee') : t('Sign in', 'Gal')),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askDirection(SyncInfo local, SyncInfo remote) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Which data to keep?', 'Xogtee la hayaa?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(
                'The cloud has ${remote.products} products, ${remote.sales} '
                    'sales.\nThis device has ${local.products} products, '
                    '${local.sales} sales.',
                'Cloud-ku wuxuu leeyahay ${remote.products} alaab, '
                    '${remote.sales} iib.\nQalabkanna wuxuu leeyahay '
                    '${local.products} alaab, ${local.sales} iib.')),
            const SizedBox(height: 8),
            Text(t('Pick one — the other is replaced.',
                'Mid dooro — kan kale waa la beddelayaa.'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7688))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Cancel', 'Jooji'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'local'),
              child: Text(t('Keep this device', 'Hay qalabkan'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'cloud'),
              child: Text(t('Use cloud', 'Isticmaal cloud'))),
        ],
      ),
    );
  }

  Future<_Reg?> _askRegister() {
    final nameC = TextEditingController(text: store.biz.name);
    var planId = 'MPQ50';
    var industry = store.biz.type.isNotEmpty ? store.biz.type : 'shop';
    if (!industries.containsKey(industry)) industry = 'shop';
    return showDialog<_Reg>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(t('Register business', 'Diiwaangeli ganacsi')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameC,
                  decoration: InputDecoration(
                      labelText: t('Business name', 'Magaca ganacsiga')),
                ),
                const SizedBox(height: 14),
                Text(t('Plan', 'Qorshaha'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7688))),
                ...plans.values.map((pl) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title:
                          Text(pl.label, style: const TextStyle(fontSize: 13)),
                      value: pl.id,
                      groupValue: planId,
                      onChanged: (v) => setD(() => planId = v ?? planId),
                    )),
                const SizedBox(height: 8),
                Text(t('Industry', 'Nooca ganacsiga'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7688))),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: industry,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: industries.keys
                      .map((k) => DropdownMenuItem(
                          value: k, child: Text(industryName(k))))
                      .toList(),
                  onChanged: (v) => setD(() => industry = v ?? industry),
                ),
                const SizedBox(height: 10),
                Text(
                    t(
                        'MareegTech approves new businesses before they go live.',
                        'MareegTech ayaa ansixiya ganacsiyada cusub ka hor inta '
                            'aan la shaqaysiin.'),
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFF98A2B3))),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t('Later', 'Hadhow'))),
            FilledButton(
              onPressed: () {
                if (nameC.text.trim().isEmpty) return;
                Navigator.pop(ctx, _Reg(nameC.text.trim(), planId, industry));
              },
              child: Text(t('Submit', 'Gudbi')),
            ),
          ],
        ),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!cloud.on) {
      return Card(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                t(
                    'Link this till to the cloud to back up automatically and '
                        'sync across devices. Works with your web business '
                        'account.',
                    'Ku xir khasnaddan cloud-ka si ay iskeed u kaydsato oo ay '
                        'ula socoto aaladaha kale. Waxay la shaqaysaa akoonkaaga '
                        'ganacsi ee web-ka.'),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF5C6B82)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined, color: kBlue),
              title: Text(t('Link to cloud', 'Ku xir cloud-ka')),
              subtitle: Text(t('Sign in or create a business account',
                  'Gal ama samee akoon ganacsi')),
              onTap: _busy ? null : _link,
            ),
          ],
        ),
      );
    }

    if (cloud.master) {
      return Card(
        child: Column(
          children: [
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: kNavy,
                  child: Icon(Icons.verified_user, color: Colors.white)),
              title: const Text('MareegTech admin',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(cloud.email),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.groups_outlined, color: kBlue),
              title: Text(t('Businesses console', 'Maamulka ganacsiyada')),
              subtitle: Text(t('Approve or revoke client businesses',
                  'Ansixi ama joojin ganacsiyada macaamiisha')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const WorkspacesAdminScreen())),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFD63B3B)),
              title: Text(t('Sign out of cloud', 'Ka bax cloud-ka')),
              onTap: _busy ? null : _unlink,
            ),
          ],
        ),
      );
    }

    // Client account.
    final approved = cloud.wsApproved;
    final pending = cloud.wsRegistered && !approved;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
                backgroundColor: approved ? kGreen : const Color(0xFFE0842B),
                child: Icon(approved ? Icons.cloud_done : Icons.hourglass_top,
                    color: Colors.white)),
            title: Text(
                cloud.wsName.isNotEmpty ? cloud.wsName : cloud.email,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(cloud.email),
          ),
          if (pending)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF4E5),
              padding: const EdgeInsets.all(12),
              child: Text(
                t(
                    'Pending approval — MareegTech must approve this business '
                        'before it goes live. Your data is safely backed up '
                        'meanwhile.',
                    'Sugaya ansixin — MareegTech waa inuu ansixiyaa ganacsigan '
                        'ka hor inta aan la shaqaysiin. Xogtaadu si ammaan ah ayay '
                        'u kaydsan tahay inta lagu jiro.'),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A5A00)),
              ),
            ),
          if (cloud.wsPlan.isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.workspace_premium_outlined, size: 20),
              title: Text('${t('Plan', 'Qorshaha')}: ${cloud.wsPlan}'),
            ),
          const Divider(height: 1),
          ListTile(
            leading: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, color: kBlue),
            title: Text(t('Sync now', 'Hadda isku waafaji')),
            subtitle: Text(cloud.lastError.isNotEmpty
                ? cloud.lastError
                : (cloud.status == 'ok'
                    ? t('Up to date', 'Waa la cusbooneysiiyay')
                    : t('Pull + push', 'Soo jiid + dir'))),
            onTap: _busy ? null : _syncNow,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFD63B3B)),
            title: Text(t('Sign out of cloud', 'Ka bax cloud-ka')),
            onTap: _busy ? null : _unlink,
          ),
        ],
      ),
    );
  }
}

class _Creds {
  final String email, password;
  final bool isNew;
  _Creds(this.email, this.password, this.isNew);
}

class _Reg {
  final String name, plan, industry;
  _Reg(this.name, this.plan, this.industry);
}
