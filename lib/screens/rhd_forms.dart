import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../feeding.dart' show fmtAmount;
import '../owner.dart';
import '../rhd.dart';
import '../settings.dart';
import '../widgets.dart';

final _dayFmt = DateFormat('yyyy-MM-dd');
final _dtFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

Widget _dateTile(BuildContext context, DateTime value, {bool withTime = false, required ValueChanged<DateTime> onChanged}) =>
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event, size: 28),
      title: Text(DateFormat(withTime ? 'EEEE, d MMMM yyyy, HH:mm' : 'EEEE, d MMMM yyyy', 'pl').format(value),
          style: const TextStyle(fontSize: 17)),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2000), lastDate: DateTime.now());
        if (d == null || !context.mounted) return;
        var t = TimeOfDay.fromDateTime(value);
        if (withTime) t = await showTimePicker(context: context, initialTime: t) ?? t;
        onChanged(DateTime(d.year, d.month, d.day, t.hour, t.minute));
      },
    );

/* ------------------------------ Mycie i dezynfekcja ------------------------------ */

class HygieneForm extends StatefulWidget {
  const HygieneForm({super.key, this.entry});
  final Map<String, dynamic>? entry;

  @override
  State<HygieneForm> createState() => _HygieneFormState();
}

class _HygieneFormState extends State<HygieneForm> {
  late final Map<String, dynamic> _e = Map<String, dynamic>.from(widget.entry ?? {});
  late DateTime _at = DateTime.tryParse('${_e['done_at']}') ?? DateTime.now();
  late String? _kind = (_e['kind'] as String?) ?? 'Mycie i dezynfekcja';
  late final Set<String> _areas = {...'${_e['area'] ?? ''}'.split(', ').where((a) => a.isNotEmpty)};
  late final _other = TextEditingController();
  late final _agent = TextEditingController(text: _e['agent'] as String?);
  late final _conc = TextEditingController(text: _e['concentration'] as String?);
  late final _by = TextEditingController(text: _e['performed_by'] as String?);
  late final _notes = TextEditingController(text: _e['notes'] as String?);

  @override
  void initState() {
    super.initState();
    if (widget.entry == null) {
      // Podpowiedzi z poprzedniego wpisu: środek, stężenie, wykonujący.
      Db.instance.meta('hygiene_last').then((v) async {
        final parts = (v ?? '').split('|');
        final owner = await Owner.load();
        if (!mounted) return;
        setState(() {
          if (parts.length == 3) {
            _agent.text = parts[0];
            _conc.text = parts[1];
            _by.text = parts[2];
          }
          if (_by.text.isEmpty) _by.text = owner['name'] ?? '';
        });
      });
    }
    final custom = _areas.where((a) => !hygieneAreas.contains(a)).toList();
    _other.text = custom.join(', ');
    _areas.removeAll(custom);
  }

  Future<void> _save() async {
    final areas = [..._areas, ..._other.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)];
    if (areas.isEmpty && _kind != 'Badanie wody') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zaznacz, co było myte lub dezynfekowane.')));
      return;
    }
    await Db.instance.save('hygiene', {
      ..._e,
      'done_at': _dtFmt.format(_at),
      'kind': _kind,
      'area': areas.join(', '),
      'agent': _agent.text.trim(),
      'concentration': _conc.text.trim(),
      'performed_by': _by.text.trim(),
      'notes': _notes.text.trim(),
    });
    await Db.instance.setMeta('hygiene_last', '${_agent.text.trim()}|${_conc.text.trim()}|${_by.text.trim()}');
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await Db.instance.remove('hygiene', _e['id'] as String);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final water = _kind == 'Badanie wody';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mycie i dezynfekcja'),
        actions: [if (widget.entry != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        _dateTile(context, _at, withTime: true, onChanged: (d) => setState(() => _at = d)),
        BigChoice<String>(
          label: 'Czynność',
          options: [for (final k in hygieneKinds) (k, k)],
          value: _kind,
          onChanged: (v) => setState(() => _kind = v ?? _kind),
        ),
        if (!water) ...[
          const SizedBox(height: 18),
          const Text('Co', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          BigGrid(children: [
            for (final a in hygieneAreas)
              BigToggle(
                label: a,
                icon: Icons.check_box_outline_blank,
                value: _areas.contains(a),
                onChanged: (v) => setState(() => v ? _areas.add(a) : _areas.remove(a)),
              ),
          ]),
          TextField(controller: _other, decoration: const InputDecoration(labelText: 'Inne (po przecinku)')),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _agent,
          decoration: InputDecoration(labelText: water ? 'Laboratorium' : 'Środek (np. płyn do mycia, preparat dezynfekujący)'),
        ),
        if (!water) ...[
          const SizedBox(height: 12),
          TextField(controller: _conc, decoration: const InputDecoration(labelText: 'Stężenie / dawkowanie')),
        ],
        const SizedBox(height: 12),
        TextField(controller: _by, decoration: const InputDecoration(labelText: 'Wykonał(a)')),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          decoration: InputDecoration(labelText: water ? 'Wynik badania i nr sprawozdania' : 'Uwagi'),
          maxLines: 2,
        ),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz', onPressed: _save),
    );
  }
}

