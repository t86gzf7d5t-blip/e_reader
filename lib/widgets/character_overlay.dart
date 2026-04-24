import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/character.dart';

enum CharacterOverlayMood { idle, pageTurnAssist }

class CharacterOverlay extends StatefulWidget {
  final CharacterManifest character;
  final CharacterOverlayMood mood;
  final bool autoPlay;
  final String style;
  final Color accentColor;
  final Alignment alignment;
  final bool facingRight;
  final double boxWidth;
  final double boxHeight;
  final bool isDashing;

  const CharacterOverlay({
    super.key,
    required this.character,
    required this.mood,
    required this.autoPlay,
    required this.style,
    required this.accentColor,
    required this.alignment,
    required this.facingRight,
    required this.boxWidth,
    required this.boxHeight,
    required this.isDashing,
  });

  @override
  State<CharacterOverlay> createState() => _CharacterOverlayState();
}

class _CharacterOverlayState extends State<CharacterOverlay> {
  Timer? _frameTimer;
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncAnimationLoop();
  }

  @override
  void didUpdateWidget(CharacterOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.character.id != widget.character.id ||
        oldWidget.style != widget.style ||
        oldWidget.isDashing != widget.isDashing) {
      _syncAnimationLoop(resetFrame: true);
    } else if (oldWidget.mood != widget.mood) {
      _syncAnimationLoop(resetFrame: true);
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  CharacterAnimationClip? get _activeClip {
    final state =
        widget.mood == CharacterOverlayMood.pageTurnAssist
            ? CharacterAnimationState.pageTurnAssist
            : CharacterAnimationState.idle;
    return widget.character.clipForState(
      state,
      preferReturn: widget.isDashing,
    );
  }

  bool get _usesProceduralSprite {
    final frames = _activeClip?.frames ?? const <String>[];
    if (frames.isEmpty) {
      return true;
    }
    return frames.every(
      (frame) => frame.contains('assets/characters/placeholder/'),
    );
  }

  void _syncAnimationLoop({bool resetFrame = false}) {
    _frameTimer?.cancel();

    final clip = _activeClip;
    final frameCount = math.max(1, clip?.frames.length ?? 0);
    if (resetFrame) {
      _frameIndex = 0;
    } else {
      _frameIndex = _frameIndex % frameCount;
    }

    if (!widget.autoPlay || frameCount <= 1) {
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final fps = math.max(1, clip?.fps ?? 4);
    final frameDuration = Duration(milliseconds: (1000 / fps).round());

    _frameTimer = Timer.periodic(frameDuration, (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (clip?.loop ?? true) {
          _frameIndex = (_frameIndex + 1) % frameCount;
        } else {
          _frameIndex = math.min(_frameIndex + 1, frameCount - 1);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isExcited = widget.mood == CharacterOverlayMood.pageTurnAssist;
    final pulse = widget.autoPlay && _frameIndex.isOdd;
    final motionScale = widget.isDashing ? 0.94 : (isExcited ? 1.10 : 1.0);
    final slideOffset = isExcited
        ? Offset(widget.facingRight ? -0.05 : 0.05, -0.03)
        : Offset(0, pulse ? -0.012 : 0.012);
    final rotationTurns = widget.isDashing
        ? (widget.facingRight ? -0.010 : 0.010)
        : (pulse ? (widget.facingRight ? -0.004 : 0.004) : 0.0);

    return IgnorePointer(
      child: AnimatedSlide(
        duration: Duration(milliseconds: widget.isDashing ? 180 : 240),
        curve: widget.isDashing ? Curves.easeOutCubic : Curves.easeInOutSine,
        offset: slideOffset,
        child: AnimatedScale(
          duration: Duration(milliseconds: widget.isDashing ? 180 : 260),
          curve: widget.isDashing ? Curves.easeOutCubic : Curves.easeOutBack,
          scale: motionScale,
          child: AnimatedRotation(
            duration: Duration(milliseconds: widget.isDashing ? 180 : 260),
            curve: Curves.easeInOut,
            turns: rotationTurns,
            child: AnimatedOpacity(
              duration: Duration(milliseconds: widget.isDashing ? 120 : 180),
              opacity: widget.isDashing ? 0.88 : 0.98,
              child: SizedBox(
                width: widget.boxWidth,
                height: widget.boxHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_usesProceduralSprite)
                      _ProceduralCharacterSprite(
                        role: widget.character.role,
                        style: widget.style,
                        accentColor: widget.accentColor,
                        facingRight: widget.facingRight,
                        excited: isExcited,
                        blinkClosed: pulse && !isExcited,
                        frameIndex: _frameIndex,
                      )
                    else if (_activeClip != null && _activeClip!.frames.isNotEmpty)
                      Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..scale(widget.facingRight ? 1.0 : -1.0, 1.0),
                        child: Image.asset(
                          _activeClip!.frames[
                              _frameIndex % _activeClip!.frames.length],
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                          errorBuilder: (context, error, stackTrace) {
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    Positioned(
                      left: widget.boxWidth * 0.18,
                      right: widget.boxWidth * 0.18,
                      bottom: 8,
                      child: IgnorePointer(
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.10),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
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
    );
  }
}

class _ProceduralCharacterSprite extends StatelessWidget {
  final String role;
  final String style;
  final Color accentColor;
  final bool facingRight;
  final bool excited;
  final bool blinkClosed;
  final int frameIndex;

  const _ProceduralCharacterSprite({
    required this.role,
    required this.style,
    required this.accentColor,
    required this.facingRight,
    required this.excited,
    required this.blinkClosed,
    required this.frameIndex,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ProceduralCharacterPainter(
        role: role,
        style: style,
        accentColor: accentColor,
        facingRight: facingRight,
        excited: excited,
        blinkClosed: blinkClosed,
        frameIndex: frameIndex,
      ),
    );
  }
}

class _ProceduralCharacterPainter extends CustomPainter {
  final String role;
  final String style;
  final Color accentColor;
  final bool facingRight;
  final bool excited;
  final bool blinkClosed;
  final int frameIndex;

  const _ProceduralCharacterPainter({
    required this.role,
    required this.style,
    required this.accentColor,
    required this.facingRight,
    required this.excited,
    required this.blinkClosed,
    required this.frameIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final spec = _spriteSpecFor(style, role, accentColor);
    final eyePaint = Paint()
      ..color = spec.eyeColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final strokePaint = Paint()
      ..color = spec.lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.24,
        size.height * 0.50,
        size.width * 0.52,
        size.height * 0.34,
      ),
      const Radius.circular(24),
    );
    final headCenter = Offset(size.width * 0.5, size.height * 0.34);
    final headRadius = math.min(size.width, size.height) * 0.22;
    final sway = frameIndex.isOdd ? 1.5 : -1.5;

    canvas.drawRRect(
      bodyRect,
      Paint()
        ..shader = LinearGradient(
          colors: [spec.outfitPrimary, spec.outfitSecondary],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(bodyRect.outerRect),
    );

    canvas.drawCircle(
      Offset(headCenter.dx, headCenter.dy + sway * 0.18),
      headRadius,
      Paint()..color = spec.skinColor,
    );

    final hairPath = Path()
      ..moveTo(headCenter.dx - headRadius * 1.05, headCenter.dy - headRadius * 0.18)
      ..quadraticBezierTo(
        headCenter.dx,
        headCenter.dy - headRadius * 1.35,
        headCenter.dx + headRadius * 1.05,
        headCenter.dy - headRadius * 0.18,
      )
      ..lineTo(headCenter.dx + headRadius * 0.82, headCenter.dy + headRadius * 0.34)
      ..quadraticBezierTo(
        headCenter.dx,
        headCenter.dy - headRadius * 0.08,
        headCenter.dx - headRadius * 0.82,
        headCenter.dy + headRadius * 0.34,
      )
      ..close();
    canvas.drawPath(hairPath, Paint()..color = spec.hairColor);

    _paintAccessory(canvas, size, spec, headCenter, headRadius);

    final leftEye = Offset(headCenter.dx - headRadius * 0.34, headCenter.dy - headRadius * 0.04);
    final rightEye = Offset(headCenter.dx + headRadius * 0.34, headCenter.dy - headRadius * 0.04);
    if (blinkClosed) {
      canvas.drawLine(
        leftEye.translate(-5, 0),
        leftEye.translate(5, 0),
        eyePaint,
      );
      canvas.drawLine(
        rightEye.translate(-5, 0),
        rightEye.translate(5, 0),
        eyePaint,
      );
    } else {
      canvas.drawCircle(leftEye, excited ? 5.0 : 4.4, Paint()..color = spec.eyeColor);
      canvas.drawCircle(rightEye, excited ? 5.0 : 4.4, Paint()..color = spec.eyeColor);
    }

    canvas.drawCircle(
      Offset(headCenter.dx - headRadius * 0.36, headCenter.dy + headRadius * 0.22),
      3.5,
      Paint()..color = spec.cheekColor,
    );
    canvas.drawCircle(
      Offset(headCenter.dx + headRadius * 0.36, headCenter.dy + headRadius * 0.22),
      3.5,
      Paint()..color = spec.cheekColor,
    );

    final mouthRect = Rect.fromCenter(
      center: Offset(headCenter.dx, headCenter.dy + headRadius * 0.34),
      width: excited ? headRadius * 0.52 : headRadius * 0.44,
      height: excited ? headRadius * 0.34 : headRadius * 0.24,
    );
    if (excited) {
      canvas.drawArc(mouthRect, 0.1, math.pi - 0.2, false, strokePaint);
    } else {
      canvas.drawArc(mouthRect, 0.25, math.pi - 0.5, false, strokePaint);
    }

    final armPaint = Paint()
      ..color = spec.outfitPrimary.withOpacity(0.92)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final leftArmY = size.height * 0.60 + (excited ? -4 : 0);
    final rightArmY = size.height * 0.60 + (excited ? -2 : 2);
    canvas.drawLine(
      Offset(size.width * 0.26, leftArmY),
      Offset(size.width * 0.13, leftArmY + (excited ? -12 : 6)),
      armPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.74, rightArmY),
      Offset(size.width * 0.87, rightArmY + (excited ? -10 : 6)),
      armPaint,
    );

    if (style == 'pokemon') {
      _paintSpark(canvas, Offset(size.width * 0.18, size.height * 0.23), spec.badgeColor);
      _paintSpark(canvas, Offset(size.width * 0.82, size.height * 0.19), spec.badgeColor);
    } else if (style == 'naruto') {
      canvas.drawLine(
        Offset(size.width * 0.14, size.height * 0.40),
        Offset(size.width * 0.08, size.height * 0.48),
        Paint()
          ..color = spec.badgeColor.withOpacity(0.6)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(size.width * 0.86, size.height * 0.40),
        Offset(size.width * 0.92, size.height * 0.48),
        Paint()
          ..color = spec.badgeColor.withOpacity(0.6)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    } else if (style == 'ghibli') {
      canvas.drawCircle(
        Offset(size.width * 0.18, size.height * 0.24),
        6,
        Paint()..color = spec.badgeColor.withOpacity(0.55),
      );
      canvas.drawCircle(
        Offset(size.width * 0.82, size.height * 0.22),
        4,
        Paint()..color = spec.badgeColor.withOpacity(0.45),
      );
    }
  }

  void _paintAccessory(
    Canvas canvas,
    Size size,
    _SpriteSpec spec,
    Offset headCenter,
    double headRadius,
  ) {
    switch (style) {
      case 'pokemon':
        final capPaint = Paint()..color = spec.badgeColor;
        canvas.drawArc(
          Rect.fromCircle(
            center: headCenter.translate(0, -headRadius * 0.30),
            radius: headRadius * 0.95,
          ),
          math.pi,
          math.pi,
          true,
          capPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              headCenter.dx - headRadius * 0.72,
              headCenter.dy - headRadius * 0.08,
              headRadius * 1.44,
              headRadius * 0.22,
            ),
            const Radius.circular(999),
          ),
          Paint()..color = spec.lineColor.withOpacity(0.82),
        );
        canvas.drawCircle(
          headCenter.translate(0, -headRadius * 0.44),
          6,
          Paint()..color = Colors.white,
        );
        break;
      case 'naruto':
        final bandRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            headCenter.dx - headRadius * 0.96,
            headCenter.dy - headRadius * 0.40,
            headRadius * 1.92,
            headRadius * 0.34,
          ),
          const Radius.circular(8),
        );
        canvas.drawRRect(bandRect, Paint()..color = spec.badgeColor);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              headCenter.dx - headRadius * 0.42,
              headCenter.dy - headRadius * 0.37,
              headRadius * 0.84,
              headRadius * 0.28,
            ),
            const Radius.circular(6),
          ),
          Paint()..color = const Color(0xFFD9DDE2),
        );
        canvas.drawLine(
          Offset(headCenter.dx + headRadius * 0.96, headCenter.dy - headRadius * 0.26),
          Offset(headCenter.dx + headRadius * 1.24, headCenter.dy - headRadius * 0.02),
          Paint()
            ..color = spec.badgeColor
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          Offset(headCenter.dx + headRadius * 0.86, headCenter.dy - headRadius * 0.20),
          Offset(headCenter.dx + headRadius * 1.12, headCenter.dy + headRadius * 0.10),
          Paint()
            ..color = spec.badgeColor.withOpacity(0.8)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round,
        );
        break;
      case 'ghibli':
        final leaf = Path()
          ..moveTo(headCenter.dx, headCenter.dy - headRadius * 1.12)
          ..quadraticBezierTo(
            headCenter.dx + headRadius * 0.42,
            headCenter.dy - headRadius * 0.84,
            headCenter.dx + headRadius * 0.26,
            headCenter.dy - headRadius * 0.34,
          )
          ..quadraticBezierTo(
            headCenter.dx,
            headCenter.dy - headRadius * 0.54,
            headCenter.dx - headRadius * 0.22,
            headCenter.dy - headRadius * 0.24,
          )
          ..quadraticBezierTo(
            headCenter.dx - headRadius * 0.36,
            headCenter.dy - headRadius * 0.82,
            headCenter.dx,
            headCenter.dy - headRadius * 1.12,
          )
          ..close();
        canvas.drawPath(leaf, Paint()..color = spec.badgeColor);
        break;
      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              size.width * 0.33,
              size.height * 0.62,
              size.width * 0.34,
              size.height * 0.08,
            ),
            const Radius.circular(999),
          ),
          Paint()..color = spec.badgeColor.withOpacity(0.75),
        );
        break;
    }
  }

  void _paintSpark(Canvas canvas, Offset center, Color color) {
    final paint = Paint()
      ..color = color.withOpacity(0.75)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center.translate(-4, 0), center.translate(4, 0), paint);
    canvas.drawLine(center.translate(0, -4), center.translate(0, 4), paint);
  }

  @override
  bool shouldRepaint(covariant _ProceduralCharacterPainter oldDelegate) {
    return oldDelegate.role != role ||
        oldDelegate.style != style ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.facingRight != facingRight ||
        oldDelegate.excited != excited ||
        oldDelegate.blinkClosed != blinkClosed ||
        oldDelegate.frameIndex != frameIndex;
  }
}

