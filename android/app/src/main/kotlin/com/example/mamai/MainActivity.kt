package com.example.mamai

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import org.vosk.android.StorageService
import java.io.IOException
import java.util.*
import java.util.concurrent.TimeUnit

class MainActivity : ComponentActivity(), RecognitionListener, TextToSpeech.OnInitListener {

    private var speechService: SpeechService? = null
    private var model: Model? = null
    private lateinit var prefs: SharedPreferences
    private var tts: TextToSpeech? = null
    private var isTtsReady = false

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    // Groq Configuration
    private val groqApiKey = "gsk_YOUR_GROQ_API_KEY" // À remplacer par l'utilisateur
    private val groqUrl = "https://api.groq.com/openai/v1/chat/completions"
    private val groqModel = "llama-3.3-70b-versatile"

    private val _liveTranscript = mutableStateOf("Initialisation...")
    private val _triggerWord = mutableStateOf("mamai")
    private val _messages = mutableStateListOf<Pair<String, Boolean>>() // Text to isUser
    private val _isListening = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        prefs = getSharedPreferences("mamai_prefs", Context.MODE_PRIVATE)
        _triggerWord.value = prefs.getString("trigger_word", "mamai") ?: "mamai"

        tts = TextToSpeech(this, this)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                var showSettings by remember { mutableStateOf(false) }

