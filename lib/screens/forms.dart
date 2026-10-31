import 'package:flutter/material.dart';

import '../api.dart';
import '../db.dart';

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

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    await Db.instance.save('apiaries', {
      ...?widget.apiary,
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'vet_number': _vet.text.trim(),
      'notes': _notes.text.trim(),
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
        TextField(controller: _vet, decoration: const InputDecoration(labelText: 'Weterynaryjny numer identyfikacyjny')),
        const SizedBox(height: 12),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Uwagi'), maxLines: 3),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Zapisz')),
      ]),
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

  Widget _counter(String label, int value, ValueChanged<int> onChanged) => Row(children: [
        Expanded(child: Text(label)),
        IconButton(onPressed: value > 0 ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        IconButton(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_circle_outline)),
      ]);

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
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Zapisz')),
      ]),
    );
  }
}