class _OverlayTheme {
  final Color cardStart;
  final Color cardEnd;
  final Color borderColor;
  final Color shadowColor;
  final Color labelColor;
  final Color badgeColor;
  final Color spriteGlow;
  final double cardRadius;
  final double spriteRadius;

  const _OverlayTheme({
    required this.cardStart,
    required this.cardEnd,
    required this.borderColor,
    required this.shadowColor,
    required this.labelColor,
    required this.badgeColor,
    required this.spriteGlow,
    required this.cardRadius,
    required this.spriteRadius,
  });
}

class _SpriteSpec {
  final Color skinColor;
  final Color hairColor;
  final Color eyeColor;
  final Color cheekColor;
  final Color outfitPrimary;
  final Color outfitSecondary;
  final Color badgeColor;
  final Color lineColor;

  const _SpriteSpec({
    required this.skinColor,
    required this.hairColor,
    required this.eyeColor,
    required this.cheekColor,
    required this.outfitPrimary,
    required this.outfitSecondary,
    required this.badgeColor,
    required this.lineColor,
  });
}

_OverlayTheme _overlayThemeFor(String style, String role, Color accentColor) {
  switch (style) {
    case 'pokemon':
      return _OverlayTheme(
        cardStart: const Color(0xFF16253A).withOpacity(0.94),
        cardEnd: const Color(0xFF243F63).withOpacity(0.88),
        borderColor: accentColor.withOpacity(0.85),
        shadowColor: accentColor.withOpacity(0.25),
        labelColor: Colors.white,
        badgeColor: const Color(0xFFFFD54F),
        spriteGlow: accentColor,
        cardRadius: 20,
        spriteRadius: 18,
      );
    case 'naruto':
      return _OverlayTheme(
        cardStart: const Color(0xFF201A2E).withOpacity(0.94),
        cardEnd: const Color(0xFF3A2D23).withOpacity(0.90),
        borderColor: accentColor.withOpacity(0.82),
        shadowColor: accentColor.withOpacity(0.24),
        labelColor: const Color(0xFFFFF1D6),
        badgeColor: const Color(0xFFFFA43B),
        spriteGlow: accentColor.withOpacity(0.9),
        cardRadius: 18,
        spriteRadius: 16,
      );
    case 'ghibli':
      return _OverlayTheme(
        cardStart: const Color(0xFFEDF5E8).withOpacity(0.95),
        cardEnd: const Color(0xFFD9E8D2).withOpacity(0.92),
        borderColor: accentColor.withOpacity(0.55),
        shadowColor: const Color(0xFF6D8C68).withOpacity(0.18),
        labelColor: const Color(0xFF415B44),
        badgeColor: const Color(0xFF7E9E6C),
        spriteGlow: accentColor.withOpacity(0.6),
        cardRadius: 28,
        spriteRadius: 24,
      );
    default:
      return _OverlayTheme(
        cardStart: accentColor.withOpacity(0.28),
        cardEnd: Colors.white.withOpacity(0.06),
        borderColor: accentColor.withOpacity(0.42),
        shadowColor: Colors.black.withOpacity(0.22),
        labelColor: accentColor,
        badgeColor: accentColor,
        spriteGlow: accentColor.withOpacity(0.8),
        cardRadius: 24,
        spriteRadius: 18,
      );
  }
}

