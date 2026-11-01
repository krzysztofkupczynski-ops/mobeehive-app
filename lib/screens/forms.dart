import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../api.dart';
import '../db.dart';
import '../location.dart';
import '../widgets.dart';

/// Formularz pasieki (nowej albo edytowanej).
class ApiaryForm extends StatefulWidget {
  const ApiaryForm({super.key, this.apiary});
  final Map<String, dynamic>? apiary;

  @override
  State<ApiaryForm> createState() => _ApiaryFormState();
}

class _ApiaryFormState extends State<ApiaryForm> {
  late final _name = TextEditingController(text: widget.apiary?['name'] as String?);
  late final _address = TextEditingController(text: widget.apiary?['address'] as String?);
  late final _vet = TextEditingController(text: widget.apiary?['vet_number'] as String?);
  late final _notes = TextEditingController(text: widget.apiary?['notes'] as String?);
  late String _kind = (widget.apiary?['kind'] as String?) ?? 'stacjonarna';
  late final _wintering = TextEditingController(text: widget.apiary?['wintering_address'] as String?);
  late final _facilities = TextEditingController(text: widget.apiary?['facilities'] as String?);
  late final _capacity = TextEditingController(text: widget.apiary?['capacity']?.toString());
  late final _period = TextEditingController(text: widget.apiary?['season_period'] as String?);
  late final _risk = TextEditingController(text: widget.apiary?['risk_notes'] as String?);
  late final _duration = TextEditingController(text: (widget.apiary?['planned_duration'] as String?) ?? 'bezterminowo');
  late double? _lat = double.tryParse('${widget.apiary?['lat']}');
  late double? _lng = double.tryParse('${widget.apiary?['lng']}');
  late Map<String, dynamic> _region = {
    for (final k in ['voivodeship', 'county', 'commune', 'teryt']) k: widget.apiary?[k],
  };
  bool _locating = false;
  bool _regionLoading = false;

  Future<void> _setPoint(LatLng p) async {
    setState(() {
      _lat = double.parse(p.latitude.toStringAsFixed(5));
      _lng = double.parse(p.longitude.toStringAsFixed(5));
      _region = {};
      _regionLoading = true;
    });
    final r = await resolveRegion({'lat': _lat, 'lng': _lng}, save: false);
    if (!mounted) return;
    setState(() {
      _regionLoading = false;
      if (r != null) _region = {for (final k in ['voivodeship', 'county', 'commune', 'teryt']) k: r[k]};
    });
  }

