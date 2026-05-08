import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/character.dart';

class SingleCharacterSceneOverlay extends StatefulWidget {
  final CharacterManifest character;
  final bool autoPlay;
  final bool canStart;
  final double homeRegionHeight;
  final double scaleMultiplier;

  const SingleCharacterSceneOverlay({
    super.key,
    required this.character,
    required this.autoPlay,
    this.canStart = true,
    this.homeRegionHeight = 140,
    this.scaleMultiplier = 1.0,
  });

  @override
  State<SingleCharacterSceneOverlay> createState() =>
      _SingleCharacterSceneOverlayState();
}

class _SingleCharacterSceneOverlayState
    extends State<SingleCharacterSceneOverlay> {
  static const Duration _frameDuration = Duration(milliseconds: 80);
  static const int _annoyedHoldFrame = 18;
  static const Duration _annoyedRecoveryFrameDuration = Duration(
    milliseconds: 56,
  );

  final math.Random _random = math.Random();
  final Set<String> _precachedFrames = {};

  Timer? _frameTimer;
  Timer? _startTimer;
  Timer? _actionTimer;
  Timer? _exitTimer;
  Timer? _respawnTimer;
  Timer? _dashHomeTimer;

  CharacterAnimationClip? _activeClip;
  String _activeClipId = 'IDLE';
  int _frameIndex = 0;
  int _frameDirection = 1;
  int _frameStep = 1;
  double _movementProgress = 0.0;
  double _dashVisualPhase = 0.0;
  bool _visible = false;
  bool _dragging = false;
  bool _initialized = false;
  bool _started = false;
  bool _facingRight = true;
  Offset _currentOffset = Offset.zero;
  Offset _homeOffset = Offset.zero;
  Offset _dragStartLocalOffset = Offset.zero;
  Size _viewportSize = Size.zero;
  VoidCallback? _onClipComplete;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheCharacterFrames();
  }

  @override
  void didUpdateWidget(covariant SingleCharacterSceneOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id != widget.character.id) {
      _resetLifecycle();
      _precacheCharacterFrames();
    }
    if (!oldWidget.canStart && widget.canStart) {
      _scheduleEntrance();
    }
  }

  @override
  void dispose() {
    _cancelAllTimers();
    super.dispose();
  }

  void _precacheCharacterFrames() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      for (final clip in widget.character.animations.values) {
        for (final frame in clip.frames) {
          if (_precachedFrames.add(frame)) {
            precacheImage(AssetImage(frame), context);
          }
        }
      }
    });
  }

  void _resetLifecycle() {
    _cancelAllTimers();
    _frameIndex = 0;
    _frameDirection = 1;
    _frameStep = 1;
    _visible = false;
    _dragging = false;
    _initialized = false;
    _started = false;
    _activeClip = null;
    _activeClipId = 'IDLE';
    _movementProgress = 0.0;
    _dashVisualPhase = 0.0;
  }

  void _cancelAllTimers() {
    _frameTimer?.cancel();
    _startTimer?.cancel();
    _actionTimer?.cancel();
    _exitTimer?.cancel();
    _respawnTimer?.cancel();
    _dashHomeTimer?.cancel();
  }

  void _ensureInitialized(Size size) {
    if (_initialized && _viewportSize == size) {
      return;
    }

    final box = _characterBox(size);
    _viewportSize = size;
    _homeOffset = _randomHomeOffset(size, box);

    if (!_visible) {
      _currentOffset = _homeOffset;
    } else {
      _currentOffset = _clampOffset(_currentOffset);
    }

    _initialized = true;
    _scheduleEntrance();
  }

  Size _characterBox(Size size) {
    final width =
        (widget.homeRegionHeight * widget.character.scale).clamp(
              96.0,
              math.min(176.0, size.width * 0.25),
            )
            as double;
    final scaledWidth =
        (width * widget.scaleMultiplier).clamp(
              84.0,
              math.min(420.0, size.width * 0.55),
            )
            as double;
    return Size(scaledWidth, scaledWidth * 1.30);
  }

  Offset _randomHomeOffset(Size size, Size box) {
    final homeBandTop = math.max(0.0, size.height - widget.homeRegionHeight);
    final zoneWidth = math.max(box.width, size.width * 0.18);
    final homeX = (size.width * 0.04) + _random.nextDouble() * zoneWidth * 0.35;
    final homeY =
        homeBandTop + math.max(0.0, widget.homeRegionHeight - box.height - 4);
    return _clampOffsetForSize(Offset(homeX, homeY), size, box);
  }

  Offset _randomBottomRestOffset(Size size, Size box) {
    final homeBandTop = math.max(0.0, size.height - widget.homeRegionHeight);
    final minX = math.max(0.0, size.width * 0.04);
    final maxX = math.max(minX, size.width - box.width - size.width * 0.04);
    final homeX = minX + _random.nextDouble() * (maxX - minX);
    final homeY =
        homeBandTop + math.max(0.0, widget.homeRegionHeight - box.height - 4);
    return _clampOffsetForSize(Offset(homeX, homeY), size, box);
  }

  void _scheduleEntrance() {
    if (!_initialized ||
        _started ||
        !widget.autoPlay ||
        !widget.canStart ||
        _viewportSize == Size.zero) {
      return;
    }

    _started = true;
    final delay = Duration(seconds: 2 + _random.nextInt(3));
    _startTimer?.cancel();
    _startTimer = Timer(delay, () {
      if (mounted && widget.canStart && widget.autoPlay) {
        _peekIn();
      }
    });
  }

  void _peekIn() {
    final box = _characterBox(_viewportSize);
    final start = Offset(-box.width * 0.9, _homeOffset.dy);
    setState(() {
      _visible = true;
      _currentOffset = start;
      _facingRight = true;
    });

    _playMovingClip(
      clipId: 'PEEK_IN',
      from: start,
      to: _homeOffset,
      onComplete: _startIdleLoop,
    );
  }

  void _startIdleLoop() {
    _playClip('IDLE', loop: true, pingPong: true);
    _scheduleRandomAction();
    _scheduleExit();
  }

  void _scheduleRandomAction() {
    _actionTimer?.cancel();
    if (!widget.autoPlay || !_visible || _dragging) {
      return;
    }

    final delay = Duration(seconds: 5 + _random.nextInt(8));
    _actionTimer = Timer(delay, () {
      if (!mounted || !_visible || _dragging) {
        return;
      }
      _runRandomAction();
    });
  }

  void _scheduleExit() {
    _exitTimer?.cancel();
    if (!widget.autoPlay || !_visible || _dragging) {
      return;
    }

    final delay = Duration(seconds: 34 + _random.nextInt(30));
    _exitTimer = Timer(delay, () {
      if (mounted && _visible && !_dragging) {
        _walkOut();
      }
    });
  }

  void _scheduleDashHome() {
    _dashHomeTimer?.cancel();
    if ((_currentOffset - _homeOffset).distance < 18) {
      _startIdleLoop();
      return;
    }

    final delay = Duration(milliseconds: 900 + _random.nextInt(1300));
    _dashHomeTimer = Timer(delay, () {
      if (mounted && _visible && !_dragging) {
        final target = _randomBottomRestOffset(
          _viewportSize,
          _characterBox(_viewportSize),
        );
        _homeOffset = target;
        _dashTo(target, onComplete: _startIdleLoop);
      }
    });
  }

  void _runRandomAction() {
    final roll = _random.nextInt(12);
    if (roll <= 4) {
      _startIdleLoop();
      return;
    }
    if (roll <= 7 && widget.character.clip('WAVE') != null) {
      _playClip('WAVE', onComplete: _startIdleLoop);
      return;
    }
    if (roll <= 9 && widget.character.clip('FLAME') != null) {
      _playClip('FLAME', onComplete: _startIdleLoop);
      return;
    }
    if (widget.character.clip('DASH') != null) {
      final box = _characterBox(_viewportSize);
      final maxX = math.max(0.0, _viewportSize.width - box.width);
      final distanceLeft = _currentOffset.dx;
      final distanceRight = maxX - _currentOffset.dx;
      final direction = distanceRight >= distanceLeft ? 1.0 : -1.0;
      final availableDistance = direction > 0 ? distanceRight : distanceLeft;
      final travel = math
          .max(
            box.width * 1.45,
            availableDistance * (0.45 + _random.nextDouble() * 0.25),
          )
          .clamp(0.0, availableDistance);
      final target = Offset(
        (_currentOffset.dx + travel * direction).clamp(0.0, maxX),
        _homeOffset.dy,
      );
      _dashTo(target, onComplete: _startIdleLoop);
      return;
    }

    _startIdleLoop();
  }

  void _walkOut() {
    final box = _characterBox(_viewportSize);
    final target = Offset(
      _viewportSize.width + box.width * 0.18,
      _homeOffset.dy,
    );
    _playMovingClip(
      clipId: 'WALK_OUT',
      from: _currentOffset,
      to: target,
      onComplete: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _visible = false;
          _activeClip = null;
        });
        _respawnTimer?.cancel();
        _respawnTimer = Timer(const Duration(seconds: 8), () {
          if (!mounted) {
            return;
          }
          _started = false;
          _scheduleEntrance();
        });
      },
    );
  }

  void _dashTo(Offset target, {VoidCallback? onComplete}) {
    _playMovingClip(
      clipId: 'DASH',
      from: _currentOffset,
      to: _clampOffset(target),
      onComplete: onComplete,
    );
  }

  void _playMovingClip({
    required String clipId,
    required Offset from,
    required Offset to,
    VoidCallback? onComplete,
  }) {
    final clip = widget.character.clip(clipId);
    if (clip == null || clip.frames.isEmpty) {
      onComplete?.call();
      return;
    }

    final distance = (to - from).distance;
    final frameCount = math.max(1, clip.frames.length);
    final motion = _motionSpecForTravel(
      clipId: clipId,
      distance: distance,
      frameCount: frameCount,
    );
    _facingRight = to.dx >= from.dx;
    _dashVisualPhase = _random.nextDouble() * math.pi;

    _playClip(
      clipId,
      frameDuration: motion.frameDuration,
      frameStep: motion.frameStep,
      onFrame: (progress) {
        final eased = motion.curve.transform(progress);
        setState(() {
          _movementProgress = progress;
          _currentOffset = Offset.lerp(from, to, eased) ?? to;
        });
      },
      onComplete: () {
        setState(() {
          _movementProgress = 0.0;
          _currentOffset = to;
        });
        onComplete?.call();
      },
    );
  }

  _MotionSpec _motionSpecForTravel({
    required String clipId,
    required double distance,
    required int frameCount,
  }) {
    if (clipId == 'DASH') {
      final longDistance = _viewportSize.width * 0.45;
      final veryLongDistance = _viewportSize.width * 0.68;
      final totalMs = (distance * 0.55).clamp(240.0, 780.0).round();
      final frameStep = distance > veryLongDistance
          ? 3
          : distance > longDistance
          ? 2
          : 1;
      final ticks = (frameCount / frameStep).ceil().clamp(1, frameCount);
      return _MotionSpec(
        frameDuration: Duration(
          milliseconds: (totalMs / ticks).clamp(18.0, 70.0).round(),
        ),
        frameStep: frameStep,
        curve: Curves.easeOutCubic,
      );
    }

    final totalMs = (distance * 1.15).clamp(760.0, 1450.0).round();
    return _MotionSpec(
      frameDuration: Duration(
        milliseconds: (totalMs / frameCount).clamp(32.0, 80.0).round(),
      ),
      frameStep: 1,
      curve: Curves.easeInOutCubic,
    );
  }

  void _playClip(
    String clipId, {
    bool loop = false,
    bool pingPong = false,
    Duration frameDuration = _frameDuration,
    bool preserveFrame = false,
    int frameStep = 1,
    ValueChanged<double>? onFrame,
    VoidCallback? onComplete,
  }) {
    final clip = widget.character.clip(clipId) ?? widget.character.clip('IDLE');
    if (clip == null || clip.frames.isEmpty) {
      return;
    }

    _frameTimer?.cancel();
    _actionTimer?.cancel();
    _exitTimer?.cancel();

    setState(() {
      _activeClip = clip;
      _activeClipId = clipId;
      if (!preserveFrame) {
        _frameIndex = 0;
      } else {
        _frameIndex = _frameIndex.clamp(0, clip.frames.length - 1);
      }
      _frameDirection = 1;
      _frameStep = frameStep.clamp(1, 4);
      _onClipComplete = onComplete;
    });

    if (!widget.autoPlay || clip.frames.length <= 1) {
      if (!loop) {
        Future.microtask(_finishClip);
      }
      return;
    }

    _frameTimer = Timer.periodic(frameDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        final lastFrame = clip.frames.length - 1;
        if (loop || clip.loop) {
          if (pingPong) {
            _frameIndex += _frameDirection * _frameStep;
            if (_frameIndex >= lastFrame || _frameIndex <= 0) {
              _frameDirection *= -1;
              _frameIndex = _frameIndex.clamp(0, lastFrame);
            }
          } else {
            _frameIndex = (_frameIndex + _frameStep) % clip.frames.length;
          }
          return;
        }

        if (_frameIndex < lastFrame) {
          _frameIndex = math.min(lastFrame, _frameIndex + _frameStep);
          onFrame?.call(_frameIndex / lastFrame);
          return;
        }

        timer.cancel();
        Future.microtask(_finishClip);
      });
    });
  }

  void _finishClip() {
    final callback = _onClipComplete;
    _onClipComplete = null;
    callback?.call();
  }

  Offset _clampOffset(Offset offset) {
    final box = _characterBox(_viewportSize);
    return _clampOffsetForSize(offset, _viewportSize, box);
  }

  Offset _clampOffsetForSize(Offset offset, Size size, Size box) {
    final maxX = math.max(0.0, size.width - box.width);
    final maxY = math.max(0.0, size.height - box.height);
    return Offset(offset.dx.clamp(0.0, maxX), offset.dy.clamp(0.0, maxY));
  }

  void _handlePanStart(DragStartDetails details) {
    if (!_visible) {
      return;
    }

    _dashHomeTimer?.cancel();
    _actionTimer?.cancel();
    _exitTimer?.cancel();
    _frameTimer?.cancel();

    final box = _characterBox(_viewportSize);
    _dragStartLocalOffset = Offset(
      details.localPosition.dx.clamp(0.0, box.width),
      details.localPosition.dy.clamp(0.0, box.height),
    );

    setState(() {
      _dragging = true;
      _activeClip =
          widget.character.clip('ANNOYED') ?? widget.character.clip('IDLE');
      _frameIndex = 0;
    });
    _playAnnoyedToHold();
  }

  void _playAnnoyedToHold() {
    final clip =
        widget.character.clip('ANNOYED') ?? widget.character.clip('IDLE');
    if (clip == null || clip.frames.isEmpty) {
      return;
    }

    final holdFrame = math.min(
      clip.frames.length - 1,
      _annoyedHoldFrameForStyle,
    );
    _frameTimer = Timer.periodic(_frameDuration, (timer) {
      if (!mounted || !_dragging) {
        timer.cancel();
        return;
      }

      if (_frameIndex >= holdFrame) {
        timer.cancel();
        setState(() {
          _frameIndex = holdFrame;
        });
        return;
      }

      setState(() {
        _frameIndex++;
      });
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_dragging) {
      return;
    }

    final targetTopLeft = details.localPosition - _dragStartLocalOffset;
    setState(() {
      _currentOffset = _clampOffset(_currentOffset + details.delta);
      if (targetTopLeft.distance.isFinite) {
        _currentOffset = _clampOffset(_currentOffset);
      }
    });
  }

  void _handlePanEnd([DragEndDetails? _]) {
    if (!_dragging) {
      return;
    }

    setState(() {
      _dragging = false;
    });

    _playClip(
      'ANNOYED',
      preserveFrame: true,
      frameDuration: _annoyedRecoveryFrameDuration,
      frameStep: 2,
      onComplete: _scheduleDashHome,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) {
          return const SizedBox.shrink();
        }

        _ensureInitialized(size);

        if (!_visible || _activeClip == null || _activeClip!.frames.isEmpty) {
          return const SizedBox.expand();
        }

        final box = _characterBox(size);
        final frame =
            _activeClip!.frames[_frameIndex % _activeClip!.frames.length];
        final isDashing = _activeClipId == 'DASH';
        final dashBob = isDashing
            ? -math.sin((_movementProgress * math.pi * 4) + _dashVisualPhase) *
                  3.0
            : 0.0;
        final dashStretch = isDashing
            ? 1.0 + (math.sin(_movementProgress * math.pi) * 0.07)
            : 1.0;
        final dashSquash = isDashing
            ? 1.0 - (math.sin(_movementProgress * math.pi) * 0.025)
            : 1.0;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: _currentOffset.dx,
              top: _currentOffset.dy,
              width: box.width,
              height: box.height,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: _handlePanStart,
                onPanUpdate: _handlePanUpdate,
                onPanEnd: _handlePanEnd,
                onPanCancel: () => _handlePanEnd(),
                child: Transform.translate(
                  offset: Offset(0, dashBob),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..scale(
                        (_facingRight ? 1.0 : -1.0) * dashStretch,
                        dashSquash,
                      ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Image.asset(
                        frame,
                        width: box.width,
                        height: box.height,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint(
                            '[CharacterOverlay] failed frame=$frame error=$error',
                          );
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

extension on _SingleCharacterSceneOverlayState {
  int get _annoyedHoldFrameForStyle {
    if (widget.character.style == CharacterStyle.monsterAdventure) {
      return 45;
    }

    return _SingleCharacterSceneOverlayState._annoyedHoldFrame;
  }
}

class _MotionSpec {
  final Duration frameDuration;
  final int frameStep;
  final Curve curve;

  const _MotionSpec({
    required this.frameDuration,
    required this.frameStep,
    required this.curve,
  });
}
