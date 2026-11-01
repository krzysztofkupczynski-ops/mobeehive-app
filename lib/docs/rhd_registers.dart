import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../feeding.dart' show fmtAmount;
import '../rhd.dart';
import 'pdf_base.dart';

String _d(dynamic v, [String f = 'dd.MM.yyyy']) {
  final d = DateTime.tryParse('$v');
  return d == null ? '' : DateFormat(f).format(d);
}

List<Map<String, dynamic>> _ofYear(List<Map<String, dynamic>> rows, String dateKey, int year) {
  final out = rows.where((r) => DateTime.tryParse('${r[dateKey]}')?.year == year).toList();
  out.sort((a, b) => '${a[dateKey]}'.compareTo('${b[dateKey]}'));
  return out;
}

pw.Widget _head(PdfKit k, String title, int year, Map<String, String> owner) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        k.h1('$title – $year'),
        pw.Text('Prowadzący: ${owner['name'] ?? '……………………………'}'
            '${(owner['city'] ?? '').isNotEmpty ? ', ${[owner['street'], owner['house'], owner['postcode'], owner['city']].where((e) => (e ?? '').isNotEmpty).join(' ')}' : ''}'),
        pw.SizedBox(height: 8),
      ],
    );

Future<Uint8List> _render(String title, List<pw.Widget> Function(PdfKit k) body) async {
  final k = await PdfKit.load();
  final d = k.doc(title);
  d.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    footer: k.footer,
    build: (_) => body(k),
  ));
  return d.save();
}

/// Rejestr mycia i dezynfekcji pracowni (wraz z kontrolą szkodników i badaniami wody).
Future<Uint8List> buildHygieneRegister(int year, List<Map<String, dynamic>> entries, Map<String, String> owner) {
  final rows = _ofYear(entries, 'done_at', year);
  return _render('Rejestr mycia i dezynfekcji', (k) => [
        _head(k, 'Rejestr mycia i dezynfekcji pomieszczeń i sprzętu', year, owner),
        k.grid(
          ['Lp.', 'Data i godzina', 'Czynność', 'Co (pomieszczenie / sprzęt)', 'Środek', 'Stężenie', 'Uwagi', 'Wykonał(a) – podpis'],
          [
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                _d(rows[i]['done_at'], 'dd.MM.yyyy HH:mm'),
                '${rows[i]['kind'] ?? ''}',
                '${rows[i]['area'] ?? ''}',
                '${rows[i]['agent'] ?? ''}',
                '${rows[i]['concentration'] ?? ''}',
                '${rows[i]['notes'] ?? ''}',
                '${rows[i]['performed_by'] ?? ''}',
              ],
          ],
          widths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FixedColumnWidth(72),
            2: const pw.FixedColumnWidth(80),
            3: const pw.FlexColumnWidth(3),
            4: const pw.FlexColumnWidth(1.6),
            5: const pw.FixedColumnWidth(54),
            6: const pw.FlexColumnWidth(1.6),
            7: const pw.FlexColumnWidth(1.4),
          },
          emptyRows: rows.length < 12 ? 12 - rows.length : 3,
        ),
      ]);
}

/// Ewidencja produkcji – miodobrania z numerami partii.
Future<Uint8List> buildProductionRegister(
    int year, List<Map<String, dynamic>> harvests, Map<String, String> apiaryNames, Map<String, String> owner) {
  final rows = _ofYear(harvests, 'harvested_on', year);
  final total = rows.fold<double>(0, (a, h) => a + qty(h['quantity']));
  final byKind = <String, double>{};
  for (final h in rows) {
    byKind['${h['product']}'] = (byKind['${h['product']}'] ?? 0) + qty(h['quantity']);
  }
  return _render('Ewidencja produkcji', (k) => [
        _head(k, 'Ewidencja produkcji (pozyskania miodu)', year, owner),
        k.grid(
          ['Lp.', 'Data', 'Pasieka', 'Produkt', 'Ilość [kg]', 'Nr partii', 'Uwagi'],
          [
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                _d(rows[i]['harvested_on']),
                apiaryNames['${rows[i]['apiary_id']}'] ?? '',
                'Miód ${'${rows[i]['product']}'.toLowerCase()}',
                fmtAmount(qty(rows[i]['quantity'])),
                '${rows[i]['lot'] ?? ''}',
                '${rows[i]['notes'] ?? ''}',
              ],
          ],
          widths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FixedColumnWidth(64),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.6),
            4: const pw.FixedColumnWidth(60),
            5: const pw.FixedColumnWidth(80),
            6: const pw.FlexColumnWidth(2),
          },
          emptyRows: 3,
        ),
        k.h2('Podsumowanie'),
        pw.Text('Razem: ${fmtAmount(total)} kg'
            '${byKind.isEmpty ? '' : ' (${byKind.entries.map((e) => '${e.key.toLowerCase()} ${fmtAmount(e.value)} kg').join(', ')})'}'),
      ]);
}

/// Ewidencja sprzedaży RHD – kolejny numer w roku, data, produkt, ilość; przy firmach nazwa i adres odbiorcy.
Future<Uint8List> buildSalesRegister(int year, List<Map<String, dynamic>> sales, Map<String, String> owner, {bool rhd = true}) {
  final rows = _ofYear(sales, 'sold_on', year);
  final t = salesTotals(rows, year);
  final money = rows.fold<double>(0, (a, s) => a + qty(s['amount']));
  return _render(rhd ? 'Ewidencja sprzedaży RHD' : 'Ewidencja sprzedaży SB', (k) => [
        _head(k, rhd ? 'Ewidencja sprzedaży – rolniczy handel detaliczny' : 'Ewidencja sprzedaży – sprzedaż bezpośrednia', year, owner),
        k.grid(
          ['Lp.', 'Data', 'Produkt', 'Nr partii', 'Ilość [kg]', 'Odbiorca', 'Nazwa i adres odbiorcy (sklep / restauracja)', 'Kwota [zł]', 'Miejsce'],
          [
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                _d(rows[i]['sold_on']),
                'Miód ${'${rows[i]['product']}'.toLowerCase()}',
                '${rows[i]['lot'] ?? ''}',
                fmtAmount(qty(rows[i]['quantity'])),
                isBusiness(rows[i]) ? 'zakład' : 'konsument',
                isBusiness(rows[i]) ? '${rows[i]['buyer_name']}, ${rows[i]['buyer_address']}' : '',
                rows[i]['amount'] == null ? '' : fmtAmount(qty(rows[i]['amount'])),
                '${rows[i]['place'] ?? ''}',
              ],
          ],
          widths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FixedColumnWidth(60),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FixedColumnWidth(72),
            4: const pw.FixedColumnWidth(54),
            5: const pw.FixedColumnWidth(58),
            6: const pw.FlexColumnWidth(2.6),
            7: const pw.FixedColumnWidth(54),
            8: const pw.FlexColumnWidth(1.2),
          },
          emptyRows: 3,
        ),
        k.h2('Podsumowanie roku'),
        pw.Text('Sprzedaż konsumentom końcowym: ${fmtAmount(t.consumers)} kg'),
        pw.Text('Sprzedaż do zakładów (sklepy, restauracje): ${fmtAmount(t.business)} kg'
            '${rhd ? ' (limit RHD dla miodu: ${fmtAmount(rhdBusinessLimitKg)} kg/rok)' : ''}'),
        pw.Text('Razem: ${fmtAmount(t.consumers + t.business)} kg${money > 0 ? ', przychód ${fmtAmount(money)} zł' : ''}'),
      ]);
}
