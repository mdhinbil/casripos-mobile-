import 'package:flutter/material.dart';
import 'data/store.dart';
import 'data/cloud.dart';
import 'screens/actions_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pending_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/products_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/workspaces_admin_screen.dart';

final store = Store();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.init();
  runApp(const CasriApp());
}

// Brand colours carried over from the web app so the two look like one product.
const kNavy = Color(0xFF0A1628);
const kBlue = Color(0xFF1A6EF5);
const kCyan = Color(0xFF00B8D9);
const kGreen = Color(0xFF1F9D63);

/// Tiny i18n helper mirroring the web app's T(en, so). Reads the live language,
/// so flipping it and calling notifyListeners() re-renders everything.
String t(String en, String so) => store.lang == 'so' ? so : en;

/// Display name for a business industry (Business.type), in the current language.
String industryName(String key) {
  switch (key) {
    case 'restaurant':
      return t('Restaurant', 'Maqaayad');
    case 'cafe':
      return t('Cafe', 'Kafateeriya');
    case 'bar':
      return t('Juice / Tea Bar', 'Casiir / Shaah');
    default:
      return t('Shop / Retail', 'Dukaan');
  }
}

class CasriApp extends StatelessWidget {
  const CasriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Casri POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kBlue, primary: kBlue),
        scaffoldBackgroundColor: const Color(0xFFF2F5F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: kNavy,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 19, fontWeight: FontWeight.w800, color: kNavy),
        ),
        // CardThemeData, not CardTheme — the theme slot takes the data class
        // on current Flutter.
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE3E8EF)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E0EA)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            // 52dp tall: comfortably tappable with a thumb on a busy counter.
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      home: const RootGate(),
    );
  }
}

/// Shows the login until someone signs in, then the tabbed shell.
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  @override
  void initState() {
    super.initState();
    store.addListener(_onChange);
    // The till gate depends on cloud approval state too, so rebuild on both.
    cloud.addListener(_onChange);
  }

  @override
  void dispose() {
    store.removeListener(_onChange);
    cloud.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (store.user == null) return const LoginScreen();
    // The MareegTech master account manages workspaces instead of selling.
    if (cloud.master) {
      return const WorkspacesAdminScreen(isHome: true);
    }
    // A client whose workspace is registered but not yet approved can't sell.
    if (cloud.tillBlocked) return const PendingApprovalScreen();
    return const HomeShell();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    store.addListener(_onChange); // rebuild nav + screens on language change
  }

  @override
  void dispose() {
    store.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // A bottom bar is what makes this read as an app rather than a web page:
    // the main jobs are always one thumb-reach away.
    final screens = [
      const PosScreen(),
      const ProductsScreen(),
      const SalesScreen(),
      const ActionsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(bottom: false, child: screens[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        height: 68,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.point_of_sale_outlined),
            selectedIcon: const Icon(Icons.point_of_sale),
            label: t('Sell', 'Iibi')),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: t('Products', 'Alaabta')),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: t('Sales', 'Iibka')),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
            label: t('Actions', 'Ficillo')),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: t('Settings', 'Dejinta')),
        ],
      ),
    );
  }
}
