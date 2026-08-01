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
  Workspace? _ws;

  @override
  void initState() {
    super.initState();
    cloud.addListener(_onCloud);
    _refreshWorkspace();
  }

  @override
  void dispose() {
    cloud.removeListener(_onCloud);
    super.dispose();
  }

  void _onCloud() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshWorkspace() async {
    if (cloud.on && !cloud.master) {
      try {
        final ws = await cloud.workspaceStatus();
        if (mounted) setState(() => _ws = ws);
      } catch (_) {}
    }
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
        _say('Signed in as MareegTech admin');
        return; // `finally` clears _busy
      }

      // Choose which side's data to keep.
      if (remote.has && (local.products > 0 || local.sales > 0)) {
        if (!mounted) return;
        final keep = await _askDirection(local, remote);
        if (keep == 'cloud') {
          await store.adoptCloudData();
          _say('Using cloud data');
        } else if (keep == 'local') {
          await store.uploadLocalData();
          _say('This device\'s data uploaded');
        }
      } else if (remote.has) {
        await store.adoptCloudData();
        _say('Cloud data restored');
      } else {
        await store.uploadLocalData();
        _say('Data uploaded to cloud');
      }

      // Register the workspace for approval if it isn't already.
      _ws = await cloud.workspaceStatus();
      if (_ws == null && mounted) {
        final reg = await _askRegister();
        if (reg != null) {
          await cloud.registerWorkspace(reg.name, reg.plan);
          store.planId = reg.plan;
          _ws = await cloud.workspaceStatus();
          _say('Workspace submitted for approval');
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
      _say('Synced');
    } catch (e) {
      _say(Cloud.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink() async {
    await cloud.signOut();
    if (!mounted) return;
    setState(() => _ws = null);
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
          title: Text(isNew ? 'Create workspace account' : 'Link to cloud'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: e,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: p,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Create a new account'),
                value: isNew,
                onChanged: (v) => setD(() => isNew = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (e.text.trim().isEmpty || p.text.isEmpty) return;
                Navigator.pop(
                    ctx, _Creds(e.text.trim(), p.text, isNew));
              },
              child: Text(isNew ? 'Create' : 'Sign in'),
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
        title: const Text('Which data to keep?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The cloud has ${remote.products} products, ${remote.sales} '
                'sales.\nThis device has ${local.products} products, '
                '${local.sales} sales.'),
            const SizedBox(height: 8),
            const Text('Pick one — the other is replaced.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7688))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'local'),
              child: const Text('Keep this device')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'cloud'),
              child: const Text('Use cloud')),
        ],
      ),
    );
  }

  Future<_Reg?> _askRegister() {
    final nameC = TextEditingController(text: store.biz.name);
    var planId = 'MPQ50';
    return showDialog<_Reg>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Register workspace'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameC,
                decoration:
                    const InputDecoration(labelText: 'Workspace name'),
              ),
              const SizedBox(height: 12),
              const Text('Plan',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7688))),
              ...plans.values.map((pl) => RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(pl.label, style: const TextStyle(fontSize: 13)),
                    value: pl.id,
                    groupValue: planId,
                    onChanged: (v) => setD(() => planId = v ?? planId),
                  )),
              const Text(
                  'MareegTech approves new workspaces before they go live.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF98A2B3))),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Later')),
            FilledButton(
              onPressed: () {
                if (nameC.text.trim().isEmpty) return;
                Navigator.pop(ctx, _Reg(nameC.text.trim(), planId));
              },
              child: const Text('Submit'),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                'Link this till to the cloud to back up automatically and sync '
                'across devices. Works with your web workspace account.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF5C6B82)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined, color: kBlue),
              title: const Text('Link to cloud'),
              subtitle: const Text('Sign in or create a workspace account'),
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
              title: const Text('Workspaces console'),
              subtitle: const Text('Approve or revoke client workspaces'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const WorkspacesAdminScreen())),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFD63B3B)),
              title: const Text('Sign out of cloud'),
              onTap: _busy ? null : _unlink,
            ),
          ],
        ),
      );
    }

    // Client account.
    final approved = _ws?.approved ?? false;
    final pending = _ws != null && !approved;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
                backgroundColor: approved ? kGreen : const Color(0xFFE0842B),
                child: Icon(approved ? Icons.cloud_done : Icons.hourglass_top,
                    color: Colors.white)),
            title: Text(
                (_ws?.name.isNotEmpty ?? false) ? _ws!.name : cloud.email,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(cloud.email),
          ),
          if (pending)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF4E5),
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Pending approval — MareegTech must approve this workspace '
                'before it goes live. Your data is safely backed up meanwhile.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF8A5A00)),
              ),
            ),
          if (_ws?.plan.isNotEmpty == true)
            ListTile(
              dense: true,
              leading: const Icon(Icons.workspace_premium_outlined, size: 20),
              title: Text('Plan: ${_ws!.plan}'),
            ),
          const Divider(height: 1),
          ListTile(
            leading: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, color: kBlue),
            title: const Text('Sync now'),
            subtitle: Text(cloud.lastError.isNotEmpty
                ? cloud.lastError
                : (cloud.status == 'ok' ? 'Up to date' : 'Pull + push')),
            onTap: _busy ? null : _syncNow,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFD63B3B)),
            title: const Text('Sign out of cloud'),
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
  final String name, plan;
  _Reg(this.name, this.plan);
}
