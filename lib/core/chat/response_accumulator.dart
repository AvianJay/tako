import '../providers/provider_event.dart';
import 'content_block.dart';
import 'message.dart';

/// Keeps streamed blocks ordered and preserves the opaque reasoning metadata.
class ResponseAccumulator {
  ResponseAccumulator({required this.sourceApi, required this.promptHash});
  final String sourceApi;
  final String promptHash;
  final List<ContentBlock> _blocks = [];
  final Map<int, int> _reasoning = {};
  final Map<String, int> _calls = {};
  TokenUsage? usage;

  List<ContentBlock> get content => List.unmodifiable(_blocks);

  /// Image payloads are imported by the controller before entering history.
  void addImage(ImageBlock image) => _blocks.add(image);

  int _reasoningIndex(int index) => _reasoning.putIfAbsent(index, () {
    _blocks.add(
      ReasoningBlock(text: '', sourceApi: sourceApi, promptHash: promptHash),
    );
    return _blocks.length - 1;
  });

  void add(ProviderEvent event) {
    switch (event) {
      case ProviderStateMetadata():
        _blocks.removeWhere((block) => block is ProviderStateBlock);
        _blocks.add(
          ProviderStateBlock(
            sourceApi: event.sourceApi,
            promptHash: promptHash,
            content: event.content,
          ),
        );
      case TextDelta(:final text):
        if (text.isEmpty) return;
        if (_blocks.isNotEmpty && _blocks.last is TextBlock) {
          _blocks[_blocks.length - 1] = TextBlock(
            '${(_blocks.last as TextBlock).text}$text',
          );
        } else {
          _blocks.add(TextBlock(text));
        }
      case ReasoningDelta(:final text, :final blockIndex):
        final index = _reasoningIndex(blockIndex);
        final old = _blocks[index] as ReasoningBlock;
        _blocks[index] = ReasoningBlock(
          text: old.text + text,
          signature: old.signature,
          redactedData: old.redactedData,
          encryptedContent: old.encryptedContent,
          itemId: old.itemId,
          sourceApi: sourceApi,
          promptHash: promptHash,
        );
      case ReasoningMetadata(:final blockIndex):
        final index = _reasoningIndex(blockIndex);
        final old = _blocks[index] as ReasoningBlock;
        _blocks[index] = ReasoningBlock(
          text: old.text,
          signature: event.signature ?? old.signature,
          redactedData: event.redactedData ?? old.redactedData,
          encryptedContent: event.encryptedContent ?? old.encryptedContent,
          itemId: event.itemId ?? old.itemId,
          sourceApi: event.sourceApi,
          promptHash: promptHash,
        );
      case ToolCallStart(:final id, :final name):
        final index = _calls[id];
        if (index == null) {
          _calls[id] = _blocks.length;
          _blocks.add(ToolCallBlock(id: id, name: name, arguments: ''));
        } else {
          final old = _blocks[index] as ToolCallBlock;
          _blocks[index] = ToolCallBlock(
            id: id,
            name: name,
            arguments: old.arguments,
          );
        }
      case ToolCallArgsDelta(:final id, :final jsonFragment):
        final index = _calls[id];
        if (index != null) {
          final old = _blocks[index] as ToolCallBlock;
          _blocks[index] = ToolCallBlock(
            id: id,
            name: old.name,
            arguments: old.arguments + jsonFragment,
          );
        }
      case Usage():
        usage = TokenUsage(
          inputTokens: event.inputTokens ?? usage?.inputTokens,
          outputTokens: event.outputTokens ?? usage?.outputTokens,
          totalTokens: event.totalTokens ?? usage?.totalTokens,
        );
      case Done() ||
          ProviderError() ||
          ToolCallEnd() ||
          HostedSearchEvent() ||
          GeneratedImage():
        break;
    }
  }
}
