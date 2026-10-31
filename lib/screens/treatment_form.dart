import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../owner.dart';
import '../widgets.dart';

/// Najczęściej używane preparaty – tylko podpowiedzi nazw; zawsze można wpisać inny.
const treatmentProducts = [
  'Apiwarol', 'Biowar 500', 'Apitraz', 'Api-Bioxal', 'Oxybee',
  'Apiguard', 'Thymovar', 'Polyvar Yellow', 'VarroMed', 'Inny',
];

/// Leczenie ula albo (gdy [hive] jest pusty) całej pasieki – jeden wpis do ewidencji.
/// Pola wymagane przez art. 108 rozporządzenia (UE) 2019/6: data pierwszego podania, nazwa produktu,
/// podana ilość, dostawca, dowód nabycia, leczone zwierzęta, lekarz weterynarii (jeśli dotyczy), okres karencji.
class TreatmentForm extends StatefulWidget {
  const TreatmentForm({super.key, required this.apiaryId, this.hive, this.treatment});
  final String apiaryId;
  final Map<String, dynamic>? hive;
  final Map<String, dynamic>? treatment;

  @override
  State<TreatmentForm> createState() => _TreatmentFormState();
}

class _TreatmentFormState extends State<TreatmentForm> {
  static final _fmt = DateFormat('yyyy-MM-dd');
  late final Map<String, dynamic> _t = Map<String, dynamic>.from(widget.treatment ?? {});
  late DateTime _on = DateTime.tryParse('${_t['treated_on']}') ?? DateTime.now();
  late DateTime? _end = DateTime.tryParse('${_t['ended_on']}');
  late String? _product = treatmentProducts.contains(_t['product']) ? _t['product'] as String : (_t['product'] == null ? null : 'Inny');
  late final _otherProduct = TextEditingController(text: treatmentProducts.contains(_t['product']) ? '' : _t['product'] as String?);
  late final _dose = TextEditingController(text: _t['dose'] as String?);
  late final _batch = TextEditingController(text: _t['batch_number'] as String?);
  late num _withdrawal = num.tryParse('${_t['withdrawal_days']}') ?? 0;
  late final _reason = TextEditingController(text: (_t['reason'] as String?) ?? 'warroza');
  late final _supplier = TextEditingController(text: _t['supplier'] as String?);
  late final _doc = TextEditingController(text: _t['purchase_doc'] as String?);
  late final _vet = TextEditingController(text: _t['vet'] as String?);
  late final _by = TextEditingController(text: _t['performed_by'] as String?);
  late final _notes = TextEditingController(text: _t['notes'] as String?);
  List<Map<String, dynamic>> _hives = [];

  bool get _whole => widget.hive == null && (widget.treatment == null || widget.treatment!['hive_id'] == null);

  @override
  void initState() {
    super.initState();
    () async {
      final hives = await Db.instance.list('hives', where: {'apiary_id': widget.apiaryId});
      final last = await Db.instance.meta('treatment_last');
      final owner = await Owner.load();
      if (!mounted) return;
      setState(() {
        _hives = hives;
        if (widget.treatment == null) {
          final p = (last ?? '').split('|');
          if (p.length == 3) {
            _supplier.text = p[0];
            _vet.text = p[1];
            _by.text = p[2];
          }
          if (_by.text.isEmpty) _by.text = owner['name'] ?? '';
        }
      });
    }();
  }

  String _hivesDesc() {
    if (!_whole) return 'ul ${widget.hive?['number'] ?? _t['hives_desc'] ?? ''}';
    final nums = _hives.map((h) => '${h['number'] ?? ''}').where((n) => n.isNotEmpty).toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return 'wszystkie ule (${_hives.length})${nums.isEmpty ? '' : ': ${nums.join(', ')}'}';
  }

