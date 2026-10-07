import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

class TriageEngine {
  Llama? _llama;
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  Future<void> initEngine(String modelPath) async {
    if (_isLoaded) return;

    final file = File(modelPath);
    if (!await file.exists()) {
      throw Exception('GGUF file missing at: $modelPath');
    }

    // CRITICAL iOS FIX:
    // On iOS, llama_cpp_dart symbols are compiled inside the framework.
    // Specifying the framework dylib prevents RTLD_DEFAULT dlsym failures.
    if (Platform.isIOS) {
      try {
        Llama.libraryPath = "llama_cpp_dart.framework/llama_cpp_dart";
      } catch (e) {
        debugPrint('Framework path assignment error: $e');
      }
    }

    final modelParams = ModelParams();
    // Use 99 layers for GPU acceleration (Metal on iOS, OpenCL/Vulkan on Android)
    modelParams.nGpuLayers = 99;

    final contextParams = ContextParams();
    contextParams.nCtx = 2048;

    _llama = Llama(
      modelPath,
      modelParams,
      contextParams,
    );

    _isLoaded = true;
  }

  Stream<String> generateTriage(String scenario) async* {
    if (_llama == null || !_isLoaded) {
      throw StateError('Engine is not loaded yet');
    }

    final prompt = '''<|begin_of_text|><|start_header_id|>system<|end_header_id|>

You are CarePulse, an offline first-aid assistant. Respond in 3 numbered steps under 70 words:
1. IMMEDIATE ACTION
2. CRITICAL PRECAUTION
3. STABILIZE & MONITOR
No disclaimers.<|eot_id|><|start_header_id|>user<|end_header_id|>

EMERGENCY: $scenario<|eot_id|><|start_header_id|>assistant<|end_header_id|>
''';

    _llama!.setPrompt(prompt);

    await for (final token in _llama!.generateText()) {
      yield token;
    }
  }

  void dispose() {
    try {
      _llama?.dispose();
    } catch (_) {}
    _llama = null;
    _isLoaded = false;
  }
}