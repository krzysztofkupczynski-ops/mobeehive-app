import 'package:flutter/material.dart';

import '../api.dart';
import '../db.dart';
import '../sync.dart';
import '../update.dart';
import 'apiary_screen.dart';
import 'documents_screen.dart';
import 'forms.dart';
import 'hive_screen.dart';
import 'login_screen.dart';
import 'scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _apiaries = [];
  Map<String, int> _hiveCounts = {};
  int _seenVersion = -1;

  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_onSync);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => AppUpdater.check(context));
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    final s = SyncService.instance;
    if (s.dataVersion != _seenVersion) _load();
    if (s.notices.isNotEmpty && mounted) {
      final msg = s.notices.removeAt(0);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    _seenVersion = SyncService.instance.dataVersion;
    final apiaries = await Db.instance.list('apiaries', orderKey: 'name');
    final hives = await Db.instance.list('hives');
    final counts = <String, int>{};
    for (final h in hives) {
      final a = h['apiary_id'] as String?;
      if (a != null) counts[a] = (counts[a] ?? 0) + 1;
    }
    if (!mounted) return;
    setState(() {
      _apiaries = apiaries;
      _hiveCounts = counts;
    });
  }

  Future<void> _addApiary() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ApiaryForm()));
    if (saved == true) {
      await _load();
      SyncService.instance.run();
    }
  }

  Future<void> _scan() async {
    final hiveId = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (hiveId == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => HiveScreen(hiveId: hiveId)));
    _load();
  }

  Future<void> _logout() async {
    final dirty = await Db.instance.dirtyRows();
    if (!mounted) return;
    if (dirty.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Niewysłane zmiany'),
          content: const Text('Część zmian nie trafiła jeszcze na serwer. Po wylogowaniu zostaną utracone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Wyloguj mimo to')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await Api.instance.logout();
    await Db.instance.wipe();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    final account = Api.instance.user?['account'] as Map<String, dynamic>?;
    final premium = account?['plan'] == 'premium';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moje pasieki'),
        actions: [
          IconButton(
            tooltip: sync.lastError ?? 'Synchronizuj',
            onPressed: sync.running ? null : sync.run,
            icon: sync.running
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(sync.lastError == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _logout();
              if (v == 'docs') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DocumentsScreen()));
              if (v == 'update') AppUpdater.check(context, manual: true);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${Api.instance.user?['email'] ?? ''}\nPlan: ${premium ? 'Premium' : 'darmowy'}'),
              ),
              const PopupMenuItem(value: 'docs', child: Text('Dokumenty')),
              if (sideload) const PopupMenuItem(value: 'update', child: Text('Sprawdź aktualizacje')),
              const PopupMenuItem(value: 'logout', child: Text('Wyloguj')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: sync.run,
        child: _apiaries.isEmpty
            ? ListView(children: [
                const SizedBox(height: 120),
                const Icon(Icons.hive_outlined, size: 72),
                const SizedBox(height: 12),
                const Center(child: Text('Nie masz jeszcze żadnej pasieki.')),
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.icon(
                    onPressed: _addApiary,
                    icon: const Icon(Icons.add),
                    label: const Text('Dodaj pasiekę'),
                  ),
                ),
              ])
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (sync.lastError != null)
                    MaterialBanner(
                      content: Text(sync.lastError!),
                      leading: const Icon(Icons.cloud_off_outlined),
                      actions: [TextButton(onPressed: sync.run, child: const Text('Ponów'))],
                    ),
                  for (final a in _apiaries)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.location_on_outlined)),
                      title: Text((a['name'] ?? '') as String),
                      subtitle: Text('Uli: ${_hiveCounts[a['id']] ?? 0}'
                          '${(a['address'] ?? '').toString().isNotEmpty ? ' · ${a['address']}' : ''}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => ApiaryScreen(apiaryId: a['id'] as String)));
                        _load();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Dodaj pasiekę'),
                    onTap: _addApiary,
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Skanuj ul'),
      ),
    );
  }
}
