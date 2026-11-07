import 'package:flutter/material.dart';

import '../api.dart';
import '../db.dart';
import '../sync.dart';
import '../update.dart';
import 'apiary_screen.dart';
import 'documents_screen.dart';
import 'rhd_screen.dart';
import 'settings_screen.dart';
import '../settings.dart';
import 'forms.dart';
import 'hive_screen.dart';
import 'login_screen.dart';
import 'rhd_forms.dart';
import 'scan_screen.dart';
import '../tasks.dart';
import 'treatment_form.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _apiaries = [];
  Map<String, int> _hiveCounts = {};
  List<Map<String, dynamic>> _tasks = [];
  bool _allTasks = false;
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
    final tasks = await AutoTasks.open();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
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

  Future<void> _quick(Widget page) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page));
    await _load();
    if (changed == true) SyncService.instance.run();
  }

  /// Leczenie: przy jednej pasiece od razu formularz, przy kilku – wybór pasieki dużymi przyciskami.
  Future<void> _treatment() async {
    String? id = _apiaries.length == 1 ? _apiaries.first['id'] as String : null;
    id ??= await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Leczenie – która pasieka?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          for (final a in _apiaries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 64,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(c, a['id'] as String),
                  child: Row(children: [
                    const Icon(Icons.location_on_outlined),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${a['name']}', style: const TextStyle(fontSize: 18))),
                    Text('${_hiveCounts[a['id']] ?? 0} uli'),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
    if (id != null && mounted) await _quick(TreatmentForm(apiaryId: id));
  }

  Widget _action(String label, IconData icon, VoidCallback onTap) => Expanded(
        child: SizedBox(
          height: 84,
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: onTap,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 30),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      );

  Widget _actions() {
    final selling = Settings.sales != SalesMode.none;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(children: [
        _action('Leczenie', Icons.medication_outlined, _treatment),
        if (selling) ...[
          const SizedBox(width: 10),
          _action('Sprzedaż', Icons.point_of_sale_outlined, () => _quick(const SaleForm())),
          const SizedBox(width: 10),
          _action('Dezynfekcja', Icons.cleaning_services_outlined, () => _quick(const HygieneForm())),
        ],
      ]),
    );
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
              if (v == 'rhd') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RhdScreen()));
              if (v == 'settings') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => setState(() {}));
              }
              if (v == 'docs') Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DocumentsScreen()));
              if (v == 'update') AppUpdater.check(context, manual: true);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('${Api.instance.user?['email'] ?? ''}\nPlan: ${premium ? 'Premium' : 'darmowy'}'),
              ),
              if (Settings.sales != SalesMode.none) PopupMenuItem(value: 'rhd', child: Text(Settings.sales.workshop)),
              const PopupMenuItem(value: 'docs', child: Text('Dokumenty')),
              const PopupMenuItem(value: 'settings', child: Text('Ustawienia')),
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
                  _actions(),
                  if (_tasks.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                      child: Text('Do zrobienia (${_tasks.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    for (final t in (_allTasks ? _tasks : _tasks.take(4)))
                      Card(
                        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        color: '${AutoTasks.dueLabel(t['due_on'])}'.startsWith('zaległe') || AutoTasks.dueLabel(t['due_on']) == 'dziś'
                            ? Theme.of(context).colorScheme.errorContainer
                            : null,
                        child: ListTile(
                          leading: IconButton(
                            iconSize: 32,
                            tooltip: 'Zrobione',
                            icon: const Icon(Icons.check_box_outline_blank),
                            onPressed: () async {
                              await AutoTasks.done(t);
                              _load();
                              SyncService.instance.run();
                            },
                          ),
                          title: Text('${t['title']}'),
                          subtitle: Text(AutoTasks.dueLabel(t['due_on'])),
                          trailing: t['hive_id'] == null ? null : const Icon(Icons.chevron_right),
                          onTap: t['hive_id'] == null
                              ? null
                              : () async {
                                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => HiveScreen(hiveId: '${t['hive_id']}')));
                                  _load();
                                },
                        ),
                      ),
                    if (_tasks.length > 4)
                      TextButton(
                        onPressed: () => setState(() => _allTasks = !_allTasks),
                        child: Text(_allTasks ? 'Pokaż mniej' : 'Pokaż wszystkie (${_tasks.length})'),
                      ),
                  ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text('Pasieki', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
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
