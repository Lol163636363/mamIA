import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'setup_page.dart';

// ─── Config ───────────────────────────────────────────────────────────────────
const String _apiUrl = 'https://TON-TUNNEL.trycloudflare.com/chat';
const String _modelPath = 'assets/models/vosk-model-small-fr';

// ─── Modèle message ───────────────────────────────────────────────────────────
enum Sender { user, ai }

enum ListenState {
  idle,       // en attente du mot-clé
  wakeWord,   // mot-clé détecté, en cours d'écoute de la commande
  loading,    // requête en cours
  playing,    // lecture audio
  initializing, // chargement du modèle Vosk
}

class ChatMessage {
  final String text;
  final Sender sender;
  ChatMessage({required this.text, required this.sender});
}

// ─── Page Chat ────────────────────────────────────────────────────────────────
class ChatPage extends StatefulWidget {
  final String wakeWord;
  const ChatPage({super.key, required this.wakeWord});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  final AudioPlayer _player = AudioPlayer();
  final ScrollController _scrollController = ScrollController();

  // Vosk variables
  final VoskFlutter _vosk = VoskFlutter.instance;
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  ListenState _state = ListenState.initializing;
  String _liveTranscript = '';
  String? _errorMessage;

  late AnimationController _orb;
  late Animation<double> _orbScale;

  @override
  void initState() {
    super.initState();

    _orb = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _orbScale = Tween(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _orb, curve: Curves.easeInOut),
    );

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _state = ListenState.idle);
        _resumeListening();
      }
    });

    _initVosk();
  }

  // ── Init Vosk Model & Service ──────────────────────────────────────────────
  Future<void> _initVosk() async {
    try {
      var status = await Permission.microphone.status;
      if (status.isDenied) {
        status = await Permission.microphone.request();
        if (!status.isGranted) {
          setState(() {
            _state = ListenState.idle;
            _errorMessage = "Microphone non autorisé";
          });
          return;
        }
      }

      // 1. Charger le modèle depuis les assets
      final path = await _vosk.modelPath(_modelPath);
      _model = await _vosk.createModel(path);

      // 2. Créer le reconnaisseur
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );

      // 3. Initialiser le service de parole
      _speechService = await _vosk.initSpeechService(_recognizer!);

      // Flux de résultats partiels (pendant qu'on parle)
      _speechService!.onPartial().listen((partialJson) {
        final partial = jsonDecode(partialJson)['partial'] ?? '';
        if (_state == ListenState.idle) {
          if (partial.toLowerCase().contains(widget.wakeWord.toLowerCase())) {
            _onWakeWordDetected();
          }
        } else if (_state == ListenState.wakeWord) {
          setState(() => _liveTranscript = partial);
        }
      });

      // Flux de résultats finaux (après un silence)
      _speechService!.onResult().listen((resultJson) {
        final result = jsonDecode(resultJson)['text'] ?? '';
        if (_state == ListenState.wakeWord && result.isNotEmpty) {
          _sendMessage(result);
        }
      });

      await _speechService!.start();
      setState(() => _state = ListenState.idle);

    } catch (e) {
      debugPrint('Vosk Init Error: $e');
      setState(() {
        _state = ListenState.idle;
        _errorMessage = "Erreur d'initialisation vocale.\nVérifiez que le modèle est bien dans assets.";
      });
    }
  }

  void _onWakeWordDetected() {
    if (_state != ListenState.idle) return;
    setState(() {
      _state = ListenState.wakeWord;
      _liveTranscript = '';
    });
    // On ne stoppe pas le service, on change juste d'état interne
  }

  void _resumeListening() async {
    if (_speechService != null) {
      // Si on était en pause pendant l'audio, on reprend
      // Mais ici avec Vosk on peut rester en start() et filtrer par état
      setState(() {
        _state = ListenState.idle;
        _liveTranscript = '';
      });
    }
  }

  // ── Envoi à l'API mamAI ───────────────────────────────────────────────────
  Future<void> _sendMessage(String texte) async {
    final trimmed = texte.trim();
    if (trimmed.isEmpty) {
      setState(() => _state = ListenState.idle);
      return;
    }

    setState(() {
      _state = ListenState.loading;
      _liveTranscript = '';
      _messages.add(ChatMessage(text: trimmed, sender: Sender.user));
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'texte': trimmed}),
      );

      if (response.statusCode == 200) {
        final iaText = Uri.decodeComponent(
          response.headers['x-ia-reponse'] ?? '...',
        );
        final Uint8List audioBytes = response.bodyBytes;

        setState(() {
          _state = ListenState.playing;
          _messages.add(ChatMessage(text: iaText, sender: Sender.ai));
        });
        _scrollToBottom();

        await _player.play(BytesSource(audioBytes));
        // onPlayerComplete relance l'écoute
      } else {
        _addError('Erreur serveur ${response.statusCode}');
        setState(() => _state = ListenState.idle);
      }
    } catch (e) {
      _addError('Connexion impossible');
      setState(() => _state = ListenState.idle);
    }
  }

  void _addError(String msg) => setState(() {
        _messages.add(ChatMessage(text: '⚠️ $msg', sender: Sender.ai));
      });

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Changer le mot-clé ────────────────────────────────────────────────────
  Future<void> _resetWakeWord() async {
    await _speechService?.stop();
    _speechService = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wake_word');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SetupPage()),
    );
  }

  @override
  void dispose() {
    _speechService?.stop();
    _speechService?.dispose();
    _recognizer?.dispose();
    _model?.dispose();
    _player.dispose();
    _orb.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('mamAI',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            Text(
              'mot-clé : "${widget.wakeWord}"',
              style: const TextStyle(
                  fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white38),
            tooltip: 'Changer le mot-clé',
            onPressed: _resetWakeWord,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              color: Colors.redAccent.withOpacity(0.1),
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              child: Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),

          // ── Liste messages ───────────────────────────────────────────
          Expanded(
            child: _state == ListenState.initializing
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _EmptyState(wakeWord: widget.wakeWord)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) =>
                            _MessageBubble(msg: _messages[i]),
                      ),
          ),

          // ── Indicateur d'état ────────────────────────────────────────
          _StateIndicator(
            state: _state,
            wakeWord: widget.wakeWord,
            liveTranscript: _liveTranscript,
            orbAnim: _orbScale,
          ),
        ],
      ),
    );
  }
}