_SpriteSpec _spriteSpecFor(String style, String role, Color accentColor) {
  final isMom = role == 'mom';
  switch (style) {
    case 'pokemon':
      return _SpriteSpec(
        skinColor: const Color(0xFFFFD7AF),
        hairColor: isMom ? const Color(0xFF5A3563) : const Color(0xFF3B4C8A),
        eyeColor: const Color(0xFF2D2D2D),
        cheekColor: const Color(0xFFFFB7B1),
        outfitPrimary: isMom ? const Color(0xFF59C7F4) : const Color(0xFFFF8D5D),
        outfitSecondary: isMom ? const Color(0xFF2676B8) : const Color(0xFFC7442F),
        badgeColor: const Color(0xFFFFD84D),
        lineColor: const Color(0xFF7A3B2B),
      );
    case 'naruto':
      return _SpriteSpec(
        skinColor: const Color(0xFFFFD3B0),
        hairColor: isMom ? const Color(0xFF3F294D) : const Color(0xFF20190F),
        eyeColor: const Color(0xFF241C18),
        cheekColor: const Color(0xFFECA59A),
        outfitPrimary: isMom ? const Color(0xFF8A76F9) : const Color(0xFFFFA134),
        outfitSecondary: isMom ? const Color(0xFF493D87) : const Color(0xFF763C17),
        badgeColor: const Color(0xFF5C6674),
        lineColor: const Color(0xFF5A3429),
      );
    case 'ghibli':
      return _SpriteSpec(
        skinColor: const Color(0xFFF8D9BA),
        hairColor: isMom ? const Color(0xFF775E4B) : const Color(0xFF5D4B39),
        eyeColor: const Color(0xFF43352F),
        cheekColor: const Color(0xFFE7B8A6),
        outfitPrimary: isMom ? const Color(0xFF90C3A2) : const Color(0xFFE4B983),
        outfitSecondary: isMom ? const Color(0xFF5F8B6D) : const Color(0xFF9E7A53),
        badgeColor: const Color(0xFF7BA35B),
        lineColor: const Color(0xFF775B4A),
      );
    default:
      return _SpriteSpec(
        skinColor: const Color(0xFFFFD8B7),
        hairColor: isMom ? const Color(0xFF7B4E6A) : const Color(0xFF4A5571),
        eyeColor: const Color(0xFF2E2E2E),
        cheekColor: const Color(0xFFE7A9A9),
        outfitPrimary: accentColor.withOpacity(0.95),
        outfitSecondary: accentColor.withOpacity(0.55),
        badgeColor: accentColor.withOpacity(0.85),
        lineColor: const Color(0xFF7A4D42),
      );
  }
}
