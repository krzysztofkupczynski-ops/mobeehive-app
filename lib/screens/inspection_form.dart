import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../db.dart';
import '../photos.dart';
import '../tasks.dart';
import '../widgets.dart';
import 'feeding_form.dart';
import 'queens.dart';
import 'treatment_form.dart';

bool _on(dynamic v) => v == true || v == 1 || v == '1';

/// Przegląd ula jako centrum: data i duże kafelki modułów. Wypełnia się tylko to, co było robione.
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
  late final Set<String> _done = {...'${_i['modules'] ?? ''}'.split(',').where((e) => e.isNotEmpty)};
  late Map<String, dynamic> _hive = Map<String, dynamic>.from(widget.hive);
  List<Map<String, dynamic>> _frames = [];
  List<String> _photos = [];
  Map<String, dynamic>? _queen;

  @override
  void initState() {
    super.initState();
    _frames = _decodeList(_i['frames']);
    _photos = Photos.ids(_i['photos']);
    () async {
      // Ramki: nowy przegląd zaczyna od układu z poprzedniego przeglądu.
      if (widget.inspection == null) {
        final prev = await Db.instance.list('inspections', where: {'hive_id': '${widget.hive['id']}'}, orderKey: 'inspected_at');
        final withFrames = prev.where((p) => _decodeList(p['frames']).isNotEmpty).toList();
        if (withFrames.isNotEmpty && mounted) setState(() => _frames = _decodeList(withFrames.last['frames']));
      }
      await _loadQueen();
    }();
  }

  Future<void> _loadQueen() async {
    final qs = await Db.instance.list('queens', where: {'hive_id': '${widget.hive['id']}'});
    final current = qs.where((q) => '${q['removed_on'] ?? ''}'.isEmpty).toList();
    if (mounted) setState(() => _queen = current.isEmpty ? null : current.last);
  }

  static List<Map<String, dynamic>> _decodeList(dynamic v) {
    if (v == null || '$v'.isEmpty) return [];
    try {
      return [for (final e in (v is String ? jsonDecode(v) : v) as List) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime(2000), lastDate: DateTime.now());
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    setState(() => _at = DateTime(d.year, d.month, d.day, t?.hour ?? _at.hour, t?.minute ?? _at.minute));
  }

  Future<void> _module(String key, Future<bool?> Function() open) async {
    final r = await open();
    if (r == true && mounted) setState(() => _done.add(key));
  }

  Future<bool?> _push(Widget page) => Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page));

  Future<void> _finish() async {
    final saved = await Db.instance.save('inspections', {
      ..._i,
      'hive_id': widget.hive['id'],
      'inspected_at': _dbFmt.format(_at),
      for (final k in ['eggs', 'open_brood', 'capped_brood', 'queen_seen', 'swarm_mood', 'no_stores', 'no_brood']) k: _on(_i[k]) ? 1 : 0,
      'queen_cells': int.tryParse('${_i['queen_cells']}') ?? 0,
      'frames': _frames.isEmpty ? null : jsonEncode(_frames),
      'equipment': _done.contains('equipment') ? _hive['equipment'] : _i['equipment'],
      'photos': _photos.isEmpty ? null : jsonEncode(_photos),
      'queen_id': _queen?['id'],
      'modules': _done.join(','),
    });
    await AutoTasks.fromInspection(saved, widget.hive);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await Db.instance.remove('inspections', _i['id'] as String);
    if (mounted) Navigator.pop(context, true);
  }

  String _familySummary() {
    final p = <String>[
      if (_i['strength'] != null) 'siła ${_i['strength']}',
      if (_on(_i['swarm_mood'])) 'nastrój rojowy',
      if (_on(_i['no_brood'])) 'brak czerwiu',
      if (_on(_i['no_stores'])) 'brak pokarmu',
      if (_on(_i['queen_seen'])) 'matka widziana',
      if ('${_i['disease'] ?? ''}'.isNotEmpty && _i['disease'] != 'Brak') '${_i['disease']}'.toLowerCase(),
    ];
    return p.join(' · ');
  }

  String _framesSummary() {
    if (_frames.isEmpty) return '';
    final brood = _frames.where((f) => (f['brood'] ?? 0) > 0).length;
    final honey = _frames.where((f) => (f['honey'] ?? 0) >= 50).length;
    return '${_frames.length} ramek · czerw na $brood${honey > 0 ? ' · miód na $honey' : ''}';
  }

  Widget _tile(String key, String label, IconData icon, Color color, String summary, VoidCallback onTap) {
    final done = _done.contains(key);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: done ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircleAvatar(radius: 30, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 30)),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              if (summary.isNotEmpty)
                Text(summary, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (done) Positioned(right: 10, top: 10, child: Icon(Icons.check_circle, color: scheme.primary, size: 26)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.hive;
    final apiaryId = '${h['apiary_id']}';
    final eq = _decodeMap(_hive['equipment']);
    final tiles = [
      _tile('family', 'Rodzina', Icons.groups_2_outlined, Colors.amber.shade700, _familySummary(), () => _module('family', () async {
            final r = await _push(FamilyModule(data: _i));
            if (r == true) setState(() {});
            return r;
          })),
      _tile('queen', 'Matka', Icons.workspace_premium_outlined, Colors.purple, _queen == null ? 'brak wpisu' : 'nr ${_queen!['number'] ?? ''} · ${_queen!['year'] ?? ''} · ${_queen!['status'] ?? ''}',
          () => _module('queen', () async {
                final r = await _push(QueensScreen(hive: h));
                await _loadQueen();
                return r;
              })),
      _tile('frames', 'Ramki', Icons.view_week_outlined, Colors.teal, _framesSummary(), () => _module('frames', () async {
            final r = await Navigator.of(context).push<List<Map<String, dynamic>>>(MaterialPageRoute(builder: (_) => FramesModule(frames: _frames)));
            if (r == null) return false;
            setState(() => _frames = r);
            return true;
          })),
      _tile('feeding', 'Karmienie', Icons.water_drop_outlined, Colors.pink, '', () => _module('feeding', () => _push(FeedingForm(apiaryId: apiaryId, hive: h)))),
      _tile('treatment', 'Leczenie', Icons.medication_outlined, Colors.blue, '', () => _module('treatment', () => _push(TreatmentForm(apiaryId: apiaryId, hive: h)))),
      _tile('equipment', 'Wyposażenie', Icons.inventory_2_outlined, Colors.green,
          '${_hive['boxes'] ?? 1} korp. · ${_hive['supers'] ?? 0} nadst.${eq['bottom'] == null ? '' : ' · ${eq['bottom']}'}', () => _module('equipment', () async {
            final r = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => EquipmentModule(hive: _hive)));
            if (r == null) return false;
            setState(() => _hive = r);
            return true;
          })),
      _tile('note', 'Notatka', Icons.mic_none, Colors.deepOrange, '${_i['notes'] ?? ''}', () => _module('note', () async {
            final r = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NoteModule(text: '${_i['notes'] ?? ''}')));
            if (r == null) return false;
            setState(() => _i['notes'] = r);
            return true;
          })),
      _tile('photos', 'Zdjęcia', Icons.photo_camera_outlined, Colors.blueGrey, _photos.isEmpty ? '' : '${_photos.length} zdjęć', () => _module('photos', () async {
            final r = await Navigator.of(context).push<List<String>>(MaterialPageRoute(builder: (_) => PhotosModule(ids: _photos)));
            if (r == null) return false;
            setState(() => _photos = r);
            return _photos.isNotEmpty;
          })),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Przegląd'),
          Text('Ul ${h['number'] ?? ''}${'${h['name'] ?? ''}'.isEmpty ? '' : ' · ${h['name']}'}', style: Theme.of(context).textTheme.bodyMedium),
        ]),
        actions: [if (widget.inspection != null) IconButton(tooltip: 'Usuń', onPressed: _delete, icon: const Icon(Icons.delete_outline))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event, size: 28),
          title: Text(DateFormat('EEEE, d MMMM, HH:mm', 'pl').format(_at), style: const TextStyle(fontSize: 17)),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: _pickDate,
        ),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: tiles,
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(_done.isEmpty ? 'Jeżeli ul nie wymaga żadnych prac, po prostu zakończ przegląd.' : 'Uzupełnione: ${_done.length} z 8.')),
        ]),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zakończ przegląd', onPressed: _finish),
    );
  }
}

