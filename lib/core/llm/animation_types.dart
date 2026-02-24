enum CharacterAnimation {
  jump(animationIndex: 0, duration: Duration(seconds: 3)),
  spin(animationIndex: 1),
  think(animationIndex: 2),
  clap(animationIndex: 3),
  chickenDance(animationIndex: 4),
  thankful(animationIndex: 7),
  greet(animationIndex: 8),
  dance1(animationIndex: 9),
  dance2(animationIndex: 10),
  dance3(animationIndex: 11);

  const CharacterAnimation({
    required this.animationIndex,
    this.duration = const Duration(milliseconds: 500),
  });

  final int animationIndex;
  final Duration duration;

  static CharacterAnimation randomDance() {
    const dances = [dance1, dance2, dance3];
    return dances[DateTime.now().millisecondsSinceEpoch % dances.length];
  }

  static CharacterAnimation? fromName(String? name) {
    if (name == null) return null;

    switch (name.toLowerCase().trim()) {
      case 'jumping':
        return CharacterAnimation.jump;
      case 'spinning':
        return CharacterAnimation.spin;
      case 'clapping':
        return CharacterAnimation.clap;
      case 'thankful':
        return CharacterAnimation.thankful;
      case 'greeting':
        return CharacterAnimation.greet;
      case 'dancing':
        return CharacterAnimation.randomDance();
      case 'chicken_dance':
        return CharacterAnimation.chickenDance;
      case 'thinking':
        return CharacterAnimation.think;
      default:
        return CharacterAnimation.thankful; // Default fallback
    }
  }
}
