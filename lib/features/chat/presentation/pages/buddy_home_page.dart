import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mybuddy/app/app_controller.dart';
import 'package:mybuddy/app/model_controller.dart';
import 'package:mybuddy/features/chat/domain/chat_line.dart';
import 'package:mybuddy/features/chat/presentation/widgets/chat_composer.dart';
import 'package:mybuddy/features/chat/presentation/widgets/chat_transcript.dart';
import 'package:mybuddy/features/settings/presentation/pages/settings_page.dart';
import 'package:mybuddy/core/llm/llm_service.dart';
import 'package:mybuddy/core/memory/memory_service.dart';
import 'package:mybuddy/core/tts/tts_service.dart';
import 'package:mybuddy/core/unity/unity_bridge.dart';
import 'package:mybuddy/shared/widgets/glass/glass.dart';

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
  final List<ChatLine> _chat = <ChatLine>[];

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
                child: GlassIconButton.pill(
                  tooltip: 'Settings',
                  icon: Icons.settings,
                  onPressed: _openSettings,
                ),
              ),
              Positioned(
                top: 10,
                left: 12,
                child: GlassPill(
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
                top: 74,
                bottom: 96,
                child: _buildTranscript(context),
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

  Widget _buildTranscript(BuildContext context) {
    if (_controller.installingLlm) {
      return const SizedBox.shrink();
    }

    if (_controller.hideChatLog) {
      return const SizedBox.shrink();
    }

    if (!_controller.llmInstalled) {
      return Center(
        child: GlassCard(
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

    return ChatTranscript(
      chat: _chat,
      scrollController: _scrollController,
      sending: _sending,
      hideChatLog: _controller.hideChatLog,
    );
  }

  Widget _buildComposer() {
    final canSend = _controller.llmInstalled && !_sending;
    return ChatComposer(
      textController: _textController,
      canSend: canSend,
      sending: _sending,
      speaking: _speaking,
      isModelReady: _controller.llmInstalled,
      onSend: _onSend,
      onStopSpeaking: _onStopSpeaking,
    );
  }

  Future<void> _onStopSpeaking() async {
    _speakGeneration++;
    try {
      await _tts.stop();
      await _unity.stopSpeak();
    } catch (e) {
      // Ignore errors
    } finally {
      if (mounted) {
        setState(() {
          _speaking = false;
        });
      }
    }
  }

  Future<void> _onSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _chat.add(ChatLine(text: text, isUser: true));
      _textController.clear();
    });

    try {
      final reply = await _controller.chatOnce(text);
      if (!mounted) return;
      if (reply.trim().isEmpty) return;
      setState(() {
        _chat.add(ChatLine(text: reply.trim(), isUser: false));
      });
      _scrollToBottom();

      final cleanReply = reply.trim();
      if (cleanReply.isNotEmpty) {
        unawaited(_speakInUnity(cleanReply));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chat.add(ChatLine(text: 'Error: $e', isUser: false));
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
