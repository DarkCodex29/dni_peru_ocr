import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/primary_button.dart';

class ResultScreenV2 extends StatelessWidget {
  const ResultScreenV2({
    super.key,
    required this.fields,
    this.format = DniFormat.unknown,
    this.frontPhoto,
    this.backPhoto,
    this.selectedFields,
    this.reniecEnriched = false,
  });

  final ExtractedFields fields;
  final DniFormat format;
  final XFile? frontPhoto;
  final XFile? backPhoto;
  final DniFields? selectedFields;
  final bool reniecEnriched;

  static const Map<String, DniField> _fieldKeyMap = {
    'documentNumber': DniField.documentNumber,
    'firstName': DniField.firstName,
    'lastName': DniField.lastName,
    'secondLastName': DniField.secondLastName,
    'dateOfBirth': DniField.dateOfBirth,
    'expirationDate': DniField.expirationDate,
    'emissionDate': DniField.emissionDate,
    'inscriptionDate': DniField.inscriptionDate,
    'sex': DniField.sex,
    'nationality': DniField.nationality,
    'address': DniField.address,
    'department': DniField.department,
    'province': DniField.province,
    'district': DniField.district,
    'stateCivil': DniField.stateCivil,
    'cardNumber': DniField.cardNumber,
    'organDonor': DniField.organDonor,
    'votingGroup': DniField.votingGroup,
    'birthUbigeoCode': DniField.birthUbigeoCode,
  };

  bool _isSelected(String name) {
    final filter = selectedFields;
    if (filter == null) return true;
    if (filter.length == DniField.values.length) return true;
    final mapped = _fieldKeyMap[name];
    if (mapped == null) return true;
    return filter.contains(mapped);
  }

  bool _applies(String name) => format.fieldApplies(name);

  Widget? _cardIfSelected(String label, String? value, String fieldKey) {
    if (!_isSelected(fieldKey)) return null;
    return _FieldCard(
      label: label,
      value: value,
      applies: _applies(fieldKey),
    );
  }

