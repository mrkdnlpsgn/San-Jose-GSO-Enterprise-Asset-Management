import 'package:flutter/material.dart';

/// Eye button for a password field, as on the web. Hidden password: the eye has a slash through
/// it; showing it draws the slash away while the eye blinks (and the reverse). With animations
/// turned off on the phone only the icon changes.
class PasswordEyeButton extends StatefulWidget {
  final bool obscured;
  final VoidCallback onPressed;
  final Color? color;

  const PasswordEyeButton({super.key, required this.obscured, required this.onPressed, this.color});

  @override
  State<PasswordEyeButton> createState() => _PasswordEyeButtonState();
}

class _PasswordEyeButtonState extends State<PasswordEyeButton> with SingleTickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 240));

  // eye height over the blink: closes to 10% at 45%, then opens again
  late final Animation<double> _scaleY = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.1).chain(CurveTween(curve: Curves.easeIn)), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 0.1, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 55),
  ]).animate(_blink);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  void _press() {
    if (!MediaQuery.of(context).disableAnimations) _blink.forward(from: 0);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final still = MediaQuery.of(context).disableAnimations;
    return IconButton(
      tooltip: widget.obscured ? 'Show password' : 'Hide password',
      onPressed: _press,
      icon: SizedBox(
        width: 24,
        height: 24,
        child: Stack(alignment: Alignment.center, children: [
          AnimatedBuilder(
            animation: _scaleY,
            builder: (_, child) => Transform.scale(scaleX: 1, scaleY: _scaleY.value, child: child),
            child: Icon(Icons.visibility_outlined, color: color, size: 24),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: widget.obscured ? 1 : 0),
            duration: still ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            builder: (_, t, __) => CustomPaint(size: const Size(24, 24), painter: _SlashPainter(t, color)),
          ),
        ]),
      ),
    );
  }
}

// The slash across the eye, drawn from top-left to bottom-right as `progress` goes 0 to 1.
class _SlashPainter extends CustomPainter {
  final double progress;
  final Color color;
  _SlashPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final start = Offset(size.width * 0.14, size.height * 0.14);
    final end = Offset.lerp(start, Offset(size.width * 0.86, size.height * 0.86), progress)!;
    canvas.drawLine(start, end, Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_SlashPainter old) => old.progress != progress || old.color != color;
}
