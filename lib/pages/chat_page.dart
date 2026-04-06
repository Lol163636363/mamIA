import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'setup_page.dart';

// ─── Config ───────────────────────────────────────────────────────────────────
const String _apiUrl = 'https://TON-TUNNEL.trycloudflare.com/chat';
//                      ↑ remplace par ton URL Cloudflare

// ─── Modèle message ───────────────────────────────────────────────────────────
enum Sender { user, ai }

enum ListenState {
  idle,       // en attente du mot-clé
  wakeWord,   // mot-clé détecté, en cours d'écoute de la commande
  loading,    // requête en cours
  playing,    // lecture audio
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
  final SpeechToText _stt = SpeechToText();
  final ScrollController _scrollController = ScrollController();

  ListenState _state = ListenState.idle;
  String _liveTranscript = '';
  bool _sttReady = false;

  // Timer pour relancer l'écoute du wake word après un cycle complet
  Timer? _restartTimer;

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
        _startWakeWordLoop();
      }
    });

    _initAndListen();
  }

  // ── Init STT + démarrage de la boucle wake word ──────────────────────────
  Future<void> _initAndListen() async {
    var status = await Permission.microphone.status;
    if (status.isDenied) {
      await Permission.microphone.request();
    }
    //──────────────────────────────────────────────────────────────────────────────
    final ok = await _stt.initialize(
      onError: (e) {
        debugPrint('STT error: $e');
        // En cas d'erreur, on relance dans 1s
        _restartTimer = Timer(const Duration(seconds: 1), _startWakeWordLoop);
      },
      onStatus: (s) {
        debugPrint('STT status: $s');
        if (s == 'notListening' && _state == ListenState.idle) {
          // La session STT s'est arrêtée toute seule → relancer
          _restartTimer =
              Timer(const Duration(milliseconds: 300), _startWakeWordLoop);
        }
      },
    );
    setState(() => _sttReady = ok);
    if (ok) _startWakeWordLoop();
  }

  // ── Boucle d'écoute du mot-clé ────────────────────────────────────────────
  //
  // speech_to_text ne fait pas de détection de hot-word nativement,
  // on utilise donc une session continue : on écoute en permanence et
  // on regarde si le transcript contient le mot-clé.
  //
  void _startWakeWordLoop() {
    if (!_sttReady) return;
    if (_state != ListenState.idle) return;
    if (_stt.isListening) return;

    _stt.listen(
      localeId: 'fr_FR',
      listenFor: const Duration(seconds: 10), // session max
      pauseFor: const Duration(seconds: 10),  // pas de coupure sur silence
      partialResults: true,
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();

        // Mot-clé détecté ?
        if (words.contains(widget.wakeWord.toLowerCase())) {
          _stt.stop();
          _onWakeWordDetected();
        }
      },
    );
  }

  // ── Mot-clé détecté → écouter la commande ─────────────────────────────────
  void _onWakeWordDetected() {
    if (_state != ListenState.idle) return;
    setState(() {
      _state = ListenState.wakeWord;
      _liveTranscript = '';
    });

    // Petit délai pour que l'utilisateur sache que mamAI l'écoute
    Future.delayed(const Duration(milliseconds: 200), () {
      _stt.listen(
        localeId: 'fr_FR',
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 2), // silence → fin de commande
        partialResults: true,
        onResult: (result) {
          setState(() => _liveTranscript = result.recognizedWords);

          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            _stt.stop();
            _sendMessage(result.recognizedWords);
          }
        },
      );
    });

    // Timeout de sécurité : si aucune commande en 15s → retour idle
    _restartTimer = Timer(const Duration(seconds: 16), () {
      if (_state == ListenState.wakeWord) {
        _stt.stop();
        setState(() => _state = ListenState.idle);
        _startWakeWordLoop();
      }
    });
  }

  // ── Envoi à l'API mamAI ───────────────────────────────────────────────────
  Future<void> _sendMessage(String texte) async {
    final trimmed = texte.trim();
    if (trimmed.isEmpty) {
      setState(() => _state = ListenState.idle);
      _startWakeWordLoop();
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
        // onPlayerComplete relance _startWakeWordLoop
      } else {
        _addError('Erreur serveur ${response.statusCode}');
        setState(() => _state = ListenState.idle);
        _startWakeWordLoop();
      }
    } catch (e) {
      _addError('Connexion impossible');
      setState(() => _state = ListenState.idle);
      _startWakeWordLoop();
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
    await _stt.cancel();
    _restartTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wake_word');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SetupPage()),
    );
  }

  @override
  void dispose() {
    _stt.cancel();
    _player.dispose();
    _orb.dispose();
    _restartTimer?.cancel();
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
          // ── Liste messages ───────────────────────────────────────────
          Expanded(
            child: _messages.isEmpty
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

// ─── Widget état vide ─────────────────────────────────────────────────────────
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

// ─── Indicateur d'état bas d'écran ────────────────────────────────────────────
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

// ─── Bulle de message ─────────────────────────────────────────────────────────
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
