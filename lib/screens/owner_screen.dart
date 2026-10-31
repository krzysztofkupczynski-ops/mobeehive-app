import 'package:flutter/material.dart';

import '../owner.dart';
import '../widgets.dart';

/// Dane pszczelarza wpisywane do dokumentów.
class OwnerScreen extends StatefulWidget {
  const OwnerScreen({super.key});

  @override
  State<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends State<OwnerScreen> {
  final Map<String, TextEditingController> _c = {for (final (k, _) in Owner.fields) k: TextEditingController()};

  @override
  void initState() {
    super.initState();
    Owner.load().then((d) {
      if (!mounted) return;
      setState(() => d.forEach((k, v) => _c[k]?.text = v));
    });
  }

  Future<void> _save() async {
    await Owner.save({for (final e in _c.entries) e.key: e.value.text.trim()});
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dane pszczelarza')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Te dane trafiają do wniosków i ewidencji. Zapisują się tylko w tym telefonie.'),
        const SizedBox(height: 16),
        for (final (k, label) in Owner.fields) ...[
          TextField(
            controller: _c[k],
            decoration: InputDecoration(labelText: label),
            keyboardType: k == 'phone'
                ? TextInputType.phone
                : k == 'pesel'
                    ? TextInputType.number
                    : TextInputType.text,
          ),
          const SizedBox(height: 12),
        ],
      ]),
      bottomNavigationBar: BigSaveBar(label: 'Zapisz', onPressed: _save),
    );
  }
}
