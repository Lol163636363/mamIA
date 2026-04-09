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

  // Vosk variables
  final VoskFlutter _vosk = VoskFlutter.instance;
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  bool _isRecording = false;
  bool _voskReady = false;
  String _preview = '';
  String? _error;

  // Suggestions rapides
  final List<String> _suggestions = [
    'Hey mamAI',
    'Jarvis',
    'Salut Nova',
    'OK Atlas',
    'Héros',
  ];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initVosk();
  }

  Future<void> _initVosk() async {
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return;

      // Charger le modèle pour la config
      final path = await _vosk.modelPath('assets/models/vosk-model-small-fr');
      _model = await _vosk.createModel(path);
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
      setState(() => _error = "Erreur d'initialisation vocale.");
    }
  }

  // Enregistre le mot-clé dit à voix haute
  Future<void> _recordWakeWord() async {
    if (_isRecording) {
      await _speechService?.stop();
      setState(() {
        _isRecording = false;
        if (_preview.isNotEmpty) _controller.text = _preview;
      });
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

    // Fermer proprement Vosk avant de changer de page
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
    _speechService?.dispose();
    _recognizer?.dispose();
    _model?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              const Text(
                'mamAI',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 4,
                  color: Color(0xFF00D4FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Choisissez\nvotre mot-clé',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Prononcez ce mot à tout moment pour\ndéclencher mamAI.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white54,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 36),

              // ── Suggestions ─────────────────────────────────────────
              const Text(
                'SUGGESTIONS',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 3,
                  color: Colors.white38,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _suggestions.map((s) {
                  return GestureDetector(
                    onTap: () => setState(() {
                      _controller.text = s;
                      _error = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF2A2A3A)),
                        borderRadius: BorderRadius.circular(20),
                        color: const Color(0xFF12121A),
                      ),
                      child: Text(
                        s,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 32),

              // ── Champ texte ──────────────────────────────────────────
              const Text(
                'OU SAISISSEZ / DITES LE VÔTRE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 3,
                  color: Colors.white38,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: (_) => setState(() => _error = null),
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: InputDecoration(
                        hintText: 'ex: Hey Nova',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: const Color(0xFF12121A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF00D4FF),
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Bouton micro pour dire le mot-clé
                  GestureDetector(
                    onTap: _voskReady ? _recordWakeWord : null,
                    child: AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, child) => Transform.scale(
                        scale: _isRecording ? _pulseAnim.value : 1.0,
                        child: child,
                      ),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording
                              ? const Color(0xFFFF3B5C)
                              : const Color(0xFF1E1E2E),
                          border: Border.all(
                            color: _isRecording
                                ? const Color(0xFFFF3B5C)
                                : const Color(0xFF2A2A3A),
                          ),
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.mic_none,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Preview Vosk en direct
              if (_isRecording && _preview.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '🎤 "$_preview"',
                  style: const TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 13,
                  ),
                ),
              ],

              // Erreur
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF3B5C),
                    fontSize: 13,
                  ),
                ),
              ],

              const Spacer(),

              // ── Bouton valider ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D4FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Activer mamAI →',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
