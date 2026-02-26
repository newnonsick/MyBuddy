import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_controller.dart';
import '../../../../app/providers.dart';
import '../../../../core/audio/audio_recorder_service.dart';
import '../../../../core/overlay/overlay_preferences.dart';
import '../../../../core/stt/whisper_languages.dart';
import '../../../../core/tts/tts_service.dart';
import '../../../../shared/widgets/glass/glass.dart';
import '../../../chat/presentation/controllers/chat_session_controller.dart';
import 'overlay_host_app.dart';

class OverlayChatPage extends ConsumerStatefulWidget {
  const OverlayChatPage({super.key});

  @override
  ConsumerState<OverlayChatPage> createState() => _OverlayChatPageState();
}

class _OverlayChatPageState extends ConsumerState<OverlayChatPage> {
  static const double _bubbleSize = 74;
  static const double _bubbleEdgeInset = 8;
  static const double _expandedEdgeInset = 8;

  final TtsService _tts = TtsService();
  final AudioRecorderService _recorder = AudioRecorderService();
  final TextEditingController _textController = TextEditingController();
  late final ChatSessionController _session;

  StreamSubscription<dynamic>? _overlaySubscription;
  Timer? _bubblePollTimer;
  OverlayPosition? _lastBubblePosition;

  OverlayUiMode _mode = OverlayUiMode.balanced;
  bool _overlayTtsEnabled = true;
  bool _collapsed = false;
  bool _collapsedOnLeft = false;
  OverlayPosition? _lastExpandedPosition;

  double _screenWidth = 0;
  double _screenHeight = 0;
  int? _customHeight;

