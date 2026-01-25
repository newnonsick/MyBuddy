import 'package:flutter/material.dart';

import '../../../../shared/widgets/glass/glass.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.textController,
    required this.canSend,
    required this.sending,
    required this.speaking,
    required this.isModelReady,
    required this.onSend,
    required this.onStopSpeaking,
  });

  final TextEditingController textController;
  final bool canSend;
  final bool sending;
  final bool speaking;
  final bool isModelReady;
  final VoidCallback onSend;
  final VoidCallback onStopSpeaking;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: textController,
              enabled: canSend,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: isModelReady
                    ? 'Message…'
                    : 'Open Settings to select a model',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
                border: InputBorder.none,
                isCollapsed: true,
              ),
              style: const TextStyle(fontSize: 16),
              minLines: 1,
              maxLines: 3,
            ),
          ),
          const SizedBox(width: 10),
          GlassIconButton.pill(
            tooltip: sending
                ? 'Sending…'
                : (speaking ? 'Stop speaking' : 'Send'),
            icon: sending
                ? Icons.more_horiz
                : (speaking ? Icons.stop_rounded : Icons.arrow_upward),
            onPressed: speaking ? onStopSpeaking : (canSend ? onSend : null),
          ),
        ],
      ),
    );
  }
}
