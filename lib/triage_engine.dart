import 'dart:async';
import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

class TriageEngine {
  LlamaEngine? _engine;
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  Future<void> initEngine(String modelPath) async {
    if (_isLoaded) return;

    final file = File(modelPath);
    if (!await file.exists()) {
      throw Exception('GGUF file missing at: $modelPath');
    }

    // New 0.9.x API spawns an isolate engine
    _engine = await LlamaEngine.spawn(
      modelParams: ModelParams(path: modelPath, gpuLayers: 99),
      contextParams: const ContextParams(nCtx: 2048),
    );

    _isLoaded = true;
  }

  Stream<String> generateTriage(String scenario) async* {
    if (_engine == null || !_isLoaded) {
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

    // Sessions manage the memory context in 0.9.x
    final session = await _engine!.createSession();

    await for (final event in session.generate(
      prompt: prompt,
      addSpecial: true,
      sampler: const SamplerParams(temperature: 0.2, topP: 0.9),
      maxTokens: 128,
    )) {
      if (event is TokenEvent) {
        yield event.text;
      }
    }
    
    await session.dispose();
  }

  void dispose() {
    _engine?.dispose();
    _engine = null;
    _isLoaded = false;
  }
}