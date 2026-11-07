import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../tasks.dart';
import '../widgets.dart';

const queenStates = ['Unasienniona', 'Nieunasienniona', 'Mateczniki', 'Trutówka', 'Brak matki'];
const queenBreeds = ['Krainka (A. m. carnica)', 'Kaukazka (A. m. caucasica)', 'Buckfast', 'Środkowoeuropejska (A. m. mellifera)', 'Włoszka (A. m. ligustica)', 'Inna'];
const queenSources = ['Kupiona', 'Własny chów', 'Cicha wymiana', 'Rój', 'Odkład', 'Inne'];

/// Kółko w kolorze rocznika matki.
class QueenDot extends StatelessWidget {
  const QueenDot({super.key, required this.year, this.size = 44, this.label});
  final int? year;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = queenColor(year);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.color, shape: BoxShape.circle, border: Border.all(color: Colors.black26)),
      child: label == null ? null : Text(label!, style: TextStyle(fontWeight: FontWeight.bold, color: c.color.computeLuminance() > 0.5 ? Colors.black : Colors.white)),
    );
  }
}

/// Matki ula: obecna i historia.
class QueensScreen extends StatefulWidget {
  const QueensScreen({super.key, required this.hive});
  final Map<String, dynamic> hive;

  @override
  State<QueensScreen> createState() => _QueensScreenState();
}

class _QueensScreenState extends State<QueensScreen> {
  List<Map<String, dynamic>> _queens = [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = await Db.instance.list('queens', where: {'hive_id': '${widget.hive['id']}'}, orderKey: 'introduced_on');
    if (mounted) setState(() => _queens = q.reversed.toList());
  }

  Future<void> _open([Map<String, dynamic>? q]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => QueenForm(hive: widget.hive, queen: q)));
    if (saved == true) _changed = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final current = _queens.where((q) => '${q['removed_on'] ?? ''}'.isEmpty).toList();
    final past = _queens.where((q) => '${q['removed_on'] ?? ''}'.isNotEmpty).toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Matki – ul ${widget.hive['number'] ?? ''}')),
        body: ListView(children: [
          if (_queens.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Brak zapisanych matek. Dodaj obecną matkę.')),
          for (final q in current) _tile(q),
          if (past.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Historia', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final q in past) _tile(q),
        ]),
        bottomNavigationBar: BigSaveBar(label: current.isEmpty ? 'Dodaj matkę' : 'Nowa matka (wymiana)', onPressed: () => _open()),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> q) {
    final year = int.tryParse('${q['year']}');
    final flags = [
      if (q['to_replace'] == 1 || q['to_replace'] == true) 'do wymiany',
      if (q['to_check'] == 1 || q['to_check'] == true) 'sprawdzić',
      if ('${q['removed_on'] ?? ''}'.isNotEmpty) 'usunięta ${q['removed_on']}',
    ];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: QueenDot(year: year, label: '${q['number'] ?? ''}'),
      title: Text('Matka ${q['number'] ?? ''}${year == null ? '' : ' · $year'}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      subtitle: Text([
        'Stan: ${q['status'] ?? '–'}',
        if ('${q['breed'] ?? ''}'.isNotEmpty) 'Rasa: ${q['breed']}${'${q['line'] ?? ''}'.isEmpty ? '' : ', linia ${q['line']}'}',
        if (flags.isNotEmpty) flags.join(' · '),
      ].join('\n')),
      isThreeLine: true,
      onTap: () => _open(q),
    );
  }
}

class QueenForm extends StatefulWidget {
  const QueenForm({super.key, required this.hive, this.queen});
  final Map<String, dynamic> hive;
  final Map<String, dynamic>? queen;

  @override
  State<QueenForm> createState() => _QueenFormState();
}

class _QueenFormState extends State<QueenForm> {
  late final Map<String, dynamic> _q = Map<String, dynamic>.from(widget.queen ?? {});
  late int _year = int.tryParse('${_q['year']}') ?? DateTime.now().year;
  late String? _status = (_q['status'] as String?) ?? 'Unasienniona';
  late String? _breed = queenBreeds.contains(_q['breed']) ? _q['breed'] as String : (_q['breed'] == null ? null : 'Inna');
  late final _otherBreed = TextEditingController(text: queenBreeds.contains(_q['breed']) ? '' : _q['breed'] as String?);
  late String? _origin = (_q['origin'] as String?) ?? 'Kupiona';
  late DateTime _introduced = DateTime.tryParse('${_q['introduced_on']}') ?? DateTime.now();
  late final _number = TextEditingController(text: '${_q['number'] ?? ''}');
  late final _line = TextEditingController(text: _q['line'] as String?);
  late final _mark = TextEditingController(text: _q['mark'] as String?);
  late final _notes = TextEditingController(text: _q['notes'] as String?);
  late bool _toReplace = _q['to_replace'] == 1 || _q['to_replace'] == true;
  late bool _toCheck = _q['to_check'] == 1 || _q['to_check'] == true;