  Future<void> _here() async {
    setState(() => _locating = true);
    try {
      await _setPoint(await currentPosition());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is String ? e : 'Nie udało się ustalić lokalizacji.')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _onMap() async {
    final p = await Navigator.of(context).push<LatLng>(MaterialPageRoute(
      builder: (_) => MapPickerScreen(initial: _lat == null ? null : LatLng(_lat!, _lng!)),
    ));
    if (p != null) await _setPoint(p);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    await Db.instance.save('apiaries', {
      ...?widget.apiary,
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'vet_number': _vet.text.trim(),
      'notes': _notes.text.trim(),
      'lat': _lat,
      'lng': _lng,
      ..._region,
      'kind': _kind,
      'wintering_address': _wintering.text.trim(),
      'facilities': _facilities.text.trim(),
      'capacity': int.tryParse(_capacity.text.trim()),
      'season_period': _period.text.trim(),
      'risk_notes': _risk.text.trim(),
      'planned_duration': _duration.text.trim(),
    });
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.apiary == null ? 'Nowa pasieka' : 'Edytuj pasiekę')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nazwa *'), autofocus: widget.apiary == null),
        const SizedBox(height: 12),
        TextField(controller: _address, decoration: const InputDecoration(labelText: 'Adres lub miejsce')),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Miejsce pasieki', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_lat == null ? 'Nieustawione – potrzebne do pogody i dokumentów.' : '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'),
              if (_regionLoading)
                const Padding(padding: EdgeInsets.only(top: 6), child: Text('Ustalam powiat…'))
              else if ('${_region['county'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(regionLabel(_region), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                )
              else if (_lat != null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Powiat ustalimy, gdy będzie połączenie z internetem.'),
                ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _locating ? null : _here,
                      icon: _locating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      label: const Text('Jestem tutaj', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.tonalIcon(
                      onPressed: _onMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Na mapie', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _vet, decoration: const InputDecoration(labelText: 'Weterynaryjny numer identyfikacyjny (WNI)')),
        const SizedBox(height: 12),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Uwagi'), maxLines: 3),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Dane do rejestracji w PLW'),
          subtitle: const Text('Potrzebne do wniosku o wpis pasieki do rejestru'),
          children: [
            BigChoice<String>(
              label: 'Rodzaj pasieki',
              options: const [('stacjonarna', 'Stacjonarna'), ('wędrowna', 'Wędrowna')],
              value: _kind,
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            if (_kind == 'wędrowna') ...[
              const SizedBox(height: 12),
              TextField(controller: _wintering, decoration: const InputDecoration(labelText: 'Adres miejsca zimowania')),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _facilities,
              decoration: const InputDecoration(labelText: 'Opis obiektów', hintText: 'np. ule na stojakach, pracownia w budynku gospodarczym'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacity,
              decoration: const InputDecoration(labelText: 'Potencjał pasieki (maks. liczba rodzin)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _period,
              decoration: const InputDecoration(labelText: 'Okres trzymania pszczół (jeśli nie cały rok)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _risk,
              decoration: const InputDecoration(labelText: 'Inne kwestie istotne dla oceny ryzyka'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(controller: _duration, decoration: const InputDecoration(labelText: 'Planowany czas prowadzenia działalności')),
            const SizedBox(height: 12),
          ],
        ),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz', onPressed: _save),
    );
  }
}

/// Formularz ula. Typ ula wybiera użytkownik ze słownika (wspólne + własne).
class HiveForm extends StatefulWidget {
  const HiveForm({super.key, required this.apiaryId, this.hive});
  final String apiaryId;
  final Map<String, dynamic>? hive;

  @override
  State<HiveForm> createState() => _HiveFormState();
}

class _HiveFormState extends State<HiveForm> {
  late final _number = TextEditingController(text: widget.hive?['number']?.toString());
  late final _name = TextEditingController(text: widget.hive?['name'] as String?);
  late final _notes = TextEditingController(text: widget.hive?['notes'] as String?);
  late int _boxes = int.tryParse('${widget.hive?['boxes'] ?? 1}') ?? 1;
  late int _supers = int.tryParse('${widget.hive?['supers'] ?? 0}') ?? 0;
  late String? _typeId = widget.hive?['hive_type_id'] as String?;
  List<Map<String, dynamic>> _types = [];

  @override
  void initState() {
    super.initState();
    Db.instance.list('hive_types', orderKey: 'name').then((t) {
      if (mounted) setState(() => _types = t);
    });
  }

  Future<void> _addType() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Własny typ ula'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Nazwa')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Dodaj')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final t = await Db.instance.save('hive_types', {'name': name});
    setState(() {
      _types = [..._types, t];
      _typeId = t['id'] as String;
    });
  }

  Future<void> _save() async {
    final isNew = widget.hive == null;
    if (isNew) {
      final account = Api.instance.user?['account'] as Map<String, dynamic>?;
      final limit = account?['hive_limit'] as int?;
      if (limit != null && await Db.instance.countActive('hives') >= limit) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Limit planu darmowego'),
            content: Text('W planie darmowym możesz mieć $limit uli. '
                'Mobeehive Premium (50 zł/rok) znosi limit – kupisz je na mobeehive.pl.'),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
        return;
      }
    }
    await Db.instance.save('hives', {
      ...?widget.hive,
      'apiary_id': widget.apiaryId,
      'number': _number.text.trim(),
      'name': _name.text.trim(),
      'hive_type_id': _typeId,
      'boxes': _boxes,
      'supers': _supers,
      'status': widget.hive?['status'] ?? 'active',
      'notes': _notes.text.trim(),
    });
    if (mounted) Navigator.pop(context, true);
  }

  Widget _counter(String label, int value, ValueChanged<int> onChanged) =>
      BigCounter(label: label, value: value, onChanged: (v) => onChanged(v.toInt()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.hive == null ? 'Nowy ul' : 'Edytuj ul')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          SizedBox(
            width: 110,
            child: TextField(controller: _number, decoration: const InputDecoration(labelText: 'Numer')),
          ),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nazwa (opcjonalnie)'))),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _types.any((t) => t['id'] == _typeId) ? _typeId : null,
          decoration: const InputDecoration(labelText: 'Typ ula'),
          items: [for (final t in _types) DropdownMenuItem(value: t['id'] as String, child: Text(t['name'] as String))],
          onChanged: (v) => setState(() => _typeId = v),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: _addType, icon: const Icon(Icons.add), label: const Text('Własny typ ula')),
        ),
        _counter('Korpusy', _boxes, (v) => setState(() => _boxes = v)),
        _counter('Nadstawki', _supers, (v) => setState(() => _supers = v)),
        const SizedBox(height: 8),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Uwagi'), maxLines: 3),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz', onPressed: _save),
    );
  }
}