Map<String, dynamic> _decodeMap(dynamic v) {
  if (v == null || '$v'.isEmpty) return {};
  try {
    return Map<String, dynamic>.from((v is String ? jsonDecode(v) : v) as Map);
  } catch (_) {
    return {};
  }
}

/* ------------------------------------ Rodzina ------------------------------------ */

class FamilyModule extends StatefulWidget {
  const FamilyModule({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  State<FamilyModule> createState() => _FamilyModuleState();
}

class _FamilyModuleState extends State<FamilyModule> {
  Map<String, dynamic> get _i => widget.data;
  int? _num(String k) => int.tryParse('${_i[k]}');

  Widget _toggle(String key, String label, IconData icon) =>
      BigToggle(label: label, icon: icon, value: _on(_i[key]), onChanged: (v) => setState(() => _i[key] = v ? 1 : 0));

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
      appBar: AppBar(title: const Text('Rodzina')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        BigGrid(children: [
          _toggle('queen_seen', 'Matka widziana', Icons.visibility_outlined),
          _toggle('eggs', 'Jajka', Icons.egg_outlined),
          _toggle('open_brood', 'Czerw otwarty', Icons.grid_view),
          _toggle('capped_brood', 'Czerw kryty', Icons.grid_on),
          _toggle('swarm_mood', 'Nastrój rojowy', Icons.warning_amber_rounded),
          _toggle('no_brood', 'Brak czerwiu / jajek', Icons.report_gmailerrorred),
          _toggle('no_stores', 'Brak pokarmu', Icons.no_food_outlined),
        ]),
        BigCounter(label: 'Mateczniki', value: _num('queen_cells') ?? 0, onChanged: (v) => setState(() => _i['queen_cells'] = v.toInt())),
        _scale('strength', 'Siła rodziny', '1 – bardzo słaba, 5 – bardzo silna'),
        _scale('stores', 'Zapasy pokarmu', '1 – brak, 5 – bardzo duże'),
        _scale('temper', 'Łagodność', '1 – bardzo agresywne, 5 – bardzo łagodne'),
        BigChoice<String>(
          label: 'Choroba',
          options: [for (final d in diseases) (d, d)],
          value: (_i['disease'] as String?) ?? 'Brak',
          onChanged: (v) => setState(() => _i['disease'] = v ?? 'Brak'),
        ),
        if (_i['disease'] == 'Zgnilec amerykański')
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            margin: const EdgeInsets.only(top: 12),
            child: const ListTile(
              leading: Icon(Icons.gpp_maybe_outlined),
              title: Text('Zgnilec amerykański podlega obowiązkowi zgłoszenia – niezwłocznie powiadom Powiatowego Lekarza Weterynarii.'),
            ),
          ),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Gotowe', onPressed: () => Navigator.pop(context, true)),
    );
  }
}

