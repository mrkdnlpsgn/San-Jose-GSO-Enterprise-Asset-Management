import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../provider/onboarding_provider.dart';

// How a page's icon moves while it's on screen.
enum _Motion { pulse, scan, wrench, swap, check }

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
    icon: Icons.verified_user_outlined,
    motion: _Motion.check,
    title: 'Sign in with your GSO account',
    body: 'Use the username and password given to you by the GSO system administrator. '
        'Office staff see the assets of their own office.',
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
                  child: TextButton(
                    onPressed: _isLast ? null : _finish,
                    child: Text(widget.replay ? 'Close' : 'Skip'),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _PageBody(page: _pages[i], active: i == _index),
              ),
            ),
            _Dots(count: _pages.length, index: _index),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _next,
                child: Text(_isLast ? (widget.replay ? 'Done' : 'Get started') : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  final _OnboardingPage page;
  final bool active;
  const _PageBody({required this.page, required this.active});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AnimatedIcon(page: page, active: active),
              const SizedBox(height: 12),
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.heading,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                page.body,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textSecondary, fontSize: 16, height: 1.5),
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
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: AppTheme.motionFast,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == index ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index ? context.brandAccent : context.colors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

/// The page's icon in its tinted circle. Each time the page comes into view the icon pops in,
/// then keeps a small looping motion that hints at what the page is about. With Reduce Motion
/// on, it only fades in and stays still.
class _AnimatedIcon extends StatefulWidget {
  final _OnboardingPage page;
  final bool active;
  const _AnimatedIcon({required this.page, required this.active});

  @override
  State<_AnimatedIcon> createState() => _AnimatedIconState();
}

class _AnimatedIconState extends State<_AnimatedIcon> with TickerProviderStateMixin {
  static const _size = 132.0;

  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final _loop = AnimationController(vsync: this, duration: _loopDuration);
  bool _reduced = false;
  bool _started = false;

  Duration get _loopDuration => switch (widget.page.motion) {
        _Motion.pulse => const Duration(milliseconds: 2400),
        _Motion.scan => const Duration(milliseconds: 1800),
        _Motion.wrench => const Duration(milliseconds: 2000),
        _Motion.swap => const Duration(milliseconds: 1600),
        _Motion.check => const Duration(milliseconds: 2600),
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
      // reset, so the entrance plays again when swiped back to
      _started = false;
      _loop.stop();
      _loop.value = 0;
      _enter.value = 0;
    }
  }

  void _play() {
    _started = true;
    _enter.forward(from: 0).whenComplete(() {
      if (mounted && widget.active && !_reduced) _loop.repeat();
    });
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
          // entrance: fade, and (unless reduced) a scale with a little overshoot and a slight rise
          final opacity = Curves.easeOut.transform((e * 1.6).clamp(0.0, 1.0));
          final scale = _reduced ? 1.0 : 0.55 + 0.45 * Curves.easeOutBack.transform(e);
          final rise = _reduced ? 0.0 : 16 * (1 - Curves.easeOutCubic.transform(e));

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
                      if (!_reduced && (page.motion == _Motion.pulse || page.motion == _Motion.check))
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
                      if (page.motion == _Motion.check) _checkBadge(accent, e),
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
      case _Motion.scan:
      case _Motion.check:
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

  // A check badge that pops onto the shield just after it lands.
  Widget _checkBadge(Color color, double e) {
    final p = _reduced ? e : ((e - 0.55) / 0.45).clamp(0.0, 1.0);
    final s = _reduced ? 1.0 : Curves.elasticOut.transform(p);
    return Positioned(
      right: 34,
      bottom: 34,
      child: Opacity(
        opacity: p,
        child: Transform.scale(
          scale: s,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.surface, width: 3),
            ),
            child: const Icon(Icons.check_rounded, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
