import 'dart:math' as math;
import 'package:flutter/material.dart';

class PulsingLoop extends StatefulWidget {
  final double size;
  final Color? color;

  const PulsingLoop({
    super.key,
    this.size = 56,
    this.color,
  });

  @override
  State<PulsingLoop> createState() => _PulsingLoopState();
}

class _PulsingLoopState extends State<PulsingLoop>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  late Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulse = Tween(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0, 0.5, curve: Curves.easeInOut),
      ),
    );
    _rotate = Tween(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = widget.color ?? cs.primary;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size * 0.55),
          painter: _LoopPainter(
            pulse: _pulse.value,
            rotate: _rotate.value,
            primary: primary,
          ),
        );
      },
    );
  }
}

class _LoopPainter extends CustomPainter {
  final double pulse;
  final double rotate;
  final Color primary;

  _LoopPainter({
    required this.pulse,
    required this.rotate,
    required this.primary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final ringWidth = 3.5 * pulse;

    final path = Path();
    const segments = 80;
    for (int i = 0; i <= segments; i++) {
      final t = (i / segments) * 2 * math.pi;
      final denom = 1 + math.sin(t) * math.sin(t);
      final x = cx + (w * 0.35 * math.cos(t) / denom);
      final y = cy + (h * 0.35 * math.sin(t) * math.cos(t) / denom);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;

    final gradient = SweepGradient(
      colors: [
        primary.withAlpha(180),
        primary.withAlpha(40),
        primary.withAlpha(160),
        primary.withAlpha(60),
        primary.withAlpha(180),
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(rotate),
    );

    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, paint);

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = primary;
    final dotT = rotate % (2 * math.pi);
    final dotDenom = 1 + math.sin(dotT) * math.sin(dotT);
    final dotX = cx + (w * 0.35 * math.cos(dotT) / dotDenom);
    final dotY =
        cy + (h * 0.35 * math.sin(dotT) * math.cos(dotT) / dotDenom);
    canvas.drawCircle(Offset(dotX, dotY), 4 * pulse, dotPaint);

    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = primary.withAlpha(15);
    canvas.drawCircle(Offset(dotX, dotY), 12 * pulse, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _LoopPainter old) => true;
}

class TypingBubble extends StatefulWidget {
  final Color? color;

  const TypingBubble({super.key, this.color});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dotColor = widget.color ?? cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: dotColor.withAlpha(60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Row(
                children: List.generate(3, (i) {
                  final delay = i * 0.2;
                  final t = (_ctrl.value - delay).clamp(0.0, 1.0);
                  final scale = 0.4 + 0.6 * math.sin(t * math.pi);
                  return Padding(
                    padding: EdgeInsets.only(
                      right: i < 2 ? 4 : 0,
                    ),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dotColor.withAlpha(
                            70 + (scale * 120).round(),
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class FloatingDust extends StatefulWidget {
  final Widget child;
  final int particleCount;

  const FloatingDust({
    super.key,
    required this.child,
    this.particleCount = 20,
  });

  @override
  State<FloatingDust> createState() => _FloatingDustState();
}

class _FloatingDustState extends State<FloatingDust>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _random = math.Random(42);
  late List<_DustParticle> _particles;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _particles = List.generate(
      widget.particleCount,
      (_) => _DustParticle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: 1.5 + _random.nextDouble() * 2.5,
        speed: 0.3 + _random.nextDouble() * 0.7,
        phase: _random.nextDouble() * 2 * math.pi,
        alpha: 20 + _random.nextInt(40),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final dustColor = isDark ? cs.secondary : cs.secondary;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _DustPainter(
                    particles: _particles,
                    progress: _ctrl.value,
                    color: dustColor,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DustParticle {
  final double x, y, size, speed, phase;
  final int alpha;

  _DustParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.alpha,
  });
}

class _DustPainter extends CustomPainter {
  final List<_DustParticle> particles;
  final double progress;
  final Color color;

  _DustPainter({
    required this.particles,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final px = p.x * size.width;
      final py = (p.y + math.sin(progress * 2 * math.pi + p.phase) * 0.15) *
          size.height;
      final alpha = (p.alpha *
              (0.5 + 0.5 * math.sin(progress * 2 * math.pi * p.speed + p.phase)))
          .round()
          .clamp(10, 60);

      paint.color = color.withAlpha(alpha);
      canvas.drawCircle(Offset(px, py), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DustPainter old) => true;
}

class StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration baseDelay;

  const StaggeredEntrance({
    super.key,
    required this.child,
    required this.index,
    this.baseDelay = const Duration(milliseconds: 60),
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    final delay = widget.index * widget.baseDelay.inMilliseconds / 1000.0;

    Future.delayed(Duration(milliseconds: (delay * 1000).round()), () {
      if (mounted) _ctrl.forward();
    });

    _slideAnim = Tween(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeOutCubic,
      ),
    );
    _fadeAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnim.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnim.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class AnimatedMessageEntrance extends StatefulWidget {
  final Widget child;
  final bool isUser;

  const AnimatedMessageEntrance({
    super.key,
    required this.child,
    this.isUser = false,
  });

  @override
  State<AnimatedMessageEntrance> createState() =>
      _AnimatedMessageEntranceState();
}

class _AnimatedMessageEntranceState extends State<AnimatedMessageEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slide;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween(
      begin: widget.isUser ? 20.0 : -20.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutBack,
    ));
    _fade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _scale = Tween(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.translate(
            offset: Offset(_slide.value * 0.5, _slide.value),
            child: Transform.scale(
              scale: _scale.value,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class MorphingSendButton extends StatefulWidget {
  final bool loading;
  final VoidCallback onSend;

  const MorphingSendButton({
    super.key,
    required this.loading,
    required this.onSend,
  });

  @override
  State<MorphingSendButton> createState() => _MorphingSendButtonState();
}

class _MorphingSendButtonState extends State<MorphingSendButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _morph;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _morph = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );

    if (widget.loading) {
      _ctrl.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant MorphingSendButton old) {
    super.didUpdateWidget(old);
    if (widget.loading != old.loading) {
      if (widget.loading) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final isIdle = _morph.value < 0.5;

        return GestureDetector(
          onTap: widget.loading ? null : widget.onSend,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.loading ? cs.outline : cs.primary,
                width: 2,
              ),
              color: widget.loading
                  ? Colors.transparent
                  : cs.primary,
            ),
            child: isIdle
                ? Icon(Icons.arrow_upward_sharp,
                    color: cs.onPrimary, size: 20)
                : Center(
                    child: BlockLoader(
                      width: 8,
                      height: 12,
                      color: cs.onSurface,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class BrainGlow extends StatefulWidget {
  final Widget child;
  final bool active;

  const BrainGlow({
    super.key,
    required this.child,
    this.active = false,
  });

  @override
  State<BrainGlow> createState() => _BrainGlowState();
}

class _BrainGlowState extends State<BrainGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _glow = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );

    if (widget.active) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BrainGlow old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      if (widget.active) {
        _ctrl.repeat(reverse: true);
      } else {
        _ctrl.stop();
        _ctrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: cs.tertiary.withAlpha(
                        (15 + _glow.value * 30).round(),
                      ),
                      blurRadius: 8 + _glow.value * 16,
                      spreadRadius: _glow.value * 2,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class PageFadeTransition extends PageRouteBuilder {
  final Widget page;

  PageFadeTransition({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              ),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        );
}

class ShimmerPulse extends StatefulWidget {
  final Widget child;

  const ShimmerPulse({super.key, required this.child});

  @override
  State<ShimmerPulse> createState() => _ShimmerPulseState();
}

class _ShimmerPulseState extends State<ShimmerPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: 0.6 + 0.4 * _ctrl.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class BlockLoader extends StatefulWidget {
  final double width;
  final double height;
  final Color? color;

  const BlockLoader({
    super.key,
    this.width = 10,
    this.height = 14,
    this.color,
  });

  @override
  State<BlockLoader> createState() => _BlockLoaderState();
}

class _BlockLoaderState extends State<BlockLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.color ?? cs.primary;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Opacity(
          opacity: _ctrl.value < 0.4 ? 1.0 : 0.0,
          child: Container(
            width: widget.width,
            height: widget.height,
            color: color,
          ),
        );
      },
    );
  }
}
