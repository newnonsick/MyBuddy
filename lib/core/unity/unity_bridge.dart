import 'package:flutter/services.dart';

class UnityBridge {
  UnityBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_defaultChannelName);

  static const String _defaultChannelName = 'unity_bridge';

  static const String defaultGameObject = 'UnityBridge';

  final MethodChannel _channel;

  Future<void> openUnity({
    String gameObject = defaultGameObject,
    String? initialSpeakPath,
    int? initialAnimIndex,
    bool initialStopSpeak = false,
  }) async {
    final args = <String, Object?>{
      'gameObject': gameObject,
      if (initialSpeakPath != null) 'initialSpeakPath': initialSpeakPath,
      if (initialAnimIndex != null) 'initialAnimIndex': initialAnimIndex,
      if (initialStopSpeak) 'initialStopSpeak': true,
    };
    await _channel.invokeMethod<void>('openUnity', args);
  }

  Future<void> speak(String path, {String gameObject = defaultGameObject}) {
    return _channel.invokeMethod<void>('unitySpeak', {
      'gameObject': gameObject,
      'path': path,
    });
  }

  Future<void> stopSpeak({String gameObject = defaultGameObject}) {
    return _channel.invokeMethod<void>('unityStopSpeak', {
      'gameObject': gameObject,
    });
  }

  Future<void> playAnimation(
    int index, {
    String gameObject = defaultGameObject,
  }) {
    return _channel.invokeMethod<void>('unityPlayAnimation', {
      'gameObject': gameObject,
      'index': index,
    });
  }

  Future<bool> moveAppToBackground() async {
    final moved = await _channel.invokeMethod<bool>('moveAppToBackground');
    return moved ?? false;
  }
}
