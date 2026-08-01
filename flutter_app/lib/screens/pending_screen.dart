import 'package:flutter/material.dart';
import '../main.dart';
import '../data/cloud.dart';

/// Shown instead of the till when a signed-in client's workspace is registered
/// but not yet approved by MareegTech. The shop can back up and re-check, but
/// cannot sell until approved.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});
  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _busy = false;

  void _say(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await cloud.refreshWorkspace();
      // If it's now approved, the RootGate rebuilds into the till automatically.
      if (mounted && !cloud.wsApproved) _say('Still pending — check back soon');
    } catch (e) {
      _say(Cloud.errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchAccount() async {
    store.signOut(); // clear local session first (no till flash)
    await cloud.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kNavy, Color(0xFF1A4DC4)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFF4E5),
                            borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.hourglass_top,
                            color: Color(0xFFE0842B), size: 34),
                      ),
                      const SizedBox(height: 16),
                      const Text('Waiting for approval',
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: kNavy)),
                      const SizedBox(height: 8),
                      Text(
                        cloud.wsName.isNotEmpty
                            ? '“${cloud.wsName}” has been submitted. MareegTech '
                                'will approve it shortly. You can sell once it is '
                                'approved.'
                            : 'Your business has been submitted. MareegTech will '
                                'approve it shortly.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13.5, color: Color(0xFF5C6B82), height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      Text(cloud.email,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6B7688))),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _check,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.refresh),
                          label: const Text('Check again'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _switchAccount,
                        child: const Text('Sign out'),
                      ),
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
