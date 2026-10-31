import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../db.dart';

/// Skaner kodu QR z ula. Zwraca id ula z Twoich pasiek.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static final _pattern = RegExp(r'^mobeehive:hive:([0-9a-f-]{36})$');
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handled = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final m = _pattern.firstMatch((b.rawValue ?? '').trim());
      if (m == null) {
        setState(() => _message = 'To nie jest kod ula Mobeehive.');
        continue;
      }
      final id = m.group(1)!;
      if (await Db.instance.get('hives', id) == null) {
        setState(() => _message = 'Tego ula nie ma w Twoich pasiekach.');
        continue;
      }
      _handled = true;
      if (mounted) Navigator.pop(context, id);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skanuj kod ula'),
        actions: [IconButton(tooltip: 'Latarka', onPressed: _controller.toggleTorch, icon: const Icon(Icons.flashlight_on_outlined))],
      ),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
          ),
        ),
        if (_message != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Material(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!, style: const TextStyle(color: Colors.white))),
            ),
          ),
      ]),
    );
  }
}
