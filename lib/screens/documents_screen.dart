import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../db.dart';
import '../docs/plw_request.dart';
import '../docs/rhd_registers.dart';
import '../docs/treatment_register.dart';
import '../location.dart';
import '../owner.dart';
import '../piw.dart';
import '../settings.dart';
import '../sync.dart';
import '../widgets.dart';
import 'owner_screen.dart';

/// Lista dokumentów do wygenerowania.
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dokumenty')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.badge_outlined, size: 30),
          title: const Text('Dane pszczelarza'),
          subtitle: const Text('Imię, adres, PESEL – wpisywane do dokumentów'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OwnerScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.folder_outlined, size: 30),
          title: const Text('Moje dokumenty'),
          subtitle: const Text('Wypełnione i zapisane w telefonie, gotowe do druku'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedDocsScreen())),
        ),
        const Divider(),
        const _Section('Powiatowy Lekarz Weterynarii'),
        ListTile(
          leading: const Icon(Icons.assignment_outlined, size: 30),
          title: const Text('Zgłoszenie pasieki do PLW'),
          subtitle: const Text('Rejestracja albo aktualizacja – właściwy PIW dobiera się sam'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlwRequestScreen())),
        ),
        if (Settings.sales != SalesMode.none) ...[
        _Section(Settings.sales == SalesMode.rhd ? 'Rolniczy handel detaliczny' : 'Sprzedaż bezpośrednia'),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined, size: 30),
          title: const Text('Rejestr mycia i dezynfekcji'),
          subtitle: const Text('Pracownia i sprzęt, kontrola szkodników, badania wody'),
          trailing: const Icon(Icons.picture_as_pdf_outlined),
          onTap: () => _yearPdf(context, 'Rejestr mycia i dezynfekcji', 'rejestr-mycia', (y, o) async {
            return buildHygieneRegister(y, await Db.instance.list('hygiene'), o);
          }),
        ),
        ListTile(
          leading: const Icon(Icons.scale_outlined, size: 30),
          title: const Text('Ewidencja produkcji'),
          subtitle: const Text('Miodobrania z numerami partii'),
          trailing: const Icon(Icons.picture_as_pdf_outlined),
          onTap: () => _yearPdf(context, 'Ewidencja produkcji', 'ewidencja-produkcji', (y, o) async {
            final apiaries = await Db.instance.list('apiaries');
            return buildProductionRegister(
                y, await Db.instance.list('harvests'), {for (final a in apiaries) '${a['id']}': '${a['name']}'}, o);
          }),
        ),
        ListTile(
          leading: const Icon(Icons.point_of_sale_outlined, size: 30),
          title: Text(Settings.sales == SalesMode.rhd ? 'Ewidencja sprzedaży RHD' : 'Ewidencja sprzedaży SB'),
          subtitle: Text(Settings.sales == SalesMode.rhd ? 'Z podsumowaniem limitu dla sklepów i restauracji' : 'Z podsumowaniem roku'),
          trailing: const Icon(Icons.picture_as_pdf_outlined),
          onTap: () => _yearPdf(context, Settings.sales == SalesMode.rhd ? 'Ewidencja sprzedaży RHD' : 'Ewidencja sprzedaży SB', 'ewidencja-sprzedazy', (y, o) async {
            return buildSalesRegister(y, await Db.instance.list('sales'), o, rhd: Settings.sales == SalesMode.rhd);
          }),
        ),
        ],
        const _Section('Leczenie'),
        ListTile(
          leading: const Icon(Icons.medication_outlined, size: 30),
          title: const Text('Ewidencja leczenia'),
          subtitle: const Text('Art. 108 rozp. (UE) 2019/6 – przechowywać 5 lat'),
          trailing: const Icon(Icons.picture_as_pdf_outlined),
          onTap: () => _yearPdf(context, 'Ewidencja leczenia', 'ewidencja-leczenia', (y, o) async {
            final apiaries = await Db.instance.list('apiaries');
            final hives = await Db.instance.list('hives');
            return buildTreatmentRegister(y, await Db.instance.list('treatments'),
                {for (final a in apiaries) '${a['id']}': a}, {for (final h in hives) '${h['id']}': h}, o);
          }),
        ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

/// Zgłoszenie pasieki: PIW dobierany automatycznie z lokalizacji pasieki, wypełnienie, zapis w telefonie.
class PlwRequestScreen extends StatefulWidget {
  const PlwRequestScreen({super.key});

  @override
  State<PlwRequestScreen> createState() => _PlwRequestScreenState();
}

class _PlwRequestScreenState extends State<PlwRequestScreen> {
  List<Map<String, dynamic>> _apiaries = [];
  String? _apiaryId;
  bool _update = false;
  final _addressee = TextEditingController();
  Map<String, String> _owner = {};
  Piw? _piw;
  String? _piwError;
  bool _piwLoading = false;
  String _species = 'pszczoła miodna';
  String? _trend;
  bool _busy = false;

  static const _speciesOptions = ['pszczoła miodna', 'trzmiele', 'pszczoły samotne'];

  Map<String, dynamic>? get _apiary => _apiaries.where((a) => a['id'] == _apiaryId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await Db.instance.list('apiaries', orderKey: 'name');
    final o = await Owner.load();
    if (!mounted) return;
    setState(() {
      _apiaries = a;
      _owner = o;
    });
    if (a.isNotEmpty) _select(a.first['id'] as String);
  }

  Future<void> _select(String id) async {
    final a = _apiaries.firstWhere((x) => x['id'] == id);
    setState(() {
      _apiaryId = id;
      _update = '${a['vet_number'] ?? ''}'.isNotEmpty;
      _species = '${a['species'] ?? ''}'.isEmpty ? 'pszczoła miodna' : '${a['species']}';
      _trend = a['capacity_trend'] as String?;
      _piw = null;
      _piwError = null;
      _piwLoading = true;
    });
    var apiary = a;
    if ('${a['county'] ?? ''}'.isEmpty && a['lat'] != null) {
      apiary = await resolveRegion(a) ?? a;
    }
    Piw? piw;
    String? err;
    try {
      piw = await Piw.forApiary(apiary);
      if (piw == null) err = 'Ustaw miejsce pasieki (edycja pasieki), żeby dobrać właściwy inspektorat.';
    } catch (e) {
      err = '$e';
    }
    if (!mounted || _apiaryId != id) return;
    setState(() {
      _piw = piw;
      _piwError = err;
      _piwLoading = false;
      if (piw != null) _addressee.text = piw.addressee;
    });
  }

  String get _purpose => switch (Settings.sales) {
        SalesMode.rhd => 'rolniczy handel detaliczny',
        SalesMode.sb => 'sprzedaż bezpośrednia',
        SalesMode.none => 'własne potrzeby',
      };

  Future<void> _openTemplate(Map<String, dynamic> form) async {
    try {
      final f = await Piw.templateFile(form);
      if ('${form['type']}' == 'pdf') {
        if (!mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PdfScreen(title: '${form['title']}', bytes: f.readAsBytesSync(), fileName: f.uri.pathSegments.last),
        ));
      } else {
        await Share.shareXFiles([XFile(f.path)], subject: '${form['title']}');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _generate() async {
    final apiary = _apiary;
    if (apiary == null) return;
    setState(() => _busy = true);
    try {
      // Zapamiętaj gatunki i tendencję potencjału w pasiece.
      final saved = await Db.instance.save('apiaries', {...apiary, 'species': _species, 'capacity_trend': _trend});
      final hives = await Db.instance.list('hives');
      int count(String id) => hives.where((h) => h['apiary_id'] == id).length;
      // Inne pasieki tego samego właściciela w tym samym inspektoracie → załącznik z lokalizacjami.
      final others = <Map<String, dynamic>>[];
      for (final a in _apiaries.where((x) => x['id'] != apiary['id'])) {
        if (_piw != null && Piw.countyCode(a) != null) {
          final p = await Piw.forApiary(a).catchError((_) => null);
          if (p?.name == _piw!.name) others.add(a);
        }
      }
      final bytes = await buildPlwRequest(
        owner: _owner,
        apiary: saved,
        colonies: count('${apiary['id']}'),
        addressee: _addressee.text.trim(),
        update: _update,
        purpose: _purpose,
        otherApiaries: others,
        otherColonies: {for (final a in others) '${a['id']}': count('${a['id']}')},
        feeAccount: _piw?.feeAccount,
        piwCity: _piw?.data['city'] as String?,
      );
      final title = '${_update ? 'Aktualizacja danych' : 'Zgłoszenie'} pasieki „${apiary['name']}” – ${_piw?.plw ?? 'PLW'}';
      final entry = await SavedDocs.save(title, 'zgloszenie-pasieki-${apiary['name']}.pdf', bytes);
      SyncService.instance.run();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfScreen(title: title, bytes: bytes, fileName: '${entry['name']}'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _piwCard() {
    final theme = Theme.of(context);
    if (_piwLoading) {
      return const Card(child: ListTile(leading: CircularProgressIndicator(), title: Text('Szukam właściwego inspektoratu…')));
    }
    if (_piw == null) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: ListTile(leading: const Icon(Icons.location_off_outlined), title: Text(_piwError ?? 'Nie udało się ustalić inspektoratu.')),
      );
    }
    final p = _piw!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.account_balance_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Text(p.address),
          if (p.phone != null) Text('tel. ${p.phone}'),
          if (p.email != null) Text(p.email!),
          if (p.note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(p.note!)),
          if (!p.verified)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Właściwość tego PIW dla Twojego powiatu jest jeszcze do potwierdzenia – zadzwoń przed wysłaniem.',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (p.forms.isNotEmpty) ...[
            const Divider(height: 20),
            const Text('Oryginalne wzory tego PIW', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final f in p.forms)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon('${f['type']}' == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.description_outlined),
                title: Text('${f['title']}'),
                subtitle: Text('${'${f['type']}'.toUpperCase()} – puste, do wypełnienia ręcznie'),
                trailing: const Icon(Icons.download_outlined),
                onTap: () => _openTemplate(f),
              ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final missingOwner = (_owner['name'] ?? '').isEmpty || (_owner['pesel'] ?? '').isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Zgłoszenie pasieki do PLW')),
      body: _apiaries.isEmpty
          ? const Center(child: Text('Najpierw dodaj pasiekę.'))
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (missingOwner)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Uzupełnij dane pszczelarza'),
                    subtitle: const Text('Imię, adres, PESEL, numer EP – inaczej pola zostaną puste.'),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OwnerScreen()));
                      final o = await Owner.load();
                      if (mounted) setState(() => _owner = o);
                    },
                  ),
                ),
              DropdownButtonFormField<String>(
                value: _apiaryId,
                decoration: const InputDecoration(labelText: 'Pasieka'),
                items: [for (final a in _apiaries) DropdownMenuItem(value: a['id'] as String, child: Text('${a['name']}'))],
                onChanged: (v) {
                  if (v != null) _select(v);
                },
              ),
              const SizedBox(height: 12),
              _piwCard(),
              BigChoice<bool>(
                label: 'Rodzaj',
                options: const [(false, 'Nowa rejestracja'), (true, 'Aktualizacja danych')],
                value: _update,
                onChanged: (v) => setState(() => _update = v ?? _update),
              ),
              BigChoice<String>(
                label: 'Gatunki',
                options: [for (final o in _speciesOptions) (o, o)],
                value: _species,
                onChanged: (v) => setState(() => _species = v ?? _species),
              ),
              BigChoice<String>(
                label: 'Potencjał zakładu (tendencja)',
                options: const [('wzrostowy', 'Wzrostowy'), ('stały', 'Stały'), ('zniżkowy', 'Zniżkowy')],
                value: _trend,
                onChanged: (v) => setState(() => _trend = v),
              ),
              const SizedBox(height: 12),
              Text('Cel prowadzenia pasieki: $_purpose (z Ustawień)'),
              const SizedBox(height: 18),
              TextField(controller: _addressee, maxLines: 3, decoration: const InputDecoration(labelText: 'Adresat')),
              const SizedBox(height: 12),
              const Text(
                'Wypełniony dokument zapisze się w telefonie w „Moje dokumenty”. Pozostałe pola pasieki (opis obiektów, '
                'potencjał, okres) uzupełnisz w edycji pasieki → „Dane do rejestracji w PLW”.',
              ),
            ]),
      bottomNavigationBar: _apiaries.isEmpty
          ? null
          : BigSaveBar(label: _busy ? 'Tworzę…' : 'Wypełnij i zapisz', onPressed: _busy ? () {} : _generate),
    );
  }
}

