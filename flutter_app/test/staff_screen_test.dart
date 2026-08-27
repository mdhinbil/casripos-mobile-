import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casripos/main.dart';
import 'package:casripos/models/models.dart';
import 'package:casripos/screens/staff_screen.dart';

/// Casri POS - the staff screen, on screen.
///
/// staff_test.dart proves the rules. This proves the WIRING: that the screen
/// tells a shop how many tills it has left BEFORE they press Add, and that a
/// refusal from the store actually reaches the person standing at the counter
/// instead of being swallowed.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.init();
    store.businesses = [Business(id: 'b1', name: 'Casri Shop')];
    store.currentBizId = 'b1';
    store.accounts = [
      Account(id: 'a1', name: 'Admin', username: 'admin', password: 'admin123',
          role: 'admin', bizId: 'b1'),
    ];
    store.user = store.accounts.first;
    store.lang = 'en';
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StaffScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('it says how many tills are used before anybody presses Add',
      (tester) async {
    store.planId = 'MPQ100';
    store.accounts.add(Account(
        id: 'a2', name: 'Hodan', username: 'hodan', password: 'till1234',
        role: 'cashier', bizId: 'b1'));

    await open(tester);
    expect(find.textContaining('1 of 2'), findsOneWidget);
    expect(find.textContaining('MPQ100 plan includes 2'), findsOneWidget);
  });

  testWidgets('a full plan says so, and says what to do about it',
      (tester) async {
    store.planId = 'MPQ50';
    store.accounts.add(Account(
        id: 'a2', name: 'Hodan', username: 'hodan', password: 'till1234',
        role: 'cashier', bizId: 'b1'));

    await open(tester);
    expect(find.textContaining('1 of 1'), findsOneWidget);
    expect(find.textContaining('is full'), findsOneWidget);
    expect(find.textContaining('move up a plan'), findsOneWidget);
  });

  testWidgets('trying to add one too many is refused, on screen',
      (tester) async {
    store.planId = 'MPQ50';
    store.accounts.add(Account(
        id: 'a2', name: 'Hodan', username: 'hodan', password: 'till1234',
        role: 'cashier', bizId: 'b1'));

    await open(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Username they type'), 'amina');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'till1234');
    await tester.tap(find.text('Add them'));
    await tester.pumpAndSettle();

    expect(find.textContaining('MPQ50 plan allows 1 cash register'),
        findsOneWidget,
        reason: 'the refusal has to be read on the sheet, not swallowed');
    expect(store.accounts.where((a) => a.username == 'amina'), isEmpty);
  });

  testWidgets('a cashier is shown the screen but cannot change it',
      (tester) async {
    store.planId = 'MPQ100';
    store.accounts.add(Account(
        id: 'a2', name: 'Hodan', username: 'hodan', password: 'till1234',
        role: 'cashier', bizId: 'b1'));
    store.user = store.accounts.last;

    await open(tester);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.textContaining('Only an administrator'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('adding a cashier works and lands in the list', (tester) async {
    store.planId = 'MPQ100';
    await open(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Hodan Ali');
    await tester.enterText(
        find.widgetWithText(TextField, 'Username they type'), 'hodan');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'till1234');
    await tester.tap(find.text('Add them'));
    await tester.pumpAndSettle();

    expect(find.text('Hodan Ali'), findsOneWidget);
    expect(find.textContaining('1 of 2'), findsOneWidget,
        reason: 'the counter has to move, or nobody trusts it');
  });
}
