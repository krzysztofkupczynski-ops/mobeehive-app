import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Lokalna baza: te same tabele co na serwerze. Pełny rekord jest w kolumnie `data` (JSON),
/// a pola do wyszukiwania (apiary_id, hive_id, colony_id) są osobno.
/// `dirty = 1` oznacza zmianę jeszcze niewysłaną na serwer.
class Db {
  Db._();
  static final Db instance = Db._();

  static const tables = [
    'apiaries', 'hive_types', 'hives', 'colonies', 'queens',
    'inspections', 'treatments', 'feedings', 'tasks',
    'hygiene', 'harvests', 'sales',
  ];

  late Database _db;
  final _uuid = const Uuid();

  Future<void> open() async {
    final path = p.join(await getDatabasesPath(), 'mobeehive.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, _) => _createAll(db),
      // Nowe tabele w kolejnych wersjach – tworzone, jeśli ich brak.
      onUpgrade: (db, _, __) => _createAll(db),
    );
  }

  static Future<void> _createAll(Database db) async {
    for (final t in tables) {
      await db.execute('''CREATE TABLE IF NOT EXISTS $t (
        id TEXT PRIMARY KEY,
        apiary_id TEXT, hive_id TEXT, colony_id TEXT,
        data TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 0)''');
      await db.execute('CREATE INDEX IF NOT EXISTS ${t}_apiary ON $t(apiary_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS ${t}_hive ON $t(hive_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS ${t}_dirty ON $t(dirty)');
    }
    await db.execute('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)');
  }

  static int now() => DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> _row(Map<String, Object?> r) => jsonDecode(r['data'] as String) as Map<String, dynamic>;

  Map<String, Object?> _columns(Map<String, dynamic> rec, {required int dirty}) => {
        'id': rec['id'],
        'apiary_id': rec['apiary_id'],
        'hive_id': rec['hive_id'],
        'colony_id': rec['colony_id'],
        'data': jsonEncode(rec),
        'updated_at': rec['updated_at'] ?? 0,
        'deleted': rec['deleted'] == true || rec['deleted'] == 1 ? 1 : 0,
        'dirty': dirty,
      };

  /// Rekordy tabeli (bez usuniętych), opcjonalnie filtrowane po kolumnie, np. {'apiary_id': x}.
  Future<List<Map<String, dynamic>>> list(String table, {Map<String, String>? where, String? orderKey}) async {
    final conds = ['deleted = 0'];
    final args = <Object?>[];
    where?.forEach((k, v) {
      conds.add('$k = ?');
      args.add(v);
    });
    final rows = await _db.query(table, where: conds.join(' AND '), whereArgs: args);
    final list = rows.map(_row).toList();
    if (orderKey != null) {
      list.sort((a, b) => (a[orderKey] ?? '').toString().compareTo((b[orderKey] ?? '').toString()));
    }
    return list;
  }

  Future<Map<String, dynamic>?> get(String table, String id) async {
    final rows = await _db.query(table, where: 'id = ? AND deleted = 0', whereArgs: [id]);
    return rows.isEmpty ? null : _row(rows.first);
  }

  /// Zapis zmiany użytkownika: nadaje id, czasy i oznacza do wysłania.
  Future<Map<String, dynamic>> save(String table, Map<String, dynamic> rec) async {
    final t = now();
    final r = Map<String, dynamic>.from(rec);
    r['id'] ??= _uuid.v4();
    r['created_at'] ??= t;
    r['updated_at'] = t;
    r['deleted'] = false;
    await _db.insert(table, _columns(r, dirty: 1), conflictAlgorithm: ConflictAlgorithm.replace);
    return r;
  }

  Future<void> remove(String table, String id) async {
    final rows = await _db.query(table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final r = _row(rows.first)
      ..['deleted'] = true
      ..['updated_at'] = now();
    await _db.insert(table, _columns(r, dirty: 1), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> countActive(String table) async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $table WHERE deleted = 0')) ?? 0;

  /* ----------------------------- Synchronizacja ----------------------------- */

  Future<Map<String, List<Map<String, dynamic>>>> dirtyRows() async {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final t in tables) {
      final rows = await _db.query(t, where: 'dirty = 1');
      if (rows.isNotEmpty) out[t] = rows.map(_row).toList();
    }
    return out;
  }

  /// Po wysłaniu: zdejmuje flagę, o ile rekord nie zmienił się w trakcie synchronizacji.
  Future<void> markClean(String table, String id, int updatedAt) =>
      _db.update(table, {'dirty': 0}, where: 'id = ? AND updated_at = ?', whereArgs: [id, updatedAt]);

  /// Rekord z serwera: zapisuje, chyba że lokalnie jest nowsza, niewysłana wersja.
  Future<void> applyRemote(String table, Map<String, dynamic> rec) async {
    final rows = await _db.query(table, columns: ['updated_at', 'dirty'], where: 'id = ?', whereArgs: [rec['id']]);
    if (rows.isNotEmpty && rows.first['dirty'] == 1 && (rows.first['updated_at'] as int) > (rec['updated_at'] as int)) {
      return;
    }
    await _db.insert(table, _columns(rec, dirty: 0), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Usuwa lokalnie rekord, którego serwer nie przyjął (np. limit uli).
  Future<void> drop(String table, String id) => _db.delete(table, where: 'id = ?', whereArgs: [id]);

  Future<String?> meta(String key) async {
    final r = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> deleteMeta(String key) => _db.delete('meta', where: 'key = ?', whereArgs: [key]);

  Future<void> setMeta(String key, String value) =>
      _db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Czyści wszystko przy wylogowaniu.
  Future<void> wipe() async {
    for (final t in tables) {
      await _db.delete(t);
    }
    await _db.delete('meta');
  }
}