                if (showSettings) {
                    SettingsScreen(onBack = { showSettings = false })
                } else {
                    MainScreen(onSettingsClick = { showSettings = true })
                }
            }
        }

        if (checkPermissions()) {
            initVosk()
        }
    }

    private fun checkPermissions(): Boolean {
        val hasMicrophone = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (!hasMicrophone) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        }
        return hasMicrophone
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1 && grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            initVosk()
        } else {
            _liveTranscript.value = "Permission micro refusée."
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = tts?.setLanguage(Locale.FRENCH)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.e("TTS", "Langue non supportée")
            } else {
                isTtsReady = true
                tts?.setPitch(1.0f)
                tts?.setSpeechRate(1.0f)
            }
        } else {
            Log.e("TTS", "Initialisation échouée")
        }
    }

    private fun speak(text: String) {
        if (isTtsReady) {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "mamai_tts")
        }
    }

    private fun initVosk() {
        _liveTranscript.value = "Chargement du modèle..."
        StorageService.unpack(this, "model-fr", "model",
            { model: Model ->
                this.model = model
                _liveTranscript.value = "Dites '${_triggerWord.value}'"
                startRecognition()
            },
            { e: IOException ->
                Log.e("VOSK", "Erreur décompression: ${e.message}")
                _liveTranscript.value = "Erreur modèle: ${e.message}"
            }
        )
    }

    private fun startRecognition() {
        try {
            val rec = Recognizer(model, 16000.0f)
            speechService = SpeechService(rec, 16000.0f)
            speechService?.startListening(this)
            _isListening.value = true
        } catch (e: Exception) {
            Log.e("VOSK", "Erreur startListening: ${e.message}")
            _liveTranscript.value = "Erreur micro: ${e.message}"
        }
    }

    override fun onPartialResult(hypothesis: String) {
        val text = extractText(hypothesis, "partial")
        if (text.isNotEmpty()) {
            _liveTranscript.value = text
            if (text.lowercase().contains(_triggerWord.value.lowercase())) {
                _liveTranscript.value = "J'écoute..."
            }
        }
    }

    override fun onResult(hypothesis: String) {
        val text = extractText(hypothesis, "text")
        if (text.isNotEmpty()) {
            _messages.add(text to true)
            sendToGroq(text)
        }
    }

    private fun extractText(hypothesis: String, key: String): String {
        return try {
            val json = JSONObject(hypothesis)
            json.optString(key, "")
        } catch (e: Exception) { "" }
    }

    private fun sendToGroq(text: String) {
        lifecycleScope.launch {
            _liveTranscript.value = "Réflexion..."
            _isListening.value = false
            speechService?.stop()

            try {
                val json = JSONObject().apply {
                    put("model", groqModel)
                    put("messages", JSONArray().apply {
                        put(JSONObject().apply {
                            put("role", "system")
                            put("content", "Tu es mamIA, un assistant personnel bienveillant et efficace. Réponds de manière concise en français.")
                        })
                        put(JSONObject().apply {
                            put("role", "user")
                            put("content", text)
                        })
                    })
                    put("temperature", 0.7)
                }

                val body = json.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder()
                    .url(groqUrl)
                    .addHeader("Authorization", "Bearer $groqApiKey")
                    .post(body)
                    .build()

                withContext(Dispatchers.IO) {
                    client.newCall(request).execute().use { resp ->
                        val responseBody = resp.body?.string()
                        if (resp.isSuccessful && responseBody != null) {
                            val jsonResp = JSONObject(responseBody)
                            val aiText = jsonResp.getJSONArray("choices")
                                .getJSONObject(0)
                                .getJSONObject("message")
                                .getString("content")

                            withContext(Dispatchers.Main) {
                                _messages.add(aiText to false)
                                _liveTranscript.value = "mamIA parle..."
                                speak(aiText)
                                startRecognition()
                            }
                        } else {
                            withContext(Dispatchers.Main) {
                                _messages.add("Erreur Groq: ${resp.code}" to false)
                                startRecognition()
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    _messages.add("Erreur: ${e.message}" to false)
                    startRecognition()
                }
            }
        }
    }

    override fun onFinalResult(hypothesis: String) {}
    override fun onError(exception: Exception) {
        Log.e("VOSK", "Erreur RecognitionListener: ${exception.message}")
        _liveTranscript.value = "Erreur: ${exception.message}"
    }
    override fun onTimeout() {}

    override fun onDestroy() {
        super.onDestroy()
        speechService?.stop()
        speechService?.shutdown()
        tts?.stop()
        tts?.shutdown()
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun MainScreen(onSettingsClick: () -> Unit) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("mamAI", fontWeight = FontWeight.Bold) },
                    actions = {
                        IconButton(onClick = onSettingsClick) {
                            Icon(Icons.Default.Settings, contentDescription = "Settings")
                        }
                        IconButton(onClick = { _messages.clear() }) {
                            Icon(Icons.Default.Refresh, contentDescription = "Clear")
                        }
                    }
                )
            },
            containerColor = Color(0xFF0A0A0F)
        ) { padding ->
            Column(modifier = Modifier.padding(padding).fillMaxSize()) {
                LazyColumn(modifier = Modifier.weight(1f).padding(16.dp)) {
                    items(_messages) { msg ->
                        MessageBubble(msg.first, msg.second)
                    }
                }
                StatusArea()
            }
        }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun SettingsScreen(onBack: () -> Unit) {
        var textState by remember { mutableStateOf(_triggerWord.value) }

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Paramètres", fontWeight = FontWeight.Bold) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                        }
                    }
                )
            },
            containerColor = Color(0xFF0A0A0F)
        ) { padding ->
            Column(
                modifier = Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    "Déclencheur (Wake Word)",
                    color = Color.White,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(
                    value = textState,
                    onValueChange = { textState = it },
                    label = { Text("Mot-clé") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                Spacer(modifier = Modifier.height(24.dp))
                Button(
                    onClick = {
                        _triggerWord.value = textState
                        prefs.edit().putString("trigger_word", textState).apply()
                        _liveTranscript.value = "Dites '${textState}'"
                        onBack()
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text("Sauvegarder")
                }
            }
        }
    }

    @Composable
    fun MessageBubble(text: String, isUser: Boolean) {
        Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = if (isUser) Alignment.End else Alignment.Start) {
            Surface(
                color = if (isUser) Color(0xFF2A2A4A) else Color(0xFF1A1A2E),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.padding(vertical = 4.dp)
            ) {
                Text(text, color = Color.White, modifier = Modifier.padding(12.dp))
            }
        }
    }

    @Composable
    fun StatusArea() {
        val color = if (_isListening.value) Color(0xFF00D4FF) else Color.Gray
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = 30.dp, topEnd = 30.dp))
                .background(Color(0xFF12121A))
                .padding(30.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(60.dp)
                    .clip(CircleShape)
                    .background(color.copy(alpha = 0.2f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Mic, contentDescription = null, tint = color, modifier = Modifier.size(30.dp))
            }
            Spacer(modifier = Modifier.height(16.dp))
            Text(_liveTranscript.value, color = Color.White.copy(alpha = 0.7f), fontSize = 16.sp)
        }
    }
}
