import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/character.dart';

class SingleCharacterSceneOverlay extends StatefulWidget {
  final CharacterManifest character;
  final bool autoPlay;

  const SingleCharacterSceneOverlay({
    super.key,
    required this.character,
    required this.autoPlay,
  });

  @override
  State<SingleCharacterSceneOverlay> createState() =>
      _SingleCharacterSceneOverlayState();
}

class _SingleCharacterSceneOverlayState
    extends State<SingleCharacterSceneOverlay> {
  final math.Random _random = math.Random();

  Timer? _frameTimer;
  Timer? _actionTimer;
  Timer? _exitTimer;
  Timer? _respawnTimer;
  Timer? _dashHomeTimer;

  CharacterAnimationClip? _activeClip;
  String _activeClipId = 'IDLE';
  int _frameIndex = 0;
  bool _visible = false;
  bool _dragging = false;
  bool _initialized = false;
  Offset _currentOffset = Offset.zero;
  Offset _homeOffset = Offset.zero;
  Size _viewportSize = Size.zero;
  VoidCallback? _onClipComplete;
  bool _facingRight = true;
  double _tiltAngle = 0.0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant SingleCharacterSceneOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id != widget.character.id) {
      _cancelAllTimers();
      _frameIndex = 0;
      _visible = false;
      _dragging = false;
      _initialized = false;
      _activeClip = null;
      _activeClipId = 'IDLE';
    }
  }

  @override
  void dispose() {
    _cancelAllTimers();
    super.dispose();
  }

  void _cancelAllTimers() {
    _frameTimer?.cancel();
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
    _homeOffset = Offset(
      18,
      math.max(12, size.height - box.height - 24),
    );
    _currentOffset = _homeOffset;
    _initialized = true;

    if (!_visible && _activeClip == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startLifecycle();
        }
      });
    }
  }

  Size _characterBox(Size size) {
    final width = math.min(230.0, math.max(150.0, size.width * 0.18));
    return Size(width, width * 1.5);
  }

  void _startLifecycle() {
    final box = _characterBox(_viewportSize);
    final startOffset = Offset(-box.width * 0.78, _homeOffset.dy);
    setState(() {
      _visible = true;
      _currentOffset = startOffset;
      _facingRight = true;
      _tiltAngle = 0.0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _setTravelVisuals(startOffset, _homeOffset);
      setState(() {
        _currentOffset = _homeOffset;
      });
      _playClip(
        'ENTER',
        onComplete: _playReturnToIdle,
      );
    });
  }

  void _playReturnToIdle() {
    _playClip(
      'RETURN',
      onComplete: _startIdleLoop,
    );
  }

  void _startIdleLoop() {
    _playClip('IDLE', loop: true);
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

    final delay = Duration(seconds: 20 + _random.nextInt(21));
    _exitTimer = Timer(delay, () {
      if (!mounted || !_visible || _dragging) {
        return;
      }
      _playExitSequence();
    });
  }

  void _scheduleDashHome() {
    _dashHomeTimer?.cancel();
    if ((_currentOffset - _homeOffset).distance < 20) {
      return;
    }

    final delay = Duration(seconds: 2 + _random.nextInt(3));
    _dashHomeTimer = Timer(delay, () {
      if (!mounted || _dragging || !_visible) {
        return;
      }
      _playDashHome();
    });
  }

  void _runRandomAction() {
    final options = <String>[];
    if (widget.character.clip('WAVE') != null) {
      options.add('WAVE');
    }
    if (widget.character.clip('WOBBLE') != null) {
      options.add('WOBBLE');
    }
    if (widget.character.clip('DASH') != null) {
      options.add('DASH');
    }

    if (options.isEmpty) {
      _startIdleLoop();
      return;
    }

    final selected = options[_random.nextInt(options.length)];
    if (selected == 'WOBBLE') {
      _playClip(
        'WOBBLE',
        onComplete: _startIdleLoop,
      );
      return;
    }

    if (selected == 'DASH') {
      _playDashAction();
      return;
    }

    _playClip(
      'WAVE',
      onComplete: _playReturnToIdle,
    );
  }

  void _playExitSequence() {
    _actionTimer?.cancel();
    _exitTimer?.cancel();
    _dashHomeTimer?.cancel();
    final box = _characterBox(_viewportSize);
    final exitTarget = Offset(_viewportSize.width - (box.width * 0.18), _homeOffset.dy);
    _setTravelVisuals(_currentOffset, exitTarget);
    setState(() {
      _currentOffset = exitTarget;
    });
    _playClip('EXIT', onComplete: _hideAndRespawn);
  }

  void _hideAndRespawn() {
    setState(() {
      _visible = false;
    });
    _respawnTimer?.cancel();
    _respawnTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) {
        return;
      }
      _startLifecycle();
    });
  }

  void _playDashHome() {
    final startOffset = _currentOffset;
    _setTravelVisuals(startOffset, _homeOffset);
    setState(() {
      _currentOffset = _homeOffset;
    });
    _playClip(
      'DASH',
      onComplete: _playReturnToIdle,
    );
  }

  void _playClip(
    String clipId, {
    bool loop = false,
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
      _frameIndex = 0;
      _onClipComplete = onComplete;
    });

    if (!widget.autoPlay || clip.frames.length <= 1) {
      if (!loop) {
        Future.microtask(() => _finishClip());
      }
      return;
    }

    final fps = math.max(1, clip.fps);
    final duration = Duration(milliseconds: (1000 / fps).round());

    _frameTimer = Timer.periodic(duration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (loop || clip.loop) {
          _frameIndex = (_frameIndex + 1) % clip.frames.length;
          return;
        }

        if (_frameIndex < clip.frames.length - 1) {
          _frameIndex++;
          return;
        }

        timer.cancel();
        Future.microtask(_finishClip);
      });
    });
  }

  void _finishClip() {
    if (_activeClipId == 'RETURN' || _activeClipId == 'IDLE' || _activeClipId == 'WAVE' || _activeClipId == 'WOBBLE') {
      setState(() {
        _tiltAngle = 0.0;
        _facingRight = true;
      });
    }
    final callback = _onClipComplete;
    _onClipComplete = null;
    callback?.call();
  }

  void _playDashAction() {
    final box = _characterBox(_viewportSize);
    final current = _currentOffset;
    final target = Offset(
      (current.dx + math.max(44.0, box.width * 0.34)).clamp(
        0.0,
        math.max(0.0, _viewportSize.width - box.width),
      ),
      (current.dy - 10).clamp(
        0.0,
        math.max(0.0, _viewportSize.height - box.height),
      ),
    );
    _setTravelVisuals(current, target);
    setState(() {
      _currentOffset = target;
    });
    _playClip(
      'DASH',
      onComplete: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _currentOffset = _homeOffset;
        });
        _playReturnToIdle();
      },
    );
  }

  void _setTravelVisuals(Offset from, Offset to) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final angle = math.atan2(dy, dx);
    setState(() {
      _facingRight = dx >= 0;
      _tiltAngle = angle.clamp(-0.35, 0.35);
    });
  }

  void _handlePanStart(DragStartDetails details) {
    if (!_visible) {
      return;
    }
    _dashHomeTimer?.cancel();
    _actionTimer?.cancel();
    _exitTimer?.cancel();
    _frameTimer?.cancel();

    setState(() {
      _dragging = true;
      _activeClip = widget.character.clip('ANNOYED') ?? widget.character.clip('IDLE');
      _activeClipId = 'ANNOYED';
      _frameIndex = 0;
      _tiltAngle = 0.0;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_dragging) {
      return;
    }

    final box = _characterBox(_viewportSize);
    final maxX = math.max(0.0, _viewportSize.width - box.width);
    final maxY = math.max(0.0, _viewportSize.height - box.height);
    setState(() {
      _currentOffset = Offset(
        (_currentOffset.dx + details.delta.dx).clamp(0.0, maxX),
        (_currentOffset.dy + details.delta.dy).clamp(0.0, maxY),
      );
    });
  }

  void _handlePanEnd([DragEndDetails? _]) {
    if (!_dragging) {
      return;
    }

    setState(() {
      _dragging = false;
    });
    _playClip('RETURN', onComplete: _startIdleLoop);
    _scheduleDashHome();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _ensureInitialized(size);

        if (!_visible || _activeClip == null || _activeClip!.frames.isEmpty) {
          return const SizedBox.shrink();
        }

        final box = _characterBox(size);
        final frame = _activeClip!.frames[_frameIndex % _activeClip!.frames.length];

        final positionChild = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          onPanCancel: () => _handlePanEnd(),
          child: Transform.rotate(
            angle: _tiltAngle,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scale(_facingRight ? 1.0 : -1.0, 1.0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    frame,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
                  Positioned(
                    left: box.width * 0.2,
                    right: box.width * 0.2,
                    bottom: 10,
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
        );

        return Stack(
          children: [
            if (_dragging)
              Positioned(
                left: _currentOffset.dx,
                top: _currentOffset.dy,
                width: box.width,
                height: box.height,
                child: positionChild,
              )
            else
              AnimatedPositioned(
                duration: Duration(
                  milliseconds: switch (_activeClipId) {
                    'ENTER' => 900,
                    'EXIT' => 900,
                    'DASH' => 520,
                    _ => 240,
                  },
                ),
                curve: _activeClipId == 'DASH'
                    ? Curves.easeOutCubic
                    : Curves.easeInOutCubic,
                left: _currentOffset.dx,
                top: _currentOffset.dy,
                width: box.width,
                height: box.height,
                child: positionChild,
              ),
          ],
        );
      },
    );
  }
}
