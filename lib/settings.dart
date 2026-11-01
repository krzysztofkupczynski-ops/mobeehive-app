import 'api.dart';
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

/// Ustawienia konta – trzymane na serwerze (wspólne dla urządzeń), z kopią w telefonie na czas bez zasięgu.
class Settings {
  static SalesMode _sales = SalesMode.none;
  static SalesMode get sales => _sales;

  static SalesMode _parse(String? v) => SalesMode.values.firstWhere((m) => m.name == v, orElse: () => SalesMode.none);

  /// Kopia lokalna; po zalogowaniu i synchronizacji nadpisywana ustawieniami z konta.
  static Future<void> load() async {
    final pending = await Db.instance.meta('sales_mode_pending');
    final fromAccount = (Api.instance.user?['account'] as Map?)?['settings'] as Map?;
    _sales = pending != null
        ? _parse(pending)
        : fromAccount != null
            ? _parse(fromAccount['sales_mode'] as String?)
            : _parse(await Db.instance.meta('sales_mode'));
  }

  /// Wywoływane po synchronizacji z danymi konta.
  static Future<void> applyAccount(Map<String, dynamic> account) async {
    final s = account['settings'];
    if (s is! Map) return;
    final pending = await Db.instance.meta('sales_mode_pending');
    if (pending != null) {
      // Zmiana zrobiona bez zasięgu – wyślij ją zamiast przyjmować wartość z serwera.
      await setSales(_parse(pending));
      return;
    }
    _sales = _parse(s['sales_mode'] as String?);
    await Db.instance.setMeta('sales_mode', _sales.name);
  }

  static Future<void> setSales(SalesMode m) async {
    _sales = m;
    await Db.instance.setMeta('sales_mode', m.name);
    try {
      await Api.instance.saveSettings({'sales_mode': m.name});
      await Db.instance.deleteMeta('sales_mode_pending');
      final acc = Api.instance.user?['account'];
      if (acc is Map) await Api.instance.updateAccount({...Map<String, dynamic>.from(acc), 'settings': {'sales_mode': m.name}});
    } catch (_) {
      await Db.instance.setMeta('sales_mode_pending', m.name);
    }
  }
}
