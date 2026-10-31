import 'package:flutter/foundation.dart';

import 'api.dart';
import 'db.dart';

/// Wysyła lokalne zmiany i pobiera zmiany z serwera. Działa w tle; brak zasięgu nie jest błędem.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  bool running = false;
  String? lastError;
  DateTime? lastSync;
  final List<String> notices = [];

  /// Zwiększa się po każdej synchronizacji, która zmieniła dane – ekrany się odświeżają.
  int dataVersion = 0;

  void touch() {
    dataVersion++;
    notifyListeners();
  }

  Future<void> run() async {
    if (running || !Api.instance.loggedIn) return;
    running = true;
    lastError = null;
    notifyListeners();
    final db = Db.instance;
    try {
      var since = int.tryParse(await db.meta('cursor') ?? '0') ?? 0;
      var first = true;
      bool hasMore;
      do {
        final changes = first ? await db.dirtyRows() : <String, List<Map<String, dynamic>>>{};
        final res = await Api.instance.sync(since, changes);

        final rejected = <String>{};
        for (final r in (res['rejected'] as List? ?? [])) {
          final m = r as Map<String, dynamic>;
          rejected.add('${m['table']}/${m['id']}');
          if (m['reason'] == 'hive_limit') {
            await db.drop('hives', m['id'] as String);
            notices.add('Plan darmowy pozwala na ograniczoną liczbę uli – jeden ul nie został zapisany.');
          }
        }
        for (final entry in changes.entries) {
          for (final row in entry.value) {
            if (!rejected.contains('${entry.key}/${row['id']}')) {
              await db.markClean(entry.key, row['id'] as String, row['updated_at'] as int);
            }
          }
        }

        final remote = res['changes'] as Map<String, dynamic>? ?? {};
        for (final entry in remote.entries) {
          for (final rec in entry.value as List) {
            await db.applyRemote(entry.key, Map<String, dynamic>.from(rec as Map));
          }
        }
        since = (res['cursor'] as num).toInt();
        await db.setMeta('cursor', '$since');
        if (res['account'] is Map) {
          await Api.instance.updateAccount(Map<String, dynamic>.from(res['account'] as Map));
        }
        hasMore = res['has_more'] == true;
        first = false;
      } while (hasMore);
      lastSync = DateTime.now();
      dataVersion++;
    } on ApiException catch (e) {
      lastError = e.message;
    } catch (_) {
      lastError = 'Brak połączenia – zmiany zostaną wysłane później.';
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
