import Flutter
import FoundationModels
import ImageIO
import ImagePlayground
import UIKit

private let textModelId = "apple:foundation-model"
private let imageModelId = "apple:image-playground"

/// Apple Intelligence over the channel protocol of the Android AICore host:
/// Foundation Models writes replies and Image Playground creates images, both
/// on this device. Tako's Dart agent loop executes approved tools.
///
/// Flutter calls in on the main thread, and everything that answers it runs
/// on the main actor. Both frameworks are newer than the deployment target
/// and weakly linked.
final class AppleIntelligenceHost: NSObject, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var generation: Task<Void, Never>?
  private var requestId: Int64?
  // Stored properties cannot require iOS 26 or 18.4, so the engines are kept
  // untyped and created on first use.
  private var textEngine: AnyObject?
  private var imageEngine: AnyObject?

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(
      name: "tw.avianjay.tako/apple_intelligence", binaryMessenger: messenger)
    events = FlutterEventChannel(
      name: "tw.avianjay.tako/apple_intelligence/events", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    events.setStreamHandler(self)
  }

  @available(iOS 26.0, *)
  @MainActor
  private var text: FoundationModelsEngine {
    if let engine = textEngine as? FoundationModelsEngine { return engine }
    let engine = FoundationModelsEngine()
    textEngine = engine
    return engine
  }

  @available(iOS 18.4, *)
  @MainActor
  private var images: ImagePlaygroundEngine {
    if let engine = imageEngine as? ImagePlaygroundEngine { return engine }
    let engine = ImagePlaygroundEngine()
    imageEngine = engine
    return engine
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "status":
      // Checks availability only; nothing is downloaded or loaded.
      result([textDetails(), imageDetails()])
    case "prepare":
      let id = args?["modelId"] as? String
      Task { @MainActor in
        do {
          let details = try await self.prepare(id)
          result(details)
        } catch {
          result(
            FlutterError(
              code: self.errorCode(error), message: "Could not prepare Apple Intelligence",
              details: nil))
        }
      }
    case "cancel":
      if (args?["requestId"] as? NSNumber)?.int64Value == requestId { generation?.cancel() }
      result(nil)
    case "unload":
      generation?.cancel()
      textEngine = nil
      imageEngine = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(
    withArguments arguments: Any?, eventSink sink: @escaping FlutterEventSink
  ) -> FlutterError? {
    let args = arguments as? [String: Any] ?? [:]
    let maxTokens = (args["maxOutputTokens"] as? NSNumber)?.intValue ?? 1024
    guard let request = (args["requestId"] as? NSNumber)?.int64Value,
      let modelId = args["modelId"] as? String,
      let prompt = args["prompt"] as? String,
      maxTokens > 0
    else {
      sink(
        FlutterError(
          code: "apple_invalid_request", message: "Invalid Apple Intelligence request",
          details: nil))
      sink(FlutterEndOfEventStream)
      return nil
    }
    let previous = generation
    previous?.cancel()
    requestId = request
    generation = Task { @MainActor in
      _ = await previous?.value
      do {
        try Task.checkCancellation()
        try await self.generate(
          modelId: modelId, prompt: prompt, maxTokens: maxTokens, args: args, send: sink)
        sink(["type": "done", "reason": "stop"])
      } catch {
        // Stop is a user action, with neither completion nor error. Framework
        // errors may contain the prompt, so only a code reaches Dart.
        if !Task.isCancelled {
          sink(
            FlutterError(
              code: self.errorCode(error), message: "Apple Intelligence request failed",
              details: nil))
        }
      }
      sink(FlutterEndOfEventStream)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    let id = ((arguments as? [String: Any])?["requestId"] as? NSNumber)?.int64Value
    if id == requestId { generation?.cancel() }
    return nil
  }

  @MainActor
  private func prepare(_ id: String?) async throws -> [String: Any] {
    switch id {
    case textModelId:
      guard #available(iOS 26.0, *) else { throw AppleFailure("apple_update") }
      try text.prepare()
      return textDetails()
    case imageModelId:
      guard #available(iOS 18.4, *) else { throw AppleFailure("apple_update") }
      _ = try await images.creator()
      return details(imageModelId, state: "ready")
    default:
      throw AppleFailure("apple_unavailable")
    }
  }

  @MainActor
  private func generate(
    modelId: String, prompt: String, maxTokens: Int, args: [String: Any],
    send: FlutterEventSink
  ) async throws {
    switch modelId {
    case textModelId:
      guard #available(iOS 26.0, *) else { throw AppleFailure("apple_update") }
      let engine = text
      try engine.prepare()
      send(textDetails().merging(["type": "ready"]) { $1 })
      let instructions = args["instructions"] as? String ?? ""
      if args["useTools"] as? Bool == true {
        let reply = try await engine.agent(
          instructions: instructions, prompt: prompt, tools: args["tools"] as? [String] ?? [],
          maxTokens: maxTokens)
        send(reply)
      } else {
        try await engine.reply(
          instructions: instructions, prompt: prompt, maxTokens: maxTokens, send: send)
      }
    case imageModelId:
      guard #available(iOS 18.4, *) else { throw AppleFailure("apple_update") }
      let engine = images
      _ = try await engine.creator()
      send(details(imageModelId, state: "ready").merging(["type": "ready"]) { $1 })
      let references = (args["images"] as? [FlutterStandardTypedData] ?? []).map(\.data)
      try await engine.create(prompt: prompt, references: references, send: send)
    default:
      throw AppleFailure("apple_unavailable")
    }
  }

  private func details(
    _ id: String, state: String, reason: String? = nil, tools: Bool = false
  ) -> [String: Any] {
    var details: [String: Any] = [
      "modelId": id, "state": state, "tools": tools, "contextWindow": 4096,
    ]
    if let reason { details["reason"] = reason }
    return details
  }

  /// The model is ready once Apple Intelligence is on and downloaded; Tako
  /// cannot download it.
  private func textDetails() -> [String: Any] {
    guard #available(iOS 26.0, *) else {
      return details(textModelId, state: "unavailable", reason: "apple_update")
    }
    guard let reason = textModelReason() else {
      return details(textModelId, state: "ready", tools: true)
    }
    return details(
      textModelId, state: reason == "apple_unavailable" ? "unavailable" : "available",
      reason: reason)
  }

  private func imageDetails() -> [String: Any] {
    guard #available(iOS 18.4, *) else {
      return details(imageModelId, state: "unavailable", reason: "apple_update")
    }
    if ImagePlaygroundViewController.isAvailable {
      return details(imageModelId, state: "ready")
    }
    let reason = imageModelReason()
    return details(
      imageModelId, state: reason == "apple_unavailable" ? "unavailable" : "available",
      reason: reason)
  }

  /// Image Playground reports no reason; before iOS 26 the likely one is
  /// that Apple Intelligence is off.
  private func imageModelReason() -> String {
    guard #available(iOS 26.0, *) else { return "apple_disabled" }
    return textModelReason() ?? "apple_not_ready"
  }

  private func errorCode(_ error: Error) -> String {
    if let failure = error as? AppleFailure { return failure.code }
    if #available(iOS 26.0, *), let error = error as? LanguageModelSession.GenerationError {
      switch error {
      case .exceededContextWindowSize: return "apple_request_too_large"
      case .guardrailViolation, .refusal: return "apple_guardrail"
      case .unsupportedLanguageOrLocale: return "apple_language"
      case .rateLimited, .concurrentRequests: return "apple_busy"
      case .assetsUnavailable: return "apple_not_ready"
      case .decodingFailure, .unsupportedGuide: return "apple_invalid_tools"
      default: return "apple_failed"
      }
    }
    if #available(iOS 18.4, *), let error = error as? ImageCreator.Error {
      switch error {
      case .notSupported: return "apple_unavailable"
      case .unavailable: return imageModelReason()
      case .unsupportedLanguage: return "apple_language"
      case .backgroundCreationForbidden: return "apple_background"
      case .faceInImageTooSmall, .unsupportedInputImage: return "apple_image_input"
      default: return "apple_failed"
      }
    }
    return "apple_failed"
  }
}

