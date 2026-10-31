import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../db.dart';

/// Ikona dla kodu pogody MET Norway (np. "partlycloudy_day", "lightrain").
IconData weatherIcon(String? code) {
  final c = code ?? '';
  if (c.contains('thunder')) return Icons.thunderstorm_outlined;
  if (c.contains('snow') || c.contains('sleet')) return Icons.ac_unit;
  if (c.contains('rain')) return Icons.water_drop_outlined;
  if (c.contains('fog')) return Icons.foggy;
  if (c.startsWith('cloudy')) return Icons.cloud_outlined;
  if (c.startsWith('partlycloudy') || c.startsWith('fair')) return Icons.wb_cloudy_outlined;
  if (c.startsWith('clearsky')) return c.endsWith('night') ? Icons.nightlight_outlined : Icons.wb_sunny_outlined;
  return Icons.cloud_queue;
}

String _n(num v) => NumberFormat('0.#', 'pl').format(v);

/// Pobiera prognozę; bez zasięgu zwraca ostatnią zapisaną w telefonie.
class WeatherRepo {
  static Future<(Map<String, dynamic>?, bool offline)> load(double lat, double lon) async {
    final key = 'wx_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
    try {
      final w = await Api.instance.weather(lat, lon);
      await Db.instance.setMeta(key, jsonEncode(w));
      return (w, false);
    } catch (_) {
      final cached = await Db.instance.meta(key);
      return (cached == null ? null : jsonDecode(cached) as Map<String, dynamic>, true);
    }
  }
}

/// Mała karta pogody na ekranie pasieki.
class WeatherCard extends StatefulWidget {
  const WeatherCard({super.key, required this.apiary});
  final Map<String, dynamic> apiary;

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  Map<String, dynamic>? _w;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WeatherCard old) {
    super.didUpdateWidget(old);
    if (old.apiary['lat'] != widget.apiary['lat'] || old.apiary['lng'] != widget.apiary['lng']) _load();
  }

  Future<void> _load() async {
    final lat = double.tryParse('${widget.apiary['lat']}');
    final lon = double.tryParse('${widget.apiary['lng']}');
    if (lat == null || lon == null) return;
    final (w, _) = await WeatherRepo.load(lat, lon);
    if (mounted) setState(() => _w = w);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lat = double.tryParse('${widget.apiary['lat']}');
    if (lat == null) {
      return const Card(
        margin: EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: ListTile(
          leading: Icon(Icons.location_off_outlined),
          title: Text('Ustaw lokalizację pasieki'),
          subtitle: Text('Edytuj pasiekę (ołówek u góry), żeby widzieć prognozę.'),
        ),
      );
    }
    final w = _w;
    final days = (w?['days'] as List?) ?? [];
    final today = days.isEmpty ? null : days.first as Map<String, dynamic>;
    final hours = (w?['hours'] as List?) ?? [];
    final now = hours.isEmpty ? null : hours.first as Map<String, dynamic>;
    final alerts = (w?['alerts'] as List?) ?? [];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: w == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WeatherScreen(apiary: widget.apiary))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: w == null
              ? const Row(children: [Icon(Icons.cloud_queue), SizedBox(width: 12), Text('Pobieranie prognozy…')])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(weatherIcon(now?['symbol'] as String?), size: 40, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text('${_n(now?['temp'] ?? 0)} °C', style: theme.textTheme.headlineMedium),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        today == null
                            ? ''
                            : 'Dziś ${_n(today['min'])}…${_n(today['max'])} °C\n'
                                '${today['flight_hours'] > 0 ? 'Lot pszczół: ok. ${today['flight_hours']} h' : 'Brak pogody lotnej'}',
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                  for (final a in alerts.take(2))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(a['type'] == 'frost' ? Icons.ac_unit : Icons.air, size: 20, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${_day(a['date'] as String)}: ${a['text']}', style: TextStyle(color: theme.colorScheme.error))),
                      ]),
                    ),
                ]),
        ),
      ),
    );
  }
}