/* ------------------------------------ Ramki ------------------------------------ */

const _pct = [(0, '0'), (25, '¼'), (50, '½'), (75, '¾'), (100, 'pełna')];
const frameKinds = ['Ramka', 'Węza', 'Susz', 'Podkarmiaczka', 'Zatwór'];

class FramesModule extends StatefulWidget {
  const FramesModule({super.key, required this.frames});
  final List<Map<String, dynamic>> frames;

  @override
  State<FramesModule> createState() => _FramesModuleState();
}

class _FramesModuleState extends State<FramesModule> {
  late final List<Map<String, dynamic>> _f = [for (final f in widget.frames) Map<String, dynamic>.from(f)];
  int? _open;

  void _add(String kind) => setState(() {
        _f.add({'kind': kind, 'brood': 0, 'pollen': 0, 'honey': 0});
        _open = _f.length - 1;
      });

  Widget _row(Map<String, dynamic> f, String key, String label) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 16))),
          Expanded(
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 48))),
              segments: [for (final (v, t) in _pct) ButtonSegment(value: v, label: Text(t))],
              selected: {(f[key] as num? ?? 0).toInt()},
              onSelectionChanged: (s) => setState(() => f[key] = s.first),
            ),
          ),
        ]),
      );

  String _short(Map<String, dynamic> f) {
    if (f['kind'] != 'Ramka') return '';
    final p = [
      if ((f['brood'] ?? 0) > 0) 'czerw ${f['brood']}%',
      if ((f['pollen'] ?? 0) > 0) 'pierzga ${f['pollen']}%',
      if ((f['honey'] ?? 0) > 0) 'miód ${f['honey']}%',
    ];
    return p.isEmpty ? 'pusta' : p.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ramki (${_f.length})')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
        if (_f.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Dodaj ramki w kolejności od ściany ula.')),
        for (final (i, f) in _f.indexed)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Column(children: [
                Row(children: [
                  CircleAvatar(radius: 22, child: Text('${i + 1}', style: const TextStyle(fontSize: 18))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _open = _open == i ? null : i),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${f['kind']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        Text(_short(f)),
                      ]),
                    ),
                  ),
                  IconButton(
                    iconSize: 30,
                    onPressed: i == 0 ? null : () => setState(() => _f.insert(i - 1, _f.removeAt(i))),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    iconSize: 30,
                    onPressed: i == _f.length - 1 ? null : () => setState(() => _f.insert(i + 1, _f.removeAt(i))),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => setState(() {
                      if (v == 'del') {
                        _f.removeAt(i);
                        _open = null;
                      } else {
                        f['kind'] = v;
                      }
                    }),
                    itemBuilder: (_) => [
                      for (final k in frameKinds) PopupMenuItem(value: k, child: Text('Zmień na: $k')),
                      const PopupMenuItem(value: 'del', child: Text('Usuń ramkę')),
                    ],
                  ),
                ]),
                if (_open == i && f['kind'] == 'Ramka') ...[
                  _row(f, 'brood', 'Czerw'),
                  _row(f, 'pollen', 'Pierzga'),
                  _row(f, 'honey', 'Miód'),
                ],
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in frameKinds)
            SizedBox(
              height: 52,
              child: FilledButton.tonalIcon(onPressed: () => _add(k), icon: const Icon(Icons.add), label: Text(k, style: const TextStyle(fontSize: 16))),
            ),
        ]),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Gotowe', onPressed: () => Navigator.pop(context, _f)),
    );
  }
}

