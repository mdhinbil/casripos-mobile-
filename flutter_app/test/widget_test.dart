// Replaces the placeholder `flutter create` writes, which refers to a MyApp
// class this project does not have and fails analysis.
//
// Checks the money formatting, because getting currency wrong on a till is
// the kind of bug a shop notices at the end of the day, not during it.
import 'package:flutter_test/flutter_test.dart';
import 'package:casripos/data/store.dart';
import 'package:casripos/models/models.dart';

void main() {
  test('cart totals add up and tax applies', () {
    final s = Store();
    s.businesses = [Business(id: 'b1', name: 'Test', tax: 10)];
    s.currentBizId = 'b1';
    final p = Product(id: 'p1', bizId: 'b1', name: 'Tea', price: 2.50, stock: 10);
    s.products = [p];

    s.addToCart(p);
    s.addToCart(p);

    expect(s.cartCount, 2);
    expect(s.cartSubtotal, closeTo(5.00, 0.001));
    expect(s.cartTax, closeTo(0.50, 0.001));
    expect(s.cartTotal, closeTo(5.50, 0.001));
  });

  test('stock caps what can be added', () {
    final s = Store();
    s.businesses = [Business(id: 'b1', name: 'Test')];
    s.currentBizId = 'b1';
    final p = Product(id: 'p1', bizId: 'b1', name: 'Bread', price: 1, stock: 2);
    s.products = [p];

    s.addToCart(p);
    s.addToCart(p);
    s.addToCart(p); // beyond stock — must not go through

    expect(s.cartCount, 2);
  });
}
