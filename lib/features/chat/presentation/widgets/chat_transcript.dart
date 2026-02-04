import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/glass/glass.dart';
import '../../domain/chat_line.dart';

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
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.14);
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
                        child: SelectableText(
                          line.text,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      )
                    : ChatBubble(
                        isUser: line.isUser,
                        tint: bubbleColor,
                        text: line.text,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.tint,
  });

  final String text;
  final bool isUser;
  final Color? tint;

  void _showCopyMenu(BuildContext context, TapDownDetails details) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: const Color(0xFF2A2A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.copy_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 10),
              Text(
                'Copy',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Copied to clipboard'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(20),
          );

    return GestureDetector(
      onSecondaryTapDown: (details) => _showCopyMenu(context, details),
      child: GlassChatBubble(
        borderRadius: borderRadius,
        tint: tint,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SelectableText(
          text,
          style: const TextStyle(fontSize: 14, height: 1.45),
          contextMenuBuilder: (context, editableTextState) {
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: [
                ContextMenuButtonItem(
                  label: 'Copy',
                  onPressed: () {
                    editableTextState.copySelection(
                      SelectionChangedCause.toolbar,
                    );
                  },
                ),
                ContextMenuButtonItem(
                  label: 'Select All',
                  onPressed: () {
                    editableTextState.selectAll(SelectionChangedCause.toolbar);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
