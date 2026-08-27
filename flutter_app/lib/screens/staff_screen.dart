import 'package:flutter/material.dart';
import '../main.dart';
import '../models/models.dart';

/// Who signs in to this till, and how many of them.
///
/// A cash register is a cashier login, and the MPQ plan pays for a number of
/// them - so this screen leads with how many are used and how many are left.
/// A shop should never have to press Add to find out it has run out.
///
/// Every rule lives in the store (saveStaff / removeStaff). This screen only
/// collects fields and shows what comes back.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  void _say(String msg, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bad ? const Color(0xFFD63B3B) : null,
      duration: Duration(seconds: bad ? 5 : 2),
    ));
  }

  Future<void> _edit([Account? who]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StaffSheet(who: who),
    );
    if (saved == true) setState(() {});
  }

  Future<void> _remove(Account who) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('Remove ${who.username}?', 'Tirtir ${who.username}?')),
        content: Text(t(
            'They will not be able to sign in. Sales they already rang up stay '
                'exactly where they are.',
            'Ma geli doonaan. Iibkii ay horay u sameeyeen sidiisa ayuu u '
                'sii jiraa.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('Keep', 'Ha sii jiro'))),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD63B3B)),
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('Remove', 'Tirtir'))),
        ],
      ),
    );
    if (yes != true) return;
    final err = store.removeStaff(who.id);
    if (err != null) {
      _say(err, bad: true);
    } else {
      _say(t('Removed', 'Waa la tirtiray'));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final people = store.bizStaff;
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(t('People who sign in', 'Dadka gala'))),
          floatingActionButton: store.canManageStaff
              ? FloatingActionButton.extended(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(t('Add', 'Ku dar')),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
            children: [
              _registers(),
              const SizedBox(height: 14),
              if (!store.canManageStaff)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(t('Only an administrator can change this.',
                        'Maamulaha oo keliya ayaa tan beddeli kara.')),
                  ),
                ),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < people.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _row(people[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// How many tills are in use, said before anybody presses Add.
  Widget _registers() {
    final limit = store.registerLimit;
    final used = store.registersUsed;
    final full = store.registerCapReached;

    if (limit == 0) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.point_of_sale_outlined, color: kBlue),
          title: Text('$used ${t('cash registers', 'rijistar')}'),
          subtitle: Text(t('No plan on this shop yet, so nothing is limited.',
              'Weli qorshe dukaankan ma saarna, sidaas darteed waxba xad ma leh.')),
        ),
      );
    }

    final colour = full ? const Color(0xFFD63B3B) : kGreen;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.point_of_sale_outlined, color: colour, size: 20),
              const SizedBox(width: 8),
              Text('$used ${t('of', 'ka mid ah')} $limit '
                  '${t('cash registers in use', 'rijistar oo la isticmaalayo')}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: colour)),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: limit == 0 ? 0 : (used / limit).clamp(0, 1).toDouble(),
                minHeight: 7,
                backgroundColor: const Color(0xFFE6EBF2),
                valueColor: AlwaysStoppedAnimation(colour),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              full
                  ? t('Your ${store.plan?.id} plan is full. Switch a cashier '
                          'off, or move up a plan.',
                      'Qorshahaaga ${store.plan?.id} wuu buuxaa. Kaash mid dami, '
                          'ama qorshaha kor u qaad.')
                  : t('Your ${store.plan?.id} plan includes $limit.',
                      'Qorshahaaga ${store.plan?.id} wuxuu leeyahay $limit.'),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF5C6B82)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Account a) {
    final me = store.user?.id == a.id;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: a.isAdmin ? kNavy : kBlue,
        child: Icon(a.isAdmin ? Icons.shield_outlined : Icons.point_of_sale,
            color: Colors.white, size: 19),
      ),
      title: Row(children: [
        Flexible(
            child: Text(a.name.isEmpty ? a.username : a.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700))),
        if (me) ...[
          const SizedBox(width: 6),
          _Pill(t('you', 'adiga'), kGreen),
        ],
        if (!a.active) ...[
          const SizedBox(width: 6),
          _Pill(t('off', 'damin'), const Color(0xFF8A94A6)),
        ],
      ]),
      subtitle: Text('${a.username} · '
          '${a.isAdmin ? t('administrator', 'maamule') : t('cashier', 'kaash')}'
          '${a.bizId.isEmpty ? ' · ${t('all shops', 'dhammaan dukaamada')}' : ''}'),
      trailing: store.canManageStaff
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _edit(a),
                tooltip: t('Edit', 'Wax ka beddel'),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Color(0xFFD63B3B)),
                onPressed: () => _remove(a),
                tooltip: t('Remove', 'Tirtir'),
              ),
            ])
          : null,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.colour);
  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: colour)),
      );
}

/// Add or edit one person.
class _StaffSheet extends StatefulWidget {
  const _StaffSheet({this.who});
  final Account? who;

  @override
  State<_StaffSheet> createState() => _StaffSheetState();
}

class _StaffSheetState extends State<_StaffSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.who?.name ?? '');
  late final TextEditingController _username =
      TextEditingController(text: widget.who?.username ?? '');
  final _password = TextEditingController();
  late String _role = widget.who?.role ?? 'cashier';
  late bool _active = widget.who?.active ?? true;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _save() {
    final err = store.saveStaff(
      id: widget.who?.id ?? '',
      name: _name.text,
      username: _username.text,
      role: _role,
      password: _password.text,
      active: _active,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.who == null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: const Color(0xFFD8DEE8),
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Text(
                  adding
                      ? t('Add somebody who signs in', 'Ku dar qof gala')
                      : t('Edit ${widget.who!.username}',
                          'Wax ka beddel ${widget.who!.username}'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: t('Name', 'Magaca'),
                  prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _username,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: t('Username they type', 'Magaca ay qoraan'),
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: t('Password', 'Furaha sirta'),
                  helperText: adding
                      ? t('At least four characters',
                          'Ugu yaraan afar xaraf')
                      : t('Leave empty to keep the one they have',
                          'Bannaan ka tag si aad u sii haysato kii hore'),
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'cashier',
                      icon: const Icon(Icons.point_of_sale, size: 17),
                      label: Text(t('Cashier', 'Kaash'))),
                  ButtonSegment(
                      value: 'admin',
                      icon: const Icon(Icons.shield_outlined, size: 17),
                      label: Text(t('Administrator', 'Maamule'))),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: 4),
              Text(
                  _role == 'cashier'
                      ? t('A cashier uses one of the cash registers your plan '
                              'pays for.',
                          'Kaashku wuxuu isticmaalaa mid ka mid ah rijistarrada '
                              'qorshahaagu bixiyo.')
                      : t('An administrator can do everything, and does not use '
                              'up a cash register.',
                          'Maamuluhu wax walba wuu samayn karaa, rijistarna ma '
                              'isticmaalo.'),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF5C6B82))),
              if (!adding) ...[
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: Text(t('Can sign in', 'Wuu geli karaa')),
                  subtitle: Text(t(
                      'Switch off instead of removing, and their sales stay '
                          'attached to them.',
                      'Dami halkii aad tirtiri lahayd, iibkooduna wuu la sii '
                          'jiraa.')),
                ),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD63B3B).withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFD63B3B).withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        size: 18, color: Color(0xFFD63B3B)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error,
                            style: const TextStyle(
                                color: Color(0xFFD63B3B), fontSize: 13))),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(adding
                      ? t('Add them', 'Ku dar')
                      : t('Save', 'Kaydi')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
