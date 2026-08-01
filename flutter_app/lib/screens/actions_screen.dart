import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../data/cloud.dart';
import '../models/models.dart';
import 'customers_screen.dart';
import 'log_screen.dart';
import 'settings_screen.dart';

/// The Vektori-style Actions grid: reports, lookups, and till tools. Actions
/// that map to real data (reports, find receipt, update products) do the work;
/// hardware-specific ones (cash drawer, terminal) report their status honestly.
class ActionsScreen extends StatefulWidget {
  const ActionsScreen({super.key});
  @override
  State<ActionsScreen> createState() => _ActionsScreenState();
}

class _ActionsScreenState extends State<ActionsScreen> {
  bool _busy = false;

  void _say(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ── report (X = current, Z = end of day) ────────────────────────────────────
  void _report(bool z) {
    final today = DateTime.now();
    bool sameDay(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;
    final sales = store.bizSales.where((s) => sameDay(s.when)).toList();
    final gross = sales.fold(0.0, (a, s) => a + s.total);
    final tax = sales.fold(0.0, (a, s) => a + s.tax);
    final byMethod = <String, double>{};
    for (final s in sales) {
      byMethod[s.payMethod] = (byMethod[s.payMethod] ?? 0) + s.total;
    }

    const w = 30;
    String line(String a, String b) =>
        a + (' ' * (w - a.length - b.length).clamp(1, w)) + b;
    final b = StringBuffer();
    b.writeln(store.biz.name.toUpperCase());
    b.writeln(z ? t('Z-REPORT (End of Day)', 'WARBIXIN-Z (Dhammaad)')
        : t('X-REPORT (Current)', 'WARBIXIN-X (Hadda)'));
    b.writeln('${today.day}/${today.month}/${today.year}');
    b.writeln('=' * w);
    b.writeln(line(t('Sales', 'Iibab'), '${sales.length}'));
    b.writeln(line(t('Gross', 'Wadar guud'), store.money(gross)));
    if (tax > 0) b.writeln(line(t('Tax', 'Cashuur'), store.money(tax)));
    b.writeln('-' * w);
    for (final e in byMethod.entries) {
      b.writeln(line(_payLabel(e.key), store.money(e.value)));
    }
    if (byMethod.isEmpty) b.writeln(t('No sales today', 'Maanta iib ma jirto'));
    b.writeln('=' * w);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(z ? t('Z-report', 'Warbixin-Z') : t('X-report', 'Warbixin-X')),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFBFD),
              border: Border.all(color: const Color(0xFFC9D3E3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(b.toString(),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12, height: 1.5)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Done', 'Diyaar'))),
        ],
      ),
    );
  }

  String _payLabel(String m) => switch (m) {
        'card' => t('Card', 'Kaadh'),
        'mobile' => t('Mobile money', 'Lacag mobile'),
        _ => t('Cash', 'Cash'),
      };

