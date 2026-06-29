package com.example.mamai

import android.Manifest
import android.content.ContentResolver
import android.content.ContentValues
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.CalendarContract
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
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Refresh
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
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.TimeUnit

class MainActivity : ComponentActivity(), RecognitionListener, TextToSpeech.OnInitListener {

    private var speechService: SpeechService? = null
    private var model: Model? = null
    private lateinit var tts: TextToSpeech

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    // Clé API Groq injectée au build via BuildConfig.GROQ_API_KEY
    // (définie par -PgGroqApiKey=... dans la commande Gradle).
    private val groqApiKey = BuildConfig.GROQ_API_KEY
    private val groqApiUrl = "https://api.groq.com/openai/v1/chat/completions"

    private val _liveTranscript = mutableStateOf("Initialisation...")
    private val _messages = mutableStateListOf<Pair<String, Boolean>>() // Text to isUser

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        tts = TextToSpeech(this, this)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                MainScreen()
            }
        }

        if (checkPermissions()) {
            initVosk()
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = tts.setLanguage(Locale.FRENCH)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.e("TTS", "Langue non supportée ou données manquantes")
            }
        } else {
            Log.e("TTS", "Échec de l'initialisation du TTS")
        }
    }

    private fun speak(text: String) {
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, null)
    }

    private fun checkPermissions(): Boolean {
        val hasMicrophone = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        val hasReadCalendar = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
        val hasWriteCalendar = ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

        val permissionsToRequest = mutableListOf<String>()
        if (!hasMicrophone) permissionsToRequest.add(Manifest.permission.RECORD_AUDIO)
        if (!hasReadCalendar) permissionsToRequest.add(Manifest.permission.READ_CALENDAR)
        if (!hasWriteCalendar) permissionsToRequest.add(Manifest.permission.WRITE_CALENDAR)

        if (permissionsToRequest.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, permissionsToRequest.toTypedArray(), 1)
        }
        return hasMicrophone && hasReadCalendar && hasWriteCalendar
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1 && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            initVosk()
        } else {
            _liveTranscript.value = "Permissions requises refusées."
        }
    }

    private fun initVosk() {
        _liveTranscript.value = "Chargement du modèle..."
        StorageService.unpack(this, "model-fr", "model",
            { model: Model ->
                this.model = model
                _liveTranscript.value = "Dites 'mamAI'"
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
            if (text.lowercase().contains("mamai")) {
                _liveTranscript.value = "J'écoute..."
            }
        }
    }

    override fun onResult(hypothesis: String) {
        val text = extractText(hypothesis, "text")
        if (text.isNotEmpty()) {
            _messages.add(text to true)
            processCommand(text)
        }
    }

    private fun extractText(hypothesis: String, key: String): String {
        return try {
            val json = JSONObject(hypothesis)
            json.optString(key, "")
        } catch (e: Exception) { "" }
    }

    private fun processCommand(command: String) {
        lifecycleScope.launch {
            _liveTranscript.value = "Réflexion..."
            val response = withContext(Dispatchers.IO) {
                // Logique de gestion de l'agenda
                if (command.contains("agenda") || command.contains("rendez-vous")) {
                    if (command.contains("ajouter")) {
                        addCalendarEvent(command)
                    } else if (command.contains("lire") || command.contains("quels sont")) {
                        readCalendarEvents()
                    } else {
                        "Je peux ajouter ou lire des événements dans votre agenda. Que souhaitez-vous faire ?"
                    }
                } else {
                    sendToGroq(command)
                }
            }
            _messages.add(response to false)
            speak(response)
            _liveTranscript.value = "Dites 'mamAI'"
        }
    }

    private fun sendToGroq(text: String): String {
        if (groqApiKey.isBlank() || groqApiKey == "VOTRE_CLE_API_GROQ") {
            return "Clé API Groq manquante — définissez le secret VOTRE_CLE_API_GROQ sur GitHub puis relancez le build."
        }
        try {
            val json = JSONObject().apply {
                put("model", "llama3-8b-8192") // Ou un autre modèle Groq
                put("messages", org.json.JSONArray().apply {
                    put(JSONObject().apply { put("role", "user"); put("content", text) })
                })
                put("temperature", 0.7)
            }
            val body = json.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url(groqApiUrl)
                .header("Authorization", "Bearer $groqApiKey")
                .post(body)
                .build()

            client.newCall(request).execute().use { resp ->
                if (resp.isSuccessful) {
                    val responseBody = resp.body?.string()
                    val jsonResponse = JSONObject(responseBody)
                    val content = jsonResponse.getJSONArray("choices")
                        .getJSONObject(0)
                        .getJSONObject("message")
                        .getString("content")
                    return content
                } else {
                    return "Erreur Groq API: ${resp.code} - ${resp.message}"
                }
            }
        } catch (e: Exception) {
            Log.e("Groq", "Erreur connexion Groq: ${e.message}")
            return "Erreur connexion Groq: ${e.message}"
        }
    }

    private fun addCalendarEvent(command: String): String {
        // Simplifié: ici, on pourrait utiliser une LLM pour extraire les détails de l'événement
        // Pour l'exemple, on va juste ajouter un événement générique.
        val title = "Événement ajouté par mamAI"
        val description = command
        val beginTime = Calendar.getInstance().apply { add(Calendar.HOUR_OF_DAY, 1) }.timeInMillis
        val endTime = Calendar.getInstance().apply { add(Calendar.HOUR_OF_DAY, 2) }.timeInMillis

        val values = ContentValues().apply {
            put(CalendarContract.Events.DTSTART, beginTime)
            put(CalendarContract.Events.DTEND, endTime)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.CALENDAR_ID, 1) // Généralement 1 pour le calendrier par défaut
            put(CalendarContract.Events.EVENT_TIMEZONE, Calendar.getInstance().timeZone.id)
        }

        try {
            val uri: Uri? = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            return if (uri != null) {
                "J'ai ajouté un événement à votre agenda: $title."
            } else {
                "Désolé, je n'ai pas pu ajouter l'événement à votre agenda."
            }
        } catch (e: SecurityException) {
            Log.e("Calendar", "Permission calendrier refusée: ${e.message}")
            return "Je n'ai pas la permission d'écrire dans votre agenda. Veuillez l'activer dans les paramètres."
        } catch (e: Exception) {
            Log.e("Calendar", "Erreur ajout événement: ${e.message}")
            return "Une erreur est survenue lors de l'ajout de l'événement: ${e.message}"
        }
    }

    private fun readCalendarEvents(): String {
        val projection = arrayOf(
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND
        )
        val uri = CalendarContract.Events.CONTENT_URI
        val selection = "${CalendarContract.Events.DTSTART} >= ?"
        val calendar = Calendar.getInstance()
        val currentTime = calendar.timeInMillis
        val selectionArgs = arrayOf(currentTime.toString())

        val cursor = contentResolver.query(uri, projection, selection, selectionArgs, CalendarContract.Events.DTSTART + " ASC")

        val events = mutableListOf<String>()
        cursor?.use {
            while (it.moveToNext()) {
                val title = it.getString(it.getColumnIndexOrThrow(CalendarContract.Events.TITLE))
                val startTime = it.getLong(it.getColumnIndexOrThrow(CalendarContract.Events.DTSTART))
                val endTime = it.getLong(it.getColumnIndexOrThrow(CalendarContract.Events.DTEND))

                val startCal = Calendar.getInstance().apply { timeInMillis = startTime }
                val endCal = Calendar.getInstance().apply { timeInMillis = endTime }

                val startFormat = java.text.SimpleDateFormat("dd/MM à HH:mm", Locale.FRENCH).format(startCal.time)
                val endFormat = java.text.SimpleDateFormat("HH:mm", Locale.FRENCH).format(endCal.time)

                events.add("$title le $startFormat jusqu'à $endFormat")
            }
        }

        return if (events.isNotEmpty()) {
            "Voici vos prochains événements: " + events.joinToString("; ")
        } else {
            "Aucun événement trouvé dans votre agenda."
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
    fun MainScreen() {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("mamAI", fontWeight = FontWeight.Bold) },
                    actions = {
                        IconButton(onClick = { _messages.clear() }) {
                            Icon(Icons.Default.Refresh, contentDescription = null)
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