  String _resultAsText() {
    final lines = <String>[
      '— Identidad —',
      'Documento: ${fields.documentNumber ?? '-'}',
      'Primer apellido: ${fields.lastName ?? '-'}',
      'Segundo apellido: ${fields.secondLastName ?? '-'}',
      'Prenombres: ${fields.firstName ?? '-'}',
      'Sexo: ${fields.sex ?? '-'}',
      'Nacionalidad: ${fields.nationality ?? '-'}',
      'Estado civil: ${fields.stateCivil ?? '-'}',
      '',
      '— Fechas —',
      'Nacimiento: ${fields.dateOfBirth ?? '-'}',
      'Inscripción: ${fields.inscriptionDate ?? '-'}',
      'Emisión: ${fields.emissionDate ?? '-'}',
      'Caducidad: ${fields.expirationDate ?? '-'}',
      '',
      '— Domicilio —',
      'Dirección: ${fields.address ?? '-'}',
      'Departamento: ${fields.department ?? '-'}',
      'Provincia: ${fields.province ?? '-'}',
      'Distrito: ${fields.district ?? '-'}',
      '',
      '— Documento adicional —',
      'Nro tarjeta: ${fields.cardNumber ?? '-'}',
      'Donación de órganos: ${fields.organDonor ?? '-'}',
      'Grupo de votación: ${fields.votingGroup ?? '-'}',
      'Ubigeo nacimiento: ${fields.birthUbigeoCode ?? '-'}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final completeness = DniCompleteness.compute(fields, format);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado'),
        actions: [
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _resultAsText()));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copiado al portapapeles')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              if (frontPhoto != null || backPhoto != null) ...[
                _PhotosRow(frontPhoto: frontPhoto, backPhoto: backPhoto),
                const SizedBox(height: 12),
              ],
              _SummaryBanner(
                filled: completeness.detected,
                total: completeness.expected,
                format: format,
              ),
              if (reniecEnriched) ...[
                const SizedBox(height: 8),
                const _ReniecEnrichedPill(),
              ],
              if (completeness.ratio < 0.75 &&
                  completeness.expected > 0) ...[
                const SizedBox(height: 10),
                _RescanHint(
                  missing: completeness.missing,
                  onRescan: () => Navigator.of(context)
                      .popUntil((route) => route.isFirst),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    _SectionIfAny(title: 'Identidad', cards: [
                      _cardIfSelected('Documento', fields.documentNumber,
                          'documentNumber'),
                      _cardIfSelected(
                          'Primer apellido', fields.lastName, 'lastName'),
                      _cardIfSelected('Segundo apellido',
                          fields.secondLastName, 'secondLastName'),
                      _cardIfSelected(
                          'Prenombres', fields.firstName, 'firstName'),
                      _cardIfSelected('Sexo', fields.sex, 'sex'),
                      _cardIfSelected(
                          'Nacionalidad', fields.nationality, 'nationality'),
                      _cardIfSelected(
                          'Estado civil', fields.stateCivil, 'stateCivil'),
                    ]),
                    _SectionIfAny(title: 'Fechas', cards: [
                      _cardIfSelected(
                          'Nacimiento', fields.dateOfBirth, 'dateOfBirth'),
                      _cardIfSelected('Inscripción', fields.inscriptionDate,
                          'inscriptionDate'),
                      _cardIfSelected(
                          'Emisión', fields.emissionDate, 'emissionDate'),
                      _cardIfSelected('Caducidad', fields.expirationDate,
                          'expirationDate'),
                    ]),
                    _SectionIfAny(title: 'Domicilio', cards: [
                      _cardIfSelected('Dirección', fields.address, 'address'),
                      _cardIfSelected(
                          'Departamento', fields.department, 'department'),
                      _cardIfSelected(
                          'Provincia', fields.province, 'province'),
                      _cardIfSelected('Distrito', fields.district, 'district'),
                    ]),
                    _SectionIfAny(title: 'Documento adicional', cards: [
                      _cardIfSelected(
                          'Nro tarjeta', fields.cardNumber, 'cardNumber'),
                      _cardIfSelected('Donación de órganos', fields.organDonor,
                          'organDonor'),
                      _cardIfSelected('Grupo de votación', fields.votingGroup,
                          'votingGroup'),
                      _cardIfSelected('Ubigeo nacimiento',
                          fields.birthUbigeoCode, 'birthUbigeoCode'),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Escanear otro',
                icon: Icons.refresh,
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({
    required this.filled,
    required this.total,
    required this.format,
  });

  final int filled;
  final int total;
  final DniFormat format;

  Color _color(ColorScheme colors) {
    final ratio = total == 0 ? 0 : filled / total;
    if (ratio < 0.4) return colors.errorContainer;
    if (ratio < 0.75) return colors.tertiaryContainer;
    return colors.primaryContainer;
  }

  Color _onColor(ColorScheme colors) {
    final ratio = total == 0 ? 0 : filled / total;
    if (ratio < 0.4) return colors.onErrorContainer;
    if (ratio < 0.75) return colors.onTertiaryContainer;
    return colors.onPrimaryContainer;
  }

  String _formatLabel() {
    switch (format) {
      case DniFormat.azulBooklet:
        return 'DNI azul';
      case DniFormat.modelo2020:
        return 'Modelo 2020';
      case DniFormat.unknown:
        return 'Formato no detectado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress = total == 0 ? 0.0 : filled / total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _color(colors),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            filled == total ? Icons.check_circle : Icons.info_outline,
            color: _onColor(colors),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Campos detectados: $filled / $total',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: _onColor(colors),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _onColor(colors).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _formatLabel(),
                        style: TextStyle(
                          color: _onColor(colors),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: _onColor(colors).withValues(alpha: 0.2),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(_onColor(colors)),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
          child: Text(
            title.toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _SectionIfAny extends StatelessWidget {
  const _SectionIfAny({required this.title, required this.cards});

  final String title;
  final List<Widget?> cards;

  @override
  Widget build(BuildContext context) {
    final visible = cards.whereType<Widget>().toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return _Section(title: title, children: visible);
  }
}

enum _FieldStatus { detected, missing, notApplicable }

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.label,
    required this.value,
    this.applies = true,
  });

  final String label;
  final String? value;
  final bool applies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasValue = value != null && value!.isNotEmpty;
    final status = !applies
        ? _FieldStatus.notApplicable
        : hasValue
            ? _FieldStatus.detected
            : _FieldStatus.missing;

    final borderColor = switch (status) {
      _FieldStatus.detected => colors.outlineVariant,
      _FieldStatus.missing => colors.error.withValues(alpha: 0.45),
      _FieldStatus.notApplicable => colors.outline.withValues(alpha: 0.2),
    };
    final valueText = switch (status) {
      _FieldStatus.detected => value!,
      _FieldStatus.missing => 'No detectado',
      _FieldStatus.notApplicable => 'No aplica',
    };
    final valueColor = switch (status) {
      _FieldStatus.detected => colors.onSurface,
      _FieldStatus.missing => colors.error,
      _FieldStatus.notApplicable => colors.outline.withValues(alpha: 0.7),
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    valueText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontStyle: status == _FieldStatus.detected
                          ? FontStyle.normal
                          : FontStyle.italic,
                      fontWeight: status == _FieldStatus.detected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: valueColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _StatusChip(status: status),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _FieldStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, icon, label) = switch (status) {
      _FieldStatus.detected => (
          colors.primaryContainer,
          colors.onPrimaryContainer,
          Icons.check_rounded,
          'OK',
        ),
      _FieldStatus.missing => (
          colors.errorContainer,
          colors.onErrorContainer,
          Icons.warning_amber_rounded,
          'Falta',
        ),
      _FieldStatus.notApplicable => (
          colors.surfaceContainerHigh,
          colors.outline,
          Icons.remove_rounded,
          'N/A',
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotosRow extends StatelessWidget {
  const _PhotosRow({this.frontPhoto, this.backPhoto});

  final XFile? frontPhoto;
  final XFile? backPhoto;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: Row(
        children: [
          Expanded(child: _PhotoTile(label: 'Frente', photo: frontPhoto)),
          const SizedBox(width: 12),
          Expanded(child: _PhotoTile(label: 'Reverso', photo: backPhoto)),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.label, required this.photo});

  final String label;
  final XFile? photo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null)
              Image.file(File(photo!.path), fit: BoxFit.cover)
            else
              Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: colors.outline,
                ),
              ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                   ),
                 ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RescanHint extends StatelessWidget {
  const _RescanHint({required this.missing, required this.onRescan});

  final List<String> missing;
  final VoidCallback onRescan;

  static const Map<String, String> _labels = {
    'documentNumber': 'documento',
    'firstName': 'prenombres',
    'lastName': 'primer apellido',
    'secondLastName': 'segundo apellido',
    'dateOfBirth': 'nacimiento',
    'expirationDate': 'caducidad',
    'emissionDate': 'emisión',
    'inscriptionDate': 'inscripción',
    'sex': 'sexo',
    'nationality': 'nacionalidad',
    'stateCivil': 'estado civil',
    'cardNumber': 'nro tarjeta',
    'address': 'dirección',
    'department': 'departamento',
    'province': 'provincia',
    'district': 'distrito',
    'organDonor': 'donación',
    'votingGroup': 'grupo de votación',
    'birthUbigeoCode': 'ubigeo nacimiento',
  };

  String _summary() {
    final names =
        missing.map((k) => _labels[k] ?? k).take(3).toList();
    if (missing.length <= 3) return names.join(', ');
    return '${names.join(', ')} y ${missing.length - 3} más';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.replay_circle_filled_outlined,
            color: colors.onErrorContainer,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Faltan campos importantes',
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _summary(),
                  style: TextStyle(
                    color: colors.onErrorContainer.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRescan,
            style: TextButton.styleFrom(
              foregroundColor: colors.onErrorContainer,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: const Text(
              'Reescanear',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReniecEnrichedPill extends StatelessWidget {
  const _ReniecEnrichedPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF1B5E20).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFF1B5E20),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Datos verificados con RENIEC',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF1B5E20),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

