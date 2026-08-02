import 'package:flutter/material.dart';
import '../main.dart';
import '../data/cloud.dart';

/// The front door. A workspace (cloud) account is the primary sign-in — the same
/// account the web app uses — so a shop's data and approval follow it here. A
/// "Staff" tab keeps the local username/password path for cashiers and for shops
/// that run fully offline.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _workspace = true; // which tab
  bool _isNew = false; // create-account toggle
  bool _hide = true;
  bool _busy = false;
  String _err = '';

  final _email = TextEditingController();
  final _wpass = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    for (final c in [_email, _wpass, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── workspace (cloud) sign-in ───────────────────────────────────────────────
  Future<void> _cloudGo() async {
    final email = _email.text.trim();
    final pw = _wpass.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() =>
          _err = t('Enter email and password', 'Geli iimayl iyo furaha'));
      return;
    }
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      final remote = await cloud.signIn(email, pw, isNew: _isNew);
      final local = await cloud.localInfo();

      // The master account manages workspaces; no till, no data direction.
      if (cloud.master) {
        store.openAsOwner('MareegTech');
        return; // finally clears _busy; RootGate shows the console
      }

      // Decide which side's data to keep.
      if (remote.has && (local.products > 0 || local.sales > 0)) {
        if (!mounted) return;
        final keep = await _askDirection(local, remote);
        if (keep == null) {
          // Cancelled — don't leave a half-signed-in state.
          await cloud.signOut();
          return;
        }
        if (keep == 'cloud') {
          await store.adoptCloudData();
        } else {
          await store.uploadLocalData();
        }
      } else if (remote.has) {
        await store.adoptCloudData();
      } else {
        await store.uploadLocalData();
      }

      // Register the workspace for approval if it isn't already.
      await cloud.refreshWorkspace();
      if (!cloud.wsRegistered) {
        if (!mounted) return;
        final reg = await _askRegister();
        if (reg != null) {
          store.applyBusinessProfile(reg.$1, reg.$3); // name + industry
          store.seedIndustryProducts(reg.$3); // starter products for industry
          store.clearBusinessTransactions(); // start with zero sales
          await cloud.registerWorkspace(reg.$1, reg.$2);
          store.planId = reg.$2;
          await cloud.refreshWorkspace();
        }
      }

      // Open the session — RootGate routes to the till or the pending screen.
      store.openAsOwner(cloud.wsName.isNotEmpty ? cloud.wsName : email);
    } catch (e) {
      if (mounted) setState(() => _err = Cloud.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _staffGo() {
    if (!store.signIn(_user.text, _pass.text)) {
      setState(() => _err =
          t('Wrong username or password', 'Magaca ama furaha waa khalad'));
    }
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

  Future<(String, String, String)?> _askRegister() {
    final nameC = TextEditingController(text: store.biz.name);
    var planId = 'MPQ50';
    var industry = store.biz.type.isNotEmpty ? store.biz.type : 'shop';
    if (!industries.containsKey(industry)) industry = 'shop';
    return showDialog<(String, String, String)>(
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
                Navigator.pop(ctx, (nameC.text.trim(), planId, industry));
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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [kNavy, Color(0xFF1A4DC4)]),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                            color: kBlue,
                            borderRadius: BorderRadius.circular(15)),
                        child: const Icon(Icons.shopping_cart,
                            color: Colors.white, size: 30),
                      ),
                      const SizedBox(height: 12),
                      const Text('Casri POS',
                          style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              color: kNavy)),
                      Text(t('Point of Sale System', 'Nidaamka Iibka'),
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF6B7688))),
                      const SizedBox(height: 12),
                      _langToggle(),
                      const SizedBox(height: 14),
                      _tabs(),
                      const SizedBox(height: 16),
                      if (_err.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFEAEA),
                              border:
                                  Border.all(color: const Color(0xFFFFB3B3)),
                              borderRadius: BorderRadius.circular(9)),
                          child: Text(_err,
                              style: const TextStyle(
                                  color: Color(0xFFBF2600), fontSize: 12.5)),
                        ),
                      _workspace ? _workspaceForm() : _staffForm(),
                      const SizedBox(height: 16),
                      const Text('Powered by MareegTech Solutions',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF98A2B3))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _langToggle() {
    Widget b(String label, String code) {
      final on = store.lang == code;
      return GestureDetector(
        onTap: () => setState(() => store.setLang(code)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: on ? kBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : const Color(0xFF6B7688))),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: const Color(0xFFEEF1F5),
          borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [b('English', 'en'), b('Soomaali', 'so')],
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String label, bool ws) {
      final on = _workspace == ws;
      return Expanded(
        child: GestureDetector(
          onTap: _busy
              ? null
              : () => setState(() {
                    _workspace = ws;
                    _err = '';
                  }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? kBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: on ? Colors.white : const Color(0xFF6B7688))),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: const Color(0xFFEEF1F5),
          borderRadius: BorderRadius.circular(11)),
      child: Row(children: [
        tab(t('Businesses', 'Ganacsiyada'), true),
        tab(t('Staff', 'Shaqaale'), false),
      ]),
    );
  }

  Widget _workspaceForm() {
    return Column(
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
              labelText: t('Business email', 'Iimaylka ganacsiga'),
              prefixIcon: const Icon(Icons.alternate_email)),
        ),
        const SizedBox(height: 11),
        TextField(
          controller: _wpass,
          obscureText: _hide,
          onSubmitted: (_) => _busy ? null : _cloudGo(),
          decoration: InputDecoration(
            labelText: t('Password', 'Furaha'),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _hide = !_hide)),
          ),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
              t('Create a new business account', 'Samee akoon ganacsi cusub'),
              style: const TextStyle(fontSize: 13)),
          value: _isNew,
          onChanged: _busy ? null : (v) => setState(() => _isNew = v),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _cloudGo,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_isNew
                    ? t('Create & continue', 'Samee & sii wad')
                    : t('Sign in', 'Gal')),
          ),
        ),
      ],
    );
  }

  Widget _staffForm() {
    return Column(
      children: [
        TextField(
          controller: _user,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
              labelText: t('Username', 'Magaca isticmaale'),
              prefixIcon: const Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 11),
        TextField(
          controller: _pass,
          obscureText: _hide,
          onSubmitted: (_) => _staffGo(),
          decoration: InputDecoration(
            labelText: t('Password', 'Furaha'),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _hide = !_hide)),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
              onPressed: _staffGo, child: Text(t('Sign in', 'Gal'))),
        ),
        const SizedBox(height: 12),
        Text(t('Demo:  admin / admin123', 'Tijaabo:  admin / admin123'),
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF98A2B3))),
      ],
    );
  }
}
