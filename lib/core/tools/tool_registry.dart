import '../providers/provider_adapter.dart';
import 'tool.dart';

class ToolRegistry {
  ToolRegistry(Iterable<Tool> tools, {Set<String> disabledTools = const {}})
    : _tools = {for (final tool in tools) tool.name: tool},
      disabledTools = Set.of(disabledTools);

  final Map<String, Tool> _tools;
  Set<String> disabledTools;

  List<Tool> get availableTools => [
    for (final tool in _tools.values)
      if (tool.requires.isAvailable && !disabledTools.contains(tool.name)) tool,
  ];

  /// Includes unavailable/disabled tools for the settings UI only.
  List<Tool> get allTools => List.unmodifiable(_tools.values);

  Tool? get(String name) {
    final tool = _tools[name];
    return tool != null &&
            tool.requires.isAvailable &&
            !disabledTools.contains(name)
        ? tool
        : null;
  }

  List<ToolDefinition> get definitions => [
    for (final tool in availableTools)
      ToolDefinition(
        name: tool.name,
        description: tool.description,
        schema: tool.schema,
      ),
  ];
}
