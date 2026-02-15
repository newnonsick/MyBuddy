import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../app/app_controller.dart';
import '../../../../app/stt_model_controller.dart';
import '../../../../core/audio/audio_recorder_service.dart';
import '../../../../core/stt/stt_service.dart';
import '../../domain/chat_line.dart';

typedef ChatSpeakHandler = Future<void> Function(String text);
typedef ChatStopSpeakHandler = Future<void> Function();
typedef ChatErrorHandler = void Function(String message);

class ChatSessionController extends ChangeNotifier {
  ChatSessionController({
    required AppController appController,
    required SttModelController sttModelController,
    required SttService sttService,
    required AudioRecorderService recorder,
    ChatSpeakHandler? onSpeak,
    ChatStopSpeakHandler? onStopSpeaking,
    ChatErrorHandler? onError,
  }) : _appController = appController,
       _sttModelController = sttModelController,
       _sttService = sttService,
       _recorder = recorder,
       _onSpeak = onSpeak,
       _onStopSpeaking = onStopSpeaking,
       _onError = onError {
    syncFromAppConversation();
  }

  final AppController _appController;
  final SttModelController _sttModelController;
  final SttService _sttService;
  final AudioRecorderService _recorder;
  final ChatSpeakHandler? _onSpeak;
  final ChatStopSpeakHandler? _onStopSpeaking;
  final ChatErrorHandler? _onError;

  final List<ChatLine> _chat = <ChatLine>[];
  List<ChatLine> get chat => List<ChatLine>.unmodifiable(_chat);

  bool _sending = false;
  bool get sending => _sending;

  bool _speaking = false;
  bool get speaking => _speaking;

  bool _recording = false;
  bool get recording => _recording;

  bool _transcribing = false;
  bool get transcribing => _transcribing;

  int _recordGeneration = 0;
  int _speakGeneration = 0;
  DateTime? _recordStartedAt;

  void syncFromAppConversation() {
    final next = _appController.conversation
        .map(_mapConversationLine)
        .whereType<ChatLine>()
        .toList(growable: false);

    if (_isSameChat(next)) return;

    _chat
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  ChatLine? _mapConversationLine(Map<String, String> line) {
    final role = line['role'];
    final text = (line['text'] ?? '').trim();
    if (text.isEmpty) return null;
    if (role == 'user') return ChatLine.user(text);
    if (role == 'assistant') return ChatLine.assistant(text);
    return null;
  }

  bool _isSameChat(List<ChatLine> next) {
    if (next.length != _chat.length) return false;
    for (var i = 0; i < next.length; i++) {
      final current = _chat[i];
      final incoming = next[i];
      if (current.isUser != incoming.isUser || current.text != incoming.text) {
        return false;
      }
    }
    return true;
  }

  Future<void> startMicHold() async {
    if (_sending || _transcribing || _recording) return;

    if (_speaking) {
      await stopSpeaking();
    }

    final generation = ++_recordGeneration;
    _recording = true;
    _recordStartedAt = null;
    notifyListeners();

    final hasPermission = await _recorder.hasPermission();

    try {
      await _recorder.start();
      if (generation != _recordGeneration) return;
      _recordStartedAt = DateTime.now();
    } catch (e) {
      _recording = false;
      _recordStartedAt = null;
      notifyListeners();
      if (!hasPermission) {
        _onError?.call('Microphone permission is required.');
      } else {
        _onError?.call('Failed to start recording: $e');
      }
    }
  }

  Future<void> cancelMicHold() async {
    _recordGeneration++;
    _recording = false;
    _recordStartedAt = null;
    notifyListeners();
    await _recorder.cancelAndDelete();
  }

  Future<void> endMicHoldAndSend() async {
    if (_sending || _transcribing || !_recording) return;

    final generation = _recordGeneration;
    final startedAt = _recordStartedAt;

    _recording = false;
    _transcribing = true;
    _recordStartedAt = null;
    notifyListeners();

    try {
      final audioPath = await _recorder.stop();
      if (generation != _recordGeneration) return;

      if (audioPath == null || audioPath.trim().isEmpty) {
        throw StateError('No audio file recorded.');
      }

      if (startedAt != null) {
        final elapsed = DateTime.now().difference(startedAt);
        if (elapsed.inMilliseconds < 450) {
          await _recorder.cancelAndDelete();
          if (generation != _recordGeneration) return;
          _onError?.call('Hold the mic a bit longer to record.');
          return;
        }
      }

      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        throw StateError('Recorded file not found.');
      }

      final bytes = await audioFile.length();
      if (bytes < 2048) {
        throw StateError('Recording is too short (file is ${bytes}B).');
      }

      final selected = _sttModelController.selectedInstalledModel;
      if (selected == null) {
        throw StateError('No STT model selected.');
      }

      final text = await _sttService.transcribe(
        modelPath: selected.localPath,
        audioPath: audioPath,
        lang: _sttModelController.selectedLanguage,
        isTranslate: true,
      );

      if (generation != _recordGeneration) return;

      if (text == null || text.trim().isEmpty) {
        _onError?.call('No speech detected.');
        return;
      }

      await sendText(text.trim());
    } catch (e) {
      _onError?.call('$e');
    } finally {
      if (generation == _recordGeneration) {
        _transcribing = false;
        notifyListeners();
      }
    }
  }

  Future<void> sendText(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _sending) return;

    _sending = true;
    _chat.add(ChatLine.user(text));
    notifyListeners();

    try {
      final reply = await _appController.chatOnce(text);

      final trimmed = reply.trim();
      if (trimmed.isEmpty) {
        _chat.add(ChatLine.assistant('[No response from model]'));
        notifyListeners();
        return;
      }

      if (_onSpeak != null) {
        final generation = ++_speakGeneration;
        _speaking = true;
        notifyListeners();
        final ChatSpeakHandler speak = _onSpeak;

        try {
          await speak(reply.trim());
        } catch (e) {
          _onError?.call('TTS failed: $e');
        } finally {
          if (generation == _speakGeneration) {
            _speaking = false;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      _chat.add(ChatLine.assistant('Error: $e'));
      notifyListeners();
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> stopSpeaking() async {
    _speakGeneration++;
    try {
      await _onStopSpeaking?.call();
    } catch (_) {
      // ignore
    } finally {
      _speaking = false;
      notifyListeners();
    }
  }
}
