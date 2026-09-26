import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:omnia_ui/core/widgets/surface_shadow.dart';

/// A hard-shadow surface that is physically pushed into its own shadow while
/// pressed: the surface slides by the shadow's offset and the shadow shrinks
/// to nothing, so it looks like the button went down onto the page.
///
/// It only draws the press. The control inside it (an [InkWell], a Material
/// button…) still owns taps, keyboard activation, focus, semantics and
/// feedback. Wire that control to the [WidgetStatesController] passed to
/// [builder] so keyboard presses show too; touch and mouse presses are picked
/// up directly, on pointer down, without waiting for the tap to be decided.
///
/// At rest it paints exactly what [SurfaceShadow] paints. Tune the feel for
/// the whole app here: [pressDuration], [releaseDuration], [depth].
class OmniaPressable extends StatefulWidget {
  const OmniaPressable({
    super.key,
    required this.radius,
    required this.builder,
    this.shadowOffset = const Offset(3, 4),
    this.enabled = true,
  });

  /// The surface's corner radius, for its shadow.
  final double radius;

  /// The resting hard shadow; a full press travels exactly this far.
  final Offset shadowOffset;

  /// False draws the resting surface and ignores presses.
  final bool enabled;

  final Widget Function(BuildContext context, WidgetStatesController states)
  builder;

  /// How fast the surface goes down, and comes back up.
  static const pressDuration = Duration(milliseconds: 70);
  static const releaseDuration = Duration(milliseconds: 110);

  /// The share of the shadow a full press travels (1 = sits flat on the page).
  static const depth = 1.0;

  @override
  State<OmniaPressable> createState() => _OmniaPressableState();
}

class _OmniaPressableState extends State<OmniaPressable>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController(
    vsync: this,
    duration: OmniaPressable.pressDuration,
    reverseDuration: OmniaPressable.releaseDuration,
  );
  late final _curve = CurvedAnimation(parent: _press, curve: Curves.easeOut);
  final _states = WidgetStatesController();

  int? _pointer;
  Offset _downAt = Offset.zero;
  bool _pointerDown = false, _keyDown = false;

  @override
  void initState() {
    super.initState();
    // Keyboard and switch activation report "pressed" through the control's
    // states; so do touches, which the pointer handlers below already cover.
    _states.addListener(() {
      final pressed = _states.value.contains(WidgetState.pressed);
      if (pressed != _keyDown) {
        _keyDown = pressed;
        _update();
      }
    });
  }

  @override
  void didUpdateWidget(OmniaPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _pointer = null;
      _pointerDown = _keyDown = false;
      _press.value = 0;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _press.dispose();
    _states.dispose();
    super.dispose();
  }

  bool get _pressed => widget.enabled && (_pointerDown || _keyDown);

  void _update() {
    if (!mounted) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _press.value = _pressed ? 1 : 0; // reduced motion: same states, no tween
    } else if (_pressed) {
      _press.forward();
    } else if (_press.status == AnimationStatus.forward) {
      // A quick tap still shows the whole press before coming back up.
      _press.forward().whenCompleteOrCancel(() {
        if (mounted && !_pressed) _press.reverse();
      });
    } else {
      _press.reverse();
    }
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _pointer = event.pointer;
    _downAt = event.position;
    _pointerDown = true;
    _update();
  }

  void _move(PointerMoveEvent event) {
    // Dragged away (usually a scroll): the tap won't happen, so let go.
    if (event.pointer == _pointer &&
        (event.position - _downAt).distance > kTouchSlop) {
      _end(event);
    }
  }

  void _end(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _pointerDown = false;
    _update();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final travel =
            widget.shadowOffset * (_curve.value * OmniaPressable.depth);
        return Transform.translate(
          offset: travel,
          child: SurfaceShadow(
            radius: widget.radius,
            offset: widget.shadowOffset - travel,
            child: child!,
          ),
        );
      },
      child: widget.builder(context, _states),
    ),
  );
}
