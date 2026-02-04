import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_controller.dart';
import '../../../../app/my_app.dart';
import '../../../../app/providers.dart';
import '../../../../core/tts/tts_service.dart';
import '../../../../core/unity/unity_bridge.dart';
import '../../../../shared/widgets/glass/glass.dart';
import '../../../google_calendar/presentation/pages/google_calendar_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../domain/chat_line.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_transcript.dart';

class BuddyHomePage extends ConsumerStatefulWidget {
  const BuddyHomePage({super.key});

  @override
  ConsumerState<BuddyHomePage> createState() => _BuddyHomePageState();
}

class _BuddyHomePageState extends ConsumerState<BuddyHomePage> {
  late final UnityBridge _unity;
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
    _unity = ref.read(unityBridgeProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = ref.read(appControllerProvider);
      await controller.startup();
    });
  }

  @override
  void dispose() {
    _tts.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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
              _buildTopRightButtons(),
              _buildStatusPill(controller),
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

  Widget _buildTopRightButtons() {
    return Positioned(
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
    );
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
                  ? AppColors.statusOnline
                  : AppColors.statusOffline,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPill(AppController controller) {
    return Positioned(
      top: 10,
      left: 12,
      child: GlassPill(
        child: Text(
          _getStatusText(controller),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  String _getStatusText(AppController controller) {
    if (controller.installingLlm) return 'Preparing model…';
    if (controller.llmInstalled) return 'MyBuddy';
    return 'Select a model in Settings';
  }

  Widget _buildTranscript(BuildContext context, AppController controller) {
    if (controller.installingLlm || controller.hideChatLog) {
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
    } catch (_) {
      // Ignore errors when stopping
    } finally {
      if (mounted) {
        setState(() => _speaking = false);
      }
    }
  }

  Future<void> _onSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _chat.add(ChatLine.user(text));
      _textController.clear();
    });

    try {
      final controller = ref.read(appControllerProvider);
      final reply = await controller.chatOnce(text);

      if (!mounted || reply.trim().isEmpty) return;

      setState(() {
        _chat.add(ChatLine.assistant(reply.trim()));
      });
      _scrollToBottom();

      if (reply.trim().isNotEmpty) {
        unawaited(_speakInUnity(reply.trim()));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chat.add(ChatLine.assistant('Error: $e'));
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _speakInUnity(String text) async {
    final generation = ++_speakGeneration;
    if (!mounted) return;

    setState(() => _speaking = true);

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
      if (mounted && generation == _speakGeneration) {
        setState(() => _speaking = false);
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
