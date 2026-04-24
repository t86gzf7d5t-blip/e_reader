import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/reader_safe_region.dart';
import 'character_overlay.dart';

enum CharacterSceneInteraction {
  idle,
  pageTurnAssist,
  storybookSpark,
  pokemonWaterVsFire,
  narutoCloneVsShuriken,
  ghibliMischief,
}

class CharacterSceneOverlay extends StatefulWidget {
  final CharacterManifest leftCharacter;
  final CharacterManifest rightCharacter;
  final String style;
  final bool autoPlay;
  final int triggerKey;
  final List<ReaderSafeRegion> safeRegions;

  const CharacterSceneOverlay({
    super.key,
    required this.leftCharacter,
    required this.rightCharacter,
    required this.style,
    required this.autoPlay,
    required this.triggerKey,
    required this.safeRegions,
  });

  @override
  State<CharacterSceneOverlay> createState() => _CharacterSceneOverlayState();
}

class _CharacterSceneOverlayState extends State<CharacterSceneOverlay> {
  static const _dashDuration = Duration(milliseconds: 260);
  static const _settleDuration = Duration(milliseconds: 650);
  static const _dashResetDuration = Duration(milliseconds: 380);
  static const _homeLockDuration = Duration(milliseconds: 1400);
  static const _minimumMoveDistance = 54.0;
  static const _minimumResizeDelta = 16.0;