/// Wypełnione dokumenty zapisane w telefonie.
class SavedDocsScreen extends StatefulWidget {
  const SavedDocsScreen({super.key});

  @override
  State<SavedDocsScreen> createState() => _SavedDocsScreenState();
}

class _SavedDocsScreenState extends State<SavedDocsScreen> {
  List<Map<String, dynamic>> _docs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await SavedDocs.list();
    if (mounted) setState(() => _docs = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moje dokumenty')),
      body: _docs.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Tu pojawią się wypełnione dokumenty.')))
          : ListView(children: [
              for (final d in _docs)
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined, size: 30),
                  title: Text('${d['title']}'),
                  subtitle: Text(DateFormat('d.MM.yyyy, HH:mm', 'pl').format(DateTime.parse('${d['created']}'))),
                  onTap: () async {
                    final f = File('${d['file']}');
                    if (!await f.exists()) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plik nie istnieje.')));
                      }
                      return;
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PdfScreen(title: '${d['title']}', bytes: f.readAsBytesSync(), fileName: '${d['name']}'),
                    ));
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Usunąć dokument?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await SavedDocs.remove(d);
                        _load();
                      }
                    },
                  ),
                ),
            ]),
    );
  }
}

/// Podgląd PDF z drukowaniem i udostępnianiem.
class PdfScreen extends StatelessWidget {
  const PdfScreen({super.key, required this.title, required this.bytes, required this.fileName});
  final String title;
  final Uint8List bytes;
  final String fileName;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: PdfPreview(
          build: (_) async => bytes,
          pdfFileName: fileName,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          allowSharing: true,
          allowPrinting: true,
        ),
      );
}

/// Wybór roku i podgląd PDF rejestru.
Future<void> _yearPdf(BuildContext context, String title, String file,
    Future<Uint8List> Function(int year, Map<String, String> owner) build) async {
  final now = DateTime.now().year;
  final year = await showDialog<int>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(title),
      children: [
        for (final y in [now, now - 1, now - 2])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, y),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Rok $y', style: const TextStyle(fontSize: 18))),
          ),
      ],
    ),
  );
  if (year == null || !context.mounted) return;
  final bytes = await build(year, await Owner.load());
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfScreen(title: '$title $year', bytes: bytes, fileName: '$file-$year.pdf')));
}
