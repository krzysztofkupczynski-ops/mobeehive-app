import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'db.dart';

/// Zdjęcia przeglądów: zapis w telefonie od razu, wysyłka na serwer w tle (kolejka), podgląd z pliku lub z serwera.
class Photos {
  static Future<Directory> _dir() async {
    final d = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'zdjecia'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> file(String id) async => File(p.join((await _dir()).path, '$id.jpg'));

  /// Przyjmuje zdjęcie (np. z aparatu), zwraca jego id i dopisuje do kolejki wysyłki.
  static Future<String> add(String sourcePath) async {
    final id = const Uuid().v4();
    await File(sourcePath).copy((await file(id)).path);
    final q = await _queue();
    q.add(id);
    await Db.instance.setMeta('photo_queue', jsonEncode(q));
    return id;
  }

  static Future<List<String>> _queue() async {
    final raw = await Db.instance.meta('photo_queue');
    return raw == null ? <String>[] : [for (final e in jsonDecode(raw) as List) '$e'];
  }

  /// Wysyła zaległe zdjęcia; wołane przy synchronizacji.
  static Future<void> upload() async {
    final q = await _queue();
    if (q.isEmpty) return;
    final token = await Api.instance.token();
    final left = <String>[];
    for (final id in q) {
      final f = await file(id);
      if (!await f.exists()) continue;
      try {
        final req = http.MultipartRequest('POST', Uri.parse('$apiBase/photo'))
          ..headers['Authorization'] = 'Bearer $token'
          ..fields['id'] = id
          ..files.add(await http.MultipartFile.fromPath('photo', f.path));
        final r = await req.send().timeout(const Duration(seconds: 90));
        if (r.statusCode != 200) left.add(id);
      } catch (_) {
        left.add(id);
      }
    }
    await Db.instance.setMeta('photo_queue', jsonEncode(left));
  }

  static List<String> ids(dynamic photos) {
    if (photos == null || '$photos'.isEmpty) return [];
    try {
      final v = photos is String ? jsonDecode(photos) : photos;
      return [for (final e in v as List) '$e'];
    } catch (_) {
      return [];
    }
  }
}

/// Miniatura zdjęcia: z telefonu, a gdy go nie ma (inne urządzenie) – z serwera.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.id, this.size = 96, this.onTap});
  final String id;
  final double size;
  final VoidCallback? onTap;

  Future<(File, String?)> _load() async => (await Photos.file(id), await Api.instance.token());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(File, String?)>(
      future: _load(),
      builder: (context, snap) {
        Widget img;
        if (!snap.hasData) {
          img = const Center(child: CircularProgressIndicator(strokeWidth: 2));
        } else if (snap.data!.$1.existsSync()) {
          img = Image.file(snap.data!.$1, fit: BoxFit.cover, width: size, height: size, cacheWidth: (size * 3).round());
        } else {
          img = Image.network('$apiBase/photo/$id',
              headers: {'Authorization': 'Bearer ${snap.data!.$2}'},
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined));
        }
        return GestureDetector(
          onTap: onTap,
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: size, height: size, child: img)),
        );
      },
    );
  }
}
