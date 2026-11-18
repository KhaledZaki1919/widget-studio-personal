package com.khaled.widgetstudio.ai

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Why an AI request failed (AIError in Swift). */
sealed class AIError(message: String) : Exception(message) {
    data object NoKey : AIError("no key")
    data object InvalidKey : AIError("invalid key")
    data object RateLimited : AIError("rate limited")
    data object DailyQuota : AIError("daily quota")
    data object ModelNotFound : AIError("model not found")
    data object Refused : AIError("refused")
    data object Truncated : AIError("truncated")
    data object Network : AIError("network")
    data object Busy : AIError("busy")
    data object Unavailable : AIError("provider unavailable")
    data object TimedOut : AIError("timed out")
    data object Cancelled : AIError("cancelled")
    data class InvalidOutput(val problems: String) : AIError("invalid output: $problems")
    data class BadRequest(val detail: String) : AIError("bad request: $detail")

    /** What the user reads, and what to do next (AIErrorView on iOS). */
    fun message(language: String, model: String): String {
        val ar = language == "ar"
        return when (this) {
            NoKey -> if (ar) "أضف مفتاح Gemini من الإعدادات أولًا." else "Add a Gemini key in Settings first."
            InvalidKey -> if (ar) "مفتاح Gemini غير صالح. تحقق منه في الإعدادات." else "The Gemini key isn't valid. Check it in Settings."
            RateLimited -> if (ar) "طلبات كثيرة في دقيقة واحدة. انتظر قليلًا ثم حاول مجددًا." else "Too many requests in a minute. Wait a moment and try again."
            DailyQuota -> if (ar) "انتهت طلبات اليوم المجانية لـ $model. جرّب غدًا أو اختر نموذجًا آخر من الإعدادات." else "Today's free requests for $model are used up. Try tomorrow or pick another model in Settings."
            ModelNotFound -> if (ar) "النموذج $model غير متاح. اختر نموذجًا آخر من الإعدادات." else "The model $model isn't available. Pick another in Settings."
            Refused -> if (ar) "رفض Gemini هذه الصورة. جرّب صورة أخرى." else "Gemini declined this image. Try another one."
            Truncated -> if (ar) "انقطع الرد قبل اكتماله. حاول مجددًا." else "The reply was cut off. Try again."
            Network -> if (ar) "لا يوجد اتصال بالإنترنت." else "No internet connection."
            Busy -> if (ar) "Google مشغول الآن. حاول بعد قليل." else "Google is busy right now. Try again soon."
            Unavailable -> if (ar) "خدمة Gemini غير متاحة الآن." else "Gemini is unavailable right now."
            TimedOut -> if (ar) "استغرق الرد وقتًا طويلًا. حاول مجددًا أو جرّب نموذجًا أسرع." else "The reply took too long. Try again or pick a faster model."
            Cancelled -> if (ar) "أُلغي." else "Cancelled."
            is InvalidOutput -> if (ar) "لم يكن الرد تصميمًا صالحًا حتى بعد إعادة المحاولة. حاول مجددًا." else "The reply wasn't a valid design, even after a retry. Try again."
            is BadRequest -> (if (ar) "رفض Gemini الطلب: " else "Gemini rejected the request: ") + detail.take(160)
        }
    }
}

/**
 * The Gemini key and model (BYOK, brief D4). The key is encrypted with an AES key that lives in the
 * Android Keystore and never leaves it; only the ciphertext is in preferences. Sent only to Google.
 */
class GeminiSettings(context: Context) {
    private val prefs = context.getSharedPreferences("ai", Context.MODE_PRIVATE)

    var model: String
        get() = prefs.getString("model", null)?.takeIf { it.isNotBlank() } ?: DEFAULT_MODEL
        set(value) = prefs.edit().putString("model", value).apply()

    var consented: Boolean
        get() = prefs.getBoolean("consent", false)
        set(value) = prefs.edit().putBoolean("consent", value).apply()

    /** False when the stored key can't be decrypted (a backup restored on another phone, whose Keystore lacks the AES key). */
    fun hasKey() = key() != null

    fun saveKey(key: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, secretKey()) }
        val data = cipher.iv + cipher.doFinal(key.toByteArray())
        prefs.edit().putString("key", Base64.encodeToString(data, Base64.NO_WRAP)).apply()
    }

    fun key(): String? {
        val stored = prefs.getString("key", null) ?: return null
        return runCatching {
            val data = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, data, 0, 12)) }
            String(cipher.doFinal(data, 12, data.size - 12))
        }.getOrNull()
    }

    fun deleteKey() = prefs.edit().remove("key").apply()

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    companion object {
        private const val ALIAS = "widgetstudio.gemini"
        const val DEFAULT_MODEL = "gemini-3.5-flash-lite"
        val suggestedModels = listOf("gemini-3.5-flash-lite", "gemini-3.5-flash", "gemini-3.8-flash")
    }
}