  double _overlayDragX = 0;
  double _overlayDragY = 0;

  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _session = ChatSessionController(
      appController: ref.read(appControllerProvider),
      sttModelController: ref.read(sttModelControllerProvider),
      sttService: ref.read(sttServiceProvider),
      recorder: _recorder,
      onSpeak: (text) async {
        if (!_overlayTtsEnabled) return;
        await _tts.speakText(text);
      },
      onStopSpeaking: () => _tts.stop(),
      onError: _showSnack,
    );
    _bootstrap();
    _overlaySubscription = ref
        .read(overlayMessageStreamProvider)
        .listen(_onOverlayPayload);
  }

  Future<void> _bootstrap() async {
    final overlayPrefs = OverlayPreferences();
    final stt = ref.read(sttModelControllerProvider);
    await overlayPrefs.load();
    await stt.loadLocalState();
    if (stt.installedModels.isEmpty) {
      await stt.refreshInstalled();
    }

    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      _overlayDragX = pos.x;
      _overlayDragY = pos.y;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _mode = overlayPrefs.mode;
      _overlayTtsEnabled = overlayPrefs.overlayTtsEnabled;
      _customHeight = overlayPrefs.customHeight;
      _booting = false;
    });
  }

  void _onOverlayPayload(dynamic payload) {
    if (payload is! String || payload.trim().isEmpty) return;

    try {
      final map = jsonDecode(payload);
      if (map is! Map<String, dynamic>) return;

      if (map['type'] == 'close_overlay') {
        _closeOverlay();
        return;
      }

      if (map['type'] != 'overlay_config') return;

      final mode = OverlayUiModeX.fromStorage(map['mode'] as String?);
      final ttsEnabled = map['ttsEnabled'] == true;

      final sw = map['screenWidth'];
      final sh = map['screenHeight'];
      if (sw is num && sw > 100) _screenWidth = sw.toDouble();
      if (sh is num && sh > 100) _screenHeight = sh.toDouble();

      if (!mounted) return;
      setState(() {
        _mode = mode;
        _overlayTtsEnabled = ttsEnabled;
      });
      if (!_collapsed) {
        _ensureExpandedOverlayFullyVisible();
      }
    } catch (_) {
      // Ignore malformed payloads.
    }
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel();
    _stopBubbleTracking();
    _session.dispose();
    unawaited(_tts.dispose());
    unawaited(_recorder.dispose());
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Material(
        color: Colors.transparent,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final app = ref.watch(appControllerProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: _collapsed
          ? _buildCollapsedState(app, key: const ValueKey('collapsed'))
          : _buildExpandedState(app, context, key: const ValueKey('expanded')),
    );
  }

  Widget _buildCollapsedState(AppController app, {required Key key}) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: SafeArea(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: _collapsedOnLeft ? Alignment.centerLeft : Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: _buildCollapsedBubble(app),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedState(AppController app, BuildContext context, {required Key key}) {
    final viewInsetBottom = MediaQuery.viewInsetsOf(context).bottom;
    final bottomInset = _mode == OverlayUiMode.minimal
        ? 8.0
        : 8.0 + viewInsetBottom;

    return Material(
      key: key,
      color: Colors.transparent,
      child: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 8,
            bottom: bottomInset,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 360;

              return ListenableBuilder(
                listenable: _session,
                builder: (_, _) => Column(
                  children: [
                    Expanded(
                      child: GlassCard(
                        padding: EdgeInsets.all(isNarrow ? 8 : 10),
                        child: Column(
                          children: [
                            _buildHeader(
                              app,
                              compact: _mode == OverlayUiMode.minimal,
                            ),
                            if (_mode == OverlayUiMode.minimal) ...[
                              const SizedBox(height: 8),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      _buildMinimalPreview(compact: true),
                                    ],
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Expanded(child: _buildTranscript(app)),
                            ],
                            if (_mode == OverlayUiMode.avatarLite) ...[
                              const SizedBox(height: 8),
                              _buildAvatarLite(),
                            ],
                            const SizedBox(height: 8),
                            _buildComposer(
                              app,
                              isNarrow: isNarrow,
                              compact: _mode == OverlayUiMode.minimal,
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildResizeHandle(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppController app, {required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                _statusText(app),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 12 : 13,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (!compact) ...[
              GlassIconButton.pill(
                tooltip: 'Quick settings',
                icon: Icons.tune_rounded,
                onPressed: _openQuickSettings,
              ),
              const SizedBox(width: 8),
            ],
            GlassIconButton.pill(
              tooltip: 'Hide to edge',
              icon: Icons.chevron_right_rounded,
              onPressed: _collapseToBubble,
            ),
            const SizedBox(width: 8),
            GlassIconButton.pill(
              tooltip: 'Close overlay',
              icon: Icons.close_rounded,
              onPressed: _closeOverlay,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCollapsedBubble(AppController app) {
    final isProcessing = _session.sending || app.generatingResponse;
    final isRecording = _session.recording;

    Color iconColor;
    Color glowColor;

    if (isRecording) {
      iconColor = const Color(0xFFE57373); // Muted elegant red
      glowColor = iconColor.withValues(alpha: 0.15);
    } else if (isProcessing) {
      iconColor = Theme.of(context).colorScheme.primary;
      glowColor = iconColor.withValues(alpha: 0.15);
    } else {
      iconColor = Colors.white.withValues(alpha: 0.85);
      glowColor = Colors.transparent;
    }

    final scale = isRecording ? 1.05 : 1.0;

    return GestureDetector(
      onTap: _expandFromBubble,
      onLongPress: _closeOverlay,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: 58,
        height: 58,
        transform: Matrix4.identity()..scale(scale, scale),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF161618).withValues(alpha: 0.80),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor,
              blurRadius: 20,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: isRecording
              ? Icon(
                  Icons.graphic_eq_rounded,
                  key: const ValueKey('recording'),
                  size: 24,
                  color: iconColor,
                )
              : isProcessing
                  ? Icon(
                      Icons.lens_blur_rounded,
                      key: const ValueKey('processing'),
                      size: 24,
                      color: iconColor,
                    )
                  : Icon(
                      Icons.smart_toy_rounded, //blur_on_rounded
                      key: const ValueKey('idle'),
                      size: 24,
                      color: iconColor,
                    ),
        ),
      ),
    );
  }

  Widget _buildMinimalPreview({required bool compact}) {
    final latest = _session.chat.isEmpty ? null : _session.chat.last;
    final isUser = latest?.isUser ?? false;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1D).withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              latest == null ? Icons.chat_bubble_outline_rounded : (isUser ? Icons.person_rounded : Icons.smart_toy_rounded),
              size: 14,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              latest?.text ?? 'Type or tap mic to start chatting...',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w400,
                letterSpacing: 0.2, // Adds a touch of elegance
              ),
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarLite() {
    final color = _session.recording
        ? Colors.redAccent
        : (_session.speaking ? Colors.greenAccent : Colors.white70);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.9), width: 1.4),
        ),
        child: Icon(Icons.auto_awesome, size: 18, color: color),
      ),
    );
  }

  Widget _buildTranscript(AppController app) {
    if (!app.llmInstalled) {
      return Center(
        child: Text(
          app.llmError ?? 'Select an LLM model in quick settings.',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_session.chat.isEmpty) {
      return const Center(child: Text('Ready to chat.'));
    }

    return ListView.builder(
      reverse: true,
      itemCount: _session.chat.length,
      itemBuilder: (context, index) {
        final line = _session.chat[_session.chat.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Align(
            alignment: line.isUser
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: GlassChatBubble(
              borderRadius: BorderRadius.circular(14),
              tint: line.isUser
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.24)
                  : null,
              child: Text(line.text),
            ),
          ),
        );
      },
    );
  }

  Widget _buildComposer(
    AppController app, {
    required bool isNarrow,
    required bool compact,
  }) {
    final stt = ref.watch(sttModelControllerProvider);
    final isSending = _session.sending || app.generatingResponse;
    final isTranscribing = _session.transcribing || app.transcribingAudio;
    final canSend = app.llmInstalled && !isSending;
    final micEnabled =
        app.llmInstalled &&
        !isSending &&
        !isTranscribing &&
        stt.selectedInstalledModel != null;

    if (isNarrow || compact) {
      return Column(
        children: [
          TextField(
            controller: _textController,
            minLines: 1,
            maxLines: compact ? 2 : 3,
            enabled: canSend,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _onSend(),
            decoration: InputDecoration(
              hintText: app.llmInstalled
                  ? 'Ask MyBuddy...'
                  : 'Select an LLM model first',
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Listener(
                onPointerDown: micEnabled ? (_) => _onMicHoldStart() : null,
                onPointerUp: micEnabled ? (_) => _onMicHoldEnd() : null,
                onPointerCancel: micEnabled ? (_) => _onMicHoldCancel() : null,
                child: GlassIconButton.pill(
                  tooltip: _session.recording
                      ? 'Release to send'
                      : 'Hold to record',
                  icon: isTranscribing
                      ? Icons.more_horiz
                      : (_session.recording
                            ? Icons.stop_rounded
                            : Icons.mic_rounded),
                  onPressed: null,
                ),
              ),
              const SizedBox(width: 8),
              GlassIconButton.pill(
                tooltip: isSending ? 'Sending...' : 'Send',
                icon: isSending
                    ? Icons.more_horiz
                    : Icons.arrow_upward_rounded,
                onPressed: canSend ? _onSend : null,
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textController,
            minLines: 1,
            maxLines: 3,
            enabled: canSend,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _onSend(),
            decoration: InputDecoration(
              hintText: app.llmInstalled
                  ? 'Ask MyBuddy...'
                  : 'Select an LLM model first',
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Listener(
          onPointerDown: micEnabled ? (_) => _onMicHoldStart() : null,
          onPointerUp: micEnabled ? (_) => _onMicHoldEnd() : null,
          onPointerCancel: micEnabled ? (_) => _onMicHoldCancel() : null,
          child: GlassIconButton.pill(
            tooltip: _session.recording ? 'Release to send' : 'Hold to record',
            icon: isTranscribing
                ? Icons.more_horiz
                : (_session.recording ? Icons.stop_rounded : Icons.mic_rounded),
            onPressed: null,
          ),
        ),
        const SizedBox(width: 6),
        GlassIconButton.pill(
          tooltip: isSending ? 'Sending...' : 'Send',
          icon: isSending
              ? Icons.more_horiz
              : Icons.arrow_upward_rounded,
          onPressed: canSend ? _onSend : null,
        ),
      ],
    );
  }

  String _statusText(AppController app) {
    if (_session.recording) return 'Listening... tap mic to send';
    if (_session.transcribing || app.transcribingAudio) return 'Transcribing...';
    if (_session.sending || app.generatingResponse) return 'Generating response...';
    if (_session.speaking) return 'Speaking...';
    if (app.installingLlm) return 'Preparing model...';
    if (!app.llmInstalled) return 'Select model in settings';
    return 'MyBuddy Overlay';
  }

  void _onMicHoldStart() {
    unawaited(_session.startMicHold());
  }

  void _onMicHoldEnd() {
    unawaited(_session.endMicHoldAndSend());
  }

  void _onMicHoldCancel() {
    unawaited(_session.cancelMicHold());
  }

  Future<void> _onSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    try {
      await _session.sendText(text);
    } catch (e) {
      debugPrint('Overlay _onSend error: $e');
      _showSnack('Send failed: $e');
    }
  }

  Future<void> _openQuickSettings() async {
    final app = ref.read(appControllerProvider);
    final models = ref.read(modelControllerProvider);
    final stt = ref.read(sttModelControllerProvider);
    final overlayService = ref.read(overlayServiceProvider);
    final overlayPrefs = overlayService.preferences;

    if (models.installedModels.isEmpty) {
      await models.loadLocalState();
      if (models.installedModels.isEmpty) {
        await models.refreshInstalled();
      }
    }

    if (stt.installedModels.isEmpty) {
      await stt.loadLocalState();
      if (stt.installedModels.isEmpty) {
        await stt.refreshInstalled();
      }
    }

    await overlayPrefs.load();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final width = MediaQuery.sizeOf(context).width;
              final compact = width < 430;
              final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;

              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxSheetHeight),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Overlay quick settings',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          _dropdownBlock<String>(
                            title: 'Overlay mode',
                            value: overlayPrefs.mode.storageValue,
                            items: OverlayUiMode.values
                                .map((m) => m.storageValue)
                                .toList(),
                            label: (v) => OverlayUiModeX.fromStorage(v).label,
                            compact: compact,
                            onChanged: (v) async {
                              final mode = OverlayUiModeX.fromStorage(v);
                              await overlayPrefs.setMode(mode);
                              if (!mounted) return;
                              setState(() => _mode = mode);
                              setSheetState(() {});
                              await overlayService.syncOverlayConfig();
                            },
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile.adaptive(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Speak replies in overlay'),
                            value: _overlayTtsEnabled,
                            onChanged: (v) async {
                              await overlayPrefs.setOverlayTtsEnabled(v);
                              if (!mounted) return;
                              setState(() => _overlayTtsEnabled = v);
                              setSheetState(() {});
                              await overlayService.syncOverlayConfig();
                            },
                          ),
                          const SizedBox(height: 8),
                          if (models.installedModels.isNotEmpty)
                            _dropdownBlock<String>(
                              title: 'LLM model',
                              value:
                                  models.selectedModelId ??
                                  models.installedModels.first.id,
                              items: models.installedModels
                                  .map((m) => m.id)
                                  .toList(),
                              label: (v) => v,
                              compact: compact,
                              onChanged: (v) async {
                                models.setPendingSelection(v);
                                await models.commitSelection();
                                await app.activateSelectedModel();
                                setSheetState(() {});
                              },
                            ),
                          if (stt.installedModels.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _dropdownBlock<String>(
                              title: 'STT model',
                              value:
                                  stt.selectedModelId ??
                                  stt.installedModels.first.id,
                              items: stt.installedModels
                                  .map((m) => m.id)
                                  .toList(),
                              label: (v) {
                                final model = stt.installedModels
                                    .where((m) => m.id == v)
                                    .first;
                                return model.display.name.isNotEmpty
                                    ? model.display.name
                                    : model.id;
                              },
                              compact: compact,
                              onChanged: (v) async {
                                stt.setPendingSelection(v);
                                await stt.commitSelection();
                                await stt.markLastUsedSelected();
                                setSheetState(() {});
                              },
                            ),
                            const SizedBox(height: 8),
                            _dropdownBlock<String>(
                              title: 'Spoken language',
                              value:
                                  WhisperLanguages.isSupported(
                                    stt.selectedLanguage,
                                  )
                                  ? stt.selectedLanguage
                                  : WhisperLanguages.auto,
                              items: WhisperLanguages.codes,
                              label: WhisperLanguages.labelFor,
                              compact: compact,
                              onChanged: (v) async {
                                await stt.setSelectedLanguage(v);
                                setSheetState(() {});
                              },
                            ),
                          ],
                          if (_customHeight != null) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () async {
                                  await overlayPrefs.setCustomHeight(null);
                                  if (!mounted) return;
                                  setState(() => _customHeight = null);
                                  setSheetState(() {});
                                  await overlayService.syncOverlayConfig();
                                },
                                icon: const Icon(
                                  Icons.restart_alt_rounded,
                                  size: 16,
                                ),
                                label: const Text('Reset overlay size'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _dropdownBlock<T>({
    required String title,
    required T value,
    required List<T> items,
    required String Function(T item) label,
    required bool compact,
    required ValueChanged<T> onChanged,
  }) {
    final titleWidget = Text(
      title,
      style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
    );

    final dropdown = Container(
      width: compact ? double.infinity : null,
      constraints: compact
          ? null
          : const BoxConstraints(minWidth: 170, maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          dropdownColor: const Color(0xFF2A2A2E),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(label(item), overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (next) {
            if (next == null) return;
            onChanged(next);
          },
        ),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [titleWidget, const SizedBox(height: 6), dropdown],
      );
    }

    return Row(
      children: [
        Expanded(child: titleWidget),
        const SizedBox(width: 12),
        dropdown,
      ],
    );
  }

  Future<void> _closeOverlay() async {
    await _tts.stop();
    await FlutterOverlayWindow.closeOverlay();
  }

  Widget _buildResizeHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onResizeDragUpdate,
      onVerticalDragEnd: _onResizeDragEnd,
      child: Center(
        child: Container(
          width: 40,
          height: 18,
          alignment: Alignment.center,
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  int _resizeBaseHeight = 0;

  void _onResizeDragUpdate(DragUpdateDetails d) {
    if (_resizeBaseHeight == 0) {
      final size = _expandedSizeForMode(_mode);
      _resizeBaseHeight = size.$2;
    }
    final delta = d.delta.dy.round();
    final newH = (_resizeBaseHeight + delta).clamp(200, 900);
    _resizeBaseHeight = newH;
    FlutterOverlayWindow.resizeOverlay(WindowSize.matchParent, newH, true);
  }

  void _onResizeDragEnd(DragEndDetails _) async {
    final h = _resizeBaseHeight;
    if (h < 200) return;
    _customHeight = h;
    _resizeBaseHeight = 0;
    final overlayPrefs = OverlayPreferences();
    await overlayPrefs.load();
    await overlayPrefs.setCustomHeight(h);
  }

  void _cacheScreenDimensionsFromView() {
    if (!_collapsed) {
      try {
        final view = View.of(context);
        final w = view.physicalSize.width / view.devicePixelRatio;
        final h = view.physicalSize.height / view.devicePixelRatio;
        if (w > 200) _screenWidth = w;
        if (h > 200) _screenHeight = h;
      } catch (_) {}
    }

    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      if (dispatcher.displays.isNotEmpty) {
        final d = dispatcher.displays.first;
        final dw = d.size.width / d.devicePixelRatio;
        final dh = d.size.height / d.devicePixelRatio;
        if (dw > _screenWidth) _screenWidth = dw;
        if (dh > _screenHeight) _screenHeight = dh;
      }
    } catch (_) {}
  }

  Future<void> _collapseToBubble() async {
    if (_collapsed) return;

    _cacheScreenDimensionsFromView();

    try {
      _lastExpandedPosition = await FlutterOverlayWindow.getOverlayPosition();
    } catch (_) {
      _lastExpandedPosition = null;
    }

    if (_lastBubblePosition != null) {
      _collapsedOnLeft = _lastBubblePosition!.x < (_displayWidth() / 2);
    }

    final screenWidth = _displayWidth();
    final screenHeight = _displayHeight();
    final targetX = _collapsedOnLeft
        ? 0.0
        : math.max(0.0, screenWidth - _bubbleSize);
    const minY = _bubbleEdgeInset;
    final maxY = math.max(
      minY,
      screenHeight - _bubbleSize - _bubbleEdgeInset,
    );
    final targetY = (_lastBubblePosition?.y ?? _lastExpandedPosition?.y ?? (screenHeight / 3))
        .clamp(minY, maxY)
        .toDouble();

    // 1. Tell Flutter to show the collapsed bubble *before* we shrink the OS window.
    // We animate it moving to the left/right side via the AnimatedContainer.
    if (mounted) setState(() => _collapsed = true);
    await Future<void>.delayed(const Duration(milliseconds: 150)); // let flutter animate first

    // 2. Shrink the OS window.
    try {
      await FlutterOverlayWindow.moveOverlay(
        OverlayPosition(targetX, targetY),
      );
    } catch (_) {}

    try {
      await FlutterOverlayWindow.resizeOverlay(
        _bubbleSize.toInt(),
        _bubbleSize.toInt(),
        true,
      );
    } catch (_) {}

    _lastBubblePosition = OverlayPosition(targetX, targetY);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      if ((pos.x - targetX).abs() > 2 || (pos.y - targetY).abs() > 2) {
        await FlutterOverlayWindow.moveOverlay(
          OverlayPosition(targetX, targetY),
        );
      }
      _lastBubblePosition = OverlayPosition(targetX, targetY);
    } catch (_) {}

    _startBubbleTracking();
  }

  Future<void> _expandFromBubble() async {
    _stopBubbleTracking();
    _cacheScreenDimensionsFromView();

    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      _lastBubblePosition = pos;
      _collapsedOnLeft = pos.x < (_displayWidth() / 2);
    } catch (_) {}

    OverlayPosition? baseTarget = _lastExpandedPosition ?? _lastBubblePosition;
    if (baseTarget == null) {
      try {
        baseTarget = await FlutterOverlayWindow.getOverlayPosition();
      } catch (_) {}
    }

    baseTarget ??= OverlayPosition(0, _displayHeight() / 3);

    final size = _expandedSizeForMode(_mode);
    final target = _clampExpandedPosition(baseTarget);

    try {
      await FlutterOverlayWindow.resizeOverlay(size.$1, size.$2, true);
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 30));

    try {
      await FlutterOverlayWindow.moveOverlay(target);
      _overlayDragX = target.x;
      _overlayDragY = target.y;
      _lastExpandedPosition = target;
    } catch (_) {}

    try {
      await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _collapsed = false);
    await _ensureExpandedOverlayFullyVisible();
  }

  void _startBubbleTracking() {
    _stopBubbleTracking();

    _bubblePollTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) async {
      if (!_collapsed) return;
      try {
        final pos = await FlutterOverlayWindow.getOverlayPosition();
        _lastBubblePosition = pos;
        final sw = _displayWidth();
        if (sw > 100) {
          _collapsedOnLeft = pos.x < (sw / 2);
        }
      } catch (_) {}
    });
  }

  void _stopBubbleTracking() {
    _bubblePollTimer?.cancel();
    _bubblePollTimer = null;
  }

  double _displayWidth() {
    if (_screenWidth > 100) return _screenWidth;
    try {
      final view = View.of(context);
      final width = view.physicalSize.width / view.devicePixelRatio;
      if (width > 100) return width;
    } catch (_) {}
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    if (dispatcher.displays.isNotEmpty) {
      final display = dispatcher.displays.first;
      return display.size.width / display.devicePixelRatio;
    }
    if (dispatcher.views.isNotEmpty) {
      final view = dispatcher.views.first;
      final w = view.physicalSize.width / view.devicePixelRatio;
      if (w > 100) return w;
    }
    return 412;
  }

  double _displayHeight() {
    if (_screenHeight > 100) return _screenHeight;
    try {
      final view = View.of(context);
      final height = view.physicalSize.height / view.devicePixelRatio;
      if (height > 100) return height;
    } catch (_) {}
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    if (dispatcher.displays.isNotEmpty) {
      final display = dispatcher.displays.first;
      return display.size.height / display.devicePixelRatio;
    }
    if (dispatcher.views.isNotEmpty) {
      final view = dispatcher.views.first;
      final h = view.physicalSize.height / view.devicePixelRatio;
      if (h > 100) return h;
    }
    return 915;
  }

  (int, int) _expandedSizeForMode(OverlayUiMode mode) {
    if (_customHeight != null && _customHeight! >= 200) {
      return (WindowSize.matchParent, _customHeight!);
    }
    final screenHeight = _displayHeight();
    final hasScreen = screenHeight > 100;
    final maxHeight = hasScreen ? (screenHeight - 24).round() : 980;

    switch (mode) {
      case OverlayUiMode.minimal:
        final target = hasScreen ? (screenHeight * 0.80).round() : 640;
        return (WindowSize.matchParent, target.clamp(480, maxHeight));
      case OverlayUiMode.avatarLite:
        final target = hasScreen ? (screenHeight * 0.95).round() : 920;
        return (WindowSize.matchParent, target.clamp(640, maxHeight));
      case OverlayUiMode.balanced:
        final target = hasScreen ? (screenHeight * 0.90).round() : 840;
        return (WindowSize.matchParent, target.clamp(600, maxHeight));
    }
  }

  OverlayPosition _clampExpandedPosition(OverlayPosition position) {
    _cacheScreenDimensionsFromView();

    final size = _expandedSizeForMode(_mode);
    final width = size.$1 == WindowSize.matchParent
        ? _displayWidth()
        : size.$1.toDouble();
    final height = size.$2.toDouble();

    final displayWidth = _displayWidth();
    final displayHeight = _displayHeight();

    final minX = width >= displayWidth ? 0.0 : _expandedEdgeInset;
    final maxX = width >= displayWidth
        ? math.max(0.0, displayWidth - width)
        : math.max(minX, displayWidth - width - _expandedEdgeInset);
    const minY = _expandedEdgeInset;
    final maxY = math.max(minY, displayHeight - height - _expandedEdgeInset);

    return OverlayPosition(
      position.x.clamp(minX, maxX).toDouble(),
      position.y.clamp(minY, maxY).toDouble(),
    );
  }

  Future<void> _ensureExpandedOverlayFullyVisible() async {
    if (_collapsed) return;

    await Future<void>.delayed(const Duration(milliseconds: 120));
    _cacheScreenDimensionsFromView();

    final size = _expandedSizeForMode(_mode);
    try {
      await FlutterOverlayWindow.resizeOverlay(size.$1, size.$2, true);
    } catch (_) {}

    for (int attempt = 0; attempt < 3; attempt++) {
      if (_collapsed || !mounted) return;

      OverlayPosition? current;
      try {
        current = await FlutterOverlayWindow.getOverlayPosition();
      } catch (_) {
        current = null;
      }

      final desired = _clampExpandedPosition(
        current ??
            _lastExpandedPosition ??
            OverlayPosition(_overlayDragX, _overlayDragY),
      );

      final needsMove =
          current == null ||
          (current.x - desired.x).abs() > 0.5 ||
          (current.y - desired.y).abs() > 0.5;

      if (!needsMove) break;

      try {
        await FlutterOverlayWindow.moveOverlay(desired);
      } catch (_) {}

      _overlayDragX = desired.x;
      _overlayDragY = desired.y;
      _lastExpandedPosition = desired;

      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }
}