  Timer? _interactionTimer;
  Timer? _dashResetTimer;
  CharacterSceneInteraction _interaction = CharacterSceneInteraction.idle;
  int _cycleIndex = 0;
  _CharacterPlacement? _leftPlacement;
  _CharacterPlacement? _rightPlacement;
  Size _lastSize = Size.zero;
  bool _leftDashing = false;
  bool _rightDashing = false;
  DateTime? _leftLockedUntil;
  DateTime? _rightLockedUntil;
  bool _pendingRelayout = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(CharacterSceneOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style || oldWidget.autoPlay != widget.autoPlay) {
      _cycleIndex = 0;
      _pendingRelayout = true;
    }
    if (oldWidget.triggerKey != widget.triggerKey) {
      _pendingRelayout = true;
      _triggerPageTurnInteraction();
    }
    if (oldWidget.safeRegions != widget.safeRegions &&
        (_leftPlacement == null || _rightPlacement == null)) {
      _pendingRelayout = true;
    }
  }

  @override
  void dispose() {
    _interactionTimer?.cancel();
    _dashResetTimer?.cancel();
    super.dispose();
  }

  void _updatePlacements((_CharacterPlacement, _CharacterPlacement) placements) {
    final nextLeft = placements.$1;
    final nextRight = placements.$2;
    _leftPlacement = nextLeft;
    _rightPlacement = nextRight;
    _leftDashing = false;
    _rightDashing = false;

    _pendingRelayout = false;
  }

  void _triggerPageTurnInteraction() {
    _setInteraction(CharacterSceneInteraction.pageTurnAssist);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _interaction = CharacterSceneInteraction.idle;
      });
    });
  }

  void _setInteraction(CharacterSceneInteraction interaction) {
    setState(() {
      _interaction = interaction;
    });
  }

  Color _accentFor(String role, String style) {
    switch (style) {
      case 'pokemon':
        return role == 'mom' ? const Color(0xFF5ED3F3) : const Color(0xFFFF8A5C);
      case 'naruto':
        return role == 'mom' ? const Color(0xFF9B7BFF) : const Color(0xFFFFC04D);
      case 'ghibli':
        return role == 'mom' ? const Color(0xFF8FD6A3) : const Color(0xFFF0B37E);
      default:
        return role == 'mom' ? const Color(0xFF8AD6FF) : const Color(0xFFFFB36B);
    }
  }

  CharacterOverlayMood get _leftMood {
    if (_interaction == CharacterSceneInteraction.idle) {
      return CharacterOverlayMood.idle;
    }
    return CharacterOverlayMood.pageTurnAssist;
  }

  CharacterOverlayMood get _rightMood {
    if (_interaction == CharacterSceneInteraction.idle) {
      return CharacterOverlayMood.idle;
    }
    return CharacterOverlayMood.pageTurnAssist;
  }

  @override
  Widget build(BuildContext context) {
    final leftAccent = _accentFor(widget.leftCharacter.role, widget.style);
    final rightAccent = _accentFor(widget.rightCharacter.role, widget.style);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          _lastSize = size;
          final shouldRelayout =
              _pendingRelayout ||
              _leftPlacement == null ||
              _rightPlacement == null;
          if (shouldRelayout) {
            final placements = _resolveSlots(size);
            _leftPlacement ??= placements.$1;
            _rightPlacement ??= placements.$2;
            _updatePlacements(placements);
          }
          final leftPlacement = _leftPlacement!;
          final rightPlacement = _rightPlacement!;

          return SizedBox.expand(
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: _leftDashing ? _dashDuration : _settleDuration,
                  curve: _leftDashing
                      ? Curves.easeOutCubic
                      : Curves.easeInOutCubic,
                  left: leftPlacement.offset.dx,
                  top: leftPlacement.offset.dy,
                  child: CharacterOverlay(
                    character: widget.leftCharacter,
                    mood: _leftMood,
                    autoPlay: widget.autoPlay,
                    style: widget.style,
                    accentColor: leftAccent,
                    alignment: Alignment.centerLeft,
                    facingRight: true,
                    boxWidth: leftPlacement.width,
                    boxHeight: leftPlacement.height,
                    isDashing: _leftDashing,
                  ),
                ),
                AnimatedPositioned(
                  duration: _rightDashing ? _dashDuration : _settleDuration,
                  curve: _rightDashing
                      ? Curves.easeOutCubic
                      : Curves.easeInOutCubic,
                  left: rightPlacement.offset.dx,
                  top: rightPlacement.offset.dy,
                  child: CharacterOverlay(
                    character: widget.rightCharacter,
                    mood: _rightMood,
                    autoPlay: widget.autoPlay,
                    style: widget.style,
                    accentColor: rightAccent,
                    alignment: Alignment.centerRight,
                    facingRight: false,
                    boxWidth: rightPlacement.width,
                    boxHeight: rightPlacement.height,
                    isDashing: _rightDashing,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  (_CharacterPlacement, _CharacterPlacement) _resolveSlots(Size size) {
    const boxWidth = 132.0;
    const boxHeight = 156.0;
    const sidePadding = 18.0;
    const bottomPadding = 26.0;

    final bottomY = math.max(12.0, size.height - boxHeight - bottomPadding);

    return (
      _CharacterPlacement(
        offset: Offset(sidePadding, bottomY),
        width: boxWidth,
        height: boxHeight,
        label: 'L fixed',
      ),
      _CharacterPlacement(
        offset: Offset(
          math.max(12.0, size.width - boxWidth - sidePadding),
          bottomY,
        ),
        width: boxWidth,
        height: boxHeight,
        label: 'R fixed',
      ),
    );
  }

  double _scoreRegion({
    required ReaderSafeRegion region,
    required Offset target,
    required _CharacterPlacement? currentPlacement,
    required Size viewportSize,
    required String role,
  }) {
    final center = Offset(
      region.x + (region.width / 2),
      region.y + (region.height / 2),
    );
    final area = region.width * region.height;
    final targetDistance = (center - target).distance;

    var score = (area * 4.5) - (targetDistance * 1.8);

    if (currentPlacement != null) {
      final currentCenter = Offset(
        (currentPlacement.offset.dx + (currentPlacement.width / 2)) /
            viewportSize.width,
        (currentPlacement.offset.dy + (currentPlacement.height / 2)) /
            viewportSize.height,
      );
      final moveDistance = (center - currentCenter).distance;
      score -= moveDistance * 1.6;

      if (_isSameRegion(currentPlacement.region, region)) {
        score += 2.2;
      }
    }

    if (role == 'left' && center.dy < 0.34) {
      score += 0.35;
    }
    if (role == 'right' && center.dy > 0.42) {
      score += 0.35;
    }

    return score;
  }

  _PlacementDecision _mergePlacement({
    required _CharacterPlacement? current,
    required _CharacterPlacement candidate,
    required DateTime? lockedUntil,
    required DateTime now,
  }) {
    if (current == null) {
      return _PlacementDecision(candidate, changed: true);
    }

    final moveDistance = (candidate.offset - current.offset).distance;
    final resizeDelta = math.max(
      (candidate.width - current.width).abs(),
      (candidate.height - current.height).abs(),
    );
    final isLocked = lockedUntil != null && now.isBefore(lockedUntil);
    final sameRegion = _isSameRegion(current.region, candidate.region);
    final shouldSnap = moveDistance >= _minimumMoveDistance;
    final shouldResize = resizeDelta >= _minimumResizeDelta;

    if (sameRegion || (!shouldSnap && !shouldResize)) {
      return _PlacementDecision(
        _blendPlacement(current, candidate, keepLabel: current.label),
        changed: false,
      );
    }

    if (isLocked && moveDistance < (_minimumMoveDistance * 1.8)) {
      return _PlacementDecision(
        _blendPlacement(current, candidate, keepLabel: current.label),
        changed: false,
      );
    }

    return _PlacementDecision(candidate, changed: true);
  }

  _CharacterPlacement _blendPlacement(
    _CharacterPlacement current,
    _CharacterPlacement candidate, {
    required String keepLabel,
  }) {
    return _CharacterPlacement(
      offset: Offset(
        lerpDouble(current.offset.dx, candidate.offset.dx, 0.12)!,
        lerpDouble(current.offset.dy, candidate.offset.dy, 0.12)!,
      ),
      width: lerpDouble(current.width, candidate.width, 0.10)!,
      height: lerpDouble(current.height, candidate.height, 0.10)!,
      label: keepLabel,
      region: current.region ?? candidate.region,
    );
  }

  bool _isSameRegion(ReaderSafeRegion? a, ReaderSafeRegion? b) {
    if (a == null || b == null) {
      return false;
    }

    return (a.x - b.x).abs() < 0.02 &&
        (a.y - b.y).abs() < 0.02 &&
        (a.width - b.width).abs() < 0.03 &&
        (a.height - b.height).abs() < 0.03;
  }

  bool _placementsOverlap(
    _CharacterPlacement left,
    _CharacterPlacement right, {
    double padding = 0,
  }) {
    final leftRect = Rect.fromLTWH(
      left.offset.dx - padding,
      left.offset.dy - padding,
      left.width + (padding * 2),
      left.height + (padding * 2),
    );
    final rightRect = Rect.fromLTWH(
      right.offset.dx - padding,
      right.offset.dy - padding,
      right.width + (padding * 2),
      right.height + (padding * 2),
    );
    return leftRect.overlaps(rightRect);
  }

  Widget _buildEffectLayer(Color leftAccent, Color rightAccent) {
    switch (_interaction) {
      case CharacterSceneInteraction.storybookSpark:
        return Stack(
          children: [
            _TravelingOrb(
              key: const ValueKey('storybook_left'),
              begin: const Alignment(-0.72, 0.70),
              end: const Alignment(-0.08, 0.54),
              color: leftAccent.withOpacity(0.85),
              glowColor: Colors.white,
              size: 16,
              icon: Icons.auto_awesome,
            ),
            _TravelingOrb(
              key: const ValueKey('storybook_right'),
              begin: const Alignment(0.72, 0.70),
              end: const Alignment(0.10, 0.50),
              color: rightAccent.withOpacity(0.85),
              glowColor: const Color(0xFFFFF0C8),
              size: 16,
              icon: Icons.auto_awesome,
              delay: 140,
            ),
            _TravelingOrb(
              key: const ValueKey('storybook_center'),
              begin: const Alignment(0.0, 0.62),
              end: const Alignment(0.0, 0.34),
              color: const Color(0xFFFFE9A8),
              glowColor: Colors.white,
              size: 18,
              icon: Icons.menu_book,
              delay: 220,
            ),
          ],
        );
      case CharacterSceneInteraction.pokemonWaterVsFire:
        return Stack(
          children: [
            _TravelingOrb(
              key: const ValueKey('water'),
              begin: const Alignment(-0.70, 0.72),
              end: const Alignment(0.54, 0.64),
              color: leftAccent,
              glowColor: Colors.white,
              size: 22,
              icon: Icons.water_drop,
            ),
            _TravelingOrb(
              key: const ValueKey('fire'),
              begin: const Alignment(0.70, 0.70),
              end: const Alignment(-0.48, 0.62),
              color: rightAccent,
              glowColor: const Color(0xFFFFF0A8),
              size: 24,
              icon: Icons.local_fire_department,
            ),
          ],
        );
      case CharacterSceneInteraction.narutoCloneVsShuriken:
        return Stack(
          children: [
            const _CloneBurst(
              key: ValueKey('clones'),
              origin: Alignment(-0.72, 0.68),
            ),
            _TravelingOrb(
              key: const ValueKey('shuriken_a'),
              begin: const Alignment(0.70, 0.68),
              end: const Alignment(-0.40, 0.45),
              color: rightAccent,
              glowColor: Colors.white,
              size: 18,
              icon: Icons.auto_awesome,
              rotate: true,
            ),
            _TravelingOrb(
              key: const ValueKey('shuriken_b'),
              begin: const Alignment(0.72, 0.75),
              end: const Alignment(-0.35, 0.60),
              color: rightAccent.withOpacity(0.9),
              glowColor: Colors.white,
              size: 16,
              icon: Icons.auto_awesome,
              rotate: true,
              delay: 120,
            ),
          ],
        );
      case CharacterSceneInteraction.ghibliMischief:
        return const _MischiefTrail(key: ValueKey('ghibli'));
      case CharacterSceneInteraction.pageTurnAssist:
        return _TravelingOrb(
          key: const ValueKey('assist'),
          begin: const Alignment(-0.18, 0.52),
          end: const Alignment(0.18, 0.52),
          color: Colors.white.withOpacity(0.8),
          glowColor: const Color(0xFFFFD98C),
          size: 16,
          icon: Icons.auto_awesome,
        );
      case CharacterSceneInteraction.idle:
        return const SizedBox.shrink();
    }
  }
}

class _CharacterPlacement {
  final Offset offset;
  final double width;
  final double height;
  final String label;
  final ReaderSafeRegion? region;

  const _CharacterPlacement({
    required this.offset,
    required this.width,
    required this.height,
    required this.label,
    this.region,
  });
}

class _PlacementDecision {
  final _CharacterPlacement placement;
  final bool changed;

  const _PlacementDecision(this.placement, {required this.changed});
}

class _DebugSafeRegionOverlay extends StatelessWidget {
  final List<ReaderSafeRegion> regions;
  final _CharacterPlacement leftPlacement;
  final _CharacterPlacement rightPlacement;

  const _DebugSafeRegionOverlay({
    required this.regions,
    required this.leftPlacement,
    required this.rightPlacement,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return IgnorePointer(
          child: Stack(
            children: [
              for (final region in regions)
                Positioned(
                  left: region.x * size.width,
                  top: region.y * size.height,
                  width: region.width * size.width,
                  height: region.height * size.height,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.75),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              _buildPlacementBox(leftPlacement, const Color(0xFF4FC3F7)),
              _buildPlacementBox(rightPlacement, const Color(0xFFFFC857)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlacementBox(_CharacterPlacement placement, Color color) {
    return Positioned(
      left: placement.offset.dx,
      top: placement.offset.dy,
      width: placement.width,
      height: placement.height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.95), width: 2),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.62),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              placement.label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _TravelingOrb extends StatefulWidget {
  final Alignment begin;
  final Alignment end;
  final Color color;
  final Color glowColor;
  final double size;
  final IconData icon;
  final bool rotate;
  final int delay;

  const _TravelingOrb({
    super.key,
    required this.begin,
    required this.end,
    required this.color,
    required this.glowColor,
    required this.size,
    required this.icon,
    this.rotate = false,
    this.delay = 0,
  });

  @override
  State<_TravelingOrb> createState() => _TravelingOrbState();
}

class _TravelingOrbState extends State<_TravelingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    if (widget.delay == 0) {
      _controller.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final alignment = Alignment.lerp(
          widget.begin,
          widget.end,
          _animation.value,
        )!;
        final spin = widget.rotate ? _animation.value * math.pi * 6 : 0.0;

        return Align(
          alignment: alignment,
          child: Opacity(
            opacity: 1 - (_animation.value * 0.35),
            child: Transform.rotate(
              angle: spin,
              child: Container(
                width: widget.size + 18,
                height: widget.size + 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(0.45),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                  gradient: RadialGradient(
                    colors: [
                      widget.glowColor.withOpacity(0.95),
                      widget.color,
                    ],
                  ),
                ),
                child: Icon(
                  widget.icon,
                  color: Colors.white,
                  size: widget.size,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CloneBurst extends StatefulWidget {
  final Alignment origin;

  const _CloneBurst({super.key, required this.origin});

  @override
  State<_CloneBurst> createState() => _CloneBurstState();
}

class _CloneBurstState extends State<_CloneBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const offsets = [
      Offset(0.00, 0.00),
      Offset(0.14, -0.12),
      Offset(0.18, 0.06),
      Offset(0.08, -0.20),
    ];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: offsets.map((offset) {
            final scale = 0.82 + ((_controller.value) * 0.18);
            final opacity = 0.85 - (_controller.value * 0.45);
            return Align(
              alignment: Alignment(
                widget.origin.x + offset.dx,
                widget.origin.y + offset.dy,
              ),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.28)),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _MischiefTrail extends StatefulWidget {
  const _MischiefTrail({super.key});

  @override
  State<_MischiefTrail> createState() => _MischiefTrailState();
}

class _MischiefTrailState extends State<_MischiefTrail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.auto_awesome,
      Icons.local_florist,
      Icons.brightness_5,
      Icons.flutter_dash,
    ];
    const colors = [
      Color(0xFFFFE38A),
      Color(0xFF9ED9A4),
      Color(0xFFFFC189),
      Color(0xFFA8C6FF),
    ];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: List.generate(icons.length, (index) {
            final progress = ((_controller.value + (index * 0.08)) % 1.0);
            final x = -0.52 + (progress * 1.08);
            final y = 0.58 + math.sin((progress * math.pi * 2) + index) * 0.10;
            return Align(
              alignment: Alignment(x, y),
              child: Opacity(
                opacity: 0.35 + (1 - progress) * 0.5,
                child: Transform.rotate(
                  angle: progress * math.pi * 2,
                  child: Icon(
                    icons[index],
                    color: colors[index],
                    size: 22 + (index * 2),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
