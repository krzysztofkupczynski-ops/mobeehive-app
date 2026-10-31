/// Stałe i obliczenia dla rolniczego handlu detalicznego (RHD).
library;

/// Roczny limit miodu sprzedawanego do sklepów i restauracji w RHD (kg).
/// Sprzedaż konsumentom końcowym nie jest limitowana.
const double rhdBusinessLimitKg = 2400;

const hygieneKinds = ['Mycie', 'Dezynfekcja', 'Mycie i dezynfekcja', 'Kontrola szkodników', 'Badanie wody', 'Inne'];

const hygieneAreas = [
  'Pracownia – podłoga',
  'Pracownia – ściany',
  'Blaty i stoły',
  'Miodarka',
  'Stół do odsklepiania',
  'Sita',
  'Odstojniki',
  'Słoiki i wieczka',
  'Narzędzia',
  'Umywalka i zlew',
];

const honeyKinds = [
  'Wielokwiatowy', 'Rzepakowy', 'Akacjowy', 'Lipowy', 'Gryczany',
  'Wrzosowy', 'Spadziowy', 'Faceliowy', 'Nawłociowy', 'Inny',
];

/// Proponowany numer partii: rok, skrót rodzaju, kolejny numer, np. „2026-RZ-02”.
String suggestLot(DateTime date, String product, List<Map<String, dynamic>> harvests) {
  final code = product.length >= 2 ? product.substring(0, 2).toUpperCase() : 'MI';
  final prefix = '${date.year}-$code-';
  var n = 1;
  for (final h in harvests) {
    final lot = '${h['lot'] ?? ''}';
    if (lot.startsWith(prefix)) {
      final k = int.tryParse(lot.substring(prefix.length)) ?? 0;
      if (k >= n) n = k + 1;
    }
  }
  return '$prefix${n.toString().padLeft(2, '0')}';
}

double qty(dynamic v) => double.tryParse('$v') ?? 0;

bool isBusiness(Map<String, dynamic> sale) => sale['buyer_type'] == 'business';

/// Sprzedaż w roku: konsumenci i firmy osobno (kg).
({double consumers, double business}) salesTotals(List<Map<String, dynamic>> sales, int year) {
  var c = 0.0, b = 0.0;
  for (final s in sales) {
    final d = DateTime.tryParse('${s['sold_on']}');
    if (d == null || d.year != year) continue;
    if (isBusiness(s)) {
      b += qty(s['quantity']);
    } else {
      c += qty(s['quantity']);
    }
  }
  return (consumers: c, business: b);
}
