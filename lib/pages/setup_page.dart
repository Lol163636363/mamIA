import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'chat_page.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  bool _isRecording = false;
  bool _voskReady = false;
  String _preview = '';
  String? _error;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _initVosk();
  }

  Future<void> _initVosk() async {
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        setState(() => _error = "Microphone non autorisé.");
        return;
      }

      final modelLoader = ModelLoader();
      final modelPath = await modelLoader.loadFromAssets('assets/models/vosk-model-small-fr');

      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(model: _model!, sampleRate: 16000);
      _speechService = await _vosk.initSpeechService(_recognizer!);

      _speechService!.onPartial().listen((partialJson) {
        if (_isRecording) {
          setState(() => _preview = jsonDecode(partialJson)['partial'] ?? '');
        }
      });

      _speechService!.onResult().listen((resultJson) {
        if (_isRecording) {
          final result = jsonDecode(resultJson)['text'] ?? '';
          if (result.isNotEmpty) {
            setState(() {
              _isRecording = false;
              _controller.text = result;
              _preview = '';
            });
            _speechService!.stop();
          }
        }
      });

      setState(() => _voskReady = true);
    } catch (e) {
      debugPrint("Vosk Setup Error: $e");
      setState(() => _error = "Erreur d'initialisation: $e");
    }
  }

  Future<void> _recordWakeWord() async {
    if (_isRecording) {
      await _speechService?.stop();
      setState(() => _isRecording = false);
      return;
    }
    setState(() {
      _isRecording = true;
      _preview = '';
      _error = null;
    });
    await _speechService?.start();
  }

  Future<void> _save() async {
    final word = _controller.text.trim().toLowerCase();
    if (word.isEmpty) {
      setState(() => _error = 'Entrez un mot-clé.');
      return;
    }
    await _speechService?.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wake_word', word);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ChatPage(wakeWord: word)),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller.dispose();
    _speechService?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('mamAI', style: TextStyle(color: Color(0xFF00D4FF), letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              const Text('Choisissez votre mot-clé', style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('C\'est le mot qui réveillera l\'IA.', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 40),
              TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'ex: Hello mamAI',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF12121A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              if (_preview.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Center(child: Text(_preview, style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 18))),
                ),
              const SizedBox(height: 30),
              Center(
                child: GestureDetector(
                  onTap: _voskReady ? _recordWakeWord : null,
                  child: ScaleTransition(
                    scale: _isRecording ? _pulseController.drive(Tween(begin: 1.0, end: 1.2)) : const AlwaysStoppedAnimation(1.0),
                    child: Container(
                      padding: const EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: !_voskReady ? Colors.grey : (_isRecording ? Colors.redAccent : const Color(0xFF2A2A4A)),
                        boxShadow: [
                          if (_isRecording) BoxShadow(color: Colors.redAccent.withOpacity(0.4), blurRadius: 20, spreadRadius: 5)
                        ],
                      ),
                      child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 35),
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _voskReady ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D4FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: Text(_voskReady ? 'VALIDER' : 'CHARGEMENT DU MODÈLE...', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
