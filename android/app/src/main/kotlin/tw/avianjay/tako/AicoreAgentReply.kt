package tw.avianjay.tako

import com.google.mlkit.genai.schema.annotations.Generable
import com.google.mlkit.genai.schema.annotations.Guide

/** An app-level protocol over ML Kit structured output, not a native Tool API. */
@Generable("The next assistant reply or requests to use the supplied tools")
data class AicoreAgentReply(
    @Guide(description = "answer for a final reply, tool_calls to request tools",
        enumValues = ["answer", "tool_calls"])
    val kind: String,
    @Guide(description = "The assistant reply, or a short introduction to the tool calls")
    val text: String,
    @Guide(description = "Requested tools; empty for a final answer", minItems = 0, maxItems = 8)
    val calls: List<AicoreToolCall>,
)

@Generable("A request to call one tool from the supplied tools list")
data class AicoreToolCall(
    @Guide(description = "Exact name of a tool from the supplied tools list")
    val name: String,
    @Guide(description = "A JSON object encoded as a string, matching that tool's parameters schema")
    val arguments: String,
)