// ─── Widget état vide (inchangé) ──────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String wakeWord;
  const _EmptyState({required this.wakeWord});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎙️',
              style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'Dites\n"$wakeWord"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'pour commencer',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─── Indicateur d'état bas d'écran (mis à jour) ───────────────────────────────
class _StateIndicator extends StatelessWidget {
  final ListenState state;
  final String wakeWord;
  final String liveTranscript;
  final Animation<double> orbAnim;

  const _StateIndicator({
    required this.state,
    required this.wakeWord,
    required this.liveTranscript,
    required this.orbAnim,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E18),
          border: Border(
              top: BorderSide(color: Color(0xFF1E1E2E), width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Orbe animé
            AnimatedBuilder(
              animation: orbAnim,
              builder: (_, __) => Transform.scale(
                scale: state == ListenState.wakeWord ||
                        state == ListenState.playing
                    ? orbAnim.value
                    : 1.0,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _orbColor(),
                    boxShadow: [
                      BoxShadow(
                        color: _orbColor().withOpacity(0.4),
                        blurRadius:
                            state == ListenState.idle ? 8 : 20,
                        spreadRadius:
                            state == ListenState.idle ? 0 : 4,
                      )
                    ],
                  ),
                  child: Icon(_orbIcon(),
                      color: Colors.white, size: 24),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Texte d'état
            Text(
              _stateLabel(),
              style: TextStyle(
                fontSize: 13,
                color: _orbColor(),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),

            // Transcript live
            if (state == ListenState.wakeWord &&
                liveTranscript.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                liveTranscript,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _orbColor() {
    switch (state) {
      case ListenState.initializing:
        return Colors.white24;
      case ListenState.idle:
        return const Color(0xFF2A2A4A);
      case ListenState.wakeWord:
        return const Color(0xFF00D4FF);
      case ListenState.loading:
        return const Color(0xFF7B2FFF);
      case ListenState.playing:
        return const Color(0xFF00FF94);
    }
  }

  IconData _orbIcon() {
    switch (state) {
      case ListenState.initializing:
        return Icons.hourglass_top;
      case ListenState.idle:
        return Icons.hearing;
      case ListenState.wakeWord:
        return Icons.mic;
      case ListenState.loading:
        return Icons.hourglass_empty;
      case ListenState.playing:
        return Icons.volume_up;
    }
  }

  String _stateLabel() {
    switch (state) {
      case ListenState.initializing:
        return 'CHARGEMENT DU MODÈLE…';
      case ListenState.idle:
        return 'EN ATTENTE DU MOT-CLÉ';
      case ListenState.wakeWord:
        return 'JE VOUS ÉCOUTE…';
      case ListenState.loading:
        return 'RÉFLEXION…';
      case ListenState.playing:
        return 'RÉPONSE EN COURS';
    }
  }
}

// ─── Bulle de message (inchangée) ─────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.sender == Sender.user;
    return Align(
      alignment:
          isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF1A3A5C)
              : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: Border.all(
            color: isUser
                ? const Color(0xFF00D4FF).withOpacity(0.3)
                : const Color(0xFF2A2A3A),
            width: 1,
          ),
        ),
        child: Text(msg.text,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, height: 1.4)),
      ),
    );
  }
}
