// Data shapes, deliberately identical to the ones the web app stores in
// localStorage. Keeping the JSON byte-compatible means a backup exported from
// the current app imports straight into this one, and both versions can share
// the same cloud documents during the changeover — no migration step, and no
// shop stranded mid-switch.

class Business {
  String id, name, addr, phone, currency, type;
  double tax;

  Business({
    required this.id,
    required this.name,
    this.addr = '',
    this.phone = '',
    this.currency = 'USD',
    this.type = 'shop',
    this.tax = 0,
  });

  factory Business.fromJson(Map<String, dynamic> j) => Business(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        addr: (j['addr'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        currency: (j['currency'] ?? 'USD').toString(),
        type: (j['type'] ?? 'shop').toString(),
        tax: _num(j['tax']),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'addr': addr, 'phone': phone,
        'currency': currency, 'type': type, 'tax': tax,
      };

  /// Restaurants and cafes take table numbers; shops don't.
  bool get usesTables => type == 'restaurant' || type == 'cafe' || type == 'bar';
}

class Product {
  String id, bizId, name, cat, icon, sku, barcode;
  double price;
  int stock;

  Product({
    required this.id,
    required this.bizId,
    required this.name,
    this.cat = '',
    this.icon = '📦',
    this.sku = '',
    this.barcode = '',
    this.price = 0,
    this.stock = 0,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: (j['id'] ?? '').toString(),
        bizId: (j['bizId'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        cat: (j['cat'] ?? '').toString(),
        icon: (j['icon'] ?? '📦').toString(),
        sku: (j['sku'] ?? '').toString(),
        barcode: (j['barcode'] ?? '').toString(),
        price: _num(j['price']),
        stock: _int(j['stock']),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'bizId': bizId, 'name': name, 'cat': cat, 'icon': icon,
        'sku': sku, 'barcode': barcode, 'price': price, 'stock': stock,
      };
}

class SaleItem {
  String id, name;
  double price;
  int qty;

  SaleItem({required this.id, required this.name, required this.price, required this.qty});

  factory SaleItem.fromJson(Map<String, dynamic> j) => SaleItem(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        price: _num(j['price']),
        qty: _int(j['qty']),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price, 'qty': qty};

  double get total => price * qty;
}

class Sale {
  String id, bizId, date, cashier, currency, bizType, tableNo, orderType;
  String payMethod, payProvider, payRef;
  List<SaleItem> items;
  double subtotal, tax, total, paid, change;

  Sale({
    required this.id,
    required this.bizId,
    required this.date,
    this.cashier = '',
    this.currency = 'USD',
    this.bizType = '',
    this.tableNo = '',
    this.orderType = '',
    this.payMethod = 'cash',
    this.payProvider = '',
    this.payRef = '',
    this.items = const [],
    this.subtotal = 0,
    this.tax = 0,
    this.total = 0,
    this.paid = 0,
    this.change = 0,
  });

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: (j['id'] ?? '').toString(),
        bizId: (j['bizId'] ?? '').toString(),
        date: (j['date'] ?? '').toString(),
        cashier: (j['cashier'] ?? '').toString(),
        currency: (j['currency'] ?? 'USD').toString(),
        bizType: (j['bizType'] ?? '').toString(),
        tableNo: (j['tableNo'] ?? '').toString(),
        orderType: (j['orderType'] ?? '').toString(),
        payMethod: (j['payMethod'] ?? 'cash').toString(),
        payProvider: (j['payProvider'] ?? '').toString(),
        payRef: (j['payRef'] ?? '').toString(),
        items: ((j['items'] ?? []) as List)
            .map((e) => SaleItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        subtotal: _num(j['subtotal']),
        tax: _num(j['tax']),
        total: _num(j['total']),
        paid: _num(j['paid']),
        change: _num(j['change']),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'bizId': bizId, 'date': date, 'cashier': cashier,
        'items': items.map((e) => e.toJson()).toList(),
        'subtotal': subtotal, 'tax': tax, 'total': total,
        'currency': currency, 'bizType': bizType,
        'tableNo': tableNo, 'orderType': orderType,
        'payMethod': payMethod, 'paid': paid, 'change': change,
        'payProvider': payProvider, 'payRef': payRef,
      };

  DateTime get when => DateTime.tryParse(date) ?? DateTime.now();
}

class Invoice {
  String id, bizId, saleId, date, customer, phone, due, addr;
  int no;

  Invoice({
    required this.id,
    required this.bizId,
    required this.saleId,
    required this.date,
    required this.no,
    this.customer = '',
    this.phone = '',
    this.due = '',
    this.addr = '',
  });

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: (j['id'] ?? '').toString(),
        bizId: (j['bizId'] ?? '').toString(),
        saleId: (j['saleId'] ?? '').toString(),
        date: (j['date'] ?? '').toString(),
        no: _int(j['no']),
        customer: (j['customer'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        due: (j['due'] ?? '').toString(),
        addr: (j['addr'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'bizId': bizId, 'no': no, 'saleId': saleId, 'date': date,
        'customer': customer, 'phone': phone, 'due': due, 'addr': addr,
      };

  String get number => 'INV-${no.toString().padLeft(4, '0')}';
}

class Account {
  String id, name, username, password, role, bizId;
  bool active;

  Account({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    this.role = 'cashier',
    this.bizId = '',
    this.active = true,
  });

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        password: (j['password'] ?? '').toString(),
        role: (j['role'] ?? 'cashier').toString(),
        bizId: (j['bizId'] ?? '').toString(),
        active: j['active'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'username': username, 'password': password,
        'role': role, 'bizId': bizId, 'active': active,
      };

  bool get isAdmin => role == 'admin';
  bool get isSuperAdmin => role == 'admin' && bizId.isEmpty;
}

class CartLine {
  final Product product;
  int qty;
  CartLine(this.product, this.qty);
  double get total => product.price * qty;
}

// The web app's JSON is loosely typed — numbers sometimes arrive as strings.
// Parse defensively so one odd value can't crash a shop's till on import.
double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse((v ?? '').toString()) ?? 0;
}

int _int(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse((v ?? '').toString()) ?? 0;
}