/* ------------------------------ Miodobranie (produkcja) ------------------------------ */

class HarvestForm extends StatefulWidget {
  const HarvestForm({super.key, this.entry});
  final Map<String, dynamic>? entry;

  @override
  State<HarvestForm> createState() => _HarvestFormState();
}

class _HarvestFormState extends State<HarvestForm> {
  late final Map<String, dynamic> _e = Map<String, dynamic>.from(widget.entry ?? {});
  late DateTime _on = DateTime.tryParse('${_e['harvested_on']}') ?? DateTime.now();
  late String? _product = (_e['product'] as String?) ?? honeyKinds.first;
  late num _qty = num.tryParse('${_e['quantity']}') ?? 0;
  late String? _apiaryId = _e['apiary_id'] as String?;
  late final _lot = TextEditingController(text: _e['lot'] as String?);
  late final _notes = TextEditingController(text: _e['notes'] as String?);
  List<Map<String, dynamic>> _apiaries = [];
  List<Map<String, dynamic>> _harvests = [];
  bool _lotTouched = false;

  @override
  void initState() {
    super.initState();
    _lotTouched = widget.entry != null;
    () async {
      final a = await Db.instance.list('apiaries', orderKey: 'name');
      final h = await Db.instance.list('harvests');
      if (!mounted) return;
      setState(() {
        _apiaries = a;
        _harvests = h;
        _apiaryId ??= a.isEmpty ? null : a.first['id'] as String;
        _suggest();
      });
    }();
  }

  void _suggest() {
    if (!_lotTouched) _lot.text = suggestLot(_on, _product ?? 'Miód', _harvests.where((h) => h['id'] != _e['id']).toList());
  }

  Future<void> _save() async {
    if (_qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Podaj ilość miodu.')));
      return;
    }
    await Db.instance.save('harvests', {
      ..._e,
      'apiary_id': _apiaryId,
      'harvested_on': _dayFmt.format(_on),
      'product': _product,
      'quantity': _qty,
      'unit': 'kg',
      'lot': _lot.text.trim(),
      'notes': _notes.text.trim(),
    });
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await Db.instance.remove('harvests', _e['id'] as String);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Miodobranie'),
        actions: [if (widget.entry != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        _dateTile(context, _on, onChanged: (d) => setState(() {
              _on = d;
              _suggest();
            })),
        if (_apiaries.length > 1)
          DropdownButtonFormField<String>(
            value: _apiaryId,
            decoration: const InputDecoration(labelText: 'Pasieka'),
            items: [for (final a in _apiaries) DropdownMenuItem(value: a['id'] as String, child: Text('${a['name']}'))],
            onChanged: (v) => setState(() => _apiaryId = v),
          ),
        BigChoice<String>(
          label: 'Rodzaj miodu',
          options: [for (final k in honeyKinds) (k, k)],
          value: _product,
          onChanged: (v) => setState(() {
            _product = v ?? _product;
            _suggest();
          }),
        ),
        BigCounter(label: 'Ilość', value: _qty, step: 1, unit: ' kg', onChanged: (v) => setState(() => _qty = v)),
        BigChoice<num>(
          label: 'Szybko ustaw',
          options: const [(10, '10'), (20, '20'), (30, '30'), (50, '50'), (100, '100')],
          value: _qty,
          onChanged: (v) => setState(() => _qty = v ?? _qty),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _lot,
          decoration: const InputDecoration(labelText: 'Numer partii', helperText: 'Trafia na etykietę i do ewidencji sprzedaży'),
          onChanged: (_) => _lotTouched = true,
        ),
        const SizedBox(height: 12),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Uwagi'), maxLines: 2),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz miodobranie', onPressed: _save),
    );
  }
}

/* ------------------------------ Sprzedaż ------------------------------ */