private struct AppleFailure: Error {
  let code: String
  init(_ code: String) { self.code = code }
}

/// Why the system language model cannot answer, or nil when it can.
@available(iOS 26.0, *)
private func textModelReason() -> String? {
  switch SystemLanguageModel.default.availability {
  case .available: return nil
  case .unavailable(.deviceNotEligible): return "apple_unavailable"
  case .unavailable(.appleIntelligenceNotEnabled): return "apple_disabled"
  case .unavailable(.modelNotReady): return "apple_not_ready"
  case .unavailable: return "apple_failed"
  }
}

/// Every request gets a new session: Dart sends the whole conversation.
@available(iOS 26.0, *)
@MainActor
private final class FoundationModelsEngine {
  private var warm: LanguageModelSession?

  /// Loads the model ahead of the first reply.
  func prepare() throws {
    if let reason = textModelReason() { throw AppleFailure(reason) }
    if warm == nil {
      let session = LanguageModelSession()
      session.prewarm()
      warm = session
    }
  }

  /// Streams the reply as deltas; the framework sends the text so far.
  func reply(
    instructions: String, prompt: String, maxTokens: Int, send: FlutterEventSink
  ) async throws {
    let session = LanguageModelSession(instructions: instructions)
    let options = GenerationOptions(temperature: 0.7, maximumResponseTokens: maxTokens)
    var sent = ""
    for try await snapshot in session.streamResponse(options: options, prompt: { prompt }) {
      let content = snapshot.content
      guard content.count > sent.count, content.hasPrefix(sent) else { continue }
      send(["type": "text", "text": String(content.dropFirst(sent.count))])
      sent = content
    }
  }

