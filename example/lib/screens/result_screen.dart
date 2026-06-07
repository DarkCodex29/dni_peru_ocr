import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/field_card.dart';
import '../widgets/primary_button.dart';

/// Displays the consensus result from a completed DNI scan.
///
/// Renders every field in [OcrConsensusResult] with its value and confidence,
/// and exposes a "Scan another" CTA that pops the navigation stack back to
/// the home screen.
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.result,
  });

  final OcrConsensusResult result;

  String _resultAsText() {
    final lines = <String>[
      'Document number: ${result.documentNumber.value ?? '-'}',
      'First name: ${result.firstName.value ?? '-'}',
      'Last name: ${result.lastName.value ?? '-'}',
      'Second last name: ${result.secondLastName.value ?? '-'}',
      'Date of birth: ${result.dateOfBirth.value ?? '-'}',
      'Expiration date: ${result.expirationDate.value ?? '-'}',
      'Address: ${result.address.value ?? '-'}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        actions: [
          IconButton(
            tooltip: 'Copy to clipboard',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: _resultAsText()),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
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
              Expanded(
                child: ListView(
                  children: [
                    FieldCard(
                      label: 'Document number',
                      value: result.documentNumber.value,
                      confidence: result.documentNumber.confidence,
                    ),
                    FieldCard(
                      label: 'First name',
                      value: result.firstName.value,
                      confidence: result.firstName.confidence,
                    ),
                    FieldCard(
                      label: 'Last name',
                      value: result.lastName.value,
                      confidence: result.lastName.confidence,
                    ),
                    FieldCard(
                      label: 'Second last name',
                      value: result.secondLastName.value,
                      confidence: result.secondLastName.confidence,
                    ),
                    FieldCard(
                      label: 'Date of birth',
                      value: result.dateOfBirth.value,
                      confidence: result.dateOfBirth.confidence,
                    ),
                    FieldCard(
                      label: 'Expiration date',
                      value: result.expirationDate.value,
                      confidence: result.expirationDate.confidence,
                    ),
                    FieldCard(
                      label: 'Address',
                      value: result.address.value,
                      confidence: result.address.confidence,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Scan another',
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