class SaleForm extends StatefulWidget {
  const SaleForm({super.key, this.entry});
  final Map<String, dynamic>? entry;

  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  late final Map<String, dynamic> _e = Map<String, dynamic>.from(widget.entry ?? {});
  late DateTime _on = DateTime.tryParse('${_e['sold_on']}') ?? DateTime.now();
  late String _buyer = (_e['buyer_type'] as String?) ?? 'consumer';
  late num _qty = num.tryParse('${_e['quantity']}') ?? 0;
  late String? _lot = _e['lot'] as String?;
  late String? _product = _e['product'] as String?;
  late final _name = TextEditingController(text: _e['buyer_name'] as String?);
  late final _address = TextEditingController(text: _e['buyer_address'] as String?);
  late final _amount = TextEditingController(text: _e['amount'] == null ? '' : '${_e['amount']}');
  late final _place = TextEditingController(text: _e['place'] as String?);
  List<Map<String, dynamic>> _harvests = [];
  List<Map<String, dynamic>> _sales = [];

  @override
  void initState() {
    super.initState();
    () async {
      final h = await Db.instance.list('harvests', orderKey: 'harvested_on');
      final s = await Db.instance.list('sales');
      final place = await Db.instance.meta('sale_place');
      if (!mounted) return;
      setState(() {
        _harvests = h.reversed.toList();
        _sales = s;
        if (widget.entry == null) {
          _place.text = place ?? '';
          if (_harvests.isNotEmpty) {
            _lot = '${_harvests.first['lot']}';
            _product = '${_harvests.first['product']}';
          }
        }
      });
    }();
  }

  Future<void> _save() async {
    if (_qty <= 0 || (_product ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wybierz miód i podaj ilość.')));
      return;
    }
    final business = _buyer == 'business';
    if (business && (_name.text.trim().isEmpty || _address.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Przy sprzedaży do sklepu lub restauracji podaj nazwę i adres odbiorcy.')));
      return;
    }
    if (business && Settings.sales == SalesMode.rhd) {
      final others = _sales.where((s) => s['id'] != _e['id']).toList();
      final used = salesTotals(others, _on.year).business;
      if (used + _qty > rhdBusinessLimitKg) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Przekroczony limit RHD'),
            content: Text('Do firm sprzedano w ${_on.year} r. już ${fmtAmount(used)} kg. Ta sprzedaż przekroczy limit '
                '${fmtAmount(rhdBusinessLimitKg)} kg miodu rocznie dla sklepów i restauracji.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Popraw')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Zapisz mimo to')),
            ],
          ),
        );
        if (ok != true) return;
      }
    }
    await Db.instance.save('sales', {
      ..._e,
      'sold_on': _dayFmt.format(_on),
      'product': _product,
      'lot': _lot,
      'quantity': _qty,
      'unit': 'kg',
      'buyer_type': _buyer,
      'buyer_name': business ? _name.text.trim() : '',
      'buyer_address': business ? _address.text.trim() : '',
      'amount': double.tryParse(_amount.text.replaceAll(',', '.')),
      'place': _place.text.trim(),
    });
    await Db.instance.setMeta('sale_place', _place.text.trim());
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await Db.instance.remove('sales', _e['id'] as String);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final business = _buyer == 'business';
    final lots = <String, String>{for (final h in _harvests) '${h['lot']}': '${h['product']}'};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sprzedaż'),
        actions: [if (widget.entry != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        _dateTile(context, _on, onChanged: (d) => setState(() => _on = d)),
        BigChoice<String>(
          label: 'Odbiorca',
          options: const [('consumer', 'Konsument'), ('business', 'Sklep / restauracja')],
          value: _buyer,
          onChanged: (v) => setState(() => _buyer = v ?? _buyer),
        ),
        if (business) ...[
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nazwa odbiorcy *')),
          const SizedBox(height: 12),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'Adres odbiorcy *')),
        ],
        if (lots.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Text('Dodaj najpierw miodobranie – sprzedaż przypisuje się do partii miodu.'),
          )
        else
          BigChoice<String>(
            label: 'Miód (partia)',
            options: [for (final e in lots.entries) (e.key, '${e.value} · ${e.key}')],
            value: _lot,
            onChanged: (v) => setState(() {
              _lot = v ?? _lot;
              _product = lots[_lot];
            }),
          ),
        BigCounter(label: 'Ilość', value: _qty, step: 0.5, unit: ' kg', onChanged: (v) => setState(() => _qty = v)),
        BigChoice<num>(
          label: 'Szybko ustaw',
          options: const [(0.4, '0,4'), (0.9, '0,9'), (1.2, '1,2'), (5, '5'), (10, '10')],
          value: _qty,
          onChanged: (v) => setState(() => _qty = v ?? _qty),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _amount,
          decoration: const InputDecoration(labelText: 'Kwota (zł, opcjonalnie)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        TextField(controller: _place, decoration: const InputDecoration(labelText: 'Miejsce sprzedaży')),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz sprzedaż', onPressed: _save),
    );
  }
}
