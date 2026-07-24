import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../models/models.dart';

/// Take payment: cash (with change owed), card, or mobile money.
class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({super.key});
  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  String _method = 'cash';
  String _provider = 'ZAAD';
  final _received = TextEditingController();
  final _ref = TextEditingController();

  static const _providers = ['ZAAD', 'EVC Plus', 'eDahab', 'Sahal', 'Other'];

  @override
  void dispose() {
    _received.dispose();
    _ref.dispose();
    super.dispose();
  }

  /// Cash is typed in the DISPLAY currency, so convert back to the USD base
  /// before working out the change — otherwise a shilling shop gets nonsense.
  double get _fx => switch (store.biz.currency) {
        'SOS' => store.fxSos,
        'SLSH' => store.fxSlsh,
        _ => 1,
      };

  double? get _paidUsd {
    final v = double.tryParse(_received.text.trim());
    if (v == null || v <= 0) return null;
    return v / _fx;
  }

  double get _change => (_paidUsd ?? 0) - store.cartTotal;
  bool get _short => _paidUsd != null && _change < -0.000001;

  void _quick(double displayAmount) {
    _received.text = displayAmount.round().toString();
    setState(() {});
  }

  Future<void> _complete() async {
    if (_method == 'cash' && _short) return;
    final sale = store.checkout(
      payMethod: _method,
      paid: _paidUsd ?? store.cartTotal,
      change: _method == 'cash' && _change > 0 ? _change : 0,
      provider: _method == 'mobile' ? _provider : '',
      ref: _method == 'cash' ? '' : _ref.text.trim(),
    );
    if (!mounted) return;
    Navigator.pop(context);
    await showDialog(
      context: context,
      builder: (_) => _ReceiptDialog(sale: sale),
    );
  }

  @override
  Widget build(BuildContext context) {
    final due = store.cartTotal;
    final dueDisplay = due * _fx;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF2F5F9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(width: 42, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFC3CBD6),
                  borderRadius: BorderRadius.circular(3))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Color(0xFFF8FBFF), Color(0xFFE8F1FF)]),
                        border: Border.all(color: const Color(0xFFC5D9F6), width: 1.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('AMOUNT DUE',
                              style: TextStyle(
                                  fontSize: 12, letterSpacing: .6,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF44536B))),
                          Text(store.money(due),
                              style: const TextStyle(
                                  fontSize: 27, fontWeight: FontWeight.w800,
                                  color: kNavy)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _MethodCard(
                          icon: Icons.payments_outlined, label: 'Cash',
                          on: _method == 'cash',
                          onTap: () => setState(() => _method = 'cash')),
                        const SizedBox(width: 9),
                        _MethodCard(
                          icon: Icons.credit_card, label: 'Card',
                          on: _method == 'card',
                          onTap: () => setState(() => _method = 'card')),
                        const SizedBox(width: 9),
                        _MethodCard(
                          icon: Icons.smartphone, label: 'Mobile',
                          on: _method == 'mobile',
                          onTap: () => setState(() => _method = 'mobile')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_method == 'cash') ...[
                      TextField(
                        controller: _received,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Amount received', hintText: '0'),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: [
                          _Quick('Exact', () => _quick(dueDisplay)),
                          // Round-ups a cashier is actually handed: next 1, 5,
                          // 10… above the amount due. Doubles throughout —
                          // ceil() returns an int and _quick wants a double.
                          for (final step in <double>[1, 5, 10, 20, 50, 100])
                            if ((dueDisplay / step).ceil() * step > dueDisplay)
                              _Quick(
                                ((dueDisplay / step).ceil() * step)
                                    .round()
                                    .toString(),
                                () => _quick(
                                    (dueDisplay / step).ceil() * step)),
                        ].take(5).toList(),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F6FC),
                          border: Border.all(color: const Color(0xFFDBE4F0)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_short ? 'STILL DUE' : 'CHANGE',
                                style: const TextStyle(
                                    fontSize: 12, letterSpacing: .5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF44536B))),
                            Text(
                              _paidUsd == null
                                  ? '—'
                                  : store.money(_change.abs()),
                              style: TextStyle(
                                  fontSize: 21, fontWeight: FontWeight.w800,
                                  color: _short
                                      ? const Color(0xFFC62F16)
                                      : const Color(0xFF1A7A4F)),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      if (_method == 'mobile')
                        DropdownButtonFormField<String>(
                          value: _provider,
                          decoration: const InputDecoration(labelText: 'Provider'),
                          items: _providers
                              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                              .toList(),
                          onChanged: (v) => setState(() => _provider = v ?? 'ZAAD'),
                        ),
                      if (_method == 'mobile') const SizedBox(height: 10),
                      TextField(
                        controller: _ref,
                        decoration: const InputDecoration(
                          labelText: 'Reference (optional)',
                          hintText: 'Transaction / approval no.'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (_method == 'cash' && _short) ? null : _complete,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(_short ? 'Not enough' : 'Complete sale'),
                        style: FilledButton.styleFrom(backgroundColor: kGreen),
                      ),
                    ),
                    SizedBox(height: 12 + MediaQuery.of(context).padding.bottom),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _MethodCard({
    required this.icon, required this.label,
    required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: on ? const Color(0xFFEAF2FF) : Colors.white,
              border: Border.all(
                  color: on ? kBlue : const Color(0xFFDBE2EC), width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(icon, size: 24, color: on ? kBlue : const Color(0xFF44536B)),
                const SizedBox(height: 5),
                Text(label,
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800,
                        color: on ? const Color(0xFF1152CC) : const Color(0xFF33415C))),
              ],
            ),
          ),
        ),
      );
}

