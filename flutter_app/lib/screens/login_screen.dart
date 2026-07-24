import 'package:flutter/material.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _u = TextEditingController();
  final _p = TextEditingController();
  bool _err = false, _hide = true;

  @override
  void dispose() { _u.dispose(); _p.dispose(); super.dispose(); }

  void _go() {
    if (!store.signIn(_u.text, _p.text)) setState(() => _err = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [kNavy, Color(0xFF1A4DC4)]),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 62, height: 62,
                        decoration: BoxDecoration(
                          color: kBlue, borderRadius: BorderRadius.circular(15)),
                        child: const Icon(Icons.shopping_cart,
                            color: Colors.white, size: 30),
                      ),
                      const SizedBox(height: 14),
                      const Text('Casri POS',
                          style: TextStyle(
                              fontSize: 23, fontWeight: FontWeight.w800, color: kNavy)),
                      const Text('Point of Sale System',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7688))),
                      const SizedBox(height: 20),
                      if (_err)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEAEA),
                            border: Border.all(color: const Color(0xFFFFB3B3)),
                            borderRadius: BorderRadius.circular(9)),
                          child: const Text('Wrong username or password',
                              style: TextStyle(color: Color(0xFFBF2600), fontSize: 12.5)),
                        ),
                      TextField(
                        controller: _u,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: _p,
                        obscureText: _hide,
                        onSubmitted: (_) => _go(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _hide = !_hide)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(onPressed: _go, child: const Text('Sign in')),
                      ),
                      const SizedBox(height: 14),
                      const Text('Demo:  admin / admin123',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF98A2B3))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
