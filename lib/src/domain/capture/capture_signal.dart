enum CapturePhase {
  waiting,
  needsFront,
  needsBack,
  gathering,
  fieldsComplete,
  readyToCapture,
}

class CaptureSignal {
  const CaptureSignal({
    required this.phase,
    required this.shouldCapture,
  });

  final CapturePhase phase;
  final bool shouldCapture;
}
