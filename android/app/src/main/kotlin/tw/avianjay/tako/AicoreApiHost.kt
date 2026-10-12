package tw.avianjay.tako

import android.os.Build
import androidx.annotation.RequiresApi
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.Candidate
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ModelPreference
import com.google.mlkit.genai.prompt.ModelReleaseStage
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.TypedCandidate
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.generateTypedContentRequest
import com.google.mlkit.genai.prompt.generationConfig
import com.google.mlkit.genai.prompt.modelConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

private const val STABLE_ID = "aicore:gemini-nano"
private const val PREVIEW_ID = "aicore:gemini-nano-preview"

/** ML Kit owns inference; Tako's Dart agent loop executes approved tools. */
class AicoreApiHost(messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "tw.avianjay.tako/aicore")
    private val events = EventChannel(messenger, "tw.avianjay.tako/aicore/events")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutex = Mutex()
    private val sessions = mutableMapOf<String, AicoreSession>()
    private var generation: Job? = null
    private var requestId: Long? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    @RequiresApi(26)
    private fun session(id: String): AicoreSession = sessions.getOrPut(id) {
        AicoreSession(preview = id == PREVIEW_ID)
    }

    private fun unavailable(id: String): Map<String, Any> = mapOf(
        "modelId" to id, "state" to "unavailable", "tools" to false,
        "contextWindow" to 4096,
    )

    @RequiresApi(26)
    private suspend fun details(id: String): Map<String, Any> {
        val client = session(id).model
        val status = client.checkStatus()
        if (status == FeatureStatus.UNAVAILABLE) return unavailable(id)
        val available = status == FeatureStatus.AVAILABLE
        return mapOf(
            "modelId" to id,
            "state" to if (available) "ready" else "available",
            "tools" to (available && client.isStructuredOutputFeatureAvailable()),
            "contextWindow" to if (available) client.getTokenLimit().coerceAtLeast(1) else 4096,
            "baseModelName" to if (available) client.getBaseModelName() else "Gemini Nano",
        )
    }

    @RequiresApi(26)
    private suspend fun ready(id: String): AicoreSession {
        // Only one model is kept warm; stable/preview share the system service.
        for ((otherId, other) in sessions) {
            if (otherId != id) other.close()
        }
        sessions.keys.removeAll { it != id }
        val current = session(id)
        when (current.model.checkStatus()) {
            FeatureStatus.UNAVAILABLE -> throw AicoreFailure("aicore_unavailable")
            FeatureStatus.DOWNLOADABLE -> current.model.download().collect { status ->
                if (status is DownloadStatus.DownloadFailed) throw status.e
            }
        }
        while (current.model.checkStatus() == FeatureStatus.DOWNLOADING) delay(1000)
        if (current.model.checkStatus() != FeatureStatus.AVAILABLE) {
            throw AicoreFailure("aicore_unavailable")
        }
        if (!current.warm) {
            current.model.warmup()
            current.warm = true
        }
        return current
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> scope.launch {
                try {
                    val statuses = mutex.withLock {
                        listOf(STABLE_ID, PREVIEW_ID).map { id ->
                            if (Build.VERSION.SDK_INT < 26) unavailable(id)
                            else try {
                                details(id)
                            } catch (error: Exception) {
                                if (error is CancellationException) throw error
                                unavailable(id)
                            }
                        }
                    }
                    result.success(statuses)
                } catch (_: CancellationException) {
                    result.error("aicore_cancelled", "AICore status cancelled", null)
                }
            }
            "cancel" -> {
                if (call.argument<Number>("requestId")?.toLong() == requestId) generation?.cancel()
                result.success(null)
            }
            "prepare" -> {
                val id = call.argument<String>("modelId") ?: STABLE_ID
                if (Build.VERSION.SDK_INT < 26 || id !in listOf(STABLE_ID, PREVIEW_ID)) {
                    result.error("aicore_unavailable", "AICore is unavailable", null)
                    return
                }
                scope.launch {
                    try {
                        val metadata = mutex.withLock {
                            ready(id)
                            details(id)
                        }
                        result.success(metadata)
                    } catch (_: CancellationException) {
                        result.error("aicore_cancelled", "AICore preparation cancelled", null)
                    } catch (error: Exception) {
                        result.error(errorCode(error), "Could not prepare AICore", null)
                    }
                }
            }
            "unload" -> scope.launch {
                generation?.cancelAndJoin()
                mutex.withLock { closeSessions() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        val args = arguments as? Map<*, *>
        val prompt = args?.get("prompt") as? String
        val id = args?.get("modelId") as? String ?: STABLE_ID
        val request = (args?.get("requestId") as? Number)?.toLong()
        val maxTokens = (args?.get("maxOutputTokens") as? Number)?.toInt() ?: 1024
        if (prompt == null || request == null || maxTokens < 1 || id !in listOf(STABLE_ID, PREVIEW_ID)) {
            sink.error("aicore_invalid_request", "Invalid AICore request", null)
            sink.endOfStream()
            return
        }
        if (Build.VERSION.SDK_INT < 26) {
            sink.error("aicore_unavailable", "AICore is unavailable", null)
            sink.endOfStream()
            return
        }
        val useTools = args?.get("useTools") == true
        val previous = generation
        requestId = request
        generation = scope.launch {
            previous?.cancelAndJoin()
            try {
                mutex.withLock {
                    val model = ready(id).model
                    sink.success(details(id) + mapOf("type" to "ready"))
                    val outgoing = generateContentRequest(TextPart(prompt)) {
                        temperature = if (useTools) 0.2f else 0.7f
                        topK = 40
                        candidateCount = 1
                        maxOutputTokens = maxTokens
                    }
                    val tokenLimit = model.getTokenLimit()
                    if (useTools) {
                        if (!model.isStructuredOutputFeatureAvailable()) {
                            throw AicoreFailure("aicore_tools_unavailable")
                        }
                        val typed = generateTypedContentRequest(outgoing, AicoreAgentReply::class)
                        val count = model.countTokens(typed).totalTokens
                        if (count > tokenLimit) throw AicoreFailure("aicore_request_too_large")
                        // Partial/truncated JSON never reaches the executor.
                        val candidate = model.generateContent(typed).candidates.firstOrNull()
                        if (candidate?.finishReason != TypedCandidate.TypedFinishReason.STOP ||
                            candidate.response == null) throw AicoreFailure("aicore_invalid_tools")
                        val reply = candidate.response!!
                        sink.success(mapOf("type" to "agent", "kind" to reply.kind,
                            "text" to reply.text, "calls" to reply.calls.map {
                                mapOf("name" to it.name, "arguments" to it.arguments)
                            }))
                        sink.success(mapOf("type" to "usage", "inputTokens" to count))
                        sink.success(mapOf("type" to "done", "reason" to "stop"))
                    } else {
                        val count = model.countTokens(outgoing).totalTokens
                        if (count > tokenLimit) throw AicoreFailure("aicore_request_too_large")
                        var reason = "stop"
                        model.generateContentStream(outgoing).collect { chunk ->
                            chunk.candidates.firstOrNull()?.let { candidate ->
                                if (candidate.text.isNotEmpty()) {
                                    sink.success(mapOf("type" to "text", "text" to candidate.text))
                                }
                                if (candidate.finishReason == Candidate.FinishReason.MAX_TOKENS) reason = "length"
                            }
                        }
                        sink.success(mapOf("type" to "usage", "inputTokens" to count))
                        sink.success(mapOf("type" to "done", "reason" to reason))
                    }
                }
            } catch (_: CancellationException) {
                // Stop is a user action, with neither completion nor error.
            } catch (error: Exception) {
                // SDK exception messages may contain input; never expose them.
                sink.error(errorCode(error), "AICore request failed", null)
            } finally {
                sink.endOfStream()
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        val id = ((arguments as? Map<*, *>)?.get("requestId") as? Number)?.toLong()
        if (id == requestId) generation?.cancel()
    }

    private fun errorCode(error: Exception): String {
        if (error is AicoreFailure) return error.code
        if (Build.VERSION.SDK_INT < 26) return "aicore_unavailable"
        return aicoreErrorCode(error)
    }

    private fun closeSessions() {
        if (Build.VERSION.SDK_INT >= 26) sessions.values.forEach { it.close() }
        sessions.clear()
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        scope.cancel()
        closeSessions()
    }
}

private class AicoreFailure(val code: String) : Exception()

@RequiresApi(26)
private class AicoreSession(preview: Boolean) : AutoCloseable {
    private val worker = Executors.newCachedThreadPool()
    var warm = false
    val model: GenerativeModel = Generation.getClient(generationConfig {
        workerExecutor = worker
        modelConfig = modelConfig {
            releaseStage = if (preview) ModelReleaseStage.PREVIEW else ModelReleaseStage.STABLE
            preference = ModelPreference.FULL
        }
    })

    override fun close() {
        try {
            model.close()
        } finally {
            worker.shutdownNow()
        }
    }
}

@RequiresApi(26)
private fun aicoreErrorCode(error: Exception): String = when ((error as? GenAiException)?.errorCode) {
    GenAiException.ErrorCode.NOT_AVAILABLE,
    GenAiException.ErrorCode.NOT_SUPPORTED,
    GenAiException.ErrorCode.AICORE_INCOMPATIBLE -> "aicore_unavailable"
    GenAiException.ErrorCode.NEEDS_SYSTEM_UPDATE -> "aicore_update"
    GenAiException.ErrorCode.NOT_ENOUGH_DISK_SPACE -> "no_space"
    GenAiException.ErrorCode.REQUEST_TOO_LARGE -> "aicore_request_too_large"
    GenAiException.ErrorCode.BUSY,
    GenAiException.ErrorCode.PER_APP_BATTERY_USE_QUOTA_EXCEEDED -> "aicore_busy"
    GenAiException.ErrorCode.BACKGROUND_USE_BLOCKED -> "aicore_background"
    GenAiException.ErrorCode.STRUCTURED_OUTPUT_REQUEST_ERROR,
    GenAiException.ErrorCode.STRUCTURED_OUTPUT_RESPONSE_ERROR,
    GenAiException.ErrorCode.STRUCTURED_OUTPUT_MAX_TOKENS_ERROR -> "aicore_invalid_tools"
    else -> "aicore_failed"
}
