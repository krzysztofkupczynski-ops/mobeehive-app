import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../db.dart';
import '../sync.dart';
import 'forms.dart';
import 'inspection_form.dart';

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
    if (!mounted) return;
    setState(() {
      _hive = hive;
      _typeName = typeName;
      _inspections = ins.reversed.toList();
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
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 24, runSpacing: 8, children: [
              _fact('Typ', _typeName ?? '–'),
              _fact('Korpusy', '${h['boxes'] ?? '–'}'),
              _fact('Nadstawki', '${h['supers'] ?? '–'}'),
              if ((h['notes'] ?? '').toString().isNotEmpty) _fact('Uwagi', '${h['notes']}'),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(InspectionForm(hive: h)),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Nowy przegląd'),
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
      if ((i['notes'] ?? '').toString().isNotEmpty) '${i['notes']}',
    ];
    return parts.isEmpty ? 'bez uwag' : parts.join(' · ');
  }
}