  Future<void> _save() async {
    final product = _product == 'Inny' ? _otherProduct.text.trim() : (_product ?? '');
    if (product.isEmpty || _dose.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Podaj preparat i podaną ilość.')));
      return;
    }
    await Db.instance.save('treatments', {
      ..._t,
      'apiary_id': widget.apiaryId,
      'hive_id': _whole ? null : (widget.hive?['id'] ?? _t['hive_id']),
      'hives_desc': _hivesDesc(),
      'treated_on': _fmt.format(_on),
      'ended_on': _end == null ? null : _fmt.format(_end!),
      'product': product,
      'dose': _dose.text.trim(),
      'batch_number': _batch.text.trim(),
      'withdrawal_days': _withdrawal.toInt(),
      'reason': _reason.text.trim(),
      'supplier': _supplier.text.trim(),
      'purchase_doc': _doc.text.trim(),
      'vet': _vet.text.trim(),
      'performed_by': _by.text.trim(),
      'notes': _notes.text.trim(),
    });
    await Db.instance.setMeta('treatment_last', '${_supplier.text.trim()}|${_vet.text.trim()}|${_by.text.trim()}');
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await Db.instance.remove('treatments', _t['id'] as String);
    if (mounted) Navigator.pop(context, true);
  }

  Future<DateTime?> _pick(DateTime initial) =>
      showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 120)));

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMMM yyyy', 'pl');
    return Scaffold(
      appBar: AppBar(
        title: Text(_whole ? 'Leczenie – cała pasieka' : 'Leczenie – ul ${widget.hive?['number'] ?? ''}'),
        actions: [if (widget.treatment != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event, size: 28),
          title: Text('Pierwsze podanie: ${df.format(_on)}', style: const TextStyle(fontSize: 17)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () async {
            final d = await _pick(_on);
            if (d != null) setState(() => _on = d);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_available, size: 28),
          title: Text(_end == null ? 'Zakończenie: nie ustawiono' : 'Zakończenie: ${df.format(_end!)}', style: const TextStyle(fontSize: 17)),
          trailing: _end == null ? const Icon(Icons.add) : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _end = null)),
          onTap: () async {
            final d = await _pick(_end ?? _on);
            if (d != null) setState(() => _end = d);
          },
        ),
        if (_whole) Text('Dotyczy: ${_hivesDesc()}', style: const TextStyle(fontSize: 16)),
        BigChoice<String>(
          label: 'Preparat',
          options: [for (final p in treatmentProducts) (p, p)],
          value: _product,
          onChanged: (v) => setState(() => _product = v),
        ),
        if (_product == 'Inny') ...[
          const SizedBox(height: 12),
          TextField(controller: _otherProduct, decoration: const InputDecoration(labelText: 'Nazwa preparatu')),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _dose,
          decoration: InputDecoration(
            labelText: 'Podana ilość *',
            hintText: _whole ? 'np. 2 paski na ul, razem 24 paski' : 'np. 2 paski',
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _batch, decoration: const InputDecoration(labelText: 'Numer serii (partii) leku')),
        BigCounter(label: 'Okres karencji', value: _withdrawal, unit: ' dni', onChanged: (v) => setState(() => _withdrawal = v)),
        const SizedBox(height: 16),
        TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Powód leczenia')),
        const SizedBox(height: 12),
        TextField(controller: _supplier, decoration: const InputDecoration(labelText: 'Dostawca leku – nazwa i adres')),
        const SizedBox(height: 12),
        TextField(controller: _doc, decoration: const InputDecoration(labelText: 'Dowód nabycia (nr faktury / paragonu)')),
        const SizedBox(height: 12),
        TextField(controller: _vet, decoration: const InputDecoration(labelText: 'Lekarz weterynarii (jeśli przepisał) – imię, nazwisko, kontakt')),
        const SizedBox(height: 12),
        TextField(controller: _by, decoration: const InputDecoration(labelText: 'Podał(a)')),
        const SizedBox(height: 12),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Uwagi'), maxLines: 2),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz leczenie', onPressed: _save),
    );
  }
}