  // ── control sheet: products + stock ─────────────────────────────────────────
  void _controlSheet() {
    final items = store.bizProducts;
    const w = 30;
    String line(String a, String b) {
      final an = a.length > 20 ? a.substring(0, 20) : a;
      return an + (' ' * (w - an.length - b.length).clamp(1, w)) + b;
    }

    final b = StringBuffer();
    b.writeln(t('STOCK CONTROL SHEET', 'XAASHIDA XAKAMAYNTA'));
    b.writeln('=' * w);
    for (final p in items) {
      b.writeln(line(p.name, '${p.stock}'));
    }
    if (items.isEmpty) b.writeln(t('No products', 'Alaab ma jirto'));
    b.writeln('=' * w);
    b.writeln(line(t('Items', 'Alaab'), '${items.length}'));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('Control sheet', 'Xaashida xakamaynta')),
        content: SingleChildScrollView(
          child: Text(b.toString(),
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12, height: 1.5)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Done', 'Diyaar'))),
        ],
      ),
    );
  }

  // ── find a sale by its short receipt/order number ───────────────────────────
  Future<void> _find(bool order) async {
    final ctrl = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(order
            ? t('Find order', 'Raadi dalab')
            : t('Find receipt', 'Raadi rasiid')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
              labelText: t('Receipt / order number', 'Lambarka rasiid / dalab'),
              hintText: 'e.g. 4F9C2A'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel', 'Jooji'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Find', 'Raadi'))),
        ],
      ),
    );
    if (go != true) return;
    final q = ctrl.text.trim().toLowerCase();
    if (q.isEmpty) return;
    Sale? found;
    for (final s in store.bizSales) {
      if (s.id.toLowerCase().endsWith(q) || s.id.toLowerCase() == q) {
        found = s;
        break;
      }
    }
    if (found == null) {
      _say(t('No match found', 'Waxba lama helin'));
      return;
    }
    if (!mounted) return;
    _showSaleReceipt(found);
  }

  void _showSaleReceipt(Sale sale) {
    const w = 30;
    String line(String a, String b) =>
        a + (' ' * (w - a.length - b.length).clamp(1, w)) + b;
    final b = StringBuffer();
    b.writeln(store.biz.name.toUpperCase());
    b.writeln('#${sale.id.substring(sale.id.length - 6)}');
    final d = sale.when;
    b.writeln('${d.day}/${d.month}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}');
    b.writeln('=' * w);
    for (final it in sale.items) {
      b.writeln(it.name);
      b.writeln(line('  ${it.qty} x ${store.money(it.price)}',
          store.money(it.total)));
    }
    b.writeln('=' * w);
    b.writeln(line(t('TOTAL', 'WADARTA'), store.money(sale.total)));
    b.writeln(line(t('Paid by', 'Lagu bixiyay'), sale.payMethod));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('Receipt', 'Rasiidka')),
        content: SingleChildScrollView(
          child: Text(b.toString(),
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12, height: 1.5)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Done', 'Diyaar'))),
        ],
      ),
    );
  }

  Future<void> _updateProducts() async {
    if (!cloud.on) {
      _say(t('Link to cloud first (Settings)', 'Marka hore ku xir cloud-ka'));
      return;
    }
    setState(() => _busy = true);
    try {
      final n = await cloud.pull(force: true);
      store.reload();
      _say(t('Products updated ($n keys)', 'Alaabta waa la cusboonaysiiyay'));
    } catch (e) {
      _say(Cloud.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetOrderNumber() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('Reset order number', 'Dib u deji lambarka dalabka')),
        content: Text(t('Set the order number back to zero?',
            'Lambarka dalabka dib ugu celi eber?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel', 'Jooji'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Reset', 'Dib u deji'))),
        ],
      ),
    );
    if (ok != true) return;
    store.resetOrderNumber();
    _say(t('Order number reset', 'Lambarka dalabka waa la dejiyay'));
  }

  Future<void> _closeApp() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('Close application', 'Xir barnaamijka')),
        content: Text(t('Close Casri POS now?', 'Hadda xir Casri POS?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel', 'Jooji'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Close', 'Xir'))),
        ],
      ),
    );
    if (ok == true) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <_Action>[
      _Action(t('Z-report', 'Warbixin-Z'), t('End of Day', 'Dhammaadka maalinta'),
          Icons.description_outlined, () => _report(true)),
      _Action(t('X-report', 'Warbixin-X'),
          t('Current sales summary', 'Kooban iibka hadda'),
          Icons.description_outlined, () => _report(false)),
      _Action(t('Control sheet', 'Xaashida xakamaynta'), '',
          Icons.article_outlined, _controlSheet),
      _Action(t('Find receipt', 'Raadi rasiid'), '', Icons.receipt_long_outlined,
          () => _find(false)),
      _Action(t('Find order', 'Raadi dalab'), '', Icons.search,
          () => _find(true)),
      _Action(t('Search customer', 'Raadi macmiil'), '', Icons.person_search,
          () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomersScreen()))),
      _Action(t('Barcode mode', 'Habka barcode'),
          store.barcodeMode ? t('On', 'Shid') : t('Off', 'Damiyay'),
          Icons.qr_code_scanner, () {
        store.toggleBarcodeMode();
        setState(() {});
      }),
      _Action(t('Open Cash Drawer', 'Fur sanduuqa lacagta'), '',
          Icons.point_of_sale, () => _say(
              t('No cash drawer connected', 'Sanduuq lacageed ma xidhna'))),
      _Action(t('Settings', 'Dejinta'), '', Icons.settings_outlined, () {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()));
      }),
      _Action(t('Update products', 'Cusboonaysii alaabta'), '', Icons.sync,
          _updateProducts),
      _Action(t('Log', 'Diiwaanka'), '', Icons.history,
          () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogScreen()))),
      _Action(t('Detach Payment Terminal', 'Ka fur Terminalka lacagta'),
          t('Detach / Attach', 'Fur / Xir'), Icons.link_off, () => _say(
              t('No payment terminal connected', 'Terminal lacageed ma xidhna'))),
      _Action(t('Reset order number', 'Dib u deji lambarka dalabka'), '',
          Icons.restart_alt, _resetOrderNumber),
      _Action(t('Close application', 'Xir barnaamijka'), '', Icons.close,
          _closeApp),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(t('Actions', 'Ficillo')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3))
            : null,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 1.25,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: tiles.length,
        itemBuilder: (_, i) => _ActionTile(tiles[i]),
      ),
    );
  }
}

class _Action {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  _Action(this.title, this.subtitle, this.icon, this.onTap);
}

class _ActionTile extends StatelessWidget {
  final _Action a;
  const _ActionTile(this.a);
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: a.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE3E8EF)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14, color: kNavy)),
              if (a.subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(a.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFF6B7688))),
                ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(a.icon, size: 34, color: const Color(0xFFBcC7D6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
