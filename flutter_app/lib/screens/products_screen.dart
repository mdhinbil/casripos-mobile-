import 'package:flutter/material.dart';
import '../main.dart';
import '../models/models.dart';

/// Products as CARDS, not a table. A table needs sideways scrolling on a phone
/// and hides the columns that matter; a card shows everything at once.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _q = '';

  List<Product> get _list {
    final q = _q.toLowerCase();
    return store.bizProducts
        .where((p) =>
            q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            p.cat.toLowerCase().contains(q) ||
            p.barcode.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _edit([Product? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductSheet(existing: existing),
    );
    if (saved == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _list;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: 'Search products…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('No products yet',
                        style: TextStyle(color: Color(0xFF6B7688))))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final p = items[i];
                      final low = p.stock > 0 && p.stock <= 5;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 9),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          leading:
                              Text(p.icon, style: const TextStyle(fontSize: 30)),
                          title: Text(p.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 3),
                              Row(children: [
                                if (p.cat.isNotEmpty) _Pill(p.cat),
                                if (p.cat.isNotEmpty) const SizedBox(width: 6),
                                _Pill('Stock ${p.stock}',
                                    danger: p.stock <= 0, warn: low),
                              ]),
                              if (p.barcode.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(p.barcode,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: Color(0xFF5C6B82))),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(store.money(p.price),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: Color(0xFF1152CC))),
                              const Icon(Icons.chevron_right,
                                  color: Color(0xFFB6C0CE)),
                            ],
                          ),
                          onTap: () => _edit(p),
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

class _Pill extends StatelessWidget {
  final String text;
  final bool danger, warn;
  const _Pill(this.text, {this.danger = false, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? const Color(0xFFFDECEC)
        : warn
            ? const Color(0xFFFDF3E2)
            : const Color(0xFFEEF1F5);
    final fg = danger
        ? const Color(0xFFC62F16)
        : warn
            ? const Color(0xFFA86A10)
            : const Color(0xFF5C6B82);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style:
              TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

class _ProductSheet extends StatefulWidget {
  final Product? existing;
  const _ProductSheet({this.existing});
  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late final TextEditingController _n, _c, _p, _s, _i, _sku, _bc;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _n = TextEditingController(text: e?.name ?? '');
    _c = TextEditingController(text: e?.cat ?? '');
    _p = TextEditingController(text: e == null ? '' : e.price.toString());
    _s = TextEditingController(text: e == null ? '' : e.stock.toString());
    _i = TextEditingController(text: e?.icon ?? '');
    _sku = TextEditingController(text: e?.sku ?? '');
    _bc = TextEditingController(text: e?.barcode ?? '');
  }

  @override
  void dispose() {
    for (final c in [_n, _c, _p, _s, _i, _sku, _bc]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _n.text.trim();
    if (name.isEmpty) return;
    // Enforce the workspace plan's product cap on NEW products only.
    if (widget.existing == null && store.productCapReached) {
      final pl = store.plan!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Your ${pl.id} plan allows ${pl.maxProducts} products. '
              'Remove one or upgrade your plan.')));
      return;
    }
    final price = double.tryParse(_p.text.trim()) ?? 0;
    final stock = int.tryParse(_s.text.trim()) ?? 0;
    final icon = _i.text.trim().isEmpty ? '📦' : _i.text.trim();
    final e = widget.existing;
    if (e != null) {
      e.name = name;
      e.cat = _c.text.trim();
      e.price = price;
      e.stock = stock;
      e.icon = icon;
      e.sku = _sku.text.trim();
      e.barcode = _bc.text.trim();
    } else {
      store.products.add(Product(
        id: 'p${DateTime.now().millisecondsSinceEpoch}',
        bizId: store.currentBizId,
        name: name,
        cat: _c.text.trim(),
        price: price,
        stock: stock,
        icon: icon,
        sku: _sku.text.trim(),
        barcode: _bc.text.trim(),
      ));
    }
    store.saveProducts();
    Navigator.pop(context, true);
  }

  void _delete() {
    final e = widget.existing;
    if (e == null) return;
    store.products.removeWhere((p) => p.id == e.id);
    store.saveProducts();
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
              Text(widget.existing == null ? 'Add product' : 'Edit product',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: kNavy)),
              const SizedBox(height: 14),
              TextField(
                  controller: _n,
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _c,
                        decoration:
                            const InputDecoration(labelText: 'Category'))),
                const SizedBox(width: 10),
                SizedBox(
                    width: 92,
                    child: TextField(
                        controller: _i,
                        decoration: const InputDecoration(labelText: 'Icon'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _p,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Price (USD)'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _s,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Stock'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _sku,
                        decoration: const InputDecoration(labelText: 'SKU'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _bc,
                        decoration:
                            const InputDecoration(labelText: 'Barcode'))),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                if (widget.existing != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          foregroundColor: const Color(0xFFC62F16),
                          side: const BorderSide(color: Color(0xFFC62F16))),
                    ),
                  ),
                if (widget.existing != null) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child:
                      FilledButton(onPressed: _save, child: const Text('Save')),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