/* ------------------------------------ Wyposażenie ------------------------------------ */

const bottomBoards = ['Wysoka higieniczna', 'Osiatkowana', 'Niska', 'Pełna'];
const equipmentItems = [
  ('feeder', 'Podkarmiaczka', Icons.water_drop_outlined),
  ('excluder', 'Krata odgrodowa', Icons.grid_4x4),
  ('pollen_trap', 'Poławiacz pyłku', Icons.grain),
  ('propolis_trap', 'Poławiacz propolisu', Icons.texture),
  ('isolator', 'Izolator matki', Icons.crop_square),
  ('entrance_reduced', 'Zwężony wylotek', Icons.compress),
  ('escape', 'Przegroda (odpszczelacz)', Icons.call_split),
  ('insulation', 'Ocieplenie', Icons.ac_unit),
];

class EquipmentModule extends StatefulWidget {
  const EquipmentModule({super.key, required this.hive});
  final Map<String, dynamic> hive;

  @override
  State<EquipmentModule> createState() => _EquipmentModuleState();
}

class _EquipmentModuleState extends State<EquipmentModule> {
  late final Map<String, dynamic> _h = Map<String, dynamic>.from(widget.hive);
  late final Map<String, dynamic> _eq = _decodeMap(_h['equipment']);

  Future<void> _save() async {
    final saved = await Db.instance.save('hives', {..._h, 'equipment': jsonEncode(_eq)});
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    int n(String k, [int d = 0]) => int.tryParse('${_h[k]}') ?? d;
    return Scaffold(
      appBar: AppBar(title: const Text('Wyposażenie')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        BigCounter(label: 'Korpusy', value: n('boxes', 1), onChanged: (v) => setState(() => _h['boxes'] = v.toInt())),
        BigCounter(label: 'Nadstawki', value: n('supers'), onChanged: (v) => setState(() => _h['supers'] = v.toInt())),
        BigCounter(label: 'Półnadstawki', value: n('half_supers'), onChanged: (v) => setState(() => _h['half_supers'] = v.toInt())),
        BigChoice<String>(
          label: 'Dennica',
          options: [for (final b in bottomBoards) (b, b)],
          value: _eq['bottom'] as String?,
          onChanged: (v) => setState(() => _eq['bottom'] = v),
        ),
        const SizedBox(height: 18),
        BigGrid(children: [
          for (final (k, label, icon) in equipmentItems)
            BigToggle(label: label, icon: icon, value: _eq[k] == true, onChanged: (v) => setState(() => _eq[k] = v)),
        ]),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Gotowe', onPressed: _save),
    );
  }
}

/* ------------------------------------ Notatka (głosowa) ------------------------------------ */

class NoteModule extends StatefulWidget {
  const NoteModule({super.key, required this.text});
  final String text;

