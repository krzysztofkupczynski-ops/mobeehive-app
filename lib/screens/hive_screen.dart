import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../db.dart';
import '../feeding.dart';
import '../sync.dart';
import 'feeding_form.dart';
import 'forms.dart';
import 'inspection_form.dart';
import 'queens.dart';
import '../tasks.dart';
import 'treatment_form.dart';

/// Treść kodu QR naklejanego na ul.
String hiveQrData(String hiveId) => 'mobeehive:hive:$hiveId';

class HiveScreen extends StatefulWidget {
  const HiveScreen({super.key, required this.hiveId});
  final String hiveId;

  @override
  State<HiveScreen> createState() => _HiveScreenState();
}

class _HiveScreenState extends State<HiveScreen> {
  Map<String, dynamic>? _hive;
  String? _typeName;
  List<Map<String, dynamic>> _inspections = [];
  List<Map<String, dynamic>> _tasks = [];
  Map<String, dynamic>? _queen;
  List<Map<String, dynamic>> _feedings = [];
  List<Map<String, dynamic>> _treatments = [];
  bool _loaded = false;

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
    final hive = await db.get('hives', widget.hiveId);
    String? typeName;
    if (hive?['hive_type_id'] != null) {
      typeName = (await db.get('hive_types', hive!['hive_type_id'] as String))?['name'] as String?;
    }
    final ins = await db.list('inspections', where: {'hive_id': widget.hiveId}, orderKey: 'inspected_at');
    final feed = await db.list('feedings', where: {'hive_id': widget.hiveId}, orderKey: 'fed_on');
    final apiaryId = hive?['apiary_id'] as String?;
    final treat = apiaryId == null
        ? <Map<String, dynamic>>[]
        : (await db.list('treatments', where: {'apiary_id': apiaryId}, orderKey: 'treated_on'))
            .where((t) =>
                t['hive_id'] == widget.hiveId ||
                (t['hive_id'] == null && ('${t['hive_ids'] ?? ''}'.isEmpty || '${t['hive_ids']}'.split(',').contains(widget.hiveId))))
            .toList();
    final tasks = await AutoTasks.open(hiveId: widget.hiveId);
    final queens = (await db.list('queens', where: {'hive_id': widget.hiveId})).where((q) => '${q['removed_on'] ?? ''}'.isEmpty).toList();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _queen = queens.isEmpty ? null : queens.last;
      _hive = hive;
      _typeName = typeName;
      _inspections = ins.reversed.toList();
      _feedings = feed.reversed.toList();
      _treatments = treat.reversed.toList();
      _loaded = true;
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
        title: const Text('Usunąć ul?'),
        content: const Text('Ul zniknie z pasieki razem z historią przeglądów.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.instance.remove('hives', widget.hiveId);
    SyncService.instance.run();
    if (mounted) Navigator.pop(context, true);
  }

