import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../db.dart';
import '../docs/plw_request.dart';
import '../docs/rhd_registers.dart';
import '../docs/treatment_register.dart';
import '../owner.dart';
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
        const Divider(),
        const _Section('Powiatowy Lekarz Weterynarii'),
        ListTile(
          leading: const Icon(Icons.assignment_outlined, size: 30),
          title: const Text('Wniosek o wpis pasieki do rejestru'),
          subtitle: const Text('Albo o aktualizację danych zarejestrowanej pasieki'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlwRequestScreen())),
        ),
        const _Section('Rolniczy handel detaliczny'),
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
          title: const Text('Ewidencja sprzedaży RHD'),
          subtitle: const Text('Z podsumowaniem limitu dla sklepów i restauracji'),
          trailing: const Icon(Icons.picture_as_pdf_outlined),
          onTap: () => _yearPdf(context, 'Ewidencja sprzedaży RHD', 'ewidencja-sprzedazy', (y, o) async {
            return buildSalesRegister(y, await Db.instance.list('sales'), o);
          }),
        ),
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

/// Wybór pasieki i rodzaju wniosku, potem podgląd PDF.
class PlwRequestScreen extends StatefulWidget {
  const PlwRequestScreen({super.key});

  @override
  State<PlwRequestScreen> createState() => _PlwRequestScreenState();
}

class _PlwRequestScreenState extends State<PlwRequestScreen> {
  List<Map<String, dynamic>> _apiaries = [];
  String? _apiaryId;
  bool _update = false;
  final _piw = TextEditingController();
  Map<String, String> _owner = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await Db.instance.list('apiaries', orderKey: 'name');
    final o = await Owner.load();
    final piw = await Owner.piw();
    if (!mounted) return;
    setState(() {
      _apiaries = a;
      _apiaryId = a.isEmpty ? null : a.first['id'] as String;
      _update = a.isNotEmpty && (a.first['vet_number'] ?? '').toString().isNotEmpty;
      _owner = o;
      _piw.text = piw;
    });
  }

  Future<void> _generate() async {
    final apiary = _apiaries.firstWhere((a) => a['id'] == _apiaryId);
    final hives = await Db.instance.list('hives', where: {'apiary_id': _apiaryId!});
    await Owner.savePiw(_piw.text.trim());
    final bytes = await buildPlwRequest(
      owner: _owner,
      apiary: apiary,
      colonies: hives.length,
      addressee: _piw.text.trim(),
      update: _update,
    );
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfScreen(title: _update ? 'Aktualizacja danych pasieki' : 'Wniosek o wpis pasieki', bytes: bytes, fileName: 'wniosek-plw-${apiary['name']}.pdf'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final missingOwner = (_owner['name'] ?? '').isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Wniosek do PLW')),
      body: _apiaries.isEmpty
          ? const Center(child: Text('Najpierw dodaj pasiekę.'))
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (missingOwner)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Uzupełnij dane pszczelarza'),
                    subtitle: const Text('Bez nich pola właściciela zostaną puste do ręcznego wpisania.'),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OwnerScreen()));
                      _load();
                    },
                  ),
                ),
              DropdownButtonFormField<String>(
                value: _apiaryId,
                decoration: const InputDecoration(labelText: 'Pasieka'),
                items: [for (final a in _apiaries) DropdownMenuItem(value: a['id'] as String, child: Text('${a['name']}'))],
                onChanged: (v) => setState(() {
                  _apiaryId = v;
                  final a = _apiaries.firstWhere((x) => x['id'] == v);
                  _update = (a['vet_number'] ?? '').toString().isNotEmpty;
                }),
              ),
              BigChoice<bool>(
                label: 'Rodzaj wniosku',
                options: const [(false, 'Rejestracja'), (true, 'Aktualizacja')],
                value: _update,
                onChanged: (v) => setState(() => _update = v ?? _update),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _piw,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Adresat',
                  hintText: 'Powiatowy Lekarz Weterynarii w …\nul. …\nkod, miejscowość',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Pola, których brakuje w aplikacji, zostaną puste do wpisania ręcznie. Dane pasieki do wniosku '
                'uzupełnisz w edycji pasieki → „Dane do rejestracji w PLW”. Każdy PIW ma własny wzór – przed '
                'pierwszym wysłaniem upewnij się, że przyjmie ten wydruk.',
              ),
            ]),
      bottomNavigationBar: _apiaries.isEmpty ? null : BigSaveBar(label: 'Utwórz PDF', onPressed: _generate),
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
