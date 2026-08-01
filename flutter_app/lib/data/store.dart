import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'cloud.dart';

/// Everything the till knows, held in memory and mirrored to disk.
///
/// Storage keys match the web app's localStorage keys exactly, and the JSON
/// written under them is the same shape. That is deliberate: a backup exported
/// from the web version imports here untouched, so a shop can move across
/// without losing a single sale.
class Store extends ChangeNotifier {
  static const kBiz = 'pos_biz_list';
  static const kCurrentBiz = 'pos_current_biz';
  static const kProducts = 'pos_prod';
  static const kSales = 'pos_sales';
  static const kInvoices = 'pos_inv';
  static const kAccounts = 'pos_acc';
  static const kFx = 'pos_fx';
  static const kRecoveryEmail = 'pos_recovery_email';

  static const allKeys = [
    kBiz, kCurrentBiz, kProducts, kSales, kInvoices, kAccounts, kFx, kRecoveryEmail
  ];

  late SharedPreferences _sp;

  List<Business> businesses = [];
  List<Product> products = [];
  List<Sale> sales = [];
  List<Invoice> invoices = [];
  List<Account> accounts = [];
  String currentBizId = '';
  Account? user;

  // Exchange rates, keyed the same way the web app stores them.
  double fxSos = 580, fxSlsh = 8500;
  String lang = 'en';

  // Live cart
  final List<CartLine> cart = [];
  String tableNo = '';
  String orderType = 'Dine-in';

  Business get biz => businesses.firstWhere(
        (b) => b.id == currentBizId,
        orElse: () => businesses.isNotEmpty
            ? businesses.first
            : Business(id: 'b1', name: 'Casri POS'),
      );

