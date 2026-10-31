import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';

/// Szybki przegląd: duże przełączniki zamiast pisania, da się wypełnić jedną ręką.
class InspectionForm extends StatefulWidget {
  const InspectionForm({super.key, required this.hive, this.inspection});
  final Map<String, dynamic> hive;
  final Map<String, dynamic>? inspection;

  @override
  State<InspectionForm> createState() => _InspectionFormState();
}

class _InspectionFormState extends State<InspectionForm> {
  static final _dbFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  late final Map<String, dynamic> _i = Map<String, dynamic>.from(widget.inspection ?? {});
  late DateTime _at = DateTime.tryParse('${_i['inspected_at']}') ?? DateTime.now();
  late final _notes = TextEditingController(text: _i['notes'] as String?);

  bool _flag(String k) => _i[k] == true || _i[k] == 1 || _i[k] == '1';
  int? _num(String k) => int.tryParse('${_i[k]}');

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime(2000), lastDate: DateTime.now());
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    setState(() => _at = DateTime(d.year, d.month, d.day, t?.hour ?? _at.hour, t?.minute ?? _at.minute));
  }

  Future<void> _save() async {
    await Db.instance.save('inspections', {
      ..._i,
      'hive_id': widget.hive['id'],
      'inspected_at': _dbFmt.format(_at),
      // Serwer zapisuje pola tak/nie jako liczby – wysyłamy 1/0, nie true/false.
      for (final k in ['eggs', 'open_brood', 'capped_brood', 'queen_seen']) k: _flag(k) ? 1 : 0,
      'queen_cells': _num('queen_cells') ?? 0,
      'notes': _notes.text.trim(),
    });
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await Db.instance.remove('inspections', _i['id'] as String);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _toggle(String key, String label, IconData icon) => FilterChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: _flag(key),
        onSelected: (v) => setState(() => _i[key] = v ? 1 : 0),
      );

  Widget _scale(String key, String label, List<String> hints) {
    final v = _num(key);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          segments: [for (var n = 1; n <= 5; n++) ButtonSegment(value: n, label: Text('$n'))],
          selected: v == null ? <int>{} : {v},
          onSelectionChanged: (s) => setState(() => _i[key] = s.isEmpty ? null : s.first),
        ),
        Text('${hints.first} … ${hints.last}', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cells = _num('queen_cells') ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text('Przegląd – ul ${widget.hive['number'] ?? ''}'),
        actions: [
          if (widget.inspection != null) IconButton(tooltip: 'Usuń', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text(DateFormat('EEEE, d MMMM yyyy, HH:mm', 'pl').format(_at)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: _pickDate,
        ),
        const SizedBox(height: 8),
        Text('Matka i czerw', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _toggle('queen_seen', 'Matka widziana', Icons.visibility_outlined),
          _toggle('eggs', 'Jajka', Icons.egg_outlined),
          _toggle('open_brood', 'Czerw otwarty', Icons.grid_view),
          _toggle('capped_brood', 'Czerw kryty', Icons.grid_on),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Mateczniki')),
          IconButton(
            onPressed: cells > 0 ? () => setState(() => _i['queen_cells'] = cells - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$cells', style: Theme.of(context).textTheme.titleMedium),
          IconButton(onPressed: () => setState(() => _i['queen_cells'] = cells + 1), icon: const Icon(Icons.add_circle_outline)),
        ]),
        _scale('strength', 'Siła rodziny', ['bardzo słaba', 'bardzo silna']),
        _scale('stores', 'Zapasy pokarmu', ['brak', 'bardzo duże']),
        _scale('temper', 'Łagodność', ['bardzo agresywne', 'bardzo łagodne']),
        const SizedBox(height: 16),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notatka'), maxLines: 4),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Zapisz przegląd'))),
      ]),
    );
  }
}
