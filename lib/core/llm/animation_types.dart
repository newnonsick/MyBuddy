enum CharacterAnimation {
  jump(animationIndex: 0, duration: Duration(seconds: 3)),
  spin(animationIndex: 1, duration: Duration(seconds: 5)),
  think(animationIndex: 2, duration: Duration(seconds: 5)),
  clap(animationIndex: 3, duration: Duration(seconds: 3)),
  chickenDance(animationIndex: 4, duration: Duration(seconds: 6)),
  thankful(animationIndex: 7, duration: Duration(seconds: 4)),
  greet(animationIndex: 8, duration: Duration(seconds: 5)),
  dance1(animationIndex: 9, duration: Duration(seconds: 9)),
  dance2(animationIndex: 10, duration: Duration(seconds: 5)),
  dance3(animationIndex: 11, duration: Duration(seconds: 9));

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
      case 'jump':
        return CharacterAnimation.jump;
      case 'spin':
        return CharacterAnimation.spin;
      case 'clap':
        return CharacterAnimation.clap;
      case 'thankful':
        return CharacterAnimation.thankful;
      case 'greet':
        return CharacterAnimation.greet;
      case 'dance':
        return CharacterAnimation.randomDance();
      case 'chicken_dance':
        return CharacterAnimation.chickenDance;
      case 'think':
        return CharacterAnimation.think;
      default:
        return CharacterAnimation.thankful; // Default fallback
    }
  }
}
