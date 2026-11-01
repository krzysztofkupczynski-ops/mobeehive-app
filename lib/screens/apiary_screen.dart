import 'package:flutter/material.dart';

import '../db.dart';
import '../feeding.dart';
import '../location.dart';
import '../sync.dart';
import 'feeding_form.dart';
import 'forms.dart';
import 'hive_screen.dart';
import 'treatment_form.dart';
import 'weather_screen.dart';

class ApiaryScreen extends StatefulWidget {
  const ApiaryScreen({super.key, required this.apiaryId});
  final String apiaryId;

  @override
  State<ApiaryScreen> createState() => _ApiaryScreenState();
}

class _ApiaryScreenState extends State<ApiaryScreen> {
  Map<String, dynamic>? _apiary;
  List<Map<String, dynamic>> _hives = [];
  final Map<String, Map<String, dynamic>> _lastInspection = {};
  List<SeasonTotal> _feedTotals = [];
  bool _regionTried = false;

  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final db = Db.instance;
    final apiary = await db.get('apiaries', widget.apiaryId);
    final hives = await db.list('hives', where: {'apiary_id': widget.apiaryId});
    hives.sort((a, b) {
      final na = int.tryParse('${a['number']}'), nb = int.tryParse('${b['number']}');
      if (na != null && nb != null) return na.compareTo(nb);
      return '${a['number']}'.compareTo('${b['number']}');
    });
    _lastInspection.clear();
    for (final h in hives) {
      final ins = await db.list('inspections', where: {'hive_id': h['id'] as String}, orderKey: 'inspected_at');
      if (ins.isNotEmpty) _lastInspection[h['id'] as String] = ins.last;
    }
    final feedings = await db.list('feedings', where: {'apiary_id': widget.apiaryId});
    // Starsze pasieki bez powiatu – uzupełnij w tle, gdy jest połączenie.
    if (apiary != null && apiary['lat'] != null && '${apiary['county'] ?? ''}'.isEmpty && !_regionTried) {
      _regionTried = true;
      resolveRegion(apiary).then((r) {
        if (r != null) {
          SyncService.instance.run();
          _load();
        }
      });
    }
    if (!mounted) return;
    setState(() {
      _feedTotals = seasonTotals(feedings);
      _apiary = apiary;
      _hives = hives;
    });
  }

  Future<void> _open(Widget page) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page));
    await _load();
    if (changed == true) SyncService.instance.run();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Usunąć pasiekę?'),
        content: Text(_hives.isEmpty ? 'Pasieka zostanie usunięta.' : 'Pasieka ma ${_hives.length} uli – zostaną usunięte razem z nią.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok != true) return;
    for (final h in _hives) {
      await Db.instance.remove('hives', h['id'] as String);
    }
    await Db.instance.remove('apiaries', widget.apiaryId);
    SyncService.instance.run();
    if (mounted) Navigator.pop(context, true);
  }

  /// Kolor kafelka: siła rodziny z ostatniego przeglądu; szary, gdy przeglądu brak lub jest starszy niż 30 dni.
  Color _color(BuildContext context, Map<String, dynamic>? ins) {
    final scheme = Theme.of(context).colorScheme;
    if (ins == null) return scheme.surfaceContainerHighest;
    final at = DateTime.tryParse('${ins['inspected_at']}');
    if (at == null || DateTime.now().difference(at).inDays > 30) return scheme.surfaceContainerHighest;
    final s = int.tryParse('${ins['strength']}') ?? 3;
    return [Colors.red.shade300, Colors.orange.shade300, Colors.amber.shade300, Colors.lightGreen.shade300, Colors.green.shade400][(s - 1).clamp(0, 4)];
  }

  @override
  Widget build(BuildContext context) {
    final a = _apiary;
    return Scaffold(
      appBar: AppBar(
        title: Text((a?['name'] ?? 'Pasieka') as String),
        actions: [
          if (a != null) IconButton(tooltip: 'Edytuj', onPressed: () => _open(ApiaryForm(apiary: a)), icon: const Icon(Icons.edit_outlined)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Usuń pasiekę'))],
          ),
        ],
      ),
      body: Column(children: [
        if (_apiary != null && '${_apiary!['county'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              const Icon(Icons.place_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(regionLabel(_apiary!))),
            ]),
          ),
        if (_apiary != null) WeatherCard(apiary: _apiary!),
        if (_feedTotals.isNotEmpty)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: ListTile(
              leading: const Icon(Icons.water_drop_outlined),
              title: Text('Podkarmianie: ${_feedTotals.first.season}'),
              subtitle: Text([
                for (final t in _feedTotals.skip(1).take(2)) '${t.season}: ${t.amount}',
              ].join(' · ')),
              trailing: Text(_feedTotals.first.amount, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
        Expanded(
          child: _hives.isEmpty
          ? const Center(child: Text('Dodaj pierwszy ul przyciskiem poniżej.'))
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisSpacing: 10, crossAxisSpacing: 10),
              itemCount: _hives.length,
              itemBuilder: (context, i) {
                final h = _hives[i];
                final ins = _lastInspection[h['id']];
                return Material(
                  color: _color(context, ins),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _open(HiveScreen(hiveId: h['id'] as String)),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('${h['number'] ?? ''}', style: Theme.of(context).textTheme.headlineSmall),
                        if ((h['name'] ?? '').toString().isNotEmpty)
                          Text('${h['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(ins == null ? 'brak przeglądu' : _ago(ins['inspected_at']), style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ),
                );
              },
            ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 64,
                child: FilledButton.icon(
                  onPressed: () => _open(HiveForm(apiaryId: widget.apiaryId)),
                  icon: const Icon(Icons.add, size: 26),
                  label: const Text('Dodaj ul', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 64,
                child: FilledButton.tonalIcon(
                  onPressed: _hives.isEmpty ? null : () => _open(FeedingForm(apiaryId: widget.apiaryId)),
                  icon: const Icon(Icons.water_drop_outlined, size: 26),
                  label: const Text('Karmienie', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 64,
              width: 64,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: _hives.isEmpty ? null : () => _open(TreatmentForm(apiaryId: widget.apiaryId)),
                child: const Icon(Icons.medication_outlined, size: 28),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  static String _ago(dynamic v) {
    final d = DateTime.tryParse('$v');
    if (d == null) return '';
    final days = DateTime.now().difference(d).inDays;
    return days == 0 ? 'dziś' : days == 1 ? 'wczoraj' : '$days dni temu';
  }
}
