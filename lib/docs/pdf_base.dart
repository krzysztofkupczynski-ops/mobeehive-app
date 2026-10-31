import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Wspólne elementy dokumentów PDF (czcionka z polskimi znakami, nagłówki, tabele).
class PdfKit {
  PdfKit._(this.regular, this.bold);
  final pw.Font regular;
  final pw.Font bold;

  static PdfKit? _cached;

  static Future<PdfKit> load() async {
    if (_cached != null) return _cached!;
    final r = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final b = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
    return _cached = PdfKit._(r, b);
  }

  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: bold).copyWith(
        defaultTextStyle: pw.TextStyle(font: regular, fontSize: 9.5),
      );

  pw.Document doc(String title) => pw.Document(title: title, author: 'Mobeehive', theme: theme);

  static String today() => DateFormat('dd.MM.yyyy').format(DateTime.now());

  pw.Widget h1(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 10),
        child: pw.Text(t, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 12.5)),
      );

  pw.Widget h2(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 10.5)),
      );

  /// Tabela „etykieta – wartość”; puste wartości zostają jako miejsce do ręcznego wpisu.
  pw.Widget fields(List<(String, String?)> rows) => pw.Table(
        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey700),
        columnWidths: {0: const pw.FlexColumnWidth(2.2), 1: const pw.FlexColumnWidth(3)},
        children: [
          for (final (label, value) in rows)
            pw.TableRow(children: [
              pw.Container(
                color: PdfColors.grey200,
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Container(
                constraints: const pw.BoxConstraints(minHeight: 20),
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(value ?? ''),
              ),
            ]),
        ],
      );

  /// Tabela z nagłówkiem kolumn (ewidencje).
  pw.Widget grid(List<String> headers, List<List<String>> rows, {Map<int, pw.TableColumnWidth>? widths, int emptyRows = 0}) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: [
          ...rows,
          for (var i = 0; i < emptyRows; i++) List.filled(headers.length, ' '),
        ],
        columnWidths: widths,
        border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey700),
        headerStyle: pw.TextStyle(font: bold, fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        cellHeight: 18,
        cellAlignment: pw.Alignment.centerLeft,
        headerAlignment: pw.Alignment.center,
      );

  pw.Widget signature(String label) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 28),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Column(children: [
            pw.Container(width: 200, height: 0.6, color: PdfColors.black),
            pw.SizedBox(height: 3),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          ]),
        ]),
      );

  pw.Widget footer(pw.Context c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Wygenerowano w aplikacji Mobeehive', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        pw.Text('Strona ${c.pageNumber} z ${c.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ]);
}
