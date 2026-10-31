import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../widgets.dart';

/// Szybki przegląd: duże kafelki i przyciski, da się wypełnić w rękawicach jedną ręką.
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

  Widget _toggle(String key, String label, IconData icon) =>
      BigToggle(label: label, icon: icon, value: _flag(key), onChanged: (v) => setState(() => _i[key] = v ? 1 : 0));

  Widget _scale(String key, String label, String hint) => BigChoice<int>(
        label: label,
        hint: hint,
        options: [for (var n = 1; n <= 5; n++) (n, '$n')],
        value: _num(key),
        onChanged: (v) => setState(() => _i[key] = v),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Przegląd – ul ${widget.hive['number'] ?? ''}'),
        actions: [
          if (widget.inspection != null) IconButton(tooltip: 'Usuń', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event, size: 28),
          title: Text(DateFormat('EEEE, d MMMM, HH:mm', 'pl').format(_at), style: const TextStyle(fontSize: 17)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: _pickDate,
        ),
        const SizedBox(height: 8),
        BigGrid(children: [
          _toggle('queen_seen', 'Matka widziana', Icons.visibility_outlined),
          _toggle('eggs', 'Jajka', Icons.egg_outlined),
          _toggle('open_brood', 'Czerw otwarty', Icons.grid_view),
          _toggle('capped_brood', 'Czerw kryty', Icons.grid_on),
        ]),
        BigCounter(label: 'Mateczniki', value: _num('queen_cells') ?? 0, onChanged: (v) => setState(() => _i['queen_cells'] = v.toInt())),
        _scale('strength', 'Siła rodziny', '1 – bardzo słaba, 5 – bardzo silna'),
        _scale('stores', 'Zapasy pokarmu', '1 – brak, 5 – bardzo duże'),
        _scale('temper', 'Łagodność', '1 – bardzo agresywne, 5 – bardzo łagodne'),
        const SizedBox(height: 18),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notatka'), maxLines: 3, style: const TextStyle(fontSize: 17)),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz przegląd', onPressed: _save),
    );
  }
}
