import 'package:flutter_gemma/flutter_gemma.dart';

abstract interface class LlmPlatform {
  Future<void> initialize({String? huggingFaceToken});

  Future<void> activateLocalModel({
    required String path,
    required ModelType modelType,
    required ModelFileType fileType,
  });

  Future<InferenceModel> getActiveModel({
    required int maxTokens,
    required PreferredBackend preferredBackend,
  });
}

final class FlutterGemmaLlmPlatform implements LlmPlatform {
  const FlutterGemmaLlmPlatform();

  @override
  Future<void> initialize({String? huggingFaceToken}) {
    return FlutterGemma.initialize(
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: 10,
    );
  }

  @override
  Future<void> activateLocalModel({
    required String path,
    required ModelType modelType,
    required ModelFileType fileType,
  }) async {
    await FlutterGemma.installModel(
      modelType: modelType,
      fileType: fileType,
    ).fromFile(path).install();
  }

  @override
  Future<InferenceModel> getActiveModel({
    required int maxTokens,
    required PreferredBackend preferredBackend,
  }) {
    return FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: preferredBackend,
    );
  }
}
