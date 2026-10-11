import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/core/widgets/omnia_pressable.dart';
import 'package:omnia_ui/features/assistant/assistant_page.dart';

/// The one floating way into Ask OmniAI, shown over the four main tabs.
///
/// A compact pill in the card language (pastel fill, outline, hard shadow,
/// press-into-shadow). Every [glintEvery] a single, brief glint sweeps across
/// it; nothing moves in between, and nothing moves at all when the platform
/// asks for reduced motion. The glint is decoration only: it is excluded from
/// semantics and never blocks taps.
class AskOmniaButton extends StatefulWidget {
  const AskOmniaButton({super.key, this.onPressed});

  /// Defaults to opening [AssistantPage].
  final VoidCallback? onPressed;

  static const label = 'Ask OmniAI';
  static const glintEvery = Duration(seconds: 6);
  static const glintLength = Duration(milliseconds: 750);

  @override
  State<AskOmniaButton> createState() => AskOmniaButtonState();
}

@visibleForTesting
class AskOmniaButtonState extends State<AskOmniaButton>
    with SingleTickerProviderStateMixin {
  late final _glint = AnimationController(
    vsync: this,
    duration: AskOmniaButton.glintLength,
  );
  Timer? _timer;

  /// True while a glint is sweeping (for tests).
  @visibleForTesting
  bool get glinting => _glint.isAnimating;

  /// True when glints are scheduled at all (false with reduced motion).
  @visibleForTesting
  bool get glintScheduled => _timer?.isActive ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _timer?.cancel();
      _timer = null;
      _glint.reset();
    } else {
      // A timer, not a repeating animation: between glints no frames are
      // scheduled, so the app stays idle.
      _timer ??= Timer.periodic(AskOmniaButton.glintEvery, (_) {
        if (mounted && TickerMode.valuesOf(context).enabled) {
          _glint.forward(from: 0);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _glint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = context.cardColor(lilac);
    final foreground = context.cardForeground(lilac);
    const radius = 14.0;
    // Floating chrome: it grows with the text size, but only so far, so it
    // never spreads across a narrow screen. Its label is also its tooltip
    // and its screen-reader name.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .6,
        ),
        child: _button(context, fill, foreground, radius),
      ),
    );
  }

  Widget _button(
    BuildContext context,
    Color fill,
    Color foreground,
    double radius,
  ) {
    return OmniaPressable(
      radius: radius,
      shadowOffset: const Offset(3, 3),
      builder: (context, states) => Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: context.outlineOn(fill), width: 1.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onPressed ?? () => AssistantPage.open(context),
          statesController: states,
          // The press into the shadow is the feedback; no ripple on top.
          splashFactory: NoSplash.splashFactory,
          child: Tooltip(
            message: AskOmniaButton.label,
            excludeFromSemantics: true,
            child: Semantics(
              button: true,
              label: AskOmniaButton.label,
              excludeSemantics: true,
              child: CustomPaint(
                foregroundPainter: _GlintPainter(_glint),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 20,
                          color: foreground,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            AskOmniaButton.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft diagonal band of light crossing the button once per glint. Kept
/// translucent so the label stays readable mid-sweep.
class _GlintPainter extends CustomPainter {
  _GlintPainter(this.progress) : super(repaint: progress);
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOut.transform(progress.value);
    if (t <= 0 || t >= 1) return;
    final band = size.height * 1.1;
    final x = -band + (size.width + band * 2) * t;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: .55),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(x - band / 2, 0, band, size.height));
    canvas.save();
    canvas.translate(x, 0);
    canvas.skew(-.35, 0);
    canvas.translate(-x, 0);
    canvas.drawRect(
      Rect.fromLTWH(x - band / 2, -2, band, size.height + 4),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlintPainter old) => old.progress != progress;
}

/// Room to leave below scrolling content on the main tabs so its last item
/// can scroll clear of the floating button (which grows with text size).
double askOmniaClearance(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(48).clamp(48.0, 112.0) + 32;
