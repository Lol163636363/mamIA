package com.example.mamai

import android.content.Context
import android.content.SharedPreferences
import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Bundle
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
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.SpeechService
import org.vosk.android.StorageService
import org.vosk.android.RecognitionListener
import java.io.IOException
import java.util.concurrent.TimeUnit

class MainActivity : ComponentActivity(), RecognitionListener {

    private var speechService: SpeechService? = null
    private var model: Model? = null
    private lateinit var prefs: SharedPreferences
    
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val backendUrl = "http://192.168.1.50:8000/chat" 

    private val _liveTranscript = mutableStateOf("Initialisation...")
    private val _triggerWord = mutableStateOf("mamai")
    private val _messages = mutableStateListOf<Pair<String, Boolean>>() // Text to isUser

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        prefs = getSharedPreferences("mamai_prefs", Context.MODE_PRIVATE)
        _triggerWord.value = prefs.getString("trigger_word", "mamai") ?: "mamai"

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
            sendToBackend(text)
        }
    }

    private fun extractText(hypothesis: String, key: String): String {
        return try {
            val json = JSONObject(hypothesis)
            json.optString(key, "")
        } catch (e: Exception) { "" }
    }

    private fun sendToBackend(text: String) {
        lifecycleScope.launch {
            _liveTranscript.value = "Réflexion..."
            try {
                val json = JSONObject().apply { put("text", text) }
                val body = json.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder().url(backendUrl).post(body).build()
                
                withContext(Dispatchers.IO) {
                    client.newCall(request).execute().use { resp ->
                        if (resp.isSuccessful) {
                            val audioBytes = resp.body?.bytes()
                            val responseHeader = resp.header("X-Response-Text") ?: "Message reçu"
                            
                            withContext(Dispatchers.Main) {
                                _messages.add(responseHeader to false)
                                _liveTranscript.value = "Dites '${_triggerWord.value}'"
                                if (audioBytes != null) {
                                    playAudio(audioBytes)
                                }
                            }
                        } else {
                            withContext(Dispatchers.Main) {
                                _messages.add("Erreur serveur: ${resp.code}" to false)
                                _liveTranscript.value = "Dites '${_triggerWord.value}'"
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                _messages.add("Erreur connexion: ${e.message}" to false)
                _liveTranscript.value = "Dites '${_triggerWord.value}'"
            }
        }
    }

    private fun playAudio(audioBytes: ByteArray) {
        try {
            val minBufferSize = AudioTrack.getMinBufferSize(22050, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            val audioTrack = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANT).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(22050).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setBufferSizeInBytes(Math.max(audioBytes.size, minBufferSize))
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            audioTrack.write(audioBytes, 0, audioBytes.size)
            audioTrack.play()
        } catch (e: Exception) {
            Log.e("TTS", "Erreur lecture audio: ${e.message}")
        }
    }

    override fun onFinalResult(hypothesis: String) {}
    override fun onError(exception: Exception) { 
        Log.e("VOSK", "Erreur RecognitionListener: ${exception.message}")
        _liveTranscript.value = "Erreur: ${exception.message}" 
    }
    override fun onTimeout() {}

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
                    .background(Color(0xFF00D4FF).copy(alpha = 0.2f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Mic, contentDescription = null, tint = Color(0xFF00D4FF), modifier = Modifier.size(30.dp))
            }
            Spacer(modifier = Modifier.height(16.dp))
            Text(_liveTranscript.value, color = Color.White.copy(alpha = 0.7f), fontSize = 16.sp)
        }
    }
}