  /// The app-level tool protocol of AICore. The schema limits names to the
  /// offered tools; Dart still validates the whole reply before any call.
  func agent(
    instructions: String, prompt: String, tools: [String], maxTokens: Int
  ) async throws -> [String: Any] {
    guard !tools.isEmpty else { throw AppleFailure("apple_invalid_tools") }
    let call = DynamicGenerationSchema(
      name: "ToolCall",
      description: "A request to call one tool from the supplied tools list",
      properties: [
        DynamicGenerationSchema.Property(
          name: "name", description: "Exact name of a tool from the supplied tools list",
          schema: DynamicGenerationSchema(name: "ToolName", anyOf: tools)),
        DynamicGenerationSchema.Property(
          name: "arguments",
          description: "A JSON object encoded as a string, matching that tool's parameters schema",
          schema: DynamicGenerationSchema(type: String.self)),
      ])
    let reply = DynamicGenerationSchema(
      name: "AgentReply",
      description: "The next assistant reply or requests to use the supplied tools",
      properties: [
        DynamicGenerationSchema.Property(
          name: "kind", description: "answer for a final reply, tool_calls to request tools",
          schema: DynamicGenerationSchema(name: "ReplyKind", anyOf: ["answer", "tool_calls"])),
        DynamicGenerationSchema.Property(
          name: "text",
          description: "The assistant reply, or a short introduction to the tool calls",
          schema: DynamicGenerationSchema(type: String.self)),
        DynamicGenerationSchema.Property(
          name: "calls", description: "Requested tools; empty for a final answer",
          schema: DynamicGenerationSchema(arrayOf: call, minimumElements: 0, maximumElements: 8)),
      ])
    let schema = try GenerationSchema(root: reply, dependencies: [])
    let session = LanguageModelSession(instructions: instructions)
    let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: maxTokens)
    // Truncated output fails to decode, so it never becomes a tool call.
    let content = try await session.respond(schema: schema, options: options, prompt: { prompt })
      .content
    let kind = try content.value(String.self, forProperty: "kind")
    let text = try content.value(String.self, forProperty: "text")
    let calls = try content.value([GeneratedContent].self, forProperty: "calls").map {
      call -> [String: String] in
      let name = try call.value(String.self, forProperty: "name")
      let arguments = try call.value(String.self, forProperty: "arguments")
      return ["name": name, "arguments": arguments]
    }
    return ["type": "agent", "kind": kind, "text": text, "calls": calls]
  }
}

@available(iOS 18.4, *)
@MainActor
private final class ImagePlaygroundEngine {
  private var cached: ImageCreator?

  func creator() async throws -> ImageCreator {
    if let cached { return cached }
    let creator = try await ImageCreator()
    cached = creator
    return creator
  }

  /// One image per request, in the first style that runs on this device.
  func create(prompt: String, references: [Data], send: FlutterEventSink) async throws {
    let creator = try await self.creator()
    // A short prompt is a concept itself; concepts are extracted from longer
    // descriptions, as a chat model tends to write.
    var concepts: [ImagePlaygroundConcept] = [
      prompt.count > 60 ? .extracted(from: prompt, title: nil) : .text(prompt)
    ]
    for data in references {
      let reference = try Self.image(data)
      concepts.append(.image(reference))
    }
    let styles: [ImagePlaygroundStyle] = [.animation, .illustration, .sketch]
    guard let style = styles.first(where: { creator.availableStyles.contains($0) }) else {
      throw AppleFailure("apple_not_ready")
    }
    for try await created in creator.images(for: concepts, style: style, limit: 1) {
      guard let png = UIImage(cgImage: created.cgImage).pngData() else {
        throw AppleFailure("apple_failed")
      }
      send(["type": "image", "data": FlutterStandardTypedData(bytes: png)])
    }
  }

  /// The upright image, at most 2048 pixels on its long side.
  private static func image(_ data: Data) throws -> CGImage {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 2048,
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw AppleFailure("apple_image_input") }
    return image
  }
}
