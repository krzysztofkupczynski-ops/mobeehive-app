import 'package:flutter/material.dart';

/// Duże elementy do obsługi w rękawicach, jedną ręką.

/// Kafelek tak/nie (np. „Matka widziana”).
class BigToggle extends StatelessWidget {
  const BigToggle({super.key, required this.label, required this.icon, required this.value, required this.onChanged});
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: value ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!value),
        child: SizedBox(
          height: 76,
          child: Row(children: [
            const SizedBox(width: 14),
            Icon(value ? Icons.check_circle : icon, size: 30, color: value ? scheme.onPrimary : scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: value ? scheme.onPrimary : scheme.onSurface)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Siatka kafelków po dwa w rzędzie.
class BigGrid extends StatelessWidget {
  const BigGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: children[i]),
          const SizedBox(width: 10),
          Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
        ]),
      ));
    }
    return Column(children: rows);
  }
}

/// Wybór jednej wartości dużymi przyciskami (np. siła 1–5). Ponowne kliknięcie odznacza.
class BigChoice<T> extends StatelessWidget {
  const BigChoice({super.key, required this.label, required this.options, required this.value, required this.onChanged, this.hint});
  final String label;
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        if (hint != null) Text(hint!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (v, text) in options)
            SizedBox(
              height: 60,
              child: Material(
                color: v == value ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onChanged(v == value ? null : v),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 60),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Center(
                        child: Text(text,
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600, color: v == value ? scheme.onPrimary : scheme.onSurface)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

/// Licznik z dużymi przyciskami − / +.
class BigCounter extends StatelessWidget {
  const BigCounter({super.key, required this.label, required this.value, required this.onChanged, this.step = 1, this.unit = ''});
  final String label;
  final num value;
  final ValueChanged<num> onChanged;
  final num step;
  final String unit;

  @override
  Widget build(BuildContext context) {
    String fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
        SizedBox(
          width: 60,
          height: 60,
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: value > 0 ? () => onChanged((value - step) < 0 ? 0 : value - step) : null,
            child: const Icon(Icons.remove, size: 30),
          ),
        ),
        SizedBox(
          width: 84,
          child: Text('${fmt(value)}$unit', textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          width: 60,
          height: 60,
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () => onChanged(value + step),
            child: const Icon(Icons.add, size: 30),
          ),
        ),
      ]),
    );
  }
}

/// Duży przycisk zapisu przyklejony do dołu ekranu.
class BigSaveBar extends StatelessWidget {
  const BigSaveBar({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 64,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.check, size: 28),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600))),
            ),
          ),
        ),
      );
}

/// Akcja dolnego paska: ikona nad podpisem.
class BarAction {
  const BarAction(this.label, this.icon, this.onTap, {this.primary = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;
}

/// Dolny pasek dużych przycisków. Podpis zawsze w jednej linii (zmniejsza się przy dużej czcionce systemowej).
class BigActionBar extends StatelessWidget {
  const BigActionBar({super.key, required this.actions});
  final List<BarAction> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          for (final (i, a) in actions.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 76,
                child: Material(
                  color: a.onTap == null
                      ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                      : a.primary
                          ? scheme.primary
                          : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: a.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(a.icon, size: 30, color: a.primary ? scheme.onPrimary : scheme.onSecondaryContainer),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            a.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: a.primary ? scheme.onPrimary : scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