  void _showQr() {
    final h = _hive!;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Ul ${h['number'] ?? ''}'),
        content: SizedBox(
          width: 240,
          height: 240,
          child: QrImageView(data: hiveQrData(widget.hiveId), backgroundColor: Colors.white),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Zamknij'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = _hive;
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (h == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Tego ula nie ma w Twoich pasiekach.')));
    }
    final theme = Theme.of(context);
    final fmt = DateFormat('d MMM yyyy, HH:mm', 'pl');
    return Scaffold(
      appBar: AppBar(
        title: Text('Ul ${h['number'] ?? ''}${(h['name'] ?? '').toString().isNotEmpty ? ' · ${h['name']}' : ''}'),
        actions: [
          IconButton(tooltip: 'Kod QR', onPressed: _showQr, icon: const Icon(Icons.qr_code_2)),
          IconButton(
            tooltip: 'Edytuj',
            onPressed: () => _open(HiveForm(apiaryId: h['apiary_id'] as String, hive: h)),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Usuń ul'))],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 24, runSpacing: 8, children: [
              _fact('Typ', _typeName ?? '–'),
              _fact('Korpusy', '${h['boxes'] ?? '–'}'),
              _fact('Nadstawki', '${h['supers'] ?? '–'}'),
              if ((int.tryParse('${h['half_supers']}') ?? 0) > 0) _fact('Półnadstawki', '${h['half_supers']}'),
              if ((h['notes'] ?? '').toString().isNotEmpty) _fact('Uwagi', '${h['notes']}'),
            ]),
          ),
        ),
        for (final t in _tasks)
          Card(
            color: theme.colorScheme.tertiaryContainer,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: CheckboxListTile(
              value: false,
              title: Text('${t['title']}'),
              subtitle: Text(AutoTasks.dueLabel(t['due_on'])),
              onChanged: (_) async {
                await AutoTasks.done(t);
                _load();
                SyncService.instance.run();
              },
            ),
          ),
        ListTile(
          leading: QueenDot(year: int.tryParse('${_queen?['year']}'), label: '${_queen?['number'] ?? ''}'),
          title: Text(_queen == null ? 'Matka: brak wpisu' : 'Matka ${_queen!['number'] ?? ''} · ${_queen!['year'] ?? ''}'),
          subtitle: _queen == null ? const Text('Dodaj matkę') : Text('${_queen!['status'] ?? ''}${'${_queen!['breed'] ?? ''}'.isEmpty ? '' : ' · ${_queen!['breed']}'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(QueensScreen(hive: h)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Podkarmianie', style: theme.textTheme.titleMedium),
        ),
        if (_feedings.isEmpty) const ListTile(title: Text('Brak wpisów.')),
        for (final t in seasonTotals(_feedings))
          ListTile(
            leading: Icon(t.season.startsWith('Jesień') ? Icons.eco_outlined : Icons.local_florist_outlined),
            title: Text(t.season),
            trailing: Text(t.amount, style: theme.textTheme.titleMedium),
            subtitle: Text('Podań: ${t.entries}'),
          ),
        if (_feedings.isNotEmpty)
          ExpansionTile(
            title: const Text('Wszystkie wpisy'),
            children: [
              for (final f in _feedings)
                ListTile(
                  dense: true,
                  title: Text('${f['fed_on']} · ${f['feed_type'] ?? ''}'),
                  trailing: Text('${fmtAmount(num.tryParse('${f['amount']}') ?? 0)} ${f['unit'] ?? 'kg'}'),
                  onTap: () => _open(FeedingForm(apiaryId: h['apiary_id'] as String, hive: h, feeding: f)),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Leczenia', style: theme.textTheme.titleMedium),
        ),
        if (_treatments.isEmpty) const ListTile(title: Text('Brak leczeń.')),
        for (final t in _treatments.take(5))
          ListTile(
            leading: const Icon(Icons.medication_outlined),
            title: Text('${t['product'] ?? ''} · ${t['treated_on'] ?? ''}'),
            subtitle: Text([
              if (t['hive_id'] == null) 'cała pasieka',
              '${t['dose'] ?? ''}',
              'karencja ${t['withdrawal_days'] ?? 0} dni',
            ].where((e) => e.isNotEmpty).join(' · ')),
            onTap: () => _open(TreatmentForm(apiaryId: h['apiary_id'] as String, hive: t['hive_id'] == null ? null : h, treatment: t)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Przeglądy', style: theme.textTheme.titleMedium),
        ),
        if (_inspections.isEmpty) const ListTile(title: Text('Brak przeglądów.')),
        for (final i in _inspections)
          ListTile(
            leading: CircleAvatar(child: Text('${i['strength'] ?? '–'}')),
            title: Text(_dt(fmt, i['inspected_at'])),
            subtitle: Text(_summary(i)),
            onTap: () => _open(InspectionForm(hive: h, inspection: i)),
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
                  onPressed: () => _open(InspectionForm(hive: h)),
                  icon: const Icon(Icons.fact_check_outlined, size: 26),
                  label: const Text('Przegląd', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 64,
                child: FilledButton.tonalIcon(
                  onPressed: () => _open(FeedingForm(apiaryId: h['apiary_id'] as String, hive: h)),
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
                onPressed: () => _open(TreatmentForm(apiaryId: h['apiary_id'] as String, hive: h)),
                child: const Icon(Icons.medication_outlined, size: 28),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _fact(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ]);

  static String _dt(DateFormat f, dynamic v) {
    final d = DateTime.tryParse('$v');
    return d == null ? '' : f.format(d);
  }

  static bool _yes(dynamic v) => v == true || v == 1 || v == '1';

  static String _summary(Map<String, dynamic> i) {
    final parts = <String>[
      if (_yes(i['queen_seen'])) 'matka widziana',
      if (_yes(i['eggs'])) 'jajka',
      if (_yes(i['open_brood'])) 'czerw otwarty',
      if (_yes(i['capped_brood'])) 'czerw kryty',
      if ((int.tryParse('${i['queen_cells']}') ?? 0) > 0) 'mateczniki: ${i['queen_cells']}',
      if (_yes(i['swarm_mood'])) 'NASTRÓJ ROJOWY',
      if (_yes(i['no_brood'])) 'brak czerwiu',
      if (_yes(i['no_stores'])) 'brak pokarmu',
      if ('${i['disease'] ?? ''}'.isNotEmpty && i['disease'] != 'Brak') '${i['disease']}',
      if ('${i['frames'] ?? ''}'.length > 2) 'ramki',
      if ('${i['photos'] ?? ''}'.length > 2) 'zdjęcia',
      if ((i['notes'] ?? '').toString().isNotEmpty) '${i['notes']}',
    ];
    return parts.isEmpty ? 'bez uwag' : parts.join(' · ');
  }
}
