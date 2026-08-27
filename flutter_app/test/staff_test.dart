import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casripos/data/store.dart';
import 'package:casripos/models/models.dart';

/// Casri POS - who may sign in, and how many of them.
///
/// A cash register IS a cashier login, so the number of them is what the MPQ
/// plan charges for. That makes this file two things at once: the rules that
/// keep a shop out of trouble, and the rules that make three prices mean three
/// different products. Every assertion is a refusal.
void main() {
  late Store store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = Store();
    await store.init();
    store.businesses = [Business(id: 'b1', name: 'Casri Shop')];
    store.currentBizId = 'b1';
    // A fresh install ships one admin and one shared cashier. Start from just
    // the admin, signed in, so each test says what it means.
    store.accounts = [
      Account(id: 'a1', name: 'Admin', username: 'admin', password: 'admin123',
          role: 'admin', bizId: 'b1'),
    ];
    store.user = store.accounts.first;
  });

  String? addCashier(String username) => store.saveStaff(
      id: '', name: username, username: username, role: 'cashier',
      password: 'till1234');

  group('the plan decides how many tills', () {
    test('MPQ50 allows one cashier and refuses the second', () {
      store.planId = 'MPQ50';
      expect(addCashier('hodan'), isNull);
      final second = addCashier('amina');
      expect(second, isNotNull);
      expect(second, contains('MPQ50'));
      expect(second, contains('1 cash register'),
          reason: 'the refusal has to say what they are allowed, and it must '
              'not say "1 cash registers"');
      expect(store.accounts.where((a) => a.role == 'cashier').length, 1,
          reason: 'a refused save must leave the books exactly as they were');
    });

    test('MPQ100 allows two, MPQ200 allows three', () {
      store.planId = 'MPQ100';
      expect(addCashier('hodan'), isNull);
      expect(addCashier('amina'), isNull);
      expect(addCashier('sagal'), isNotNull);

      store.planId = 'MPQ200';
      expect(addCashier('sagal'), isNull,
          reason: 'moving up a plan should let the next one in immediately');
      expect(addCashier('cabdi'), isNotNull);
    });

    test('the refusal names the plan and pluralises properly', () {
      store.planId = 'MPQ200';
      for (final n in ['a', 'b', 'c']) {
        expect(addCashier('till$n'), isNull);
      }
      final over = addCashier('tilld');
      expect(over, contains('3 cash registers'));
    });

    test('switching a cashier off frees the register', () {
      store.planId = 'MPQ50';
      expect(addCashier('hodan'), isNull);
      expect(addCashier('amina'), isNotNull);

      final hodan = store.accounts.firstWhere((a) => a.username == 'hodan');
      expect(
          store.saveStaff(
              id: hodan.id, name: 'Hodan', username: 'hodan',
              role: 'cashier', active: false),
          isNull);
      expect(addCashier('amina'), isNull,
          reason: 'a till that is switched off is not a till in use');
    });

    test('renaming a cashier who already counts is not refused', () {
      store.planId = 'MPQ50';
      expect(addCashier('hodan'), isNull);
      final hodan = store.accounts.firstWhere((a) => a.username == 'hodan');
      expect(
          store.saveStaff(
              id: hodan.id, name: 'Hodan Ali', username: 'hodan',
              role: 'cashier'),
          isNull,
          reason: 'they are inside the limit already - editing them is not '
              'asking for another register');
    });

    test('an admin does not use up a cash register', () {
      store.planId = 'MPQ50';
      expect(
          store.saveStaff(
              id: '', name: 'Manager', username: 'manager', role: 'admin',
              password: 'boss1234'),
          isNull);
      expect(addCashier('hodan'), isNull,
          reason: 'the plan pays for tills, not for the owner');
    });

    test('a shop with no plan on it is not capped', () {
      store.planId = '';
      for (final n in ['a', 'b', 'c', 'd', 'e']) {
        expect(addCashier('till$n'), isNull);
      }
      expect(store.registersUsed, 5);
      expect(store.registerCapReached, isFalse);
    });
  });

  group('who may change who signs in', () {
    test('a cashier cannot add anybody', () {
      store.planId = 'MPQ200';
      expect(addCashier('hodan'), isNull);
      store.user = store.accounts.firstWhere((a) => a.username == 'hodan');

      final err = addCashier('amina');
      expect(err, isNotNull);
      expect(err, contains('administrator'));
      expect(store.accounts.any((a) => a.username == 'amina'), isFalse);
    });

    test('a cashier cannot remove anybody', () {
      store.planId = 'MPQ200';
      expect(addCashier('hodan'), isNull);
      final admin = store.accounts.firstWhere((a) => a.username == 'admin');
      store.user = store.accounts.firstWhere((a) => a.username == 'hodan');

      expect(store.removeStaff(admin.id), isNotNull);
      expect(store.accounts.any((a) => a.username == 'admin'), isTrue);
    });
  });

  group('the shop is never locked out of itself', () {
    test('the only administrator cannot demote themselves', () {
      final me = store.accounts.first;
      final err = store.saveStaff(
          id: me.id, name: 'Admin', username: 'admin', role: 'cashier');
      expect(err, isNotNull);
      expect(store.accounts.first.role, 'admin',
          reason: 'a refused save must not half-apply');
    });

    test('the only administrator cannot switch themselves off', () {
      final me = store.accounts.first;
      expect(
          store.saveStaff(
              id: me.id, name: 'Admin', username: 'admin', role: 'admin',
              active: false),
          isNotNull);
      expect(store.accounts.first.active, isTrue);
    });

    test('with a second administrator, the first may step down', () {
      expect(
          store.saveStaff(
              id: '', name: 'Manager', username: 'manager', role: 'admin',
              password: 'boss1234'),
          isNull);
      final me = store.accounts.firstWhere((a) => a.username == 'admin');
      store.planId = 'MPQ50';
      expect(
          store.saveStaff(
              id: me.id, name: 'Admin', username: 'admin', role: 'cashier'),
          isNull);
      expect(store.accounts.firstWhere((a) => a.username == 'admin').role,
          'cashier');
    });

    test('the only administrator cannot be removed', () {
      final me = store.accounts.first;
      store.user = Account(
          id: 'owner', name: 'Owner', username: 'owner', password: '',
          role: 'admin');
      expect(store.removeStaff(me.id), isNotNull);
      expect(store.accounts.length, 1);
    });

    test('you cannot remove the account you are signed in with', () {
      expect(
          store.saveStaff(
              id: '', name: 'Manager', username: 'manager', role: 'admin',
              password: 'boss1234'),
          isNull);
      final me = store.accounts.firstWhere((a) => a.username == 'admin');
      final err = store.removeStaff(me.id);
      expect(err, isNotNull);
      expect(err, contains('signed in'));
    });
  });

  group('what a login has to be', () {
    test('a username of two letters is refused', () {
      expect(
          store.saveStaff(
              id: '', name: 'X', username: 'ab', role: 'cashier',
              password: 'till1234'),
          isNotNull);
    });

    test('two people cannot share a username, whatever the capitals', () {
      store.planId = 'MPQ200';
      expect(addCashier('hodan'), isNull);
      final err = store.saveStaff(
          id: '', name: 'Another', username: 'HODAN', role: 'cashier',
          password: 'till1234');
      expect(err, isNotNull);
      expect(err, contains('taken'));
    });

    test('a new login must have a password', () {
      expect(
          store.saveStaff(
              id: '', name: 'Hodan', username: 'hodan', role: 'cashier',
              password: '12'),
          isNotNull);
    });

    test('leaving the password box empty keeps the password they had', () {
      store.planId = 'MPQ200';
      expect(addCashier('hodan'), isNull);
      final hodan = store.accounts.firstWhere((a) => a.username == 'hodan');

      expect(
          store.saveStaff(
              id: hodan.id, name: 'Hodan Ali', username: 'hodan',
              role: 'cashier'),
          isNull);
      expect(store.accounts.firstWhere((a) => a.username == 'hodan').password,
          'till1234',
          reason: 'the blank box means "leave it alone" - writing it through '
              'would wipe a working password every time a name was fixed');
      expect(store.signIn('hodan', 'till1234'), isTrue);
    });

    test('a new password does take effect', () {
      store.planId = 'MPQ200';
      expect(addCashier('hodan'), isNull);
      final hodan = store.accounts.firstWhere((a) => a.username == 'hodan');
      expect(
          store.saveStaff(
              id: hodan.id, name: 'Hodan', username: 'hodan', role: 'cashier',
              password: 'newpass1'),
          isNull);
      expect(store.signIn('hodan', 'till1234'), isFalse);
      expect(store.signIn('hodan', 'newpass1'), isTrue);
    });

    test('a switched-off login cannot sign in', () {
      store.planId = 'MPQ200';
      expect(addCashier('hodan'), isNull);
      final hodan = store.accounts.firstWhere((a) => a.username == 'hodan');
      store.saveStaff(
          id: hodan.id, name: 'Hodan', username: 'hodan', role: 'cashier',
          active: false);
      expect(store.signIn('hodan', 'till1234'), isFalse);
    });
  });

  group('one shop cannot see another\'s people', () {
    test('a new login is pinned to the business that made it', () {
      store.planId = 'MPQ200';
      expect(addCashier('hodan'), isNull);
      expect(store.accounts.firstWhere((a) => a.username == 'hodan').bizId,
          'b1');
    });

    test('another shop\'s cashiers do not use up this shop\'s registers', () {
      store.planId = 'MPQ50';
      store.accounts.add(Account(
          id: 'x1', name: 'Theirs', username: 'theirs', password: 'x',
          role: 'cashier', bizId: 'b2'));
      expect(store.registersUsed, 0);
      expect(addCashier('hodan'), isNull);
      expect(store.registersUsed, 1);
    });
  });
}
