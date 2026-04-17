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

const String _apiUrl = 'https://TON-TUNNEL.trycloudflare.com/chat';

enum Sender { user, ai }

enum ListenState {
  idle,         // En attente du mot-clé
  wakeWord,     // Mot-clé détecté, écoute de la commande
  loading,      // Traitement IA
  playing,      // L'IA parle
  initializing, // Chargement Vosk
  error         // Erreur fatale
}

class ChatMessage {
  final String text;
  final Sender sender;
  ChatMessage({required this.text, required this.sender});
}

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

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  ListenState _state = ListenState.initializing;
  String _liveTranscript = 'Initialisation...';
  String? _errorMessage;

  late AnimationController _orb;
  late Animation<double> _orbScale;

  @override
  void initState() {
    super.initState();
    _orb = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _orbScale = Tween(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _orb, curve: Curves.easeInOut),
    );

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        _startListening();
      }
    });

    _initVosk();
  }

  Future<void> _initVosk() async {
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        setState(() {
          _state = ListenState.error;
          _errorMessage = "Permission micro refusée";
        });
        return;
      }

      final modelLoader = ModelLoader();
      final modelPath = await modelLoader.loadFromAssets('assets/models/vosk-model-small-fr');

      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(model: _model!, sampleRate: 16000);
      _speechService = await _vosk.initSpeechService(_recognizer!);

      _speechService!.onPartial().listen((partialJson) {
        final partial = jsonDecode(partialJson)['partial'] ?? '';
        if (partial.isEmpty) return;

        setState(() => _liveTranscript = partial);

        if (_state == ListenState.idle) {
          if (partial.toLowerCase().contains(widget.wakeWord.toLowerCase())) {
            setState(() {
              _state = ListenState.wakeWord;
              _liveTranscript = "J'écoute...";
            });
          }
        }
      });

      _speechService!.onResult().listen((resultJson) {
        final result = jsonDecode(resultJson)['text'] ?? '';
        if (_state == ListenState.wakeWord && result.isNotEmpty) {
          _sendMessage(result);
        } else if (_state == ListenState.wakeWord && result.isEmpty) {
          // Si on attendait une commande mais qu'on n'a rien reçu, on repasse en idle
          setState(() => _state = ListenState.idle);
        }
      });

      _startListening();
    } catch (e) {
      setState(() {
        _state = ListenState.error;
        _errorMessage = "Erreur Vosk: $e";
      });
    }
  }

  void _startListening() {
    _speechService?.start();
    setState(() {
      _state = ListenState.idle;
      _liveTranscript = "Dites '${widget.wakeWord}'";
    });
  }

  Future<void> _sendMessage(String texte) async {
    await _speechService?.stop(); // On arrête d'écouter pendant que l'IA réfléchit/parle

    setState(() {
      _state = ListenState.loading;
      _liveTranscript = 'Analyse en cours...';
      _messages.add(ChatMessage(text: texte, sender: Sender.user));
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'texte': texte}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final iaText = Uri.decodeComponent(response.headers['x-ia-reponse'] ?? '...');
        final Uint8List audioBytes = response.bodyBytes;

        setState(() {
          _state = ListenState.playing;
          _liveTranscript = 'mamIA parle...';
          _messages.add(ChatMessage(text: iaText, sender: Sender.ai));
        });
        _scrollToBottom();
        await _player.play(BytesSource(audioBytes));
      } else {
        _startListening();
      }
    } catch (e) {
      _startListening();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _reset() async {
    await _speechService?.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wake_word');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const SetupPage()));
  }

  @override
  void dispose() {
    _speechService?.stop();
    _player.dispose();
    _orb.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('mamIA', style: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _reset)],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
            ),
          ),
          _StatusArea(state: _state, transcript: _liveTranscript, anim: _orbScale, error: _errorMessage),
        ],
      ),
    );
  }
}

class _StatusArea extends StatelessWidget {
  final ListenState state;
  final String transcript;
  final String? error;
  final Animation<double> anim;

  const _StatusArea({required this.state, required this.transcript, this.error, required this.anim});

  @override
  Widget build(BuildContext context) {
    Color color = Colors.blueGrey;
    if (state == ListenState.wakeWord) color = const Color(0xFF00D4FF);
    if (state == ListenState.playing) color = const Color(0xFF00FF94);
    if (state == ListenState.error) color = Colors.redAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF12121A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ScaleTransition(
            scale: anim,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.2)),
              child: Icon(state == ListenState.loading ? Icons.hourglass_empty : Icons.mic, color: color, size: 30),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            transcript,
            textAlign: TextAlign.center,
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage msg;
  const _MessageBubble({required this.msg});
  @override
  Widget build(BuildContext context) {
    bool isUser = msg.sender == Sender.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF2A2A4A) : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isUser ? Radius.zero : const Radius.circular(20),
            bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
          ),
        ),
        child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 15)),
      ),
    );
  }
}
