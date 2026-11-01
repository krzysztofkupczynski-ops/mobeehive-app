import 'dart:convert';

import 'db.dart';

/// Dane pszczelarza do dokumentów. Przechowywane tylko w telefonie (PESEL nie trafia na serwer).
class Owner {
  static const fields = <(String, String)>[
    ('name', 'Imię i nazwisko (lub nazwa firmy)'),
    ('city', 'Miejscowość'),
    ('street', 'Ulica'),
    ('house', 'Nr domu'),
    ('flat', 'Nr lokalu'),
    ('postcode', 'Kod pocztowy'),
    ('post', 'Poczta'),
    ('pesel', 'PESEL (NIP w przypadku firmy)'),
    ('ep', 'Numer gospodarstwa z ARiMR (EP) lub KRS'),
    ('phone', 'Telefon'),
    ('email', 'E-mail / strona / adres do e-Doręczeń'),
    ('delivery', 'Adres do doręczeń (jeśli inny)'),
  ];

  static Future<Map<String, String>> load() async {
    final raw = await Db.instance.meta('owner');
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  static Future<void> save(Map<String, String> data) => Db.instance.setMeta('owner', jsonEncode(data));

  /// Ostatnio użyty adresat wniosków (PLW), żeby nie wpisywać za każdym razem.
  static Future<String> piw() async => await Db.instance.meta('piw') ?? '';
  static Future<void> savePiw(String v) => Db.instance.setMeta('piw', v);
}
