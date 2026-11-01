import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_base.dart';

/// Zgłoszenie pasieki do rejestru Powiatowego Lekarza Weterynarii (rejestracja albo aktualizacja danych)
/// na podstawie art. 55 ustawy z dnia 21 listopada 2025 r. o zdrowiu zwierząt.
/// Zawiera pola wspólne dla wzorów PIW województwa łódzkiego (m.in. Łódź, Kutno, Wieluń, Rawa Maz., Poddębice).
Future<Uint8List> buildPlwRequest({
  required Map<String, String> owner,
  required Map<String, dynamic> apiary,
  required int colonies,
  required String addressee,
  required bool update,
  String purpose = 'własne potrzeby',
  List<Map<String, dynamic>> otherApiaries = const [],
  Map<String, int> otherColonies = const {},
  String? feeAccount,
  String? piwCity,
}) async {
  final k = await PdfKit.load();
  final d = k.doc(update ? 'Aktualizacja danych pasieki' : 'Zgłoszenie pasieki do rejestru PLW');
  String? s(dynamic v) => (v == null || '$v'.trim().isEmpty) ? null : '$v'.trim();
  final wandering = apiary['kind'] == 'wędrowna';
  final lat = double.tryParse('${apiary['lat']}');
  final lng = double.tryParse('${apiary['lng']}');
  final trend = s(apiary['capacity_trend']);
  String coords(Map<String, dynamic> a) {
    final la = double.tryParse('${a['lat']}'), lo = double.tryParse('${a['lng']}');
    return la == null || lo == null ? '' : '${la.toStringAsFixed(5)} N, ${lo.toStringAsFixed(5)} E';
  }

  String place(Map<String, dynamic> a) =>
      [s(a['address']), s(a['commune']) == null ? null : 'gm. ${a['commune']}', s(a['county'])].whereType<String>().join(', ');

  d.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(42, 36, 42, 36),
    footer: k.footer,
    build: (c) => [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Text('${s(owner['city']) ?? '…………………'}, dnia ${PdfKit.today()}'),
      ]),
      pw.SizedBox(height: 12),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.SizedBox(
          width: 240,
          child: pw.Text(addressee.isEmpty ? 'Powiatowy Lekarz Weterynarii w ……………………' : addressee, style: pw.TextStyle(font: k.bold)),
        ),
      ]),
      pw.SizedBox(height: 12),
      k.h1(update
          ? 'OŚWIADCZENIE – AKTUALIZACJA DANYCH ZAREJESTROWANEJ PASIEKI'
          : 'ZGŁOSZENIE PASIEKI DO REJESTRU POWIATOWEGO LEKARZA WETERYNARII\noraz wniosek o nadanie weterynaryjnego numeru identyfikacyjnego'),
      pw.Text('na podstawie art. 55 ustawy z dnia 21 listopada 2025 r. o zdrowiu zwierząt (Dz. U. z 2025 r. poz. 1795)',
          textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
      k.h2('I. Dane podmiotu (właściciela pasieki)'),
      k.fields([
        ('1. Imię i nazwisko albo nazwa podmiotu', s(owner['name'])),
        (
          '2. Adres zamieszkania albo siedziba i adres podmiotu',
          [
            [s(owner['street']), [s(owner['house']), s(owner['flat'])].whereType<String>().join('/')].where((e) => e != null && e.isNotEmpty).join(' '),
            [s(owner['postcode']), s(owner['city'])].whereType<String>().join(' '),
            s(owner['post']) == null ? null : 'poczta ${owner['post']}',
          ].where((e) => e != null && e.isNotEmpty).join(', ')
        ),
        ('3. PESEL (NIP w przypadku firmy)', s(owner['pesel'])),
        ('4. Numer gospodarstwa nadany przez ARiMR (EP) lub KRS', s(owner['ep'])),
        ('5. Telefon', s(owner['phone'])),
        ('6. E-mail, strona www, adres do doręczeń elektronicznych', s(owner['email'])),
        ('7. Adres do doręczeń (jeżeli inny)', s(owner['delivery'])),
      ]),
      k.h2('II. Dane zakładu (pasieki)'),
      k.fields([
        if (update) ('Dotychczasowy weterynaryjny numer identyfikacyjny (WNI)', s(apiary['vet_number'])),
        ('8. Rodzaj zakładu', 'gospodarstwo pasieczne'),
        ('9. Gatunki utrzymywanych zwierząt', s(apiary['species']) ?? 'pszczoła miodna (Apis mellifera)'),
        ('10. Rodzaj pasieki', wandering ? 'wędrowna' : 'stacjonarna'),
        (
          '11. Lokalizacja pasieki${wandering ? ' (miejsce zimowania)' : ''}',
          wandering ? (s(apiary['wintering_address']) ?? place(apiary)) : place(apiary)
        ),
        ('12. Współrzędne geograficzne', lat == null || lng == null ? null : coords(apiary)),
        ('13. Opis obiektów (rodzaj uli, usytuowanie, otoczenie)', s(apiary['facilities'])),
        ('14. Aktualna liczba rodzin (pni pszczelich)', '$colonies'),
        (
          '15. Potencjał zakładu (maksymalna liczba rodzin)',
          [s(apiary['capacity']), trend == null ? null : 'tendencja: $trend'].whereType<String>().join(', ')
        ),
        ('16. Więcej niż jedna lokalizacja', otherApiaries.isEmpty ? 'nie' : 'tak – ${otherApiaries.length + 1} lokalizacje (załącznik)'),
        ('17. Cel prowadzenia pasieki', purpose),
        ('18. Okres utrzymywania pszczół (jeżeli nie cały rok)', s(apiary['season_period']) ?? 'cały rok'),
        ('19. Inne kwestie istotne dla oceny ryzyka', s(apiary['risk_notes']) ?? 'nie dotyczy'),
        ('20. Planowany czas prowadzenia działalności', s(apiary['planned_duration']) ?? 'bezterminowo'),
      ]),
      k.signature('czytelny podpis zgłaszającego'),
      if (!update) ...[
        k.h2('Wniosek o nadanie weterynaryjnego numeru identyfikacyjnego'),
        pw.Text('Wnoszę o nadanie weterynaryjnego numeru identyfikacyjnego dla zgłaszanej działalności.'),
        k.signature('czytelny podpis'),
        k.h2('Opłata'),
        pw.Text('Opłata skarbowa 10 zł za decyzję o nadaniu WNI – tylko przy nowej rejestracji, nie przy aktualizacji danych.'
            '${feeAccount == null ? '' : '\nRachunek: $feeAccount'}'
            '${piwCity == null ? '' : '\nW tytule: imię i nazwisko, „decyzja WNI – pasieka”.'}'),
        pw.Text('Załącznik: potwierdzenie uiszczenia opłaty skarbowej.'),
      ],
      if (otherApiaries.isNotEmpty) ...[
        pw.NewPage(),
        k.h1('Załącznik – lokalizacje pasiek'),
        pw.Text('Podmiot: ${s(owner['name']) ?? '……………………'}'),
        pw.SizedBox(height: 8),
        k.grid(
          ['Lp.', 'Nazwa', 'Lokalizacja (adres / opis)', 'Współrzędne', 'Liczba pni', 'Rodzaj'],
          [
            for (final (i, a) in [apiary, ...otherApiaries].indexed)
              [
                '${i + 1}',
                '${a['name'] ?? ''}',
                place(a),
                coords(a),
                '${i == 0 ? colonies : (otherColonies['${a['id']}'] ?? 0)}',
                a['kind'] == 'wędrowna' ? 'wędrowna' : 'stacjonarna',
              ],
          ],
          widths: {
            0: const pw.FixedColumnWidth(22),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(2.4),
            3: const pw.FlexColumnWidth(1.6),
            4: const pw.FixedColumnWidth(44),
            5: const pw.FixedColumnWidth(58),
          },
        ),
        k.signature('czytelny podpis'),
      ],
      pw.SizedBox(height: 14),
      pw.Text(
        'Zmiany danych oraz zaprzestanie działalności zgłasza się powiatowemu lekarzowi weterynarii. '
        'Informację o liczbie pni pszczelich przekazuje się do 31 marca i do 30 września każdego roku (art. 68 ustawy o zdrowiu zwierząt). '
        'Wyrażam zgodę na przetwarzanie moich danych osobowych w celu prowadzenia sprawy.',
        style: const pw.TextStyle(fontSize: 8),
      ),
    ],
  ));
  return d.save();
}
