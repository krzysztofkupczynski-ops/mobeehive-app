import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'db.dart';
import 'widgets.dart';

/// Bieżąca pozycja telefonu albo komunikat błędu (String).
Future<LatLng> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) throw 'Włącz lokalizację w telefonie.';
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    throw 'Aplikacja nie ma zgody na lokalizację – możesz ją dać w ustawieniach telefonu.';
  }
  final p = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 30)),
  );
  return LatLng(p.latitude, p.longitude);
}

/// Uzupełnia w pasiece województwo, powiat, gminę i TERYT na podstawie współrzędnych.
/// Zwraca zaktualizowany rekord albo null, gdy brak współrzędnych lub połączenia.
Future<Map<String, dynamic>?> resolveRegion(Map<String, dynamic> apiary, {bool save = true}) async {
  final lat = double.tryParse('${apiary['lat']}');
  final lng = double.tryParse('${apiary['lng']}');
  if (lat == null || lng == null) return null;
  try {
    final r = await Api.instance.region(lat, lng);
    final updated = {
      ...apiary,
      'voivodeship': r['voivodeship'],
      'county': r['county'],
      'commune': r['commune'],
      'teryt': r['teryt'],
    };
    if (save) await Db.instance.save('apiaries', updated);
    return updated;
  } catch (_) {
    return null;
  }
}

String regionLabel(Map<String, dynamic> a) {
  final parts = [a['commune'], a['county'], a['voivodeship'] == null ? null : 'woj. ${a['voivodeship']}']
      .where((e) => '${e ?? ''}'.isNotEmpty)
      .toList();
  return parts.join(', ');
}

/// Wybór miejsca pasieki na mapie (OpenStreetMap). Zwraca wybrany punkt.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.initial});
  final LatLng? initial;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _poland = LatLng(52.07, 19.48);
  final _map = MapController();
  late LatLng? _point = widget.initial;
  bool _locating = false;

  Future<void> _here() async {
    setState(() => _locating = true);
    try {
      final p = await currentPosition();
      setState(() => _point = p);
      _map.move(p, 16);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is String ? e : 'Nie udało się ustalić lokalizacji.')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Miejsce pasieki')),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: widget.initial ?? _poland,
            initialZoom: widget.initial == null ? 6 : 16,
            onTap: (_, p) => setState(() => _point = p),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'pl.mobeehive.mobeehive',
            ),
            if (_point != null)
              MarkerLayer(markers: [
                Marker(
                  point: _point!,
                  width: 56,
                  height: 56,
                  alignment: Alignment.topCenter,
                  child: Icon(Icons.location_on, size: 56, color: scheme.primary),
                ),
              ]),
            RichAttributionWidget(attributions: [
              TextSourceAttribution('OpenStreetMap', onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'))),
            ]),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _point == null
                    ? 'Dotknij mapy w miejscu, gdzie stoją ule.'
                    : '${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)} – dotknij, żeby poprawić.',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.large(
            heroTag: 'here',
            tooltip: 'Moja lokalizacja',
            onPressed: _locating ? null : _here,
            child: _locating ? const CircularProgressIndicator() : const Icon(Icons.my_location, size: 36),
          ),
        ),
      ]),
      bottomNavigationBar: _point == null
          ? null
          : BigSaveBar(
              label: 'Wybierz to miejsce',
              onPressed: () => Navigator.pop(
                context,
                LatLng(double.parse(_point!.latitude.toStringAsFixed(5)), double.parse(_point!.longitude.toStringAsFixed(5))),
              ),
            ),
    );
  }
}