/** One request: the system prompt, the user text, JPEG images and the reply size limit. */
data class AIRequest(
    val system: String, val userText: String, val images: List<ByteArray>, val maxOutputTokens: Int = 16_000, val timeoutMs: Int = 110_000,
    /** ADR-029: the JSON Schema for Gemini's responseJsonSchema; null = JSON mode with the schema in the prompt. */
    val schema: String? = null,
) {
    /** The fallback: the schema moves into the prompt and the request goes in plain JSON mode. */
    fun withSchemaInstructions(): AIRequest = if (schema == null) this else copy(
        system = system + "\n\nReply with only one JSON object, no prose and no code fences. It must match this JSON Schema:\n" + schema,
        schema = null,
    )
}

/**
 * Gemini generateContent with plain HttpURLConnection (no SDK), in JSON mode with the schema in the
 * prompt (Gemini's responseSchema hung in the iOS eval, ADR-019); low thinking where supported.
 */
class GeminiClient(private val key: String) {
    suspend fun complete(request: AIRequest, model: String): String = withContext(Dispatchers.IO) {
        val parts = JSONArray()
        request.images.forEach { parts.put(JSONObject().put("inlineData", JSONObject().put("mimeType", "image/jpeg").put("data", Base64.encodeToString(it, Base64.NO_WRAP)))) }
        parts.put(JSONObject().put("text", request.userText))
        val id = model.lowercase()
        val legacy = listOf("gemini-1.", "gemini-2.0").any { id.contains(it) }
        val config = JSONObject().put("responseMimeType", "application/json").put("maxOutputTokens", if (legacy) minOf(request.maxOutputTokens, 8192) else request.maxOutputTokens + 24_576)
        // ADR-029: structured output with the full JSON Schema (responseJsonSchema).
        request.schema?.let { schema -> runCatching { config.put("responseJsonSchema", JSONObject(schema)) } }
        when {
            legacy || listOf("flash-lite", "gemma", "image", "tts").any { id.contains(it) } -> Unit
            id.contains("gemini-2.5") -> config.put("thinkingConfig", JSONObject().put("thinkingBudget", 1024))
            else -> config.put("thinkingConfig", JSONObject().put("thinkingLevel", "low"))
        }
        val body = JSONObject()
            .put("systemInstruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", request.system))))
            .put("contents", JSONArray().put(JSONObject().put("role", "user").put("parts", parts)))
            .put("generationConfig", config)
        val connection = (URL("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 20_000
            readTimeout = request.timeoutMs
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("x-goog-api-key", key)
        }
        try {
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
            val status = connection.responseCode
            val text = (if (status in 200..299) connection.inputStream else connection.errorStream)?.bufferedReader()?.readText() ?: ""
            if (status !in 200..299) throw mapError(status, text)
            parse(text)
        } catch (error: SocketTimeoutException) {
            throw AIError.TimedOut
        } catch (error: UnknownHostException) {
            throw AIError.Network
        } catch (error: IOException) {
            throw AIError.Network
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        private val blocked = setOf("SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION", "IMAGE_SAFETY")

        fun parse(text: String): String {
            val json = runCatching { JSONObject(text) }.getOrNull() ?: throw AIError.InvalidOutput("unreadable response")
            if (json.optJSONObject("promptFeedback")?.optString("blockReason")?.isNotEmpty() == true) throw AIError.Refused
            val candidate = json.optJSONArray("candidates")?.optJSONObject(0)
            val finish = candidate?.optString("finishReason") ?: "none"
            if (finish in blocked) throw AIError.Refused
            if (finish == "MAX_TOKENS") throw AIError.Truncated
            val parts = candidate?.optJSONObject("content")?.optJSONArray("parts")
            val reply = (0 until (parts?.length() ?: 0)).mapNotNull { i -> parts?.optJSONObject(i)?.takeIf { !it.optBoolean("thought") }?.optString("text") }.joinToString("")
            if (reply.isEmpty()) throw AIError.InvalidOutput("empty reply (finishReason $finish)")
            return reply
        }

        /** The same mapping as AIHTTP.mapError on iOS. */
        fun mapError(status: Int, body: String): AIError {
            val json = runCatching { JSONObject(body) }.getOrNull()
            val message = json?.optJSONObject("error")?.optString("message") ?: ""
            val lower = message.lowercase()
            val errorStatus = json?.optJSONObject("error")?.optString("status")
            if (errorStatus == "RESOURCE_EXHAUSTED") return if (body.contains("PerDay") || body.lowercase().contains("per day")) AIError.DailyQuota else AIError.RateLimited
            if (errorStatus == "UNAVAILABLE" || status == 503 || status == 529) return AIError.Busy
            return when (status) {
                401, 403 -> AIError.InvalidKey
                404, 410 -> AIError.ModelNotFound
                408 -> AIError.TimedOut
                429 -> AIError.RateLimited
                400 -> when {
                    lower.contains("api key") && (lower.contains("invalid") || lower.contains("not valid") || lower.contains("expired")) -> AIError.InvalidKey
                    lower.contains("model") && listOf("not found", "does not exist", "invalid model", "not a valid model").any { lower.contains(it) } -> AIError.ModelNotFound
                    else -> AIError.BadRequest(message)
                }
                in 500..599 -> AIError.Unavailable
                else -> AIError.BadRequest(message.ifEmpty { "HTTP $status" })
            }
        }
    }
}
