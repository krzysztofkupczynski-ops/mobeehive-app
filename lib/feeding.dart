/// Sezony podkarmiania i podsumowania ilości.
library;

/// Sezon wg daty: wiosna (luty–czerwiec), jesień (lipiec–listopad), zima (grudzień–styczeń).
String seasonOf(DateTime d) {
  if (d.month >= 2 && d.month <= 6) return 'Wiosna ${d.year}';
  if (d.month >= 7 && d.month <= 11) return 'Jesień ${d.year}';
  return 'Zima ${d.month == 12 ? d.year : d.year - 1}/${(d.month == 12 ? d.year + 1 : d.year) % 100}';
}

/// Klucz do sortowania sezonów od najnowszego.
int _seasonOrder(DateTime d) => d.year * 10 + (d.month == 1 ? -7 : d.month <= 6 ? 1 : d.month <= 11 ? 2 : 3);

const feedTypes = ['Syrop 3:2', 'Syrop 1:1', 'Inwert', 'Ciasto', 'Miód', 'Inny'];

String fmtAmount(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// Suma podkarmiania w sezonie, osobno kg i l.
class SeasonTotal {
  SeasonTotal(this.season, this.order);
  final String season;
  final int order;
  double kg = 0;
  double l = 0;
  int entries = 0;
  final Set<String> hives = {};

  String get amount => [if (kg > 0) '${fmtAmount(kg)} kg', if (l > 0) '${fmtAmount(l)} l'].join(' + ');
}

/// Podsumowanie listy karmień (najnowszy sezon pierwszy).
List<SeasonTotal> seasonTotals(List<Map<String, dynamic>> feedings) {
  final map = <String, SeasonTotal>{};
  for (final f in feedings) {
    final d = DateTime.tryParse('${f['fed_on']}');
    if (d == null) continue;
    final s = map.putIfAbsent(seasonOf(d), () => SeasonTotal(seasonOf(d), _seasonOrder(d)));
    final a = double.tryParse('${f['amount']}') ?? 0;
    if (f['unit'] == 'l') {
      s.l += a;
    } else {
      s.kg += a;
    }
    s.entries++;
    if (f['hive_id'] != null) s.hives.add(f['hive_id'] as String);
  }
  return map.values.toList()..sort((a, b) => b.order.compareTo(a.order));
}
