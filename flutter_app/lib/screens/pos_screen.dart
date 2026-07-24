import 'package:flutter/material.dart';
import '../main.dart';
import '../models/models.dart';
import 'checkout_sheet.dart';

/// The till. Products on top, a cart bar pinned to the bottom that expands into
/// a sheet — the pattern people already know from every delivery app, rather
/// than a side column that falls off the bottom of a phone.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  String _query = '';
  String _cat = 'all';

  List<Product> get _filtered {
    final q = _query.toLowerCase();
    return store.bizProducts.where((p) {
      if (_cat != 'all' && p.cat != _cat) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.cat.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q);
    }).toList();
  }

  List<String> get _cats {
    final s = <String>{};
    for (final p in store.bizProducts) {
      if (p.cat.isNotEmpty) s.add(p.cat);
    }
    final list = s.toList()..sort();
    return ['all', ...list];
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Sell'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(store.biz.name,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF5C6B82),
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search or scan barcode…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          if (_cats.length > 1)
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _cats.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = _cats[i];
                  final on = c == _cat;
                  return ChoiceChip(
                    label: Text(c == 'all' ? 'All' : c),
                    selected: on,
                    onSelected: (_) => setState(() => _cat = c),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: on ? Colors.white : const Color(0xFF33415C),
                    ),
                    selectedColor: kBlue,
                    backgroundColor: const Color(0xFFEAEEF4),
                    side: BorderSide(
                        color: on ? kBlue : const Color(0xFFDBE2EC)),
                  );
                },
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? const _Empty()
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      childAspectRatio: 0.86,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _ProductTile(
                      product: items[i],
                      onTap: () => setState(() => store.addToCart(items[i])),
                    ),
                  ),
          ),
        ],
      ),
      bottomSheet: store.cart.isEmpty ? null : _CartBar(onChanged: () => setState(() {})),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 46, color: Color(0xFFB6C0CE)),
            SizedBox(height: 10),
            Text('No products match',
                style: TextStyle(color: Color(0xFF6B7688), fontSize: 14)),
          ],
        ),
      );
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final out = product.stock <= 0;
    final low = product.stock > 0 && product.stock <= 5;
    return Opacity(
      opacity: out ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: out ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FBFF), Color(0xFFE8F1FF)],
              ),
              border: Border.all(color: const Color(0xFFC5D9F6), width: 1.5),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Text(product.icon, style: const TextStyle(fontSize: 30))),
                const SizedBox(height: 4),
                if (product.cat.isNotEmpty)
                  Text(product.cat.toUpperCase(),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 9.5, letterSpacing: .5,
                          fontWeight: FontWeight.w800, color: Color(0xFF5C6B82))),
                Text(product.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, height: 1.25,
                        fontWeight: FontWeight.w800, color: kNavy)),
                const Spacer(),
                Text(store.money(product.price),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800,
                        color: Color(0xFF1152CC))),
                Text(
                  out ? 'Out of stock' : 'Stock: ${product.stock}',
                  style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w800,
                    color: out || low
                        ? const Color(0xFFC62F16)
                        : const Color(0xFF1A7A4F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsed cart bar. Tapping it opens the full cart; the checkout button is
/// always reachable without opening anything.
class _CartBar extends StatelessWidget {
  final VoidCallback onChanged;
  const _CartBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.fromLTRB(
          14, 12, 14, 12 + MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                await showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const CartSheet(),
                );
                onChanged();
              },
              child: Row(
                children: [
                  Badge(
                    label: Text('${store.cartCount}'),
                    backgroundColor: kCyan,
                    child: const Icon(Icons.shopping_cart_outlined,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('View cart',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                      Text(store.money(store.cartTotal),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const CheckoutSheet(),
              );
              onChanged();
            },
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Charge'),
            style: FilledButton.styleFrom(backgroundColor: kGreen),
          ),
        ],
      ),
    );
  }
}

/// The full cart, as a draggable sheet.
class CartSheet extends StatefulWidget {
  const CartSheet({super.key});
  @override
  State<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<CartSheet> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF2F5F9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 42, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFC3CBD6),
                borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  Text('Cart · ${store.cartCount} items',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800, color: kNavy)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      store.clearCart();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFC62F16)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: store.cart.length,
                itemBuilder: (_, i) {
                  final line = store.cart[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      child: Row(
                        children: [
                          Text(line.product.icon, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.product.name,
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800, fontSize: 13)),
                                Text(
                                    '${store.money(line.product.price)} × ${line.qty}',
                                    style: const TextStyle(
                                        fontSize: 11.5, color: Color(0xFF5C6B82))),
                              ],
                            ),
                          ),
                          _QtyButton(
                            icon: Icons.remove,
                            onTap: () => setState(() =>
                                store.setQty(line.product.id, line.qty - 1)),
                          ),
                          SizedBox(
                            width: 34,
                            child: Text('${line.qty}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          _QtyButton(
                            icon: Icons.add,
                            onTap: () => setState(() =>
                                store.setQty(line.product.id, line.qty + 1)),
                          ),
                          SizedBox(
                            width: 74,
                            child: Text(store.money(line.total),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5, color: Color(0xFF1152CC))),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
              child: Column(
                children: [
                  _SumRow('Subtotal', store.money(store.cartSubtotal)),
                  if (store.biz.tax > 0)
                    _SumRow('Tax (${store.biz.tax}%)', store.money(store.cartTax)),
                  const Divider(height: 18),
                  _SumRow('TOTAL', store.money(store.cartTotal), big: true),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const CheckoutSheet(),
                        );
                      },
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Charge'),
                      style: FilledButton.styleFrom(backgroundColor: kGreen),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD8E0EA)),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 18, color: kNavy),
        ),
      );
}

class _SumRow extends StatelessWidget {
  final String label, value;
  final bool big;
  const _SumRow(this.label, this.value, {this.big = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: big ? 15 : 13,
                    fontWeight: big ? FontWeight.w800 : FontWeight.w600,
                    color: big ? kNavy : const Color(0xFF44536B))),
            Text(value,
                style: TextStyle(
                    fontSize: big ? 21 : 13.5,
                    fontWeight: FontWeight.w800,
                    color: kNavy)),
          ],
        ),
      );
}
