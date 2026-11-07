import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'db.dart';

final _day = DateFormat('yyyy-MM-dd');

/// Kolor znakowania matek wg roku (międzynarodowy kod: ostatnia cyfra roku).
({String name, Color color}) queenColor(int? year) {
  if (year == null) return (name: '–', color: Colors.grey.shade400);
  switch (year % 5) {
    case 1:
      return (name: 'biały', color: Colors.white);
    case 2:
      return (name: 'żółty', color: Colors.yellow.shade600);
    case 3:
      return (name: 'czerwony', color: Colors.red.shade600);
    case 4:
      return (name: 'zielony', color: Colors.green.shade600);
    case 0:
      return (name: 'niebieski', color: Colors.blue.shade600);
    default:
      return (name: '–', color: Colors.grey);
  }
}

const diseases = ['Brak', 'Warroza', 'Zgnilec amerykański', 'Zgnilec europejski', 'Nosemoza', 'Grzybica wapienna', 'Wirus zdeformowanych skrzydeł', 'Inna'];

/// Zadania tworzone automatycznie. Jedno zadanie danego rodzaju na źródło (ref_id) – ponowny zapis je aktualizuje.
class AutoTasks {
  static Future<void> _upsert({
    required String source,
    required String refId,
    required String title,
    required DateTime due,
    String? apiaryId,
    String? hiveId,
  }) async {
    final existing = (await Db.instance.list('tasks'))
        .where((t) => t['source'] == source && t['ref_id'] == refId && !(t['done'] == true || t['done'] == 1))
        .toList();
    await Db.instance.save('tasks', {
      if (existing.isNotEmpty) ...existing.first,
      'source': source,
      'ref_id': refId,
      'title': title,
      'due_on': _day.format(due),
      'apiary_id': apiaryId,
      'hive_id': hiveId,
      'done': 0,
    });
  }

  static Future<void> _close(String source, String refId) async {
    for (final t in await Db.instance.list('tasks')) {
      if (t['source'] == source && t['ref_id'] == refId && !(t['done'] == true || t['done'] == 1)) {
        await Db.instance.remove('tasks', t['id'] as String);
      }
    }
  }

  static bool _on(dynamic v) => v == true || v == 1 || v == '1';

  /// Po przeglądzie: nastrój rojowy, brak czerwiu/jajek, brak pokarmu.
  static Future<void> fromInspection(Map<String, dynamic> ins, Map<String, dynamic> hive) async {
    final at = DateTime.tryParse('${ins['inspected_at']}') ?? DateTime.now();
    final hiveId = '${hive['id']}';
    final apiaryId = hive['apiary_id'] as String?;
    final no = 'ul ${hive['number'] ?? ''}';
    // Zadania wiążemy z ulem (a nie z przeglądem), żeby kolejny przegląd mógł je zamknąć.
    if (_on(ins['swarm_mood'])) {
      await _upsert(source: 'swarm', refId: hiveId, title: '$no: sprawdź nastrój rojowy', due: at.add(const Duration(days: 7)), apiaryId: apiaryId, hiveId: hiveId);
    } else {
      await _close('swarm', hiveId);
    }
    if (_on(ins['no_brood'])) {
      await _upsert(source: 'brood', refId: hiveId, title: '$no: brak czerwiu – sprawdź matkę', due: at.add(const Duration(days: 7)), apiaryId: apiaryId, hiveId: hiveId);
    } else {
      await _close('brood', hiveId);
    }
    if (_on(ins['no_stores'])) {
      await _upsert(source: 'stores', refId: hiveId, title: '$no: brak pokarmu – podkarm', due: at, apiaryId: apiaryId, hiveId: hiveId);
    } else {
      await _close('stores', hiveId);
    }
  }

  /// Po leczeniu: koniec okresu karencji.
  static Future<void> fromTreatment(Map<String, dynamic> t) async {
    final days = int.tryParse('${t['withdrawal_days']}') ?? 0;
    final start = DateTime.tryParse('${t['ended_on'] ?? t['treated_on']}');
    if (days <= 0 || start == null) {
      await _close('withdrawal', '${t['id']}');
      return;
    }
    await _upsert(
      source: 'withdrawal',
      refId: '${t['id']}',
      title: 'Koniec karencji: ${t['product']} (${t['hives_desc'] ?? ''})',
      due: start.add(Duration(days: days)),
      apiaryId: t['apiary_id'] as String?,
      hiveId: t['hive_id'] as String?,
    );
  }

  /// Po zapisie matki: do wymiany (na najbliższy sezon) albo do sprawdzenia (za tydzień).
  static Future<void> fromQueen(Map<String, dynamic> q, Map<String, dynamic> hive) async {
    final id = '${q['id']}';
    final no = 'ul ${hive['number'] ?? ''}';
    final active = '${q['removed_on'] ?? ''}'.isEmpty;
    if (active && _on(q['to_replace'])) {
      final now = DateTime.now();
      // Wymianę matek planujemy na maj–czerwiec; poza sezonem – na 15 maja następnego sezonu.
      final due = (now.month >= 5 && now.month <= 8) ? now.add(const Duration(days: 14)) : DateTime(now.month > 8 ? now.year + 1 : now.year, 5, 15);
      await _upsert(source: 'queen_replace', refId: id, title: '$no: wymień matkę', due: due, apiaryId: hive['apiary_id'] as String?, hiveId: '${hive['id']}');
    } else {
      await _close('queen_replace', id);
    }
    if (active && _on(q['to_check'])) {
      await _upsert(source: 'queen_check', refId: id, title: '$no: sprawdź matkę', due: DateTime.now().add(const Duration(days: 7)), apiaryId: hive['apiary_id'] as String?, hiveId: '${hive['id']}');
    } else {
      await _close('queen_check', id);
    }
  }

  /// Otwarte zadania, najbliższe pierwsze.
  static Future<List<Map<String, dynamic>>> open({String? hiveId}) async {
    final all = await Db.instance.list('tasks', where: hiveId == null ? null : {'hive_id': hiveId});
    final l = all.where((t) => !(t['done'] == true || t['done'] == 1)).toList()
      ..sort((a, b) => '${a['due_on']}'.compareTo('${b['due_on']}'));
    return l;
  }

  static Future<void> done(Map<String, dynamic> t) => Db.instance.save('tasks', {...t, 'done': 1});

  static String dueLabel(dynamic v) {
    final d = DateTime.tryParse('$v');
    if (d == null) return '';
    final today = DateTime.now();
    final diff = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (diff < 0) return 'zaległe ${-diff} dni';
    if (diff == 0) return 'dziś';
    if (diff == 1) return 'jutro';
    return DateFormat('d MMM', 'pl').format(d);
  }
}