class _Quick extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Quick(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          foregroundColor: const Color(0xFF33415C),
          side: const BorderSide(color: Color(0xFFDBE2EC)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      );
}

/// Fixed-width slip, same 32-column layout the web app prints.
class _ReceiptDialog extends StatelessWidget {
  final Sale sale;
  const _ReceiptDialog({required this.sale});

  String _slip() {
    const w = 32;
    String pad(int n) => n > 0 ? ' ' * n : '';
    String center(String s) =>
        s.length >= w ? s.substring(0, w) : pad((w - s.length) ~/ 2) + s;
    String line(String a, String b) =>
        a + pad(w - a.length - b.length < 1 ? 1 : w - a.length - b.length) + b;

    final b = StringBuffer();
    b.writeln(center(store.biz.name.toUpperCase()));
    if (store.biz.addr.isNotEmpty) b.writeln(center(store.biz.addr));
    if (store.biz.phone.isNotEmpty) b.writeln(center(store.biz.phone));
    b.writeln();
    b.writeln('=' * w);
    b.writeln(line('Receipt', '#${sale.id.substring(sale.id.length - 6)}'));
    b.writeln(line('Cashier', sale.cashier));
    if (sale.tableNo.isNotEmpty) b.writeln(line('Table', '#${sale.tableNo}'));
    b.writeln('=' * w);
    for (final it in sale.items) {
      b.writeln(it.name);
      b.writeln(line('  ${it.qty} x ${store.money(it.price)}',
          store.money(it.total)));
    }
    b.writeln('-' * w);
    b.writeln(line('Subtotal', store.money(sale.subtotal)));
    if (sale.tax > 0) b.writeln(line('Tax', store.money(sale.tax)));
    b.writeln('=' * w);
    b.writeln(line('TOTAL', store.money(sale.total)));
    b.writeln('=' * w);
    b.writeln(line('Paid by', sale.payMethod));
    if (sale.payMethod == 'cash' && sale.change > 0) {
      b.writeln(line('Received', store.money(sale.paid)));
      b.writeln(line('Change', store.money(sale.change)));
    }
    b.writeln();
    b.writeln(center('Thank you!'));
    return b.toString();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Receipt'),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFBFD),
              border: Border.all(color: const Color(0xFFC9D3E3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_slip(),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11.5, height: 1.5)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done')),
        ],
      );
}
