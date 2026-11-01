import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'db.dart';

/// Powiatowy Inspektorat Weterynarii właściwy dla pasieki – z serwera, z kopią w telefonie.
class Piw {
  Piw(this.data);
  final Map<String, dynamic> data;

  String get name => '${data['name'] ?? ''}';
  String get plw => '${data['plw'] ?? ''}';
  String get address => '${data['address'] ?? ''}';
  String? get phone => data['phone'] as String?;
  String? get email => data['email'] as String?;
  String? get feeAccount => data['fee_account'] as String?;
  String? get note => data['note'] as String?;
  bool get verified => data['verified'] != false;
  List<Map<String, dynamic>> get forms => [for (final f in (data['forms'] as List? ?? [])) Map<String, dynamic>.from(f as Map)];

  /// Adresat wniosku: „Powiatowy Lekarz Weterynarii w …”, ulica, kod i miasto.
  String get addressee => '$plw\n${data['street'] ?? ''}\n${data['postcode'] ?? ''} ${data['city'] ?? ''}'.trim();

  static String? countyCode(Map<String, dynamic> apiary) {
    final m = RegExp(r'^(\d{4})').firstMatch('${apiary['teryt'] ?? ''}');
    return m?.group(1);
  }

  /// PIW dla pasieki. Bez zasięgu – ostatnio pobrany dla tego powiatu. Null, gdy powiat nieznany.
  static Future<Piw?> forApiary(Map<String, dynamic> apiary) async {
    final county = '${apiary['county'] ?? ''}';
    final code = countyCode(apiary);
    if (code == null && county.isEmpty) return null;
    final key = 'piw_${code ?? county}';
    try {
      final d = await Api.instance.piw(teryt: '${apiary['teryt'] ?? ''}', county: county);
      await Db.instance.setMeta(key, jsonEncode(d));
      return Piw(d);
    } on ApiException catch (e) {
      if (e.status == 404 || e.status == 400) throw e.message;
    } catch (_) {}
    final cached = await Db.instance.meta(key);
    return cached == null ? null : Piw(jsonDecode(cached) as Map<String, dynamic>);
  }

  /// Oryginalny wzór PIW – pobierany raz i trzymany w telefonie.
  static Future<File> templateFile(Map<String, dynamic> form) async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'wzory'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final url = '${form['url']}';
    final name = '${url.hashCode.toUnsigned(32)}_${p.basename(Uri.parse(url).path)}';
    final file = File(p.join(dir.path, name));
    if (await file.exists() && await file.length() > 0) return file;
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw 'Nie udało się pobrać wzoru (HTTP ${r.statusCode}).';
    await file.writeAsBytes(r.bodyBytes);
    return file;
  }
}

/// Wypełnione dokumenty zapisane w telefonie (lista w bazie lokalnej, pliki PDF w katalogu aplikacji).
class SavedDocs {
  static Future<Directory> _dir() async {
    final d = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'dokumenty'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final raw = await Db.instance.meta('saved_docs');
    final l = raw == null ? <Map<String, dynamic>>[] : [for (final e in jsonDecode(raw) as List) Map<String, dynamic>.from(e as Map)];
    l.sort((a, b) => '${b['created']}'.compareTo('${a['created']}'));
    return l;
  }

  static Future<Map<String, dynamic>> save(String title, String fileName, Uint8List bytes) async {
    final dir = await _dir();
    final now = DateTime.now();
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]+'), '_');
    final path = p.join(dir.path, '${now.millisecondsSinceEpoch}_$safe');
    await File(path).writeAsBytes(bytes);
    final entry = {'title': title, 'file': path, 'name': safe, 'created': now.toIso8601String()};
    final l = await list();
    l.insert(0, entry);
    await Db.instance.setMeta('saved_docs', jsonEncode(l));
    return entry;
  }

  static Future<void> remove(Map<String, dynamic> entry) async {
    final f = File('${entry['file']}');
    if (await f.exists()) await f.delete();
    final l = (await list()).where((e) => e['file'] != entry['file']).toList();
    await Db.instance.setMeta('saved_docs', jsonEncode(l));
  }
}
