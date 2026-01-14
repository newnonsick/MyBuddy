import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_controller.dart';
import 'app/model_controller.dart';
import 'app/settings_page.dart';
import 'core/llm/llm_service.dart';
import 'core/memory/memory_service.dart';
import 'core/tts/tts_service.dart';
import 'core/unity/unity_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyBuddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A84FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const BuddyHomePage(),
    );
  }
}

class BuddyHomePage extends StatefulWidget {
  const BuddyHomePage({super.key});

  @override
  State<BuddyHomePage> createState() => _BuddyHomePageState();
}

class _BuddyHomePageState extends State<BuddyHomePage> {
  static const MethodChannel _unityChannel = MethodChannel('unity_bridge');
  final UnityBridge _unity = UnityBridge(channel: _unityChannel);
  final TtsService _tts = TtsService();

  late final AppController _controller;
  late final ModelController _models;

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatLine> _chat = <_ChatLine>[];

  bool _sending = false;
  bool _speaking = false;

  int _speakGeneration = 0;

  @override
  void initState() {
    super.initState();

    _models = ModelController();
    _controller = AppController(
      models: _models,
      llm: LlmService(unityBridge: _unity),
      memory: MemoryService(),
    );

    _controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _controller.startup();
    });
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(models: _models, app: _controller),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _tts.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 10,
                right: 12,
                child: _GlassIconButton(
                  tooltip: 'Settings',
                  icon: Icons.settings,
                  onPressed: _openSettings,
                ),
              ),
              Positioned(
                top: 10,
                left: 12,
                child: _GlassPill(
                  child: Text(
                    _controller.installingLlm
                        ? 'Preparing model…'
                        : (_controller.llmInstalled
                              ? 'MyBuddy'
                              : 'Select a model in Settings'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 58,
                bottom: 96,
                child: _buildTranscript(),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _buildComposer(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranscript() {
    if (_controller.installingLlm) {
      return const SizedBox.shrink();
    }

    if (!_controller.llmInstalled) {
      return Center(
        child: _GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _controller.llmError ?? 'No model selected.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _openSettings,
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    return IgnorePointer(
      ignoring: _sending,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        itemCount: _chat.length,
        itemBuilder: (context, index) {
          final line = _chat[index];
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
                child: _GlassPill(
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

  Widget _buildComposer() {
    final canSend = _controller.llmInstalled && !_sending;
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: canSend,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _onSend(),
              decoration: InputDecoration(
                hintText: _controller.llmInstalled
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
          _GlassIconButton(
            tooltip: _speaking ? 'Speaking…' : 'Send',
            icon: _sending
                ? Icons.more_horiz
                : (_speaking ? Icons.volume_up : Icons.arrow_upward),
            onPressed: canSend ? _onSend : null,
          ),
        ],
      ),
    );
  }

  Future<void> _onSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _chat.add(_ChatLine(text: text, isUser: true));
      _textController.clear();
    });

    try {
      final reply = await _controller.chatOnce(text);
      if (!mounted) return;
      if (reply.trim().isEmpty) return;
      setState(() {
        _chat.add(_ChatLine(text: reply.trim(), isUser: false));
      });
      _scrollToBottom();

      final cleanReply = reply.trim();
      if (cleanReply.isNotEmpty) {
        unawaited(_speakInUnity(cleanReply));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chat.add(_ChatLine(text: 'Error: $e', isUser: false));
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _speakInUnity(String text) async {
    final int generation = ++_speakGeneration;
    if (!mounted) return;
    setState(() {
      _speaking = true;
    });

    try {
      await _tts.stop();
      await _unity.stopSpeak();

      final wavPath = await _tts.synthesizeToWavFile(
        text: text,
        fileNameBase: 'reply_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted || generation != _speakGeneration) return;

      await _unity.speak(wavPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('TTS/Unity failed: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        if (generation == _speakGeneration) {
          _speaking = false;
        }
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }
}

class _ChatLine {
  const _ChatLine({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, this.tint});

  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (tint ?? Colors.white.withValues(alpha: 0.10)),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return _GlassPill(
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
      ),
    );
  }
}
