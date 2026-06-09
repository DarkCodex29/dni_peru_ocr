import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/material.dart';

import 'scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const String _libraryName = 'dni_peru_ocr';
  static const String _libraryVersion = '0.11.0';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Preset _selected = _Preset.full;
  Set<DniField> _customFields = <DniField>{DniField.documentNumber};

  DniFields _resolveFields() {
    return switch (_selected) {
      _Preset.minimal => DniFields.minimal(),
      _Preset.kyc => DniFields.kyc(),
      _Preset.full => DniFields.full(),
      _Preset.custom => DniFields.required(_customFields),
    };
  }

  Future<void> _openCustomEditor() async {
    final result = await showModalBottomSheet<Set<DniField>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CustomFieldsSheet(initial: _customFields),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _customFields = result;
        _selected = _Preset.custom;
      });
    }
  }

  void _startScan() {
    final fields = _resolveFields();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanScreen(fields: fields),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCount = _resolveFields().length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ejemplo'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                HomeScreen._libraryName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'v${HomeScreen._libraryVersion}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Elegí qué campos querés extraer',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'La library solo activa los extractores necesarios para los campos seleccionados. Menos CPU, menos batería.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              _PresetTile(
                preset: _Preset.minimal,
                title: 'Minimal',
                description: 'DNI + nombres + apellidos',
                count: 4,
                selected: _selected == _Preset.minimal,
                onTap: () => setState(() => _selected = _Preset.minimal),
              ),
              const SizedBox(height: 8),
              _PresetTile(
                preset: _Preset.kyc,
                title: 'KYC',
                description: 'Identidad + fechas + dirección',
                count: 7,
                selected: _selected == _Preset.kyc,
                onTap: () => setState(() => _selected = _Preset.kyc),
              ),
              const SizedBox(height: 8),
              _PresetTile(
                preset: _Preset.full,
                title: 'Full',
                description: 'Todos los campos disponibles',
                count: 19,
                selected: _selected == _Preset.full,
                onTap: () => setState(() => _selected = _Preset.full),
              ),
              const SizedBox(height: 8),
              _PresetTile(
                preset: _Preset.custom,
                title: 'Custom',
                description: _selected == _Preset.custom
                    ? '${_customFields.length} campos seleccionados — toca para editar'
                    : 'Definí tu propio set',
                count: _selected == _Preset.custom ? _customFields.length : null,
                selected: _selected == _Preset.custom,
                onTap: _openCustomEditor,
                trailingIcon: Icons.tune,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$activeCount campos activos en el próximo scan',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Iniciar escaneo'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Se requiere un dispositivo físico.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Preset { minimal, kyc, full, custom }

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.count,
    this.trailingIcon,
  });

  final _Preset preset;
  final String title;
  final String description;
  final int? count;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? colors.primary : colors.outline,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? colors.onPrimaryContainer
                                : colors.onSurface,
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? colors.primary
                                  : colors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                color: selected
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? colors.onPrimaryContainer
                            : colors.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(
                  trailingIcon,
                  size: 18,
                  color: selected ? colors.primary : colors.outline,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomFieldsSheet extends StatefulWidget {
  const _CustomFieldsSheet({required this.initial});

  final Set<DniField> initial;

  @override
  State<_CustomFieldsSheet> createState() => _CustomFieldsSheetState();
}

class _CustomFieldsSheetState extends State<_CustomFieldsSheet> {
  late Set<DniField> _selection;

  @override
  void initState() {
    super.initState();
    _selection = {...widget.initial};
  }

  void _toggle(DniField field) {
    setState(() {
      if (_selection.contains(field)) {
        if (_selection.length > 1) _selection.remove(field);
      } else {
        _selection.add(field);
      }
    });
  }

  void _selectAll() {
    setState(() => _selection = DniField.values.toSet());
  }

  void _reset() {
    setState(() => _selection = {DniField.documentNumber});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Campos custom',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
                TextButton(
                  onPressed: _selectAll,
                  child: const Text('Todos'),
                ),
              ],
            ),
            Text(
              '${_selection.length} seleccionados',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: DniField.values.map((f) {
                    final selected = _selection.contains(f);
                    return FilterChip(
                      label: Text(_labelFor(f)),
                      selected: selected,
                      onSelected: (_) => _toggle(f),
                      showCheckmark: false,
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_selection),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Aplicar (${_selection.length} campos)'),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _labelFor(DniField field) {
    return switch (field) {
      DniField.documentNumber => 'DNI',
      DniField.firstName => 'Nombres',
      DniField.lastName => 'Apellido paterno',
      DniField.secondLastName => 'Apellido materno',
      DniField.dateOfBirth => 'Nacimiento',
      DniField.expirationDate => 'Caducidad',
      DniField.emissionDate => 'Emisión',
      DniField.inscriptionDate => 'Inscripción',
      DniField.sex => 'Sexo',
      DniField.nationality => 'Nacionalidad',
      DniField.address => 'Dirección',
      DniField.department => 'Departamento',
      DniField.province => 'Provincia',
      DniField.district => 'Distrito',
      DniField.stateCivil => 'Estado civil',
      DniField.cardNumber => 'Nro tarjeta',
      DniField.organDonor => 'Donación',
      DniField.votingGroup => 'Grupo votación',
      DniField.birthUbigeoCode => 'Ubigeo nacimiento',
    };
  }
}
