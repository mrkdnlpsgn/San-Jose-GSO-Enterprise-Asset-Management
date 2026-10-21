import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_touch.dart';
import '../provider/onboarding_provider.dart';

// How a page's icon moves while it's on screen.
enum _Motion { pulse, scan, wrench, swap, sparkle }

class _OnboardingPage {
  final IconData? icon; // null = the municipal seal
  final _Motion motion;
  final String title;
  final String body;
  const _OnboardingPage({this.icon, required this.motion, required this.title, required this.body});
}

const _pages = [
  _OnboardingPage(
    motion: _Motion.pulse,
    title: 'San Jose GSO\nAsset Management',
    body: 'Keep track of the property of San Jose Municipal Hall, from the day it is registered '
        'to the day it is disposed of, right from your phone.',
  ),
  _OnboardingPage(
    icon: Icons.qr_code_scanner_rounded,
    motion: _Motion.scan,
    title: 'Scan a property tag',
    body: 'Every asset has a QR tag. Open the Scan tab and point the camera at it to see the '
        'asset\'s details, accountable person, condition and history.',
  ),
  _OnboardingPage(
    icon: Icons.build_rounded,
    motion: _Motion.wrench,
    title: 'Maintenance and disposal',
    body: 'Record repairs and check-ups, and request disposal of unserviceable property. '
        'Requests from office staff go to the GSO administrator for approval.',
  ),
  _OnboardingPage(
    icon: Icons.swap_horiz_rounded,
    motion: _Motion.swap,
    title: 'Transfers and accountability',
    body: 'Move property to another office or accountable person. Each transfer is recorded, '
        'so the PAR and Property Card always show who holds it.',
  ),
  _OnboardingPage(
    icon: Icons.auto_awesome_rounded,
    motion: _Motion.sparkle,
    title: 'AI-assisted insights',
    body: 'Built-in AI looks at each asset\'s age, condition and repair history and suggests the next '
        'step, from routine maintenance to review for disposal. It also drafts maintenance summaries '
        'and disposal justifications for GSO staff to review.',
  ),
];

