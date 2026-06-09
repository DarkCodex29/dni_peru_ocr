part of 'dni_camera_mask.dart';

Widget animatedSwitcherDedupeLayoutHelper(
  Widget? current,
  List<Widget> previous,
) =>
    animatedSwitcherDedupeLayout(current, previous);

// ─── Manual capture panel ─────────────────────────────────────────────────

class _ManualCapturePanel extends StatelessWidget {
  const _ManualCapturePanel({
    required this.isBackSide,
    required this.onPressed,
  });

  final bool isBackSide;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = KycTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      decoration: const BoxDecoration(
        color: Color(0xCC0D0D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isBackSide
                ? 'Encuadra el reverso del DNI y toca para capturar'
                : 'Encuadra el anverso del DNI y toca para capturar',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onPressed,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.white.withValues(alpha: 0.15),
                border: Border.all(color: theme.white, width: 3),
              ),
              child: Center(
                child: Icon(Icons.camera_alt_outlined,
                    color: theme.white, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Capturar',
            style: TextStyle(
              color: theme.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Side intro ribbon ────────────────────────────────────────────────────

class _SideIntroRibbon extends StatefulWidget {
  const _SideIntroRibbon();

  @override
  State<_SideIntroRibbon> createState() => _SideIntroRibbonState();
}

class _SideIntroRibbonState extends State<_SideIntroRibbon>
    with TickerProviderStateMixin {
  late final AnimationController _slideController;
  late final AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    HapticFeedback.mediumImpact();
    _slideController.forward();
    _rotateController.repeat();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = KycTheme.of(context);
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      )),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.gradientStart, theme.gradientEnd],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RotationTransition(
              turns: _rotateController,
              child: Icon(
                Icons.flip_camera_android_rounded,
                color: theme.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Anverso listo — ahora voltea el DNI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Debug telemetry overlay ──────────────────────────────────────────────

/// Debug-only HUD that surfaces the G.1 telemetry signals on top of the
/// camera preview. Entry point in [DniCameraMask] is wrapped in `kDebugMode`
/// so this renders nothing in release builds.
class _G1TelemetryOverlay extends StatelessWidget {
  const _G1TelemetryOverlay({
    required this.tilt,
    required this.mlkitAngle,
    required this.lines,
    required this.rawBlocks,
    required this.rotation,
    required this.format,
    required this.stableFrames,
    required this.failingGate,
    required this.perfectSinceMs,
  });

  final double tilt;
  final double? mlkitAngle;
  final int lines;
  final int rawBlocks;
  final int rotation;
  final String format;
  final int stableFrames;
  final String? failingGate;
  final int perfectSinceMs;

  String _fmtAngle(double v) => v.toStringAsFixed(1);
  String _fmtMaybeAngle(double? v) => v == null ? '-' : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = KycTheme.of(context);
    final lineStyle = TextStyle(
      color: theme.white,
      fontSize: 11,
      fontFamily: 'monospace',
      height: 1.25,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.overlayMedium.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('tilt: ${_fmtAngle(tilt)}°', style: lineStyle),
          Text('mlkit_angle: ${_fmtMaybeAngle(mlkitAngle)}°', style: lineStyle),
          Text('lines: $lines', style: lineStyle),
          Text('blocks: $rawBlocks', style: lineStyle),
          Text('rot: $rotation', style: lineStyle),
          Text('fmt: $format', style: lineStyle),
          Text('stableFrames: $stableFrames', style: lineStyle),
          Text('failing_gate: ${failingGate ?? "-"}', style: lineStyle),
          Text('perfectSince_ms: $perfectSinceMs', style: lineStyle),
        ],
      ),
    );
  }
}

// ─── Guide text banner ────────────────────────────────────────────────────

class _GuideTextBanner extends StatelessWidget {
  const _GuideTextBanner({
    required this.text,
    required this.holeHeight,
    this.insideHole = false,
  });
  final String text;
  final double holeHeight;
  final bool insideHole;

  @override
  Widget build(BuildContext context) {
    final theme = KycTheme.of(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final holeBottom = screenH / 2 + holeHeight / 2;
    final top = insideHole ? holeBottom - 52 : holeBottom + 16;
    return Positioned(
      top: top,
      left: 32,
      right: 32,
      child: AnimatedSwitcher(
        duration: const Duration(
          milliseconds: CameraOverlayTuning.switcherFadeMs,
        ),
        layoutBuilder: animatedSwitcherDedupeLayoutHelper,
        child: Container(
          key: ValueKey(text),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: theme.overlayMedium,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Data match indicator ────────────────────────────────────────────────

class _DataMatchIndicator extends StatelessWidget {
  const _DataMatchIndicator({required this.matches, this.bottom = 80});
  final bool matches;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = KycTheme.of(context);
    return Positioned(
      bottom: bottom,
      left: 24,
      right: 24,
      child: AnimatedSwitcher(
        duration: const Duration(
          milliseconds: CameraOverlayTuning.torchSwitcherFadeMs,
        ),
        layoutBuilder: animatedSwitcherDedupeLayoutHelper,
        child: Container(
          key: ValueKey(matches),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: matches
                ? theme.success.withValues(alpha: 0.85)
                : theme.warningIcon.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                matches ? Icons.verified_rounded : Icons.info_outline_rounded,
                color: theme.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  matches
                      ? 'DNI coincide con tu perfil'
                      : 'DNI no coincide — verifica el documento',
                  style: TextStyle(
                    color: theme.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

// ─── Flash toggle ─────────────────────────────────────────────────────────

class _FlashToggle extends StatelessWidget {
  const _FlashToggle({
    required this.isOn,
    required this.onToggle,
    super.key,
  });
  final bool isOn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = KycTheme.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onToggle();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isOn
              ? theme.warningIcon
              : Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.white.withValues(alpha: 0.85),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          color: theme.white,
          size: 26,
        ),
      ),
    );
  }
}
