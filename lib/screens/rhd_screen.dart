import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db.dart';
import '../feeding.dart' show fmtAmount;
import '../rhd.dart';
import '../sync.dart';
import 'rhd_forms.dart';

/// Pracownia RHD: rejestr mycia i dezynfekcji, produkcja (miodobrania), sprzedaż.
class RhdScreen extends StatefulWidget {
  const RhdScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<RhdScreen> createState() => _RhdScreenState();
}

class _RhdScreenState extends State<RhdScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  List<Map<String, dynamic>> _hygiene = [];
  List<Map<String, dynamic>> _harvests = [];
  List<Map<String, dynamic>> _sales = [];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    SyncService.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_load);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = Db.instance;
    final hy = await db.list('hygiene', orderKey: 'done_at');
    final ha = await db.list('harvests', orderKey: 'harvested_on');
    final sa = await db.list('sales', orderKey: 'sold_on');
    if (!mounted) return;
    setState(() {
      _hygiene = hy.reversed.toList();
      _harvests = ha.reversed.toList();
      _sales = sa.reversed.toList();
    });
  }

  Future<void> _open(Widget page) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page));
    await _load();
    if (changed == true) SyncService.instance.run();
  }

  static String _d(dynamic v, [String f = 'd.MM.yyyy']) {
    final d = DateTime.tryParse('$v');
    return d == null ? '' : DateFormat(f, 'pl').format(d);
  }

  Widget _empty(String t) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t, textAlign: TextAlign.center)));

  Widget _hygieneTab() => _hygiene.isEmpty
      ? _empty('Brak wpisów. Zapisuj każde mycie i dezynfekcję pracowni oraz sprzętu.')
      : ListView(children: [
          for (final h in _hygiene)
            ListTile(
              leading: Icon(h['kind'] == 'Badanie wody'
                  ? Icons.water_outlined
                  : h['kind'] == 'Kontrola szkodników'
                      ? Icons.pest_control_outlined
                      : Icons.cleaning_services_outlined),
              title: Text('${h['kind'] ?? ''} · ${_d(h['done_at'], 'd.MM.yyyy, HH:mm')}'),
              subtitle: Text([h['area'], h['agent'], h['performed_by']].where((e) => '${e ?? ''}'.isNotEmpty).join(' · ')),
              onTap: () => _open(HygieneForm(entry: h)),
            ),
        ]);

  Widget _harvestTab() {
    final year = DateTime.now().year;
    final total = _harvests.where((h) => DateTime.tryParse('${h['harvested_on']}')?.year == year).fold<double>(0, (a, h) => a + qty(h['quantity']));
    return _harvests.isEmpty
        ? _empty('Brak miodobrań. Każde miodobranie to partia miodu z własnym numerem.')
        : ListView(children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: ListTile(
                leading: const Icon(Icons.scale_outlined, size: 30),
                title: Text('Zebrano w $year r.'),
                trailing: Text('${fmtAmount(total)} kg', style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            for (final h in _harvests)
              ListTile(
                leading: const Icon(Icons.hive_outlined),
                title: Text('${h['product']} · ${fmtAmount(qty(h['quantity']))} kg'),
                subtitle: Text('${_d(h['harvested_on'])} · partia ${h['lot'] ?? '–'}'),
                onTap: () => _open(HarvestForm(entry: h)),
              ),
          ]);
  }

  Widget _salesTab() {
    final year = DateTime.now().year;
    final t = salesTotals(_sales, year);
    final share = (t.business / rhdBusinessLimitKg).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    return ListView(children: [
      Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sprzedaż w $year r.', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Konsumenci: ${fmtAmount(t.consumers)} kg (bez limitu)'),
            const SizedBox(height: 4),
            Text('Sklepy i restauracje: ${fmtAmount(t.business)} z ${fmtAmount(rhdBusinessLimitKg)} kg'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 12,
                color: share >= 0.9 ? scheme.error : share >= 0.75 ? Colors.orange : scheme.primary,
              ),
            ),
          ]),
        ),
      ),
      if (_sales.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Brak sprzedaży.')),
      for (final s in _sales)
        ListTile(
          leading: Icon(isBusiness(s) ? Icons.storefront_outlined : Icons.person_outline),
          title: Text('${s['product']} · ${fmtAmount(qty(s['quantity']))} kg'),
          subtitle: Text([
            _d(s['sold_on']),
            if (isBusiness(s)) '${s['buyer_name']}',
            if ('${s['lot'] ?? ''}'.isNotEmpty) 'partia ${s['lot']}',
          ].join(' · ')),
          trailing: s['amount'] == null ? null : Text('${fmtAmount(qty(s['amount']))} zł'),
          onTap: () => _open(SaleForm(entry: s)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final add = [
      ('Mycie / dezynfekcja', Icons.cleaning_services_outlined, () => _open(const HygieneForm())),
      ('Miodobranie', Icons.add, () => _open(const HarvestForm())),
      ('Sprzedaż', Icons.point_of_sale_outlined, () => _open(const SaleForm())),
    ][_tabs.index];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pracownia RHD'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Higiena'), Tab(text: 'Produkcja'), Tab(text: 'Sprzedaż')]),
      ),
      body: TabBarView(controller: _tabs, children: [_hygieneTab(), _harvestTab(), _salesTab()]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 64,
            child: FilledButton.icon(
              onPressed: add.$3,
              icon: Icon(add.$2, size: 28),
              label: Text(add.$1, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}
