import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/// Wersje APK spoza sklepu (budowane z --dart-define=SIDELOAD=true) sprawdzają
/// nowe wersje na mobeehive.pl. Wersje ze sklepów aktualizuje sam sklep.
const bool sideload = bool.fromEnvironment('SIDELOAD');
const String _updateBase = 'https://mobeehive.pl/wp-json/mobeehive-update/v1';

class AppUpdater {
  static bool _checked = false;

  static Future<void> check(BuildContext context, {bool manual = false}) async {
    if (!sideload || (_checked && !manual) || !Api.instance.loggedIn) return;
    _checked = true;
    Map<String, dynamic> latest;
    int current;
    try {
      current = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      final r = await http
          .get(Uri.parse('$_updateBase/app-latest'), headers: {'Authorization': 'Bearer ${await Api.instance.token()}'})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return;
      latest = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return; // brak zasięgu – sprawdzimy przy następnym uruchomieniu
    }
    final code = (latest['version_code'] as num?)?.toInt() ?? 0;
    final required = ((latest['min_version_code'] as num?)?.toInt() ?? 0) > current;
    if (code <= current || latest['url'] == null) {
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Masz najnowszą wersję.')));
      }
      return;
    }
    if (!context.mounted) return;
    final mb = ((latest['size'] as num?) ?? 0) / 1048576;
    await showDialog<void>(
      context: context,
      barrierDismissible: !required,
      builder: (c) => PopScope(
        canPop: !required,
        child: AlertDialog(
          title: Text('Nowa wersja ${latest['version_name']}'),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (required) const Text('Ta aktualizacja jest wymagana.\n', style: TextStyle(fontWeight: FontWeight.bold)),
              if ((latest['notes'] ?? '').toString().isNotEmpty) Text('${latest['notes']}\n'),
              Text('Rozmiar: ${mb.toStringAsFixed(1)} MB. Po pobraniu otwórz plik, żeby zainstalować – '
                  'Twoje dane zostaną w telefonie.'),
            ]),
          ),
          actions: [
            if (!required) TextButton(onPressed: () => Navigator.pop(c), child: const Text('Później')),
            FilledButton(
              onPressed: () => launchUrl(Uri.parse(latest['url'] as String), mode: LaunchMode.externalApplication),
              child: const Text('Pobierz'),
            ),
          ],
        ),
      ),
    );
  }
}
