import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../db.dart';
import '../docs/plw_request.dart';
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
        const ListTile(
          enabled: false,
          leading: Icon(Icons.cleaning_services_outlined, size: 30),
          title: Text('Ewidencja mycia i dezynfekcji pracowni'),
          subtitle: Text('W przygotowaniu'),
        ),
        const ListTile(
          enabled: false,
          leading: Icon(Icons.point_of_sale_outlined, size: 30),
          title: Text('Ewidencja sprzedaży RHD'),
          subtitle: Text('W przygotowaniu'),
        ),
        const _Section('Leczenie'),
        const ListTile(
          enabled: false,
          leading: Icon(Icons.medication_outlined, size: 30),
          title: Text('Ewidencja leczenia (art. 108 rozp. UE 2019/6)'),
          subtitle: Text('W przygotowaniu'),
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
