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
    required this.micEnabled,
    required this.isRecording,
    required this.isTranscribing,
    required this.onMicHoldStart,
    required this.onMicHoldEnd,
    required this.onMicHoldCancel,
    required this.onSend,
    required this.onStopSpeaking,
  });

  final TextEditingController textController;
  final bool canSend;
  final bool sending;
  final bool speaking;
  final bool isModelReady;
  final bool micEnabled;
  final bool isRecording;
  final bool isTranscribing;
  final VoidCallback onMicHoldStart;
  final VoidCallback onMicHoldEnd;
  final VoidCallback onMicHoldCancel;
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
          _buildMicButton(context),
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

  Widget _buildMicButton(BuildContext context) {
    final enabled = micEnabled && !isTranscribing;
    final iconColor = isRecording
        ? Colors.redAccent.withValues(alpha: 0.95)
        : (enabled
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.45));

    final child = SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: isTranscribing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                isRecording ? Icons.mic : Icons.mic_rounded,
                size: 20,
                color: iconColor,
              ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 90),
        scale: isRecording ? 0.92 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: isRecording
                ? [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.28),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : const [],
          ),
          child: GlassPill(
            child: Listener(
              onPointerDown: enabled ? (_) => onMicHoldStart() : null,
              onPointerUp: enabled ? (_) => onMicHoldEnd() : null,
              onPointerCancel: enabled ? (_) => onMicHoldCancel() : null,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
