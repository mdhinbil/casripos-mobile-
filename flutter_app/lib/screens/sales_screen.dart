import 'package:flutter/material.dart';
import '../main.dart';
import '../models/models.dart';

/// Today's takings up top, then the day's sales as cards.
class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sales = store.bizSales;
    final today = DateTime.now();
    bool sameDay(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;

    final todaySales = sales.where((s) => sameDay(s.when)).toList();
    final todayTotal = todaySales.fold(0.0, (a, s) => a + s.total);
    final byMethod = <String, double>{};
    for (final s in todaySales) {
      byMethod[s.payMethod] = (byMethod[s.payMethod] ?? 0) + s.total;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(t('Sales', 'Iibka'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('TODAY', 'MAANTA'),
                      style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: .7,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6B7688))),
                  const SizedBox(height: 4),
                  Text(store.money(todayTotal),
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: kNavy)),
                  Text('${todaySales.length} ${t('sales', 'iib')}',
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFF5C6B82))),
                  if (byMethod.isNotEmpty) ...[
                    const Divider(height: 22),
                    // Tells the owner how much cash should physically be in the
                    // drawer versus what went to mobile money.
                    for (final e in byMethod.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Icon(
                                  e.key == 'cash'
                                      ? Icons.payments_outlined
                                      : e.key == 'card'
                                          ? Icons.credit_card
                                          : Icons.smartphone,
                                  size: 16,
                                  color: const Color(0xFF5C6B82)),
                              const SizedBox(width: 7),
                              Text(_label(e.key),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF44536B))),
                            ]),
                            Text(store.money(e.value),
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(t('Recent', 'Kuwii dhawaa'),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF44536B))),
          ),
          if (sales.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                  child: Text(t('No sales yet', 'Weli iib ma jirto'),
                      style: const TextStyle(color: Color(0xFF6B7688)))),
            ),
          for (final s in sales.take(60)) _SaleCard(sale: s),
        ],
      ),
    );
  }

  static String _label(String m) => switch (m) {
        'card' => t('Card', 'Kaadh'),
        'mobile' => t('Mobile money', 'Lacag mobile'),
        _ => t('Cash', 'Cash'),
      };
}

class _SaleCard extends StatelessWidget {
  final Sale sale;
  const _SaleCard({required this.sale});

  @override
  Widget build(BuildContext context) {
    final d = sale.when;
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final date = '${d.day}/${d.month}/${d.year}';
    final count = sale.items.fold(0, (a, i) => a + i.qty);

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF4FF),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                  sale.payMethod == 'cash'
                      ? Icons.payments_outlined
                      : sale.payMethod == 'card'
                          ? Icons.credit_card
                          : Icons.smartphone,
                  color: kBlue,
                  size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${sale.id.substring(sale.id.length - 6)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5)),
                  Text('$date · $time · $count ${t('items', 'shay')}',
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFF5C6B82))),
                  if (sale.tableNo.isNotEmpty)
                    Text('${t('Table', 'Miis')} ${sale.tableNo} · ${sale.orderType}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF8B97A8))),
                ],
              ),
            ),
            Text(store.money(sale.total),
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF1152CC))),
          ],
        ),
      ),
    );
  }
}
