List<String> extractJsonBlocks(String input) {
  final result = <String>[];

  int depth = 0;
  int start = -1;
  bool inString = false;
  bool escape = false;

  for (int i = 0; i < input.length; i++) {
    final char = input[i];

    if (char == '\\' && !escape) {
      escape = true;
      continue;
    }

    if (char == '"' && !escape) {
      inString = !inString;
    }

    if (!inString) {
      if (char == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0 && start != -1) {
          result.add(input.substring(start, i + 1));
          start = -1;
        }
      }
    }

    escape = false;
  }

  return result;
}
