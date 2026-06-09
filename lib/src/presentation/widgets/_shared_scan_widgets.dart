import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/kyc_theme.dart';

class FlipDocumentBanner extends StatefulWidget {
  const FlipDocumentBanner({super.key, required this.visible});

  final bool visible;

  @override
  State<FlipDocumentBanner> createState() => _FlipDocumentBannerState();
}

class _FlipDocumentBannerState extends State<FlipDocumentBanner>
    with TickerProviderStateMixin {
  late final AnimationController _rotate;

  @override
  void initState() {
    super.initState();
    _rotate = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    if (widget.visible) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void didUpdateWidget(covariant FlipDocumentBanner old) {
    super.didUpdateWidget(old);
    if (!old.visible && widget.visible) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _rotate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSlide(
        offset: widget.visible ? Offset.zero : const Offset(0, -1.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 280),
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              right: 20,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFB8C00), Color(0xFFF57C00)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RotationTransition(
                    turns: _rotate,
                    child: const Icon(
                      Icons.flip_camera_android_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'Voltee el documento',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScannerHint extends StatelessWidget {
  const ScannerHint({super.key, required this.hint, required this.theme});

  final String hint;
  final KycTheme theme;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Container(
          key: ValueKey<String>(hint),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class ScannerFlashToggle extends StatelessWidget {
  const ScannerFlashToggle({
    super.key,
    required this.isOn,
    required this.onToggle,
    required this.theme,
  });

  final bool isOn;
  final Future<void> Function() onToggle;
  final KycTheme theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        unawaited(onToggle());
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isOn
              ? theme.warningIcon
              : Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.white.withValues(alpha: 0.85),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          color: theme.white,
          size: 20,
        ),
      ),
    );
  }
}