  @override
  void initState() {
    super.initState();
    if (widget.queen == null) {
      Db.instance.list('queens', where: {'hive_id': '${widget.hive['id']}'}).then((l) {
        if (mounted && _number.text.isEmpty) setState(() => _number.text = '${l.length + 1}');
      });
    }
  }

  Future<void> _save() async {
    final breed = _breed == 'Inna' ? _otherBreed.text.trim() : _breed;
    final isNew = widget.queen == null;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // Nowa matka zastępuje dotychczasową – stara trafia do historii.
    if (isNew) {
      for (final old in await Db.instance.list('queens', where: {'hive_id': '${widget.hive['id']}'})) {
        if ('${old['removed_on'] ?? ''}'.isEmpty) {
          final closed = await Db.instance.save('queens', {...old, 'removed_on': today, 'to_replace': 0, 'to_check': 0});
          await AutoTasks.fromQueen(closed, widget.hive);
        }
      }
    }
    final saved = await Db.instance.save('queens', {
      ..._q,
      'hive_id': widget.hive['id'],
      'number': _number.text.trim(),
      'year': _year,
      'color': queenColor(_year).name,
      'status': _status,
      'breed': breed,
      'line': _line.text.trim(),
      'mark': _mark.text.trim(),
      'origin': _origin,
      'introduced_on': DateFormat('yyyy-MM-dd').format(_introduced),
      'to_replace': _toReplace ? 1 : 0,
      'to_check': _toCheck ? 1 : 0,
      'notes': _notes.text.trim(),
    });
    await AutoTasks.fromQueen(saved, widget.hive);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    final saved = await Db.instance.save('queens', {..._q, 'removed_on': DateFormat('yyyy-MM-dd').format(DateTime.now()), 'to_replace': 0, 'to_check': 0});
    await AutoTasks.fromQueen(saved, widget.hive);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    final c = queenColor(_year);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.queen == null ? 'Nowa matka' : 'Matka ${_q['number'] ?? ''}'),
        actions: [
          if (widget.queen != null && '${_q['removed_on'] ?? ''}'.isEmpty)
            TextButton(onPressed: _remove, child: const Text('Usuń z ula')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Row(children: [
          QueenDot(year: _year, size: 56),
          const SizedBox(width: 12),
          Expanded(child: Text('Kolor znakowania: ${c.name}', style: const TextStyle(fontSize: 17))),
        ]),
        BigChoice<int>(
          label: 'Rok matki',
          options: [for (var y = now; y >= now - 5; y--) (y, '$y')],
          value: _year,
          onChanged: (v) => setState(() => _year = v ?? _year),
        ),
        BigChoice<String>(label: 'Stan', options: [for (final s in queenStates) (s, s)], value: _status, onChanged: (v) => setState(() => _status = v)),
        BigChoice<String>(label: 'Rasa', options: [for (final s in queenBreeds) (s, s.split(' (').first)], value: _breed, onChanged: (v) => setState(() => _breed = v)),
        if (_breed == 'Inna') ...[const SizedBox(height: 12), TextField(controller: _otherBreed, decoration: const InputDecoration(labelText: 'Rasa'))],
        BigChoice<String>(label: 'Źródło', options: [for (final s in queenSources) (s, s)], value: _origin, onChanged: (v) => setState(() => _origin = v)),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event, size: 28),
          title: Text('Data poddania: ${DateFormat('d MMMM yyyy', 'pl').format(_introduced)}', style: const TextStyle(fontSize: 17)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _introduced, firstDate: DateTime(2010), lastDate: DateTime.now());
            if (d != null) setState(() => _introduced = d);
          },
        ),
        Row(children: [
          SizedBox(width: 110, child: TextField(controller: _number, decoration: const InputDecoration(labelText: 'Numer'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _mark, decoration: const InputDecoration(labelText: 'Oznaczenie (opalitek)'))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _line, decoration: const InputDecoration(labelText: 'Linia')),
        const SizedBox(height: 16),
        BigGrid(children: [
          BigToggle(label: 'Do wymiany', icon: Icons.swap_horiz, value: _toReplace, onChanged: (v) => setState(() => _toReplace = v)),
          BigToggle(label: 'Sprawdzić', icon: Icons.search, value: _toCheck, onChanged: (v) => setState(() => _toCheck = v)),
        ]),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notatki'), maxLines: 2),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz', onPressed: _save),
    );
  }
}
