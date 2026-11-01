import 'package:flutter/material.dart';

import '../settings.dart';
import 'owner_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Sprzedaż miodu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Od tego zależy, które rejestry i dokumenty pokazuje aplikacja.'),
        ),
        for (final m in SalesMode.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Material(
              color: Settings.sales == m ? scheme.primaryContainer : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  await Settings.setSales(m);
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Settings.sales == m ? Icons.radio_button_checked : Icons.radio_button_off, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        Text(m.hint),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.badge_outlined, size: 30),
          title: const Text('Dane pszczelarza'),
          subtitle: const Text('Wpisywane do dokumentów, tylko w tym telefonie'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OwnerScreen())),
        ),
      ]),
    );
  }
}
