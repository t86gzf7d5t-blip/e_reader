enum CharacterStyle {
  storybook,
  monsterAdventure,
  ninjaAnime,
  cozyWatercolor,
}

enum CharacterAnimationState {
  idle,
  wave,
  wobble,
  pageTurnAssist,
  dragged,
  annoyed,
  returnToSafeSpot,
  interactWithOtherCharacter,
  celebrate,
  sleep,
}

class CharacterAnimationClip {
  final String id;
  final List<String> frames;
  final int fps;
  final bool loop;

  const CharacterAnimationClip({
    required this.id,
    required this.frames,
    required this.fps,
    required this.loop,
  });

  bool get hasFrames => frames.isNotEmpty;
}

class CharacterManifest {
  final String id;
  final String name;
  final String role;
  final CharacterStyle style;
  final String defaultPosition;
  final double scale;
  final Map<String, CharacterAnimationClip> animations;

  const CharacterManifest({
    required this.id,
    required this.name,
    required this.role,
    required this.style,
    required this.defaultPosition,
    required this.scale,
    required this.animations,
  });

  CharacterAnimationClip? clip(String id) => animations[id];

  CharacterAnimationClip? clipForState(
    CharacterAnimationState state, {
    bool preferReturn = false,
  }) {
    if (preferReturn && animations.containsKey('RETURN')) {
      return animations['RETURN'];
    }

    switch (state) {
      case CharacterAnimationState.pageTurnAssist:
        return animations['WAVE'] ??
            animations['WOBBLE'] ??
            animations['IDLE'];
      case CharacterAnimationState.annoyed:
        return animations['ANNOYED'] ?? animations['IDLE'];
      case CharacterAnimationState.returnToSafeSpot:
        return animations['RETURN'] ?? animations['IDLE'];
      case CharacterAnimationState.wave:
        return animations['WAVE'] ?? animations['IDLE'];
      case CharacterAnimationState.wobble:
        return animations['WOBBLE'] ?? animations['IDLE'];
      case CharacterAnimationState.interactWithOtherCharacter:
        return animations['WAVE'] ?? animations['IDLE'];
      case CharacterAnimationState.idle:
      case CharacterAnimationState.dragged:
      case CharacterAnimationState.celebrate:
      case CharacterAnimationState.sleep:
        return animations['IDLE'];
    }
  }

  List<String> get states => animations.keys.toList(growable: false);

  List<String> get idleFrames => clip('IDLE')?.frames ?? const [];

  bool get hasIdleFrames => idleFrames.isNotEmpty;
}
