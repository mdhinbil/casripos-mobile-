import 'package:flutter/material.dart';
import '../main.dart';
import '../data/cloud.dart';

/// MareegTech super-admin console: list every client workspace and approve or
/// revoke it. Only reachable when signed in as the master cloud account.
class WorkspacesAdminScreen extends StatefulWidget {
  const WorkspacesAdminScreen({super.key});
  @override
  State<WorkspacesAdminScreen> createState() => _WorkspacesAdminScreenState();
}

class _WorkspacesAdminScreenState extends State<WorkspacesAdminScreen> {
  bool _loading = true;
  String _error = '';
  List<Workspace> _rows = [];
  final Set<String> _working = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final rows = await cloud.listWorkspaces();
      rows.sort((a, b) {
        if (a.approved != b.approved) return a.approved ? 1 : -1; // pending first
        return b.createdAt.compareTo(a.createdAt);
      });
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = Cloud.errText(e);
        _loading = false;
      });
    }
  }

  Future<void> _toggle(Workspace w) async {
    setState(() => _working.add(w.uid));
    try {
      await cloud.approveWorkspace(w.uid, !w.approved);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Cloud.errText(e))));
      }
    } finally {
      if (mounted) setState(() => _working.remove(w.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _rows.where((w) => !w.approved).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspaces'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _ErrorView(message: _error, onRetry: _load)
              : _rows.isEmpty
                  ? const Center(
                      child: Text('No workspaces yet',
                          style: TextStyle(color: Color(0xFF6B7688))))
                  : Column(
                      children: [
                        if (pending > 0)
                          Container(
                            width: double.infinity,
                            color: const Color(0xFFFFF4E5),
                            padding: const EdgeInsets.all(12),
                            child: Text('$pending awaiting approval',
                                style: const TextStyle(
                                    color: Color(0xFF8A5A00),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _row(_rows[i]),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _row(Workspace w) {
    final working = _working.contains(w.uid);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.name.isNotEmpty ? w.name : '(unnamed)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(w.email,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF5C6B82))),
                  Row(
                    children: [
                      if (w.plan.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4, right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAEEF4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(w.plan,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: kNavy)),
                        ),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: w.approved
                              ? const Color(0xFFE3F6EC)
                              : const Color(0xFFFFF0DB),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(w.approved ? 'Approved' : 'Pending',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: w.approved
                                    ? const Color(0xFF1A7A4F)
                                    : const Color(0xFF8A5A00))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            working
                ? const SizedBox(
                    width: 34,
                    height: 34,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : w.approved
                    ? OutlinedButton(
                        onPressed: () => _toggle(w),
                        child: const Text('Revoke'))
                    : FilledButton(
                        onPressed: () => _toggle(w),
                        style:
                            FilledButton.styleFrom(backgroundColor: kGreen),
                        child: const Text('Approve')),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 42, color: Color(0xFFB6C0CE)),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6B7688))),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
