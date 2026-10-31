import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_base.dart';

/// Ewidencja stosowania produktów leczniczych weterynaryjnych u pszczół
/// (art. 108 rozporządzenia (UE) 2019/6; przechowywać co najmniej 5 lat).
Future<Uint8List> buildTreatmentRegister(
  int year,
  List<Map<String, dynamic>> treatments,
  Map<String, Map<String, dynamic>> apiaries,
  Map<String, Map<String, dynamic>> hives,
  Map<String, String> owner,
) async {
  final k = await PdfKit.load();
  final f = DateFormat('dd.MM.yyyy');
  String d(dynamic v) {
    final x = DateTime.tryParse('$v');
    return x == null ? '' : f.format(x);
  }

  final rows = treatments.where((t) => DateTime.tryParse('${t['treated_on']}')?.year == year).toList()
    ..sort((a, b) => '${a['treated_on']}'.compareTo('${b['treated_on']}'));

  final doc = k.doc('Ewidencja leczenia $year');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(26),
    footer: k.footer,
    build: (_) => [
      k.h1('Ewidencja stosowania produktów leczniczych weterynaryjnych – pszczoły – $year'),
      pw.Text('Posiadacz zwierząt: ${owner['name'] ?? '……………………………'}'
          '${(owner['city'] ?? '').isNotEmpty ? ', ${[owner['street'], owner['house'], owner['postcode'], owner['city']].where((e) => (e ?? '').isNotEmpty).join(' ')}' : ''}'),
      pw.Text('Podstawa: art. 108 rozporządzenia (UE) 2019/6. Ewidencję przechowuje się co najmniej 5 lat.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      pw.SizedBox(height: 8),
      k.grid(
        [
          'Lp.',
          'Data pierwszego podania\n(zakończenia)',
          'Pasieka (WNI)',
          'Leczone ule',
          'Produkt, nr serii',
          'Podana ilość',
          'Dostawca (nazwa, adres)',
          'Dowód nabycia',
          'Lekarz weterynarii',
          'Karencja\n(do dnia)',
          'Podpis',
        ],
        [
          for (var i = 0; i < rows.length; i++)
            () {
              final t = rows[i];
              final a = apiaries['${t['apiary_id']}'];
              final start = DateTime.tryParse('${t['treated_on']}');
              final end = DateTime.tryParse('${t['ended_on']}') ?? start;
              final w = int.tryParse('${t['withdrawal_days']}') ?? 0;
              final hiveNo = hives['${t['hive_id']}']?['number'];
              return [
                '${i + 1}',
                '${d(t['treated_on'])}${t['ended_on'] == null ? '' : '\n(${d(t['ended_on'])})'}',
                '${a?['name'] ?? ''}${(a?['vet_number'] ?? '').toString().isEmpty ? '' : '\n${a?['vet_number']}'}',
                '${t['hives_desc'] ?? (hiveNo == null ? '' : 'ul $hiveNo')}',
                '${t['product'] ?? ''}${(t['batch_number'] ?? '').toString().isEmpty ? '' : '\nseria ${t['batch_number']}'}',
                '${t['dose'] ?? ''}',
                '${t['supplier'] ?? ''}',
                '${t['purchase_doc'] ?? ''}',
                (t['vet'] ?? '').toString().isEmpty ? 'nie dotyczy' : '${t['vet']}',
                '$w dni${end == null ? '' : '\n(${f.format(end.add(Duration(days: w)))})'}',
                '',
              ];
            }(),
        ],
        widths: {
          0: const pw.FixedColumnWidth(22),
          1: const pw.FixedColumnWidth(62),
          2: const pw.FlexColumnWidth(1.2),
          3: const pw.FlexColumnWidth(1.4),
          4: const pw.FlexColumnWidth(1.2),
          5: const pw.FlexColumnWidth(1.1),
          6: const pw.FlexColumnWidth(1.6),
          7: const pw.FlexColumnWidth(1),
          8: const pw.FlexColumnWidth(1.1),
          9: const pw.FixedColumnWidth(58),
          10: const pw.FixedColumnWidth(50),
        },
        emptyRows: rows.length < 8 ? 8 - rows.length : 2,
      ),
    ],
  ));
  return doc.save();
}