  List<Product> get bizProducts =>
      products.where((p) => p.bizId == currentBizId).toList();
  List<Sale> get bizSales => sales.where((s) => s.bizId == currentBizId).toList();
  List<Invoice> get bizInvoices =>
      invoices.where((i) => i.bizId == currentBizId).toList();

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
    _readAll();
    // Restore any saved cloud session and pull BEFORE deciding the device is
    // empty — otherwise a device that persisted its session would recreate demo
    // defaults on top of real cloud data. A fresh install has no session, so it
    // falls through to defaults and the user re-links from Settings.
    try {
      final applied = await cloud.boot();
      if (applied > 0) _readAll();
    } catch (_) {}
    if (businesses.isEmpty) {
      businesses = [Business(id: 'b1', name: 'Casri POS')];
      currentBizId = 'b1';
      _write(kBiz, businesses.map((e) => e.toJson()).toList());
      _sp.setString(kCurrentBiz, jsonEncode('b1'));
    }
    if (accounts.isEmpty) {
      accounts = [
        Account(id: 'a1', name: 'Admin', username: 'admin', password: 'admin123', role: 'admin'),
        Account(id: 'a2', name: 'Cashier', username: 'cashier', password: 'cash123'),
      ];
      _write(kAccounts, accounts.map((e) => e.toJson()).toList());
    }
    notifyListeners();
  }

  void _readAll() {
    businesses = _readList(kBiz).map((e) => Business.fromJson(e)).toList();
    products = _readList(kProducts).map((e) => Product.fromJson(e)).toList();
    sales = _readList(kSales).map((e) => Sale.fromJson(e)).toList();
    invoices = _readList(kInvoices).map((e) => Invoice.fromJson(e)).toList();
    accounts = _readList(kAccounts).map((e) => Account.fromJson(e)).toList();
    currentBizId = _readString(kCurrentBiz);
    if (currentBizId.isEmpty && businesses.isNotEmpty) currentBizId = businesses.first.id;
    final fx = _readMap(kFx);
    fxSos = (fx['sos'] as num?)?.toDouble() ?? 580;
    fxSlsh = (fx['slsh'] as num?)?.toDouble() ?? 8500;
  }

  List<Map<String, dynamic>> _readList(String k) {
    try {
      final raw = _sp.getString(k);
      if (raw == null || raw.isEmpty) return [];
      final v = jsonDecode(raw);
      if (v is! List) return [];
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _readMap(String k) {
    try {
      final raw = _sp.getString(k);
      if (raw == null || raw.isEmpty) return {};
      final v = jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }

  /// The web app stores some values as bare JSON strings (e.g. "b1").
  String _readString(String k) {
    try {
      final raw = _sp.getString(k);
      if (raw == null || raw.isEmpty) return '';
      final v = jsonDecode(raw);
      return v is String ? v : raw;
    } catch (_) {
      return _sp.getString(k) ?? '';
    }
  }

  void _write(String k, Object v) {
    _sp.setString(k, jsonEncode(v));
    // Stamp the write so cloud pull can tell whose copy is newer, exactly as
    // the web app does.
    _sp.setInt('pos_ts_$k', DateTime.now().millisecondsSinceEpoch);
    // Mirror to the cloud (debounced; no-op when not signed in).
    cloud.queue(k);
  }

  // ── cloud direction (called from Settings after signing in) ────────────────
  /// Replace this device's data with what is in the cloud for this account.
  Future<void> adoptCloudData() async {
    for (final k in cloudKeys) {
      await _sp.remove(k);
      await _sp.remove('pos_ts_$k');
    }
    await cloud.pull(force: true);
    _readAll();
    _ensureDefaults();
    notifyListeners();
  }

  /// Push everything this device has up to the (empty/new) cloud account.
  Future<void> uploadLocalData() async {
    await cloud.pushAll();
  }

  /// Re-read everything from disk (after a cloud pull changed it underneath us).
  void reload() {
    _readAll();
    notifyListeners();
  }

  void _ensureDefaults() {
    if (businesses.isEmpty) {
      businesses = [Business(id: 'b1', name: 'Casri POS')];
      currentBizId = 'b1';
      saveBusinesses();
    }
    if (accounts.isEmpty) {
      accounts = [
        Account(id: 'a1', name: 'Admin', username: 'admin', password: 'admin123', role: 'admin'),
        Account(id: 'a2', name: 'Cashier', username: 'cashier', password: 'cash123'),
      ];
      saveAccounts();
    }
  }

  // ── plan (MPQ tier) ─────────────────────────────────────────────────────────
  String get planId => _sp.getString('pos_plan') ?? '';
  Plan? get plan => plans[planId];
  set planId(String id) => _sp.setString('pos_plan', id);

  /// True when the current business is already at its plan's product cap.
  bool get productCapReached {
    final p = plan;
    if (p == null) return false;
    return bizProducts.length >= p.maxProducts;
  }

  void saveProducts() {
    _write(kProducts, products.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  void saveSales() {
    _write(kSales, sales.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  void saveInvoices() {
    _write(kInvoices, invoices.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  void saveBusinesses() {
    _write(kBiz, businesses.map((e) => e.toJson()).toList());
    _sp.setString(kCurrentBiz, jsonEncode(currentBizId));
    notifyListeners();
  }

  void saveAccounts() {
    _write(kAccounts, accounts.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  // ── auth ──────────────────────────────────────────────────
  bool signIn(String username, String password) {
    for (final a in accounts) {
      if (a.active &&
          a.username.toLowerCase() == username.toLowerCase().trim() &&
          a.password == password) {
        user = a;
        // A business-scoped account is pinned to its own business, so staff
        // can never see another shop's takings.
        if (a.bizId.isNotEmpty && businesses.any((b) => b.id == a.bizId)) {
          currentBizId = a.bizId;
          _sp.setString(kCurrentBiz, jsonEncode(currentBizId));
        }
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void signOut() {
    user = null;
    cart.clear();
    notifyListeners();
  }

  // ── cart ──────────────────────────────────────────────────
  void addToCart(Product p) {
    if (p.stock <= 0) return;
    final i = cart.indexWhere((c) => c.product.id == p.id);
    if (i >= 0) {
      if (cart[i].qty < p.stock) cart[i].qty++;
    } else {
      cart.add(CartLine(p, 1));
    }
    notifyListeners();
  }

  void setQty(String productId, int qty) {
    final i = cart.indexWhere((c) => c.product.id == productId);
    if (i < 0) return;
    if (qty <= 0) {
      cart.removeAt(i);
    } else {
      cart[i].qty = qty.clamp(1, cart[i].product.stock);
    }
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    tableNo = '';
    notifyListeners();
  }

  double get cartSubtotal => cart.fold(0.0, (a, c) => a + c.total);
  double get cartTax => cartSubtotal * (biz.tax / 100);
  double get cartTotal => cartSubtotal + cartTax;
  int get cartCount => cart.fold(0, (a, c) => a + c.qty);

  /// Records the sale, decrements stock, and clears the cart.
  Sale checkout({
    required String payMethod,
    double paid = 0,
    double change = 0,
    String provider = '',
    String ref = '',
  }) {
    final sale = Sale(
      id: 's${DateTime.now().millisecondsSinceEpoch}',
      bizId: currentBizId,
      date: DateTime.now().toIso8601String(),
      cashier: user?.name ?? 'Admin',
      items: cart.map((c) => SaleItem(
            id: c.product.id, name: c.product.name,
            price: c.product.price, qty: c.qty,
          )).toList(),
      subtotal: cartSubtotal,
      tax: cartTax,
      total: cartTotal,
      currency: biz.currency,
      bizType: biz.type,
      tableNo: biz.usesTables ? tableNo : '',
      orderType: biz.usesTables ? orderType : '',
      payMethod: payMethod,
      paid: paid == 0 ? cartTotal : paid,
      change: change,
      payProvider: provider,
      payRef: ref,
    );

    for (final line in cart) {
      final p = products.firstWhere((x) => x.id == line.product.id,
          orElse: () => line.product);
      p.stock = (p.stock - line.qty).clamp(0, 1 << 30);
    }
    sales.insert(0, sale);
    saveProducts();
    saveSales();
    clearCart();
    return sale;
  }

  // ── money ─────────────────────────────────────────────────
  /// Prices are held in USD; display converts to the business currency.
  String money(double usd) {
    switch (biz.currency) {
      case 'SOS':
        return 'Sh ${(usd * fxSos).round()}';
      case 'SLSH':
        return 'SlSh ${(usd * fxSlsh).round()}';
      default:
        return '\$${usd.toStringAsFixed(2)}';
    }
  }

  // ── backup ────────────────────────────────────────────────
  /// Same envelope the web app writes, so files move either direction.
  String exportBackup() {
    final data = <String, String>{};
    for (final k in allKeys) {
      final v = _sp.getString(k);
      if (v != null) data[k] = v;
    }
    return const JsonEncoder.withIndent(' ').convert({
      'app': 'CasriPOS',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'businesses': businesses.length,
      'products': products.length,
      'sales': sales.length,
      'data': data,
    });
  }

  /// Returns null on success, or a human-readable reason it failed.
  Future<String?> importBackup(String jsonText) async {
    Map<String, dynamic> obj;
    try {
      obj = Map<String, dynamic>.from(jsonDecode(jsonText));
    } catch (_) {
      return 'That file is not valid JSON.';
    }
    if (obj['app'] != 'CasriPOS' || obj['data'] is! Map) {
      return 'That is not a Casri POS backup.';
    }
    final data = Map<String, dynamic>.from(obj['data']);
    for (final entry in data.entries) {
      if (allKeys.contains(entry.key)) {
        await _sp.setString(entry.key, entry.value.toString());
      }
    }
    _readAll();
    notifyListeners();
    return null;
  }
}
