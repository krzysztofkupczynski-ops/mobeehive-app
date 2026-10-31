import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_base.dart';

/// Wniosek o wpis pasieki do rejestru zakładów i podmiotów zarejestrowanych (PLW)
/// albo o aktualizację danych zarejestrowanej pasieki. Układ jak w typowych wzorach PIW.
Future<Uint8List> buildPlwRequest({
  required Map<String, String> owner,
  required Map<String, dynamic> apiary,
  required int colonies,
  required String addressee,
  required bool update,
}) async {
  final k = await PdfKit.load();
  final d = k.doc(update ? 'Wniosek o aktualizację danych pasieki' : 'Wniosek o wpis pasieki do rejestru');
  String? s(dynamic v) => (v == null || '$v'.trim().isEmpty) ? null : '$v'.trim();
  final wandering = apiary['kind'] == 'wędrowna';
  final lat = double.tryParse('${apiary['lat']}');
  final lng = double.tryParse('${apiary['lng']}');

  d.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(42, 36, 42, 36),
    footer: k.footer,
    build: (c) => [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.Text('${s(owner['city']) ?? '…………………'}, dnia ${PdfKit.today()}'),
      ]),
      pw.SizedBox(height: 14),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
        pw.SizedBox(
          width: 230,
          child: pw.Text(addressee.isEmpty ? 'Powiatowy Lekarz Weterynarii w ……………………\n…………………………………………' : addressee,
              style: pw.TextStyle(font: k.bold)),
        ),
      ]),
      pw.SizedBox(height: 14),
      k.h1(update
          ? 'WNIOSEK O AKTUALIZACJĘ DANYCH DOTYCZĄCYCH ZAREJESTROWANEJ PASIEKI'
          : 'WNIOSEK O WPIS PASIEKI DO REJESTRU ZAKŁADÓW I PODMIOTÓW ZAREJESTROWANYCH'),
      k.h2('I. Dane dotyczące właściciela pasieki'),
      k.fields([
        ('1. Imię i nazwisko (lub nazwa firmy)', s(owner['name'])),
        ('2. Adres zamieszkania (lub siedziby firmy)', null),
        ('    Miejscowość', s(owner['city'])),
        ('    Ulica, nr domu / nr lokalu',
            [s(owner['street']), [s(owner['house']), s(owner['flat'])].whereType<String>().join(' / ')].where((e) => e != null && e.isNotEmpty).join(' ')),
        ('    Kod pocztowy, poczta', [s(owner['postcode']), s(owner['post'])].whereType<String>().join(' ')),
        ('3. PESEL (NIP w przypadku firmy)', s(owner['pesel'])),
        ('4. Numer telefonu', s(owner['phone'])),
        ('5. Adres do doręczeń (jeżeli inny)', s(owner['delivery'])),
        ('6. Strona internetowa, e-mail, adres do doręczeń elektronicznych', s(owner['email'])),
      ]),
      k.h2('II. Dane dotyczące pasieki'),
      k.fields([
        if (update) ('Weterynaryjny Numer Identyfikacyjny pasieki (WNI)', s(apiary['vet_number'])),
        ('1. Gatunek utrzymywanych zwierząt', 'pszczoła miodna (Apis mellifera)'),
        ('2. Rodzaj pasieki', wandering ? 'wędrowna' : 'stacjonarna'),
        (
          '3. Lokalizacja pasieki (pełny adres; dla pasieki wędrownej – adres miejsca zimowania)',
          wandering ? (s(apiary['wintering_address']) ?? s(apiary['address'])) : s(apiary['address'])
        ),
        ('4. Współrzędne geograficzne lokalizacji pasieki',
            lat == null || lng == null ? null : '${lat.toStringAsFixed(5)} N, ${lng.toStringAsFixed(5)} E'),
        ('5. Opis obiektów', s(apiary['facilities'])),
        ('6. Aktualna liczba rodzin', '$colonies'),
        ('7. Potencjał pasieki (maksymalna możliwa liczba rodzin)', s(apiary['capacity'])),
        ('8. Okres, w którym pszczoły są trzymane w pasiece (jeżeli nie jest stale zajęta)', s(apiary['season_period']) ?? 'cały rok'),
        ('9. Inne kwestie istotne dla ustalenia ryzyka (jeżeli dotyczy)', s(apiary['risk_notes']) ?? 'nie dotyczy'),
        ('10. Planowany czas prowadzenia działalności', s(apiary['planned_duration']) ?? 'bezterminowo'),
      ]),
      if (!update) ...[
        k.h2('Załączniki'),
        pw.Text('1. Potwierdzenie uiszczenia opłaty skarbowej za wydanie decyzji (nadanie WNI) – zgodnie z informacją '
            'właściwego Powiatowego Inspektoratu Weterynarii.'),
      ],
      k.h2('Pouczenie'),
      pw.Text(
        'Podmioty utrzymujące zwierzęta zgłaszają je do rejestracji przed rozpoczęciem działalności (art. 84 rozporządzenia '
        '(UE) 2016/429). Zmiany danych oraz zaprzestanie działalności zgłasza się powiatowemu lekarzowi weterynarii '
        '(termin podaje właściwy PIW, zwykle 7 dni od zdarzenia). Wniosek składa się osobno dla każdej pasieki, '
        'w PIW właściwym dla jej lokalizacji – pocztą, przez e-Doręczenia albo osobiście.',
        style: const pw.TextStyle(fontSize: 8.5),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'Wyrażam zgodę na przetwarzanie moich danych osobowych w celu prowadzenia sprawy administracyjnej. '
        'Oświadczam, że podanie danych jest dobrowolne.',
        style: const pw.TextStyle(fontSize: 8.5),
      ),
      k.signature('czytelny podpis zgłaszającego'),
    ],
  ));
  return d.save();
}