/// Shown once on first launch, before sign-in. Also opened from Settings ("App tour")
/// with [replay], where finishing just closes it.
class OnboardingScreen extends ConsumerStatefulWidget {
  final bool replay;
  const OnboardingScreen({super.key, this.replay = false});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    HapticFeedback.lightImpact(); // the one commit moment on this screen
    if (widget.replay) {
      context.pop();
      return;
    }
    // the router sends the user on to sign-in once this is marked done
    ref.read(onboardingDoneProvider.notifier).complete();
  }

  void _next() {
    if (_isLast) return _finish();
    _controller.nextPage(
      duration: context.prefersReducedMotion ? const Duration(milliseconds: 1) : AppTheme.motionMedium,
      curve: AppTheme.motionCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: AnimatedOpacity(
                  opacity: _isLast ? 0 : 1,
                  duration: AppTheme.motionFast,
                  child: PressScale(
                    child: TextButton(
                      onPressed: _isLast ? null : _finish,
                      child: Text(widget.replay ? 'Close' : 'Skip'),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) =>
                    _PageBody(page: _pages[i], index: i, controller: _controller, active: i == _index),
              ),
            ),
            _Dots(count: _pages.length, index: _index, controller: _controller),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: PressScale(
                scale: 0.97,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _next,
                  child: Text(_isLast ? (widget.replay ? 'Done' : 'Get started') : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The pager's live scroll position in pages (1.4 = 40% of the way from page 1 to page 2), so
// anything tied to it follows the finger frame by frame instead of jumping when a page settles.
double _pagePosition(PageController c, int fallback) =>
    c.hasClients && c.position.haveDimensions ? c.page ?? fallback.toDouble() : fallback.toDouble();

class _PageBody extends StatelessWidget {
  final _OnboardingPage page;
  final int index;
  final PageController controller;
  final bool active;
  const _PageBody({required this.page, required this.index, required this.controller, required this.active});

  @override
  Widget build(BuildContext context) {
    final reduced = context.prefersReducedMotion;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Depth while swiping: the icon trails the page a little, as if it sat further
              // back, and fades as it leaves. It tracks the drag 1:1, so a swipe that's let go
              // halfway just slides back. Reduce Motion keeps only the fade.
              AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  final d = _pagePosition(controller, index) - index; // -1..1 while on screen
                  final width = MediaQuery.sizeOf(context).width;
                  return Opacity(
                    opacity: (1 - d.abs() * 0.8).clamp(0.0, 1.0),
                    child: Transform.translate(offset: Offset(reduced ? 0 : d * width * 0.35, 0), child: child),
                  );
                },
                child: _AnimatedIcon(page: page, active: active),
              ),
              const SizedBox(height: 12),
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.heading,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1.15, // tight leading and negative tracking on large type
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                page.body,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textSecondary, fontSize: 18, height: 1.45),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  final PageController controller;
  const _Dots({required this.count, required this.index, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${index + 1} of $count',
      // the active pill stretches and recolours with the swipe itself, not after it
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final p = _pagePosition(controller, index);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                Builder(builder: (context) {
                  final near = (1 - (p - i).abs()).clamp(0.0, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8 + 14 * near,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color.lerp(context.colors.border, context.brandAccent, near),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

/// The page's icon in its tinted circle. Each time the page comes into view the icon settles in
/// on a spring, then keeps a small looping motion that hints at what the page is about; leaving
/// the page plays the entrance in reverse. With Reduce Motion on, it only cross-fades and stays
/// still.
class _AnimatedIcon extends StatefulWidget {
  final _OnboardingPage page;
  final bool active;
  const _AnimatedIcon({required this.page, required this.active});

  @override
  State<_AnimatedIcon> createState() => _AnimatedIconState();
}

class _AnimatedIconState extends State<_AnimatedIcon> with TickerProviderStateMixin {
  static const _size = 132.0;

  // Critically damped (no overshoot: nothing was flung, the page just arrived), ~0.45 s response.
  static final _spring = SpringDescription.withDampingRatio(
      mass: 1, stiffness: math.pow(2 * math.pi / 0.45, 2).toDouble(), ratio: 1.0);

  late final _enter = AnimationController(vsync: this);
  late final _loop = AnimationController(vsync: this, duration: _loopDuration);
  bool _reduced = false;
  bool _started = false;

  Duration get _loopDuration => switch (widget.page.motion) {
        _Motion.pulse => const Duration(milliseconds: 2400),
        _Motion.scan => const Duration(milliseconds: 1800),
        _Motion.wrench => const Duration(milliseconds: 2000),
        _Motion.swap => const Duration(milliseconds: 1600),
        _Motion.sparkle => const Duration(milliseconds: 2600),
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = context.prefersReducedMotion;
    if (widget.active && !_started) _play();
  }

  @override
  void didUpdateWidget(_AnimatedIcon old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _play();
    if (!widget.active && old.active) {
      // leave the way it came, so swiping back plays the entrance again
      _started = false;
      _loop.animateTo(0, duration: AppTheme.motionFast, curve: Curves.easeOut);
      _settle(0);
    }
  }

  void _play() {
    _started = true;
    _settle(1).whenComplete(() {
      if (mounted && widget.active && !_reduced) _loop.repeat();
    });
  }

  // Always from the icon's current value and speed, so a swipe that changes its mind
  // mid-entrance turns the motion around smoothly instead of restarting it.
  TickerFuture _settle(double target) {
    if (_reduced) return _enter.animateTo(target, duration: const Duration(milliseconds: 200));
    return _enter.animateWith(SpringSimulation(_spring, _enter.value, target, _enter.velocity));
  }

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.brandAccent;
    final tint = AppTheme.brand.withValues(alpha: context.isLight ? 0.12 : 0.18);
    final page = widget.page;

    final Widget glyph = page.icon == null
        ? Image.asset('assets/images/images.png', width: _size, height: _size, fit: BoxFit.cover)
        : Icon(page.icon, size: 64, color: accent);

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _loop]),
        builder: (context, _) {
          final e = _enter.value;
          final t = _loop.value;
          // entrance: fade, and (unless reduced) grow from 80% and rise into place; the spring
          // supplies the easing, so these follow it linearly
          final opacity = (e * 1.6).clamp(0.0, 1.0);
          final scale = _reduced ? 1.0 : 0.8 + 0.2 * e;
          final rise = _reduced ? 0.0 : 14 * (1 - e);

          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, rise),
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: _size + 48,
                  height: _size + 48,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      if (!_reduced && (page.motion == _Motion.pulse || page.motion == _Motion.sparkle))
                        _ring(accent, t),
                      Container(
                        width: _size,
                        height: _size,
                        decoration: BoxDecoration(color: page.icon == null ? null : tint, shape: BoxShape.circle),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _reduced ? glyph : _move(glyph, t),
                            if (!_reduced && page.motion == _Motion.scan) _scanLine(accent, t),
                          ],
                        ),
                      ),
                      if (!_reduced && page.motion == _Motion.sparkle) ..._sparkles(accent, e, t),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // The icon's own looping motion.
  Widget _move(Widget glyph, double t) {
    switch (widget.page.motion) {
      case _Motion.pulse:
        // a slow breath
        return Transform.scale(scale: 1 + 0.025 * math.sin(t * 2 * math.pi), child: glyph);
      case _Motion.wrench:
        // two quick turns of the wrench that die down, then a rest
        final turn = t < 0.5 ? math.sin(t / 0.5 * 4 * math.pi) * (1 - t / 0.5) : 0.0;
        return Transform.rotate(angle: 0.45 * turn, child: glyph);
      case _Motion.swap:
        // slides toward one office, then the other
        return Transform.translate(offset: Offset(9 * math.sin(t * 2 * math.pi), 0), child: glyph);
      case _Motion.sparkle:
        // a gentle shimmer: a small turn and swell, twice per loop
        final w = math.sin(t * 4 * math.pi);
        return Transform.rotate(
          angle: 0.08 * w,
          child: Transform.scale(scale: 1 + 0.05 * w.abs(), child: glyph),
        );
      case _Motion.scan:
        return glyph;
    }
  }

  // A soft ring that grows out from the circle and fades.
  Widget _ring(Color color, double t) {
    final grow = Curves.easeOut.transform(t);
    return IgnorePointer(
      child: Container(
        width: _size + 44 * grow,
        height: _size + 44 * grow,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.35 * (1 - grow)), width: 2),
        ),
      ),
    );
  }

  // A bar that sweeps up and down across the QR icon, like a scanner.
  Widget _scanLine(Color color, double t) {
    final y = 22 * math.sin(t * 2 * math.pi); // stays within the icon's frame
    return Transform.translate(
      offset: Offset(0, y),
      child: Container(
        width: 58,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)],
        ),
      ),
    );
  }

  // Small stars around the circle that twinkle in turn, after the icon lands.
  List<Widget> _sparkles(Color color, double e, double t) {
    final shown = ((e - 0.6) / 0.4).clamp(0.0, 1.0); // fade in at the end of the entrance
    // (left, top, size, phase) inside the icon's 180 × 180 box
    const stars = [(136.0, 18.0, 22.0, 0.0), (20.0, 128.0, 18.0, 0.33), (26.0, 30.0, 14.0, 0.66)];
    return [
      for (final (left, top, size, phase) in stars)
        Positioned(
          left: left,
          top: top,
          child: Builder(builder: (context) {
            // each star brightens and swells once per loop, offset from the others
            final glow = math.max(0.0, math.sin((t + phase) * 2 * math.pi));
            return Opacity(
              opacity: shown * (0.25 + 0.75 * glow),
              child: Transform.scale(
                scale: 0.6 + 0.5 * glow,
                child: Icon(Icons.auto_awesome, size: size, color: color),
              ),
            );
          }),
        ),
    ];
  }
}
