import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybuddy/app/app_controller.dart';
import 'package:mybuddy/app/providers.dart';
import 'package:mybuddy/features/chat/domain/chat_line.dart';
import 'package:mybuddy/features/chat/presentation/widgets/chat_composer.dart';
import 'package:mybuddy/features/chat/presentation/widgets/chat_transcript.dart';
import 'package:mybuddy/features/google_calendar/presentation/pages/google_calendar_page.dart';
import 'package:mybuddy/features/settings/presentation/pages/settings_page.dart';
import 'package:mybuddy/core/tts/tts_service.dart';
import 'package:mybuddy/core/unity/unity_bridge.dart';
import 'package:mybuddy/shared/widgets/glass/glass.dart';

class BuddyHomePage extends ConsumerStatefulWidget {
  const BuddyHomePage({super.key});

  @override
  ConsumerState<BuddyHomePage> createState() => _BuddyHomePageState();
}

class _BuddyHomePageState extends ConsumerState<BuddyHomePage> {
  static const MethodChannel _unityChannel = MethodChannel('unity_bridge');
  final UnityBridge _unity = UnityBridge(channel: _unityChannel);
  final TtsService _tts = TtsService();

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatLine> _chat = <ChatLine>[];

  bool _sending = false;
  bool _speaking = false;

  int _speakGeneration = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = ref.read(appControllerProvider);
      await controller.startup();
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  Future<void> _openCalendar() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const GoogleCalendarPage()));
  }

  Widget _buildCalendarButton() {
    final authService = ref.watch(googleAuthServiceProvider);
    final isSignedIn = authService.isSignedIn;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GlassIconButton.pill(
          tooltip: 'Calendar',
          icon: Icons.calendar_month_rounded,
          onPressed: _openCalendar,
        ),
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isSignedIn
                  ? const Color(0xFF34C759)
                  : const Color(0xFFFF3B30),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF111217), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tts.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);

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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCalendarButton(),
                    const SizedBox(width: 8),
                    GlassIconButton.pill(
                      tooltip: 'Settings',
                      icon: Icons.settings,
                      onPressed: _openSettings,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 10,
                left: 12,
                child: GlassPill(
                  child: Text(
                    controller.installingLlm
                        ? 'Preparing model…'
                        : (controller.llmInstalled
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
                child: _buildTranscript(context, controller),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _buildComposer(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranscript(BuildContext context, AppController controller) {
    if (controller.installingLlm) {
      return const SizedBox.shrink();
    }

    if (controller.hideChatLog) {
      return const SizedBox.shrink();
    }

    if (!controller.llmInstalled) {
      return Center(
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                controller.llmError ?? 'No model selected.',
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
      hideChatLog: controller.hideChatLog,
    );
  }

  Widget _buildComposer(AppController controller) {
    final canSend = controller.llmInstalled && !_sending;
    return ChatComposer(
      textController: _textController,
      canSend: canSend,
      sending: _sending,
      speaking: _speaking,
      isModelReady: controller.llmInstalled,
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
      final controller = ref.read(appControllerProvider);
      final reply = await controller.chatOnce(text);
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
      if (mounted) {
        setState(() {
          if (generation == _speakGeneration) {
            _speaking = false;
          }
        });
      }
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
