part of '../../app/app_controller.dart';

/// Shared streaming/tool loop with independent per-host state.
extension AgentRunner on AppController {
  Future<void> _generate(ProviderConfig provider, String parentId) async {
    if (!bindControls) return _generateInternal(provider, parentId);
    if (!await automation.acquireChat(cancel: _cancel)) {
      throw const AgentSuspended('busy');
    }
    final heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(automation.repository.acquire('chat'));
    });
    try {
      await _generateInternal(provider, parentId);
    } finally {
      heartbeat.cancel();
      services.browser.endModelSession();
      services.screen.endModelSession(returnToApp: !_automationWorker);
      await automation.releaseChat();
    }
  }

  Future<void> _generateInternal(
    ProviderConfig provider,
    String parentId,
  ) async {
    final token = _cancel!;
    final turnTimer = Stopwatch()..start();
    var mainModelMs = 0;
    var mainRounds = 0;
    final allowed =
        toolSettings.enabled &&
        provider.capabilities.tools &&
        !provider.capabilities.imagesOnly;
    final wantsHostedSearch =
        allowed &&
        provider.capabilities.builtInWebSearch &&
        supportsBuiltInWebSearch(provider) &&
        !toolSettings.disabled.contains('web_search');
    final backend = allowed
        ? ToolRegistry(
            toolRegistry.allTools,
            disabledTools: {
              ..._disabledTools(incognito: conversation!.incognito),
              if (wantsHostedSearch) 'web_search',
            },
          )
        : ToolRegistry(const []);
    final executor = ToolExecutor(
      registry: backend,
      permissions: permissionGate,
      audit: audit,
      maxOutputChars: toolSettings.maxOutputChars,
      onStarted: onToolStarted,
      onFinished: onToolFinished,
    );
    var leaf = parentId;
    var executed = 0;
    final loops = ToolLoopDetector();
    var resumeResponse = _automationResume;
    _automationResume = null;
    Future<void> remember(ToolCallBlock call, ToolResultBlock result) async {
      try {
        final attachments = result.attachments.any((b) => b is ImageBlock)
            ? await services.workspace.hydrateBlocks(
                result.attachments,
                vision: true,
                cancel: token,
              )
            : result.attachments;
        loops.record(call, result, attachments: attachments);
      } catch (_) {
        // Loop bookkeeping must never lose a committed tool receipt.
        if (!token.isCancelled) loops.record(call, result);
      }
    }

    // Controlling the screen takes an action and a look per step, so a turn
    // that uses screen tools gets the larger loop-check threshold.
    var screenTurn = false;
    ToolLoop? replLoop;
    int limit() => screenTurn
        ? max(toolSettings.maxSteps, toolSettings.maxScreenSteps)
        : toolSettings.maxSteps;
    final session = allowed && _usesControlRepl(provider)
        ? _replSession(backend, (call, context) async {
            await beforeAgentStep?.call();
            if (screenToolNames.contains(call.name)) screenTurn = true;
            replLoop ??= executed >= limit()
                ? loops.repeatingBefore(call)
                : null;
            if (replLoop != null) {
              return executor.reject(call, context, 'tool_loop_detected');
            }
            final execution = await executor.execute(call, context);
            executed++;
            if (!token.isCancelled) await remember(call, execution.result);
            return execution;
          })
        : null;
    _activeRepl = session;
    final registry = session != null && session.skills.isNotEmpty
        ? replPresentation(backend, session)
        : backend;
    final modelExecutor = ToolExecutor(
      registry: registry,
      permissions: permissionGate,
      audit: audit,
      maxOutputChars: toolSettings.maxOutputChars,
      onStarted: onToolStarted,
      onFinished: onToolFinished,
    );
    while (!token.isCancelled) {
      await beforeAgentStep?.call();
      var hostedAllowed = false;
      int? hostedAudit;
      if (wantsHostedSearch) {
        final args = <String, Object?>{
          'provider': provider.displayName,
          'model': provider.model,
          'mode': 'provider_managed_search',
          'max_calls': 1,
        };
        hostedAudit = await audit.start(
          conversationId: conversation!.id,
          messageId: leaf,
          toolCallId: newId(),
          toolName: 'web_search',
          arguments: jsonEncode(args),
          risk: RiskLevel.safe,
        );
        try {
          final decision = await permissionGate.authorize(
            toolName: 'web_search',
            args: args,
            risk: RiskLevel.safe,
            context: ToolContext(
              conversationId: conversation!.id,
              messageId: leaf,
              cancel: token,
            ),
          );
          hostedAllowed = decision.allowed;
          if (hostedAllowed) executed++;
          if (!hostedAllowed) {
            await audit.finish(
              hostedAudit,
              decision: decision.reason,
              resultSummary: '{"error":"denied_by_user"}',
              isError: true,
            );
            hostedAudit = null;
          }
        } on RequestCancelled {
          if (hostedAudit case final auditId?) {
            await audit.finish(
              auditId,
              decision: 'cancelled',
              resultSummary: '{"error":"cancelled"}',
              isError: true,
            );
          }
          rethrow;
        }
      }
      ChatMessage? response;
      final mainTimer = Stopwatch()..start();
      mainRounds++;
      try {
        response =
            resumeResponse ??
            await _streamResponse(
              provider,
              leaf,
              registry.definitions,
              builtInWebSearch: hostedAllowed,
            );
        resumeResponse = null;
      } finally {
        mainModelMs += mainTimer.elapsedMilliseconds;
        if (hostedAudit != null) {
          await audit.finish(
            hostedAudit,
            decision: token.isCancelled ? 'cancelled' : 'provider_managed',
            resultSummary: response?.text ?? '{"error":"request_incomplete"}',
            isError: response?.status != MessageStatus.done,
          );
        }
      }
      if (response == null || response.status != MessageStatus.done) return;
      final calls = response.content.whereType<ToolCallBlock>().toList();
      if (calls.isEmpty) {
        if (hostedAllowed && _lastStopReason == 'pause_turn') {
          const call = ToolCallBlock(
            id: 'hosted',
            name: 'provider_web_search',
            arguments: '{}',
          );
          loops.record(
            call,
            ToolResultBlock(
              toolCallId: call.id,
              toolName: call.name,
              content: jsonEncode([
                for (final state
                    in response.content.whereType<ProviderStateBlock>())
                  for (final item in state.content)
                    {
                      for (final entry in item.entries)
                        if (entry.key != 'id') entry.key: entry.value,
                    },
                response.text,
              ]),
            ),
          );
          final loop = executed >= limit() ? loops.repeatingBefore(call) : null;
          if (loop != null) {
            await _finishToolLoop(provider, response.id, loop);
            return;
          }
          leaf = response.id;
          continue;
        }
        return;
      }
      final existingReceipt = messages
          .where(
            (m) => m.parentId == response!.id && m.role == MessageRole.tool,
          )
          .firstOrNull;
      final results = <ContentBlock>[...?existingReceipt?.content];
      final receiptAt = existingReceipt?.createdAt ?? DateTime.now();
      final receiptId = existingReceipt?.id ?? newId();
      Future<void> saveReceipts() async {
        if (results.isEmpty) return;
        await _saveChatMessage(
          ChatMessage(
            id: receiptId,
            conversationId: response!.conversationId,
            parentId: response.id,
            role: MessageRole.tool,
            content: List.of(results),
            createdAt: receiptAt,
            timezoneOffsetMinutes: receiptAt.timeZoneOffset.inMinutes,
            providerId: provider.id,
            model: provider.model,
          ),
        );
      }

      final seen = <String>{};
      ToolLoop? blockedLoop;
      for (final (index, call) in calls.indexed) {
        if (results.whereType<ToolResultBlock>().any(
          (r) => r.toolCallId == call.id,
        )) {
          continue;
        }
        await beforeAgentStep?.call();
        activeToolCallId = call.id;
        _emit();
        if (screenToolNames.contains(call.name) &&
            registry.get(call.name) != null) {
          screenTurn = true;
        }
        blockedLoop ??= executed >= limit()
            ? loops.repeatingBefore(call)
            : null;
        if (blockedLoop != null || call.id.isEmpty || !seen.add(call.id)) {
          final code = blockedLoop != null
              ? 'tool_loop_detected'
              : 'invalid_tool_call';
          final id = await audit.start(
            conversationId: response.conversationId,
            messageId: response.id,
            toolCallId: call.id,
            toolName: call.name,
            arguments: call.arguments,
            risk: RiskLevel.high,
          );
          final result = ToolResultBlock(
            toolCallId: call.id,
            toolName: call.name,
            content: jsonEncode({
              'error': code,
              if (blockedLoop != null) 'message': blockedLoop.contextHint,
            }),
            isError: true,
          );
          await audit.finish(
            id,
            decision: code,
            resultSummary: result.content,
            isError: true,
          );
          results.add(result);
          if (blockedLoop == null) {
            await remember(call, result);
            executed++;
          }
        } else {
          final beforeWorkerMs = turnTimer.elapsedMilliseconds;
          ToolExecution execution;
          try {
            execution = await modelExecutor.execute(
              call,
              ToolContext(
                conversationId: response.conversationId,
                messageId: response.id,
                cancel: token,
                lastCall: index == calls.length - 1,
              ),
            );
          } on AgentSuspended {
            await saveReceipts();
            rethrow;
          }
          var receipt = execution.result;
          if (call.name == 'remote_control') {
            final data = tryDecodeObject(receipt.content);
            if (data?['task_id'] is String) {
              receipt = ToolResultBlock(
                toolCallId: receipt.toolCallId,
                toolName: receipt.toolName,
                content: jsonEncode({
                  ...data!,
                  'main_timing': {
                    'elapsed_before_worker_ms': beforeWorkerMs,
                    'model_ms_before_worker': mainModelMs,
                    'model_rounds_before_worker': mainRounds,
                  },
                }),
                isError: receipt.isError,
                sideEffects: receipt.sideEffects,
                attachments: receipt.attachments,
              );
            }
          }
          results.add(receipt);
          await saveReceipts();
          if (agentSuspension case final pause?) throw pause;
          blockedLoop ??= replLoop;
          // Persist committed actions even if Stop prevents image hydration.
          if (!token.isCancelled) await remember(call, receipt);
          executed++;
          if (!token.isCancelled && services.screen.modelActive) {
            services.screen.updateModelSession(
              phase: ScreenSessionPhase.thinking,
            );
          }
        }
      }
      activeToolCallId = null;
      final now = receiptAt;
      final resultMessage = ChatMessage(
        id: receiptId,
        conversationId: response.conversationId,
        parentId: response.id,
        role: MessageRole.tool,
        content: results,
        createdAt: now,
        timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
        providerId: provider.id,
        model: provider.model,
      );
      // Receipts are persisted even when Stop raced with a committed action.
      await _saveChatMessage(resultMessage);
      if (token.isCancelled) {
        final expired = results.whereType<ToolResultBlock>().any(
          (r) =>
              r.toolName == 'remote_control' &&
              tryDecodeObject(r.content)?['stop_reason'] == 'system_expiration',
        );
        if (expired) {
          await _saveChatMessage(
            ChatMessage(
              id: newId(),
              conversationId: response.conversationId,
              parentId: resultMessage.id,
              role: MessageRole.assistant,
              content: [
                TextBlock(
                  locale.languageCode == 'zh'
                      ? 'iOS 已結束此任務的背景執行，操作未完成。已保留完成的動作紀錄，沒有重複執行。'
                      : 'iOS ended background execution before the task finished. Completed action receipts were kept; no action was repeated.',
                ),
              ],
              createdAt: DateTime.now(),
              timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
            ),
          );
        }
        return;
      }
      if (blockedLoop != null) {
        await _finishToolLoop(provider, resultMessage.id, blockedLoop);
        return;
      }
      if (calls.length == 1 &&
          results.length == 1 &&
          calls.single.name == 'remote_control' &&
          tryDecodeObject(calls.single.arguments)?['reply_direct'] == true) {
        final result = results.single as ToolResultBlock;
        final outcome = tryDecodeObject(result.content);
        final note = outcome?['worker_note'] as String?;
        final verified =
            outcome?['verified'] == true &&
            outcome?['semantic_review_needed'] != true;
        if (outcome?['task_id'] is String &&
            (note?.trim().isNotEmpty == true || verified) &&
            {
              'verified',
              'reported_complete',
              'blocked',
              'incomplete',
            }.contains(outcome?['status'])) {
          final zh = locale.languageCode == 'zh';
          final heading = verified
              ? (zh ? '已由畫面核對。' : 'Verified on the device.')
              : outcome?['status'] == 'reported_complete'
              ? (zh
                    ? '操作模型回報（尚未獨立驗證）：'
                    : 'Worker report (not independently verified):')
              : (zh ? '操作未完成。' : 'The phone task is incomplete.');
          final details = note?.trim().isNotEmpty == true
              ? note!.trim()
              : (asList(outcome?['matched_text']) ?? [])
                    .whereType<String>()
                    .join(' · ');
          final now = DateTime.now();
          await _saveChatMessage(
            ChatMessage(
              id: newId(),
              conversationId: response.conversationId,
              parentId: resultMessage.id,
              role: MessageRole.assistant,
              content: [
                TextBlock('$heading${details.isEmpty ? '' : '\n$details'}'),
              ],
              createdAt: now,
              timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
              providerId: outcome?['worker_provider_id'] as String?,
              model: outcome?['worker_model'] as String?,
            ),
          );
          return;
        }
      }
      leaf = resultMessage.id;
    }
  }

  Future<void> _finishToolLoop(
    ProviderConfig provider,
    String leaf,
    ToolLoop loop,
  ) async {
    // One tool-free response makes the injected hint visible to the model and
    // lets it explain the blockage without executing the same actions again.
    final response = await _streamResponse(
      provider,
      leaf,
      const [],
      contextHint: loop.contextHint,
    );
    if (_cancel!.isCancelled) return;
    errorCode = 'toolLoopDetected';
    _limitedAt = response?.id ?? leaf;
    _emit();
  }

  Future<ChatMessage?> _streamResponse(
    ProviderConfig provider,
    String parentId,
    List<ToolDefinition> definitions, {
    bool builtInWebSearch = false,
    String? contextHint,
  }) async {
    _lastStopReason = null;
    final current = conversation!;
    var systemPrompt = contextHint == null
        ? current.systemPrompt
        : '${current.systemPrompt}\n\n$contextHint';
    final token = _cancel!;
    token.throwIfCancelled();
    final imagesOnly = provider.capabilities.imagesOnly;
    ContextSummary? summary;
    final history = tree.pathTo(
      parentId,
      stopAt: imagesOnly ? (message) => message.role == MessageRole.user : null,
    );
    final screenHistory = limitRemoteScreenImages(history);
    var rawPath = imagesOnly
        ? screenHistory.messages
              .where((m) => m.role == MessageRole.user)
              .toList()
        : screenHistory.messages;
    // A tool round is still part of the same user turn. An optional summary
    // that just failed need not be requested again while the full path fits.
    final deferredThisTurn = contextCompactionDeferred;
    contextCompactionDeferred = false;
    if (!imagesOnly) {
      final contextWindow = provider.capabilities.contextWindow ?? 32768;
      final inputBudget =
          contextWindow -
          provider.maxOutputTokens -
          ContextBudget.estimateTokens(
            jsonEncode([
              for (final d in definitions) [d.name, d.description, d.schema],
            ]),
          );
      ContextCompactionPlan planForPath() => ContextCompactionPlan.build(
        path: rawPath,
        previous: summary,
        systemPrompt: systemPrompt,
        inputBudget: inputBudget,
        policy: compactionPolicy,
      );
      try {
        // A checkpoint from a smaller model (or the old fixed 12K threshold)
        // must not hide original history that fits the current preference.
        var plan = planForPath();
        final fullHistoryFits = plan.fitsWithoutNewSummary;
        var start = 0;
        if (plan.needsSummary) {
          final checkpoints = await chats.getContextSummaries(current.id);
          token.throwIfCancelled();
          final index = history.lastIndexWhere(
            (m) => m.role == MessageRole.user && checkpoints.containsKey(m.id),
          );
          if (index >= 0) {
            start = index;
            summary = checkpoints[history[index].id];
            rawPath = rawPath.sublist(index);
            try {
              plan = planForPath();
            } on ContextTooLarge {
              // A checkpoint made with another model may itself be too big.
              // Use the original plan, whose boundary does not depend on it.
              summary = null;
              rawPath = screenHistory.messages;
              start = 0;
            }
          }
        }
        if (deferredThisTurn &&
            plan.needsSummary &&
            plan.fitsWithoutNewSummary) {
          contextCompactionDeferred = true;
        } else if (plan.needsSummary) {
          isCompactingContext = true;
          _emit();
          try {
            final resumeAt = rawPath[plan.keepFrom];
            final text = await summarizeContext(
              adapterFor: () => adapterFor(
                provider.copyWith(reasoningMode: ReasoningMode.off),
              ),
              resumeAt: resumeAt,
              history: history.sublist(start, start + plan.keepFrom),
              previous: summary,
              contextWindow: contextWindow,
              maxOutputTokens: plan.summaryTokens,
              cancel: token,
            );
            token.throwIfCancelled();
            final checkpoint = ContextSummary(
              resumeAt: resumeAt.id,
              text: text,
            );
            await chats.saveContextSummary(checkpoint);
            token.throwIfCancelled();
            summary = checkpoint;
            rawPath = rawPath.sublist(plan.keepFrom);
          } on ContextCompactionFailed {
            token.throwIfCancelled();
            // A soft threshold should not cost the user their turn. Never
            // drop messages, and never send a known over-budget fallback.
            if (fullHistoryFits) {
              summary = null;
              rawPath = screenHistory.messages;
            } else if (!plan.fitsWithoutNewSummary) {
              rethrow;
            }
            contextCompactionDeferred = true;
          } finally {
            isCompactingContext = false;
            _emit();
          }
        }
      } on ContextTooLarge {
        errorCode = 'contextTooLarge';
        return null;
      } on ContextCompactionFailed catch (failure) {
        errorCode = failure.code;
        _compactionRetry = (parent: parentId, active: current.activeLeafId);
        return null;
      }
    }
    final checkpoint = summary;
    contextCompacted = checkpoint != null;
    if (checkpoint != null) systemPrompt += ContextSummary.instruction;
    // Providers may reuse call IDs across turns. Pair within the actual
    // assistant -> tool edge, never against a global set of IDs in history.
    final pairedIds = <String, Set<String>>{};
    for (var index = 0; index + 1 < rawPath.length; index++) {
      final assistant = rawPath[index];
      final results = rawPath[index + 1];
      if (assistant.role != MessageRole.assistant ||
          assistant.status != MessageStatus.done ||
          results.role != MessageRole.tool ||
          results.status != MessageStatus.done ||
          results.parentId != assistant.id) {
        continue;
      }
      final resultIds = {
        for (final result in results.content.whereType<ToolResultBlock>())
          result.toolCallId,
      };
      final completed = {
        for (final call in assistant.content.whereType<ToolCallBlock>())
          if (call.id.isNotEmpty && resultIds.contains(call.id)) call.id,
      };
      pairedIds[assistant.id] = completed;
      pairedIds[results.id] = completed;
    }
    final path = <ChatMessage>[];
    var historyChanged = screenHistory.changed;
    for (final message in rawPath) {
      final content = message.content
          .where(
            (block) => switch (block) {
              ToolCallBlock() =>
                pairedIds[message.id]?.contains(block.id) ?? false,
              ToolResultBlock() =>
                pairedIds[message.id]?.contains(block.toolCallId) ?? false,
              _ => true,
            },
          )
          .toList();
      if (content.isEmpty ||
          message.role == MessageRole.assistant &&
              !_hasAnswer(content) &&
              !content.any(
                (b) =>
                    b is ToolCallBlock ||
                    b is ProviderStateBlock && builtInWebSearch,
              )) {
        historyChanged = true;
        continue;
      }
      if (content.length != message.content.length) historyChanged = true;
      if (content.whereType<ToolCallBlock>().any(
        (call) => tryDecodeObject(call.arguments) == null,
      )) {
        historyChanged = true;
      }
      path.add(
        content.length == message.content.length
            ? message
            : message.copyWith(content: content),
      );
    }
    final preparedMessages = <ChatMessage>[
      if (checkpoint != null) checkpoint.asMessage(rawPath.first),
    ];
    for (final message in path) {
      final hasAttachments = message.content.any(
        (b) =>
            b is ImageBlock ||
            b is FileBlock ||
            b is ToolResultBlock && b.attachments.isNotEmpty,
      );
      preparedMessages.add(
        hasAttachments
            ? message.copyWith(
                content: await services.workspace.hydrateBlocks(
                  message.content,
                  vision: provider.capabilities.acceptsImageInput,
                  cancel: token,
                ),
              )
            : message,
      );
    }
    final adapter = await token.bind(adapterFor(provider));
    token.throwIfCancelled();
    final now = DateTime.now();
    var response = ChatMessage(
      id: newId(),
      conversationId: current.id,
      parentId: parentId,
      role: MessageRole.assistant,
      content: [],
      createdAt: now,
      timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
      providerId: provider.id,
      model: provider.model,
      status: MessageStatus.streaming,
    );
    await _saveChatMessage(response);
    final fingerprint = promptFingerprint(
      checkpoint == null ? systemPrompt : '$systemPrompt\n${checkpoint.text}',
    );
    var accumulator = ResponseAccumulator(
      sourceApi: provider.apiType.name,
      promptHash: fingerprint,
    );
    var status = MessageStatus.done;
    String? error;
    var completed = false;
    var lastSave = DateTime.now();
    Timer? publishTimer;
    void publish() {
      if (_disposed) return;
      response = response.copyWith(
        content: accumulator.content,
        usage: accumulator.usage,
        clearUsage: accumulator.usage == null,
      );
      liveResponse.value = response;
    }

    try {
      if (!token.isCancelled) {
        await for (final event in adapter.sendWithRetry(
          ChatRequest(
            systemPrompt: systemPrompt,
            messages: preparedMessages,
            tools: definitions,
            builtInWebSearch: builtInWebSearch,
            maxTokens: provider.maxOutputTokens,
            promptHash: fingerprint,
            replayOpaqueReasoning: !historyChanged,
          ),
          cancel: token,
          onRetry: () {
            accumulator = ResponseAccumulator(
              sourceApi: provider.apiType.name,
              promptHash: fingerprint,
            );
            publishTimer?.cancel();
            publishTimer = null;
            publish();
          },
        )) {
          if (token.isCancelled) break;
          if (event is GeneratedImage) {
            accumulator.addImage(
              await storeGeneratedImage(
                services.workspace,
                event,
                cancel: token,
              ),
            );
          } else {
            accumulator.add(event);
          }
          if (event is ProviderError) {
            error = switch (event.code) {
              'model_missing' when provider.apiType == ApiType.onDevice =>
                'localModelMissing',
              'model_load' when provider.apiType == ApiType.onDevice =>
                'localModelLoad',
              'aicore_unavailable' => 'aicoreUnavailable',
              'aicore_update' => 'aicoreUpdate',
              'aicore_request_too_large' => 'aicoreRequestTooLarge',
              'aicore_busy' => 'aicoreBusy',
              'aicore_failed' => 'aicoreFailed',
              'aicore_text_only' => 'aicoreHelp',
              'aicore_tools_unavailable' => 'aicoreToolsUnavailable',
              'aicore_invalid_tools' => 'aicoreInvalidTools',
              'aicore_background' => 'aicoreBackground',
              'no_space' when isAicoreModel(provider.model) =>
                'modelErrorNoSpace',
              'apple_unavailable' => 'appleUnavailable',
              'apple_update' => 'appleUpdate',
              'apple_disabled' => 'appleDisabled',
              'apple_not_ready' => 'appleNotReady',
              'apple_request_too_large' => 'appleRequestTooLarge',
              'apple_busy' => 'appleBusy',
              'apple_background' => 'appleBackground',
              'apple_guardrail' => 'appleGuardrail',
              'apple_language' => 'appleLanguage',
              'apple_image_input' => 'appleImageInput',
              'apple_invalid_tools' => 'aicoreInvalidTools',
              'apple_failed' => 'appleFailed',
              _ => event.toString(),
            };
            status = MessageStatus.error;
          }
          if (event is Done) {
            completed = true;
            _lastStopReason = event.stopReason;
          }
          // Batch network fragments; a model may deliver hundreds per second.
          publishTimer ??= Timer(const Duration(milliseconds: 40), () {
            publishTimer = null;
            publish();
          });
          if (DateTime.now().difference(lastSave).inMilliseconds > 800) {
            response = response.copyWith(
              content: accumulator.content,
              usage: accumulator.usage,
            );
            await chats.saveMessage(response);
            lastSave = DateTime.now();
          }
          if (event is ProviderError || event is Done) break;
        }
      }
      if (token.isCancelled) {
        status = MessageStatus.stopped;
      } else if (status != MessageStatus.error &&
          (!completed ||
              (!_hasAnswer(accumulator.content) &&
                  !(builtInWebSearch && _lastStopReason == 'pause_turn') &&
                  !(definitions.isNotEmpty &&
                      accumulator.content.any((b) => b is ToolCallBlock))))) {
        status = MessageStatus.error;
        error = accumulator.content.any((block) => block is ToolCallBlock)
            ? 'toolsLater'
            : 'emptyResponse';
      }
    } catch (_) {
      status = token.isCancelled ? MessageStatus.stopped : MessageStatus.error;
      error = token.isCancelled ? null : 'operationFailed';
    } finally {
      publishTimer?.cancel();
    }
    if (definitions.isEmpty) {
      final unsolicited = accumulator.content.whereType<ToolCallBlock>();
      for (final call in unsolicited) {
        final auditId = await audit.start(
          conversationId: response.conversationId,
          messageId: response.id,
          toolCallId: call.id,
          toolName: call.name,
          arguments: call.arguments,
          risk: RiskLevel.high,
        );
        await audit.finish(
          auditId,
          decision: 'tools_disabled',
          resultSummary: '{"error":"tool_unavailable"}',
          isError: true,
        );
      }
      // Text accompanying unsolicited calls does not authorize execution.
      // Keep stopped/provider-error states, otherwise make rejection explicit.
      if (unsolicited.isNotEmpty && status == MessageStatus.done) {
        status = MessageStatus.error;
        error = 'toolsLater';
      }
    }
    response = response.copyWith(
      content: accumulator.content,
      usage: accumulator.usage,
      status: status,
      error: error,
    );
    await _saveChatMessage(response);
    if (!_disposed) liveResponse.value = null;
    return response;
  }
}
