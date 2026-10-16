part of 'app_controller.dart';

extension AutomationAgent on AppController {
  bool get wasAutomationStopped => _cancel?.isCancelled ?? false;
  Future<ChatMessage?> runAutomation(
    AutomationRun run, {
    required Future<void> Function(String) onConversation,
  }) async {
    final provider = providers
        .where((p) => p.id == run.rule.providerId)
        .firstOrNull
        ?.forModel(run.rule.model);
    if (provider == null || provider.capabilities.imagesOnly) {
      throw const FormatException('Text provider required');
    }
    selectedProviderId = provider.id;
    selectedModelId = provider.model;
    _cancel = CancelToken();
    _generating = true;
    final priorId =
        run.conversationId ??
        (run.rule.continueConversation ? run.rule.conversationId : null);
    if (priorId != null) conversation = await chats.getConversation(priorId);
    final now = DateTime.now();
    if (conversation == null) {
      final device = await services.deviceContext();
      final profile = memorySettings.enabled
          ? await memory.profileSnapshot()
          : '';
      conversation = Conversation(
        id: newId(),
        title: run.rule.name,
        createdAt: now,
        updatedAt: now,
        providerId: provider.id,
        model: provider.model,
        automationRuleId: run.rule.id,
        systemPrompt: _renderPrompt(
          provider,
          device,
          incognito: false,
          memoryProfile: profile,
          userNotes: personalization.promptNotes,
          automation: true,
        ),
        promptConfigKey: _promptConfigKey(
          provider,
          incognito: false,
          automation: true,
        ),
        memoryProfile: profile,
        userNotes: personalization.promptNotes,
      );
      await chats.createConversation(conversation!);
    } else {
      conversation = await _withProviderPrompt(
        conversation!,
        provider,
        cancel: _cancel,
      );
    }
    await _refresh();
    if (run.conversationId == null) {
      final message = ChatMessage(
        id: newId(),
        conversationId: conversation!.id,
        parentId: conversation!.activeLeafId,
        role: MessageRole.user,
        content: [
          TextBlock(
            '${run.rule.prompt}\n\nTrigger: ${run.rule.trigger.name}; time: ${now.toIso8601String()}\n<untrusted_automation_input>\n${jsonEncode(run.inputs)}\n</untrusted_automation_input>',
          ),
        ],
        createdAt: now,
        timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
        providerId: provider.id,
        model: provider.model,
      );
      await chats.saveMessage(message);
      await _refresh();
    }
    await onConversation(conversation!.id);
    var leaf = visibleMessages.lastOrNull;
    if (leaf == null) return null;
    if (leaf.role == MessageRole.assistant &&
        leaf.status == MessageStatus.done &&
        !leaf.content.any((b) => b is ToolCallBlock)) {
      return leaf;
    }
    if (leaf.role == MessageRole.assistant &&
        leaf.status != MessageStatus.done) {
      leaf = messages.where((m) => m.id == leaf!.parentId).firstOrNull;
      if (leaf == null) return null;
    }
    ChatMessage? assistant;
    if (leaf.role == MessageRole.assistant) assistant = leaf;
    if (leaf.role == MessageRole.tool) {
      assistant = messages.where((m) => m.id == leaf!.parentId).firstOrNull;
    }
    if (assistant != null) {
      final receipt = leaf.role == MessageRole.tool ? leaf : null;
      final restored = <ContentBlock>[...?receipt?.content];
      final known = restored
          .whereType<ToolResultBlock>()
          .map((r) => r.toolCallId)
          .toSet();
      final durable = (asList(run.pending['receipts']) ?? [])
          .map(asMap)
          .whereType<JsonMap>()
          .where((r) => r['messageId'] == assistant!.id)
          .toList();
      final inFlight = asMap(run.pending['inFlight']) ?? {};
      for (final call in assistant.content.whereType<ToolCallBlock>()) {
        if (known.contains(call.id)) continue;
        final saved = durable
            .where((r) => asMap(r['call'])?['id'] == call.id)
            .firstOrNull;
        final block = asMap(saved?['result']);
        if (block != null) {
          final parsed = ContentBlock.fromJson(block);
          if (parsed is ToolResultBlock) restored.add(parsed);
        } else if (inFlight.containsKey('${assistant.id}:${call.id}')) {
          // No success receipt means the operation may have committed. Never
          // replay the old call or a partially executed REPL program.
          restored.add(
            ToolResultBlock(
              toolCallId: call.id,
              toolName: call.name,
              isError: true,
              content: jsonEncode({
                'error': 'interrupted_operation_not_replayed',
                'completed_operations': durable,
                'unconfirmed_operations': inFlight.values.toList(),
                'session_reset': call.name == 'js_repl',
              }),
            ),
          );
        }
      }
      if (restored.length != (receipt?.content.length ?? 0)) {
        final date = receipt?.createdAt ?? DateTime.now();
        await chats.saveMessage(
          ChatMessage(
            id: receipt?.id ?? newId(),
            conversationId: conversation!.id,
            parentId: assistant.id,
            role: MessageRole.tool,
            content: restored,
            createdAt: date,
            timezoneOffsetMinutes: date.timeZoneOffset.inMinutes,
            providerId: provider.id,
            model: provider.model,
          ),
        );
        await _refresh();
        leaf = visibleMessages.last;
      }
      final completed = {
        for (final r in restored.whereType<ToolResultBlock>()) r.toolCallId,
      };
      if (assistant.content.whereType<ToolCallBlock>().any(
        (c) => !completed.contains(c.id),
      )) {
        _automationResume = assistant;
      }
    }
    try {
      await _generate(provider, leaf.id);
    } finally {
      _generating = false;
      activeToolCallId = null;
      _activeRepl?.close();
      _activeRepl = null;
      services.browser.endModelSession();
      services.screen.endModelSession(returnToApp: false);
      _emit();
    }
    return visibleMessages.lastOrNull;
  }
}
