import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'triage_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CarePulseApp());
}

class CarePulseApp extends StatelessWidget {
  const CarePulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CarePulse MVP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121A22), // Calm blue-gray
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2F8F9D), // Soft healthcare teal
          surface: Color(0xFF1B242D),
        ),
      ),
      home: const MVPTestHarnessScreen(),
    );
  }
}

class MVPTestHarnessScreen extends StatefulWidget {
  const MVPTestHarnessScreen({super.key});

  @override
  State<MVPTestHarnessScreen> createState() => _MVPTestHarnessScreenState();
}

class _MVPTestHarnessScreenState extends State<MVPTestHarnessScreen> {
  static const String modelUrl =
      'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf';
  static const String modelFileName = 'Llama-3.2-1B-Instruct-Q4_K_M.gguf';

  final TriageEngine _engine = TriageEngine();
  final TextEditingController _queryController =
      TextEditingController(text: 'Severe cut on hand, bleeding heavily');

  bool _isChecking = true;
  bool _isModelDownloaded = false;
  bool _isDownloading = false;
  bool _isEngineReady = false;
  bool _isGenerating = false;

  double _downloadProgress = 0.0;
  String _downloadStats = '';
  String _streamOutput = '';
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _checkModelFile();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _engine.dispose();
    super.dispose();
  }

  Future<String> _getModelPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, modelFileName);
  }

  Future<void> _checkModelFile() async {
    setState(() {
      _isChecking = true;
      _statusMessage = 'Checking local storage...';
    });

    try {
      final path = await _getModelPath();
      final file = File(path);

      if (await file.exists() && (await file.length()) > 700 * 1024 * 1024) {
        setState(() {
          _isModelDownloaded = true;
          _statusMessage = 'Model exists in sandbox. Initializing engine...';
        });
        await _initializeEngine(path);
      } else {
        setState(() {
          _isModelDownloaded = false;
          _statusMessage = 'Model not found. Ready to download.';
        });
      }
    } catch (e) {
      setState(() => _statusMessage = 'Check error: $e');
    } finally {
      setState(() => _isChecking = false);
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = 'Starting chunked download...';
    });

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final tempPath = p.join(docsDir.path, '$modelFileName.tmp');
      final finalPath = p.join(docsDir.path, modelFileName);

      final dio = Dio();
      await dio.download(
        modelUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final double prog = received / total;
            final int recMB = received ~/ (1024 * 1024);
            final int totMB = total ~/ (1024 * 1024);
            setState(() {
              _downloadProgress = prog;
              _downloadStats = '$recMB MB / $totMB MB (${(prog * 100).toStringAsFixed(1)}%)';
            });
          }
        },
      );

      final tempFile = File(tempPath);
      await tempFile.rename(finalPath);

      setState(() {
        _isModelDownloaded = true;
        _isDownloading = false;
        _statusMessage = 'Download complete! Initializing engine...';
      });

      await _initializeEngine(finalPath);
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Download failed: $e';
      });
    }
  }

  Future<void> _initializeEngine(String modelPath) async {
    try {
      await _engine.initEngine(modelPath);
      setState(() {
        _isEngineReady = true;
        _statusMessage = 'Engine ready! 100% Offline Active.';
      });
    } catch (e) {
      setState(() {
        _isEngineReady = false;
        _statusMessage = 'Engine init failed: $e';
      });
    }
  }

  Future<void> _runInference() async {
    final text = _queryController.text.trim();
    if (text.isEmpty || !_isEngineReady || _isGenerating) return;

    setState(() {
      _isGenerating = true;
      _streamOutput = '';
    });

    try {
      await for (final token in _engine.generateTriage(text)) {
        setState(() {
          _streamOutput += token;
        });
      }
    } catch (e) {
      setState(() => _streamOutput = 'Generation error: $e');
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CarePulse MVP Test Harness'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1B242D),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B242D),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334250)),
                ),
                child: Text(
                  _statusMessage ?? 'Idle',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF72C2CE)),
                ),
              ),
              const SizedBox(height: 16),

              // Download / Setup Button or Progress
              if (_isChecking)
                const Center(child: CircularProgressIndicator())
              else if (!_isModelDownloaded && !_isDownloading)
                ElevatedButton.icon(
                  onPressed: _downloadModel,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download Llama 3.2 1B (~808 MB)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF2F8F9D),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                )
              else if (_isDownloading) ...[
                LinearProgressIndicator(value: _downloadProgress),
                const SizedBox(height: 8),
                Text(_downloadStats, textAlign: TextAlign.center),
              ],

              const SizedBox(height: 20),
              const Divider(color: Color(0xFF334250)),
              const SizedBox(height: 12),

              // Query Input
              TextField(
                controller: _queryController,
                enabled: _isEngineReady && !_isGenerating,
                decoration: InputDecoration(
                  labelText: 'Emergency Scenario',
                  filled: true,
                  fillColor: const Color(0xFF1B242D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: (_isEngineReady && !_isGenerating) ? _runInference : null,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_isGenerating ? 'Generating...' : 'Run Offline Triage'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFFE05A4F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),

              const SizedBox(height: 20),

              // Live Streaming Token Output Box
              Container(
                constraints: const BoxConstraints(minHeight: 140),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B242D),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isGenerating ? const Color(0xFF72C2CE) : const Color(0xFF334250),
                  ),
                ),
                child: SelectableText(
                  _streamOutput.isEmpty
                      ? (_isGenerating ? 'Awaiting first token...' : 'Generated tokens will stream here.')
                      : _streamOutput,
                  style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFFE6EDF3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}