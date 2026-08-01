import 'package:flutter/material.dart';
import '../main.dart';
import '../models/models.dart';
import 'checkout_sheet.dart';

/// The till. Colored product tiles by category (Vektori-style). On a tablet the
/// receipt/cart sits beside the products; on a phone it collapses to a bottom
/// sheet. Native, so it always fills the screen.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

// A stable, readable colour per category — a colourful, menu-like grid.
const _pal = [
  Color(0xFF1A6EF5), Color(0xFF0091AE), Color(0xFF2E9E63), Color(0xFFE0842B),
  Color(0xFFE0503F), Color(0xFF6554C0), Color(0xFFC2185B), Color(0xFF00897B),
  Color(0xFF7E57C2), Color(0xFF3949AB), Color(0xFFD81B60), Color(0xFF00838F),
];
Color catColor(String cat) {
  final s = cat.isEmpty ? 'x' : cat;
  int n = 5;
  for (final r in s.codeUnits) {
    n = (n * 33 + r) & 0x7fffffff;
  }
  return _pal[n % _pal.length];
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

  int _qtyInCart(String id) {
    for (final l in store.cart) {
      if (l.product.id == id) return l.qty;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Casri POS'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(store.biz.name,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5C6B82),
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 760;
        final grid = _productsPane(items, wide);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: grid),
              SizedBox(
                width: 360,
                child: _CartPanel(onChanged: () => setState(() {})),
              ),
            ],
          );
        }
        return grid;
      }),
      bottomSheet: _isWide(context) || store.cart.isEmpty
          ? null
          : _CartBar(onChanged: () => setState(() {})),
    );
  }

  bool _isWide(BuildContext context) =>
      MediaQuery.of(context).size.width >= 760;

  Widget _productsPane(List<Product> items, bool wide) {
    return Column(
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
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final ct = _cats[i];
                final on = ct == _cat;
                final col = ct == 'all' ? kBlue : catColor(ct);
                return GestureDetector(
                  onTap: () => setState(() => _cat = ct),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 17),
                    decoration: BoxDecoration(
                      color: on ? col : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: col, width: 2),
                    ),
                    child: Text(
                      ct == 'all' ? 'All' : ct,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: on ? Colors.white : col,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? const _Empty()
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(14, 10, 14, wide ? 14 : 120),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    childAspectRatio: 1.15,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _ProductTile(
                    product: items[i],
                    qtyInCart: _qtyInCart(items[i].id),
                    onTap: () => setState(() => store.addToCart(items[i])),
                  ),
                ),
        ),
      ],
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

/// Compact colored tile: category colour, white text, name + price, cart badge.
class _ProductTile extends StatelessWidget {
  final Product product;
  final int qtyInCart;
  final VoidCallback onTap;
  const _ProductTile(
      {required this.product, required this.qtyInCart, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final out = product.stock <= 0;
    final col = catColor(product.cat);
    return Opacity(
      opacity: out ? 0.45 : 1,
      child: Material(
        color: col,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: out ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        '${product.icon} ${product.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    Text(store.money(product.price),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ],
                ),
              ),
              if (qtyInCart > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Color(0x6B000000),
                      borderRadius: BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomLeft: Radius.circular(11)),
                    ),
                    child: Text('$qtyInCart',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tablet cart: a flush side panel with a receipt table + totals + charge.
class _CartPanel extends StatelessWidget {
  final VoidCallback onChanged;
  const _CartPanel({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE6EAF0))),
      ),
      child: Column(
        children: [
          Container(
            color: kNavy,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text('🛒 Cart (${store.cartCount})',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                const Spacer(),
                if (store.cart.isNotEmpty)
                  InkWell(
                    onTap: () {
                      store.clearCart();
                      onChanged();
                    },
                    child: const Text('✕ Clear',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: store.cart.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 42, color: Color(0xFFC3CBD6)),
                        SizedBox(height: 8),
                        Text('Cart is empty',
                            style: TextStyle(color: Color(0xFF8A93A3))),
                      ],
                    ),
                  )
                : _ReceiptTable(onChanged: onChanged),
          ),
          _CartFooter(onChanged: onChanged),
        ],
      ),
    );
  }
}

/// The receipt as a table: Product · Qty · Unit price · Line total.
class _ReceiptTable extends StatefulWidget {
  final VoidCallback onChanged;
  const _ReceiptTable({required this.onChanged});
  @override
  State<_ReceiptTable> createState() => _ReceiptTableState();
}

class _ReceiptTableState extends State<_ReceiptTable> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(children: [
            Expanded(flex: 5, child: _Hd('PRODUCT')),
            Expanded(flex: 4, child: Center(child: _Hd('QTY'))),
            Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: _Hd('TOTAL'))),
            SizedBox(width: 22),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: store.cart.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final line = store.cart[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 12.5)),
                          Text(store.money(line.product.price),
                              style: const TextStyle(
                                  fontSize: 10.5, color: Color(0xFF5C6B82))),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _MiniBtn(
                              icon: Icons.remove,
                              onTap: () {
                                store.setQty(line.product.id, line.qty - 1);
                                widget.onChanged();
                                setState(() {});
                              }),
                          SizedBox(
                            width: 24,
                            child: Text('${line.qty}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 13)),
                          ),
                          _MiniBtn(
                              icon: Icons.add,
                              onTap: () {
                                store.setQty(line.product.id, line.qty + 1);
                                widget.onChanged();
                                setState(() {});
                              }),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(store.money(line.total),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: Color(0xFF1152CC))),
                    ),
                    SizedBox(
                      width: 22,
                      child: InkWell(
                        onTap: () {
                          store.setQty(line.product.id, 0);
                          widget.onChanged();
                          setState(() {});
                        },
                        child: const Icon(Icons.delete_outline,
                            size: 17, color: Color(0xFFBF2600)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Hd extends StatelessWidget {
  final String t;
  const _Hd(this.t);
  @override
  Widget build(BuildContext context) => Text(t,
      style: const TextStyle(
          fontSize: 9,
          letterSpacing: .4,
          fontWeight: FontWeight.w800,
          color: Color(0xFF8A93A3)));
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD8E0EA)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: kNavy),
        ),
      );
}

class _CartFooter extends StatelessWidget {
  final VoidCallback onChanged;
  const _CartFooter({required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF7F9FC),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          _SumRow('Subtotal', store.money(store.cartSubtotal)),
          if (store.biz.tax > 0)
            _SumRow('Tax (${store.biz.tax}%)', store.money(store.cartTax)),
          const Divider(height: 16),
          _SumRow('TOTAL', store.money(store.cartTotal), big: true),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: store.cart.isEmpty
                  ? null
                  : () async {
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
              style: FilledButton.styleFrom(
                  backgroundColor: kGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone cart bar (bottom sheet trigger) — unchanged behaviour.
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
                              color: Colors.white70,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                      Text(store.money(store.cartTotal),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
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

/// Phone full cart, as a draggable sheet.
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
            Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFC3CBD6),
                    borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  Text('Cart · ${store.cartCount} items',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: kNavy)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      store.clearCart();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFC62F16)),
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
                          Text(line.product.icon,
                              style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13)),
                                Text(
                                    '${store.money(line.product.price)} × ${line.qty}',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF5C6B82))),
                              ],
                            ),
                          ),
                          _MiniBtn(
                              icon: Icons.remove,
                              onTap: () => setState(() => store.setQty(
                                  line.product.id, line.qty - 1))),
                          SizedBox(
                            width: 34,
                            child: Text('${line.qty}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          _MiniBtn(
                              icon: Icons.add,
                              onTap: () => setState(() => store.setQty(
                                  line.product.id, line.qty + 1))),
                          SizedBox(
                            width: 74,
                            child: Text(store.money(line.total),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    color: Color(0xFF1152CC))),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            _CartFooter(onChanged: () => setState(() {})),
          ],
        ),
      ),
    );
  }
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