  @override
  State<NoteModule> createState() => _NoteModuleState();
}

class _NoteModuleState extends State<NoteModule> {
  late final _c = TextEditingController(text: widget.text);
  final _speech = SpeechToText();
  bool _ready = false;
  bool _listening = false;
  String _partial = '';
  String _base = '';

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    _ready = _ready ||
        await _speech.initialize(
          onStatus: (s) {
            if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
          },
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
        );
    if (!_ready) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rozpoznawanie mowy niedostępne – sprawdź zgodę na mikrofon.')));
      }
      return;
    }
    _base = _c.text.trim();
    setState(() => _listening = true);
    await _speech.listen(
      localeId: 'pl_PL',
      listenOptions: SpeechListenOptions(partialResults: true, listenMode: ListenMode.dictation),
      onResult: (r) => setState(() {
        _partial = r.recognizedWords;
        _c.text = [_base, _partial].where((e) => e.isNotEmpty).join(_base.isEmpty ? '' : ' ');
        _c.selection = TextSelection.collapsed(offset: _c.text.length);
      }),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notatka')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Expanded(
            child: TextField(
              controller: _c,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(labelText: 'Treść notatki', alignLabelWithHint: true),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 110,
            height: 110,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: const CircleBorder(), backgroundColor: _listening ? scheme.error : scheme.primary),
              onPressed: _toggle,
              child: Icon(_listening ? Icons.stop : Icons.mic, size: 52),
            ),
          ),
          const SizedBox(height: 6),
          Text(_listening ? 'Słucham… naciśnij, żeby zakończyć' : 'Naciśnij i mów'),
        ]),
      ),
      bottomNavigationBar: BigSaveBar(label: 'Gotowe', onPressed: () => Navigator.pop(context, _c.text.trim())),
    );
  }
}

/* ------------------------------------ Zdjęcia ------------------------------------ */

class PhotosModule extends StatefulWidget {
  const PhotosModule({super.key, required this.ids});
  final List<String> ids;

  @override
  State<PhotosModule> createState() => _PhotosModuleState();
}

class _PhotosModuleState extends State<PhotosModule> {
  late final List<String> _ids = [...widget.ids];
  final _picker = ImagePicker();

  Future<void> _take(ImageSource src) async {
    final x = await _picker.pickImage(source: src, maxWidth: 1800, imageQuality: 75);
    if (x == null) return;
    final id = await Photos.add(x.path);
    setState(() => _ids.add(id));
  }

  void _show(String id) {
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PhotoThumb(id: id, size: MediaQuery.of(context).size.width - 32),
          TextButton.icon(
            onPressed: () {
              setState(() => _ids.remove(id));
              Navigator.pop(c);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Usuń z przeglądu'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Zdjęcia (${_ids.length})')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 10, runSpacing: 10, children: [for (final id in _ids) PhotoThumb(id: id, size: 104, onTap: () => _show(id))]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 64,
              child: FilledButton.icon(
                onPressed: () => _take(ImageSource.camera),
                icon: const Icon(Icons.photo_camera, size: 28),
                label: const Text('Zrób zdjęcie', style: TextStyle(fontSize: 17)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 64,
              child: FilledButton.tonalIcon(
                onPressed: () => _take(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 28),
                label: const Text('Z galerii', style: TextStyle(fontSize: 17)),
              ),
            ),
          ),
        ]),
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Gotowe', onPressed: () => Navigator.pop(context, _ids)),
    );
  }
}
