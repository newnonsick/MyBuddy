import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';

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
  bool _headerDragReady = false;
  bool _dragMoveScheduled = false;
  OverlayPosition? _pendingDragPosition;

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
    await overlayPrefs.load();

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
    } catch (_) {
      // Ignore malformed payloads.
    }
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel();
    _stopBubbleTracking();
    _dragMoveScheduled = false;
    _pendingDragPosition = null;
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
    if (_collapsed) {
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _buildCollapsedBubble(),
            ),
          ),
        ),
      );
    }

    final viewInsetBottom = MediaQuery.viewInsetsOf(context).bottom;
    final bottomInset = _mode == OverlayUiMode.minimal
        ? 8.0
        : 8.0 + viewInsetBottom;

    return Material(
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
    return GestureDetector(
      onPanStart: _onHeaderDragStart,
      onPanUpdate: _onHeaderDragUpdate,
      onPanEnd: _onHeaderDragEnd,
      behavior: HitTestBehavior.opaque,
      child: Column(
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
      ),
    );
  }

  Widget _buildCollapsedBubble() {
    final glowColor = _session.recording
        ? Colors.redAccent
        : (_session.sending
              ? Theme.of(context).colorScheme.primary
              : Colors.white);

    return GestureDetector(
      onTap: _expandFromBubble,
      onLongPress: _closeOverlay,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.35),
          border: Border.all(
            color: glowColor.withValues(alpha: 0.85),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.2),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.smart_toy_rounded, size: 28, color: Colors.white),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _session.sending
                      ? Colors.orangeAccent
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimalPreview({required bool compact}) {
    final latest = _session.chat.isEmpty ? null : _session.chat.last;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        latest?.text ?? 'Type or tap mic to start chatting',
        maxLines: compact ? 2 : 3,
        overflow: TextOverflow.ellipsis,
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
    final canSend = app.llmInstalled && !_session.sending;

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
              GlassIconButton.pill(
                tooltip: _session.recording ? 'Stop recording' : 'Record voice',
                icon: _session.transcribing
                    ? Icons.more_horiz
                    : (_session.recording
                          ? Icons.stop_rounded
                          : Icons.mic_rounded),
                onPressed: _session.transcribing ? null : _toggleRecording,
              ),
              const SizedBox(width: 8),
              GlassIconButton.pill(
                tooltip: _session.sending ? 'Sending...' : 'Send',
                icon: _session.sending
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
        GlassIconButton.pill(
          tooltip: _session.recording ? 'Stop recording' : 'Record voice',
          icon: _session.transcribing
              ? Icons.more_horiz
              : (_session.recording ? Icons.stop_rounded : Icons.mic_rounded),
          onPressed: _session.transcribing ? null : _toggleRecording,
        ),
        const SizedBox(width: 6),
        GlassIconButton.pill(
          tooltip: _session.sending ? 'Sending...' : 'Send',
          icon: _session.sending
              ? Icons.more_horiz
              : Icons.arrow_upward_rounded,
          onPressed: canSend ? _onSend : null,
        ),
      ],
    );
  }

  String _statusText(AppController app) {
    if (_session.recording) return 'Listening... tap mic to send';
    if (_session.transcribing) return 'Transcribing...';
    if (_session.sending) return 'Generating response...';
    if (_session.speaking) return 'Speaking...';
    if (app.installingLlm) return 'Preparing model...';
    if (!app.llmInstalled) return 'Select model in settings';
    return 'MyBuddy Overlay';
  }

  Future<void> _toggleRecording() async {
    if (_session.recording) {
      await _session.endMicHoldAndSend();
      return;
    }
    await _session.startMicHold();
  }

  Future<void> _onSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await _session.sendText(text);
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
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return GlassCard(
                padding: const EdgeInsets.all(14),
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
                        items: models.installedModels.map((m) => m.id).toList(),
                        label: (v) => v,
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
                            stt.selectedModelId ?? stt.installedModels.first.id,
                        items: stt.installedModels.map((m) => m.id).toList(),
                        label: (v) {
                          final model = stt.installedModels
                              .where((m) => m.id == v)
                              .first;
                          return model.display.name.isNotEmpty
                              ? model.display.name
                              : model.id;
                        },
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
                            WhisperLanguages.isSupported(stt.selectedLanguage)
                            ? stt.selectedLanguage
                            : WhisperLanguages.auto,
                        items: WhisperLanguages.codes,
                        label: WhisperLanguages.labelFor,
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
                          icon: const Icon(Icons.restart_alt_rounded, size: 16),
                          label: const Text('Reset overlay size'),
                        ),
                      ),
                    ],
                  ],
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
    required ValueChanged<T> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
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
        ),
      ],
    );
  }

  Future<void> _closeOverlay() async {
    await _tts.stop();
    await FlutterOverlayWindow.closeOverlay();
  }

  void _onHeaderDragStart(DragStartDetails d) async {
    _headerDragReady = false;
    _dragMoveScheduled = false;
    _pendingDragPosition = null;
    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      _overlayDragX = pos.x;
      _overlayDragY = pos.y;
    } catch (_) {}
    _headerDragReady = true;
  }

  void _onHeaderDragUpdate(DragUpdateDetails d) {
    if (!_headerDragReady) return;
    _overlayDragX += d.delta.dx;
    _overlayDragY += d.delta.dy;
    _pendingDragPosition = OverlayPosition(_overlayDragX, _overlayDragY);

    if (_dragMoveScheduled) return;
    _dragMoveScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _dragMoveScheduled = false;
      final pending = _pendingDragPosition;
      if (pending == null || !_headerDragReady) return;
      _pendingDragPosition = null;
      FlutterOverlayWindow.moveOverlay(pending);
    });
  }

  void _onHeaderDragEnd(DragEndDetails _) {
    _dragMoveScheduled = false;
    final finalPosition =
        _pendingDragPosition ?? OverlayPosition(_overlayDragX, _overlayDragY);
    _pendingDragPosition = null;
    // Final move to ensure we land at the exact accumulated position.
    FlutterOverlayWindow.moveOverlay(finalPosition);
    _overlayDragX = finalPosition.x;
    _overlayDragY = finalPosition.y;
    _lastExpandedPosition = finalPosition;
    _headerDragReady = false;
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
    FlutterOverlayWindow.resizeOverlay(WindowSize.matchParent, newH, false);
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
    try {
      final view = View.of(context);
      final w = view.physicalSize.width / view.devicePixelRatio;
      final h = view.physicalSize.height / view.devicePixelRatio;
      if (w > 200) _screenWidth = w;
      if (h > 200) _screenHeight = h;
    } catch (_) {}
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

    // Use last known bubble side if available, otherwise keep current default.
    if (_lastBubblePosition != null) {
      _collapsedOnLeft = _lastBubblePosition!.x < (_displayWidth() / 2);
    }

    try {
      await FlutterOverlayWindow.resizeOverlay(
        _bubbleSize.toInt(),
        _bubbleSize.toInt(),
        true, // enable native drag for the bubble
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() => _collapsed = true);

    try {
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
      final targetY = (_lastExpandedPosition?.y ?? (screenHeight / 3))
          .clamp(minY, maxY)
          .toDouble();
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(targetX, targetY));
      _lastBubblePosition = OverlayPosition(targetX, targetY);
    } catch (_) {}

    _startBubbleTracking();
  }

  Future<void> _expandFromBubble() async {
    _stopBubbleTracking();

    // Record which side the bubble was on before expanding.
    try {
      final pos = await FlutterOverlayWindow.getOverlayPosition();
      _lastBubblePosition = pos;
      _collapsedOnLeft = pos.x < (_displayWidth() / 2);
    } catch (_) {}

    final size = _expandedSizeForMode(_mode);
    try {
      await FlutterOverlayWindow.resizeOverlay(
        size.$1,
        size.$2,
        false, // disable native drag in expanded mode
      );
      await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
    } catch (_) {}

    if (_lastExpandedPosition != null) {
      try {
        await FlutterOverlayWindow.moveOverlay(_lastExpandedPosition!);
        _overlayDragX = _lastExpandedPosition!.x;
        _overlayDragY = _lastExpandedPosition!.y;
      } catch (_) {}
    } else {
      try {
        final pos = await FlutterOverlayWindow.getOverlayPosition();
        _overlayDragX = pos.x;
        _overlayDragY = pos.y;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _collapsed = false);
  }

  /// Polls the bubble position so we know which edge it snapped to.
  /// Native [PositionGravity.auto] handles the actual snap animation.
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
    switch (mode) {
      case OverlayUiMode.minimal:
        return (WindowSize.matchParent, 420);
      case OverlayUiMode.avatarLite:
        return (WindowSize.matchParent, 760);
      case OverlayUiMode.balanced:
        return (WindowSize.matchParent, 680);
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }
}
