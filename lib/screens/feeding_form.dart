import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../feeding.dart';
import '../widgets.dart';

/// Podkarmianie jednego ula albo (gdy [hive] jest pusty) wszystkich uli w pasiece –
/// wtedy każdy ul dostaje własny wpis z podaną ilością.
class FeedingForm extends StatefulWidget {
  const FeedingForm({super.key, required this.apiaryId, this.hive, this.feeding});
  final String apiaryId;
  final Map<String, dynamic>? hive;
  final Map<String, dynamic>? feeding;

  @override
  State<FeedingForm> createState() => _FeedingFormState();
}

class _FeedingFormState extends State<FeedingForm> {
  static final _dbFmt = DateFormat('yyyy-MM-dd');
  late final Map<String, dynamic> _f = Map<String, dynamic>.from(widget.feeding ?? {});
  late DateTime _on = DateTime.tryParse('${_f['fed_on']}') ?? DateTime.now();
  late String? _type = _f['feed_type'] as String? ?? feedTypes.first;
  late String _unit = (_f['unit'] as String?) ?? 'kg';
  late num _amount = num.tryParse('${_f['amount']}') ?? 0;
  late final _notes = TextEditingController(text: _f['notes'] as String?);
  List<Map<String, dynamic>> _hives = [];

  @override
  void initState() {
    super.initState();
    if (widget.hive == null) {
      Db.instance.list('hives', where: {'apiary_id': widget.apiaryId}).then((h) {
        if (mounted) setState(() => _hives = h);
      });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _on, firstDate: DateTime(2000), lastDate: DateTime.now());
    if (d != null) setState(() => _on = d);
  }

  Future<void> _save() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Podaj ilość pokarmu.')));
      return;
    }
    final base = {
      'apiary_id': widget.apiaryId,
      'fed_on': _dbFmt.format(_on),
      'feed_type': _type,
      'amount': _amount,
      'unit': _unit,
      'notes': _notes.text.trim(),
    };
    if (widget.hive != null || widget.feeding != null) {
      await Db.instance.save('feedings', {..._f, ...base, 'hive_id': widget.hive?['id'] ?? _f['hive_id']});
    } else {
      for (final h in _hives) {
        await Db.instance.save('feedings', {...base, 'hive_id': h['id']});
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await Db.instance.remove('feedings', _f['id'] as String);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.hive == null && widget.feeding == null;
    final title = all ? 'Podkarmianie – cała pasieka' : 'Podkarmianie – ul ${widget.hive?['number'] ?? ''}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.feeding != null) IconButton(tooltip: 'Usuń', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event, size: 28),
          title: Text(DateFormat('EEEE, d MMMM yyyy', 'pl').format(_on), style: const TextStyle(fontSize: 17)),
          subtitle: Text(seasonOf(_on)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: _pickDate,
        ),
        BigChoice<String>(
          label: 'Pokarm',
          options: [for (final t in feedTypes) (t, t)],
          value: _type,
          onChanged: (v) => setState(() => _type = v),
        ),
        BigCounter(
          label: all ? 'Ilość na każdy ul' : 'Ilość',
          value: _amount,
          step: 0.5,
          unit: ' $_unit',
          onChanged: (v) => setState(() => _amount = v),
        ),
        BigChoice<num>(
          label: 'Szybko ustaw',
          options: const [(1, '1'), (2, '2'), (3, '3'), (5, '5'), (10, '10')],
          value: _amount,
          onChanged: (v) => setState(() => _amount = v ?? _amount),
        ),
        BigChoice<String>(
          label: 'Jednostka',
          options: const [('kg', 'kg'), ('l', 'litry')],
          value: _unit,
          onChanged: (v) => setState(() => _unit = v ?? _unit),
        ),
        if (all) ...[
          const SizedBox(height: 18),
          Text(
            _hives.isEmpty
                ? 'Ta pasieka nie ma jeszcze uli.'
                : 'Wpis trafi do ${_hives.length} uli – razem ${fmtAmount(_amount * _hives.length)} $_unit.',
            style: const TextStyle(fontSize: 16),
          ),
        ],
        const SizedBox(height: 18),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notatka'), maxLines: 2, style: const TextStyle(fontSize: 17)),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz podkarmianie', onPressed: _save),
    );
  }
}
