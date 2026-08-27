import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casripos/data/cloud.dart';
import 'package:casripos/data/store.dart';
import 'package:casripos/models/models.dart';

/// Casri POS - the MPQ plan is what a shop pays for every month.
///
/// $10, $20 or $30 buys a number of products and a number of tills, so the cap
/// IS the product. If it does not bite, we are charging three prices for one
/// thing; if it bites at the wrong number, we are charging for something we do
/// not deliver. Every assertion here is one of those two.
void main() {
  late Store store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = Store();
    await store.init();
    store.businesses = [Business(id: 'b1', name: 'Casri Shop')];
    store.currentBizId = 'b1';
    store.products = [];
  });

  void fill(int n) {
    for (var i = 0; i < n; i++) {
      store.products.add(Product(
          id: 'p$i', bizId: 'b1', name: 'Item $i', price: 1, stock: 1));
    }
  }

  group('the tiers are what the member area sells', () {
    test('MPQ50, MPQ100 and MPQ200 exist and nothing else does', () {
      expect(plans.keys.toList()..sort(), ['MPQ100', 'MPQ200', 'MPQ50']);
    });

    test('each allows exactly what is charged for', () {
      expect(plans['MPQ50']!.maxProducts, 50);
      expect(plans['MPQ50']!.registers, 1);
      expect(plans['MPQ100']!.maxProducts, 100);
      expect(plans['MPQ100']!.registers, 2);
      expect(plans['MPQ200']!.maxProducts, 200);
      expect(plans['MPQ200']!.registers, 3);
    });
  });

  group('the product cap', () {
    test('a shop on MPQ50 may hold 49 and is stopped at 50', () {
      store.planId = 'MPQ50';
      fill(49);
      expect(store.productCapReached, isFalse,
          reason: 'they paid for fifty - forty-nine is not fifty');
      fill(1);
      expect(store.productCapReached, isTrue);
    });

    test('paying more lifts the cap there and then', () {
      store.planId = 'MPQ50';
      fill(50);
      expect(store.productCapReached, isTrue);

      store.planId = 'MPQ100';
      expect(store.productCapReached, isFalse,
          reason: 'a shop that upgrades should not have to restart the app');
    });

    test('another shop\'s products do not count against this one', () {
      store.planId = 'MPQ50';
      fill(40);
      for (var i = 0; i < 40; i++) {
        store.products.add(Product(
            id: 'other$i', bizId: 'b2', name: 'Theirs $i', price: 1, stock: 1));
      }
      expect(store.productCapReached, isFalse,
          reason: 'the cap is per business, and eighty rows are two shops');
    });

    test('an unknown plan string does not silently cap a paying shop', () {
      store.planId = 'MPQ500';
      fill(300);
      expect(store.plan, isNull);
      expect(store.productCapReached, isFalse,
          reason: 'better an uncapped shop than a paying one locked out by a '
              'typo in a plan name');
    });

    test('a shop nobody has switched on yet is not capped', () {
      // Deliberate, and worth knowing: the cap binds only once a plan has been
      // put on the workspace. Shops from before the plans existed keep working.
      store.planId = '';
      fill(300);
      expect(store.productCapReached, isFalse);
    });
  });

  group('the register cap', () {
    test('every tier states how many tills it allows', () {
      for (final p in plans.values) {
        expect(p.registers, greaterThan(0), reason: '${p.id} allows none?');
      }
    });

    // NOT YET ENFORCED. There is no screen in this app for adding a cashier -
    // accounts arrive from the store and sign-in matches against them - so
    // there is nothing here to refuse. The web app enforces it where cashiers
    // are created. When a staff screen lands here, the rule to copy is:
    // count ACTIVE accounts with role 'cashier' scoped to the current business,
    // and refuse the next one at plan.registers.
  }, skip: 'no staff screen in the native app yet - see the note above');
}
