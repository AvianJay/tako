# ML Kit structured output discovers the generated schema and deserializes
# these annotated classes at runtime, including in Flutter release builds.
-keep class tw.avianjay.tako.AicoreAgentReply { *; }
-keep class tw.avianjay.tako.AicoreToolCall { *; }
-keep class tw.avianjay.tako.** implements com.google.mlkit.genai.schema.guided.GenerableProvider { *; }
