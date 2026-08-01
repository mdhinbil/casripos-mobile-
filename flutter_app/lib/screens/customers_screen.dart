import 'package:flutter/material.dart';
import '../main.dart';
import '../models/models.dart';

/// A real customer directory: add, search, edit and remove customers. Stored
/// per business and synced to the cloud with everything else.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _q = '';

  List<Customer> get _list {
    final q = _q.toLowerCase();
    final all = store.bizCustomers
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (q.isEmpty) return all;
    return all
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.phone.toLowerCase().contains(q) ||
            c.note.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _edit([Customer? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerSheet(existing: existing),
    );
    if (saved == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _list;
    return Scaffold(
      appBar: AppBar(title: Text(t('Customers', 'Macaamiisha'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt),
        label: Text(t('Add', 'Ku dar')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: t('Search customers…', 'Raadi macaamiisha…'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                        _q.isEmpty
                            ? t('No customers yet', 'Weli macmiil ma jiro')
                            : t('No match', 'Waxba lama helin'),
                        style: const TextStyle(color: Color(0xFF6B7688))))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final c = items[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFEAF2FF),
                            child: Text(
                                c.name.isNotEmpty
                                    ? c.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: kBlue)),
                          ),
                          title: Text(c.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14)),
                          subtitle: c.phone.isEmpty && c.note.isEmpty
                              ? null
                              : Text(
                                  [c.phone, c.note]
                                      .where((s) => s.isNotEmpty)
                                      .join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.chevron_right,
                              color: Color(0xFFB6C0CE)),
                          onTap: () => _edit(c),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustomerSheet extends StatefulWidget {
  final Customer? existing;
  const _CustomerSheet({this.existing});
  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  late final TextEditingController _n, _p, _note;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _n = TextEditingController(text: e?.name ?? '');
    _p = TextEditingController(text: e?.phone ?? '');
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _n.dispose();
    _p.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final name = _n.text.trim();
    if (name.isEmpty) return;
    final e = widget.existing;
    if (e != null) {
      e.name = name;
      e.phone = _p.text.trim();
      e.note = _note.text.trim();
    } else {
      store.customers.add(Customer(
        id: 'c${DateTime.now().millisecondsSinceEpoch}',
        bizId: store.currentBizId,
        name: name,
        phone: _p.text.trim(),
        note: _note.text.trim(),
      ));
    }
    store.saveCustomers();
    store.log('Customer saved: $name');
    Navigator.pop(context, true);
  }

  void _delete() {
    final e = widget.existing;
    if (e == null) return;
    store.customers.removeWhere((c) => c.id == e.id);
    store.saveCustomers();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF2F5F9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFFC3CBD6),
                        borderRadius: BorderRadius.circular(3))),
              ),
              const SizedBox(height: 16),
              Text(
                  widget.existing == null
                      ? t('Add customer', 'Ku dar macmiil')
                      : t('Edit customer', 'Wax ka beddel macmiil'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: kNavy)),
              const SizedBox(height: 14),
              TextField(
                  controller: _n,
                  decoration:
                      InputDecoration(labelText: t('Name', 'Magaca'))),
              const SizedBox(height: 10),
              TextField(
                  controller: _p,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: t('Phone', 'Telefoon'))),
              const SizedBox(height: 10),
              TextField(
                  controller: _note,
                  decoration:
                      InputDecoration(labelText: t('Note', 'Qoraal'))),
              const SizedBox(height: 16),
              Row(children: [
                if (widget.existing != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(t('Delete', 'Tirtir')),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          foregroundColor: const Color(0xFFC62F16),
                          side: const BorderSide(color: Color(0xFFC62F16))),
                    ),
                  ),
                if (widget.existing != null) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                      onPressed: _save, child: Text(t('Save', 'Kaydi'))),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
