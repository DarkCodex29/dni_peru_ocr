import 'dart:async';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../lookup/in_memory_dni_cache.dart';
import '../widgets/loading_overlay.dart';
import 'error_screen.dart';
import 'result_screen_v2.dart';

DniLookupService? _lookupService;

DniLookupService? _resolveLookupService() {
  if (_lookupService != null) return _lookupService;
  final token = dotenv.maybeGet('APISPERU_TOKEN')?.trim();
  if (token == null || token.isEmpty) {
    debugPrint(
      'APISPERU_TOKEN missing in .env — DNI lookup disabled. '
      'Copy example/.env.example to example/.env and set the token.',
    );
    return null;
  }
  return _lookupService = CachingDniLookupService(
    delegate: ApisPeruLookupService(
      client: DioDniHttpClient(Dio()),
      token: token,
    ),
    cache: InMemoryDniCache(),
    ttl: const Duration(minutes: 5),
  );
}

const Duration _lookupTimeout = Duration(milliseconds: 2500);

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.fields});

  final DniFields? fields;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _controller;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      if (!mounted) return;
      await _goToError(ExampleErrorType.initialization);
    }
  }

  Future<void> _goToError(ExampleErrorType type) async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ErrorScreen(type: type)),
    );
  }

  Future<void> _onScanComplete(DniScanResult result) async {
    if (_resolving) return;
    _resolving = true;
    final dni = result.hunt.fields.documentNumber;
    final wantsNameMerge = _wantsNameMerge();
    var enriched = result.hunt.fields;
    DniData? lookupData;

    if (dni != null && dni.isNotEmpty) {
      lookupData = await _safeLookup(dni);
      if (lookupData != null && wantsNameMerge) {
        enriched = _applyReniecMerge(enriched, lookupData);
      }
    }

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ResultScreenV2(
          fields: enriched,
          format: result.hunt.format,
          frontPhoto: result.frontPhoto,
          backPhoto: result.backPhoto,
          selectedFields: widget.fields,
          reniecEnriched: lookupData != null,
        ),
      ),
    );
  }

  bool _wantsNameMerge() {
    final filter = widget.fields;
    if (filter == null) return true;
    return filter.contains(DniField.firstName) ||
        filter.contains(DniField.lastName) ||
        filter.contains(DniField.secondLastName);
  }

  Future<DniData?> _safeLookup(String dni) async {
    final service = _resolveLookupService();
    if (service == null) return null;
    try {
      final result = await service.lookup(dni).timeout(
        _lookupTimeout,
        onTimeout: () => const DniLookupNetworkError(),
      );
      if (result is DniLookupSuccess && result.data.dni == dni) {
        debugPrint(
          'Background lookup enriched DNI $dni: ${result.data.nombreCompleto}',
        );
        return result.data;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  ExtractedFields _applyReniecMerge(ExtractedFields ocr, DniData reniec) {
    final filter = widget.fields;
    String? pick(String reniecValue, String? ocrValue, DniField field) {
      if (filter != null && !filter.contains(field)) return ocrValue;
      final trimmed = reniecValue.trim();
      if (trimmed.isEmpty) return ocrValue;
      return trimmed;
    }

    ocr.firstName = pick(reniec.nombres, ocr.firstName, DniField.firstName);
    ocr.lastName =
        pick(reniec.apellidoPaterno, ocr.lastName, DniField.lastName);
    ocr.secondLastName = pick(
      reniec.apellidoMaterno,
      ocr.secondLastName,
      DniField.secondLastName,
    );
    return ocr;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        body: LoadingOverlay(message: 'Preparando cámara...'),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goToError(ExampleErrorType.cancelled),
        ),
        title: const Text('Escanear DNI'),
      ),
      body: DniScanner(
        controller: controller,
        fields: widget.fields ?? DniFields.full(),
        onScanComplete: _onScanComplete,
      ),
    );
  }
}