String _day(String iso) {
  final d = DateTime.parse(iso);
  final today = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  if (diff == 0) return 'Dziś';
  if (diff == 1) return 'Jutro';
  final s = DateFormat('EEEE d.MM', 'pl').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

/// Pełna prognoza: alerty, najbliższe godziny (lot/przegląd), kolejne dni.
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key, required this.apiary});
  final Map<String, dynamic> apiary;

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  Map<String, dynamic>? _w;
  bool _offline = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (w, offline) = await WeatherRepo.load(double.parse('${widget.apiary['lat']}'), double.parse('${widget.apiary['lng']}'));
    if (!mounted) return;
    setState(() {
      _w = w;
      _offline = offline;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = _w;
    return Scaffold(
      appBar: AppBar(title: Text('Pogoda – ${widget.apiary['name'] ?? ''}')),
      body: w == null
          ? Center(child: _loading ? const CircularProgressIndicator() : const Text('Prognoza niedostępna – sprawdź połączenie.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                if (_offline)
                  const MaterialBanner(
                    leading: Icon(Icons.cloud_off_outlined),
                    content: Text('Brak połączenia – pokazuję ostatnią pobraną prognozę.'),
                    actions: [SizedBox()],
                  ),
                for (final a in (w['alerts'] as List))
                  Card(
                    color: theme.colorScheme.errorContainer,
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: ListTile(
                      leading: Icon(a['type'] == 'frost' ? Icons.ac_unit : Icons.air, color: theme.colorScheme.onErrorContainer),
                      title: Text('${_day(a['date'] as String)}: ${a['text']}', style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Najbliższe godziny', style: theme.textTheme.titleMedium),
                ),
                SizedBox(
                  height: 132,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final h in (w['hours'] as List).take(24)) _HourTile(h as Map<String, dynamic>),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Wrap(spacing: 16, children: [
                    _legend(Colors.green.shade400, 'pogoda lotna'),
                    _legend(theme.colorScheme.primary, 'dobra na przegląd'),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text('Kolejne dni', style: theme.textTheme.titleMedium),
                ),
                for (final d in (w['days'] as List)) _DayTile(d as Map<String, dynamic>),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    'Progi: ${w['thresholds']['flight']}; ${w['thresholds']['inspect']}.\n${w['attribution']}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(t, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _HourTile extends StatelessWidget {
  const _HourTile(this.h);
  final Map<String, dynamic> h;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = DateTime.parse(h['time'] as String).toLocal();
    final inspect = h['inspect'] == true;
    final flight = h['flight'] == true;
    return Container(
      width: 70,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            width: 6,
            color: inspect ? theme.colorScheme.primary : flight ? Colors.green.shade400 : Colors.transparent,
          ),
        ),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        Text(DateFormat('HH:mm').format(t), style: theme.textTheme.bodySmall),
        Icon(weatherIcon(h['symbol'] as String?)),
        Text('${_n(h['temp'])}°', style: theme.textTheme.titleMedium),
        Text('${_n(h['wind'])} m/s', style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile(this.d);
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = <String>[
      if ((d['flight_hours'] as num) > 0) 'lot ok. ${d['flight_hours']} h',
      if (d['good_inspection'] == true) 'dobry na przegląd',
      if ((d['rain'] as num) > 0) 'opad ${_n(d['rain'])} mm',
      'wiatr do ${_n(d['wind_max'])} m/s',
    ];
    return ListTile(
      leading: Icon(weatherIcon(d['symbol'] as String?), size: 32),
      title: Text(_day(d['date'] as String)),
      subtitle: Text(tags.join(' · ')),
      trailing: Text(
        '${_n(d['min'])}…${_n(d['max'])} °C',
        style: theme.textTheme.titleMedium?.copyWith(color: d['frost'] == true ? theme.colorScheme.error : null),
      ),
    );
  }
}
