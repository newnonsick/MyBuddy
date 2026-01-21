import 'package:flutter/material.dart';

import '../../domain/chat_line.dart';
import '../../../../shared/widgets/glass/glass.dart';

class ChatTranscript extends StatelessWidget {
  const ChatTranscript({
    super.key,
    required this.chat,
    required this.scrollController,
    required this.sending,
    required this.hideChatLog,
  });

  final List<ChatLine> chat;
  final ScrollController scrollController;
  final bool sending;
  final bool hideChatLog;

  @override
  Widget build(BuildContext context) {
    if (hideChatLog) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: sending,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        itemCount: chat.length,
        itemBuilder: (context, index) {
          final line = chat[index];
          final hideBubbles = hideChatLog;
          final bubbleColor = line.isUser
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.10);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Align(
              alignment: line.isUser
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: hideBubbles
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Text(
                          line.text,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      )
                    : GlassPill(
                        tint: bubbleColor,
                        child: Text(
                          line.text,
                          style: const TextStyle(fontSize: 14, height: 1.35),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
