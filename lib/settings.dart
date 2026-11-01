import 'db.dart';

/// Forma sprzedaży produktów pszczelich – decyduje, które moduły i dokumenty są widoczne.
enum SalesMode {
  none('Nie sprzedaję', 'Miód na własne potrzeby'),
  rhd('Rolniczy handel detaliczny (RHD)', 'Wpis do rejestru PLW, limit 2400 kg/rok do sklepów i restauracji'),
  sb('Sprzedaż bezpośrednia (SB)', 'Decyzja PLW po kontroli, projekt technologiczny');

  const SalesMode(this.label, this.hint);
  final String label;
  final String hint;

  /// Nazwa modułu pracowni w menu.
  String get workshop => this == rhd ? 'Pracownia RHD' : 'Pracownia SB';
}

class Settings {
  static SalesMode _sales = SalesMode.none;
  static SalesMode get sales => _sales;

  static Future<void> load() async {
    final v = await Db.instance.meta('sales_mode');
    _sales = SalesMode.values.firstWhere((m) => m.name == v, orElse: () => SalesMode.none);
  }

  static Future<void> setSales(SalesMode m) async {
    _sales = m;
    await Db.instance.setMeta('sales_mode', m.name);
  }
}
