// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get controlToolMode => 'Browser and phone control';

  @override
  String get controlToolModeAuto => 'Automatic';

  @override
  String get controlToolModeBasic => 'Basic tools';

  @override
  String get controlToolModeRepl => 'JavaScript REPL';

  @override
  String get controlToolModeHelp =>
      'Automatic uses REPL for remote API models and basic tools for on-device or local-server models. REPL can combine operations with JavaScript; every action still follows tool permissions.';

  @override
  String get readSkillTool => 'Load control guide';

  @override
  String get jsReplTool => 'Run JavaScript';

  @override
  String get toolLoopDetected =>
      'A repeated tool loop was stopped. Review the explanation, then press Continue to try a different approach.';

  @override
  String get appUpdates => 'App updates';

  @override
  String get appUpdatesHelp =>
      'Check and install Android full updates from GitHub nightly releases.';

  @override
  String get installedVersion => 'Installed version';

  @override
  String get checkUpdates => 'Check for updates';

  @override
  String get downloadUpdate => 'Download and install';

  @override
  String get updateAvailable => 'An update is available.';

  @override
  String get updateCurrent => 'You have the latest nightly build.';

  @override
  String get updateCheckFailed =>
      'Could not check for updates. Try again later.';

  @override
  String get updateInstallPermission =>
      'Allow installs from Tako in Android settings, then tap download and install again.';

  @override
  String get updateInstallerOpened =>
      'Android has opened the installation confirmation.';

  @override
  String get updateInstallFailed =>
      'Could not download or install the update. Check the connection and make sure the installed app uses the release signing certificate.';

  @override
  String get generateChatTitle => 'Generate chat title';

  @override
  String get titleGenerationFailed =>
      'Could not generate a title. The current title was kept.';

  @override
  String toolRunSummary(String tool, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '1 step',
    );
    return '$tool · $_temp0';
  }

  @override
  String get toolRunTitle => 'Tool activity';

  @override
  String get toolRunIncomplete => 'Incomplete';

  @override
  String get toolRunUnavailable =>
      'This tool activity is no longer on the current conversation branch.';

  @override
  String get undo => 'Undo';

  @override
  String get deleteAttachmentBody =>
      'This attachment may be used by earlier chats. Deleting it will make those image/file references unavailable. A backup and Undo will be offered.';

  @override
  String get toolsSettings => 'Tools and permissions';

  @override
  String get toolsEnabled => 'Enable tools';

  @override
  String get maxToolSteps => 'Start loop detection after this many tool calls';

  @override
  String get maxScreenToolSteps =>
      'Start loop detection after this many screen tool calls';

  @override
  String get toolOutputLimit => 'Tool result limit (characters)';

  @override
  String get permissions => 'Permissions';

  @override
  String get fullPermissions => 'Full permissions';

  @override
  String get fullPermissionsWarning =>
      'Sensitive reads and reversible actions will run without asking. High-risk actions still require confirmation.';

  @override
  String get skipHighRisk => 'Also skip high-risk confirmations';

  @override
  String get skipHighRiskWarning =>
      'Tools may send data, delete files, or change things without another confirmation. Enable only if you accept these actions.';

  @override
  String get toolOverrides => 'Individual tools';

  @override
  String get defaultPolicy => 'Default policy';

  @override
  String get alwaysAllow => 'Always allow this tool';

  @override
  String get alwaysAsk => 'Always ask';

  @override
  String get deny => 'Deny';

  @override
  String get allowOnce => 'Allow once';

  @override
  String get allowChat => 'Allow in this chat';

  @override
  String get approvalTitle => 'Tool approval';

  @override
  String get approvalBody =>
      'Review the action and exact arguments before allowing it.';

  @override
  String get riskSafe => 'Safe';

  @override
  String get riskSensitive => 'Reads private data';

  @override
  String get riskAction => 'Changes something';

  @override
  String get riskHigh => 'High-risk action';

  @override
  String get auditLog => 'Tool activity';

  @override
  String get clearAudit => 'Clear activity';

  @override
  String get clearAuditBody => 'Delete the local tool activity log?';

  @override
  String get noAudit => 'No tool activity yet.';

  @override
  String get arguments => 'Arguments';

  @override
  String get result => 'Result';

  @override
  String get search => 'Web search';

  @override
  String get searchProvider => 'Search provider';

  @override
  String get searchUrl => 'Search endpoint';

  @override
  String get searchKey => 'Search API key';

  @override
  String get searchResults => 'Number of results';

  @override
  String get searchHelp =>
      'Search keys are stored securely and kept separate for each provider.';

  @override
  String get searchKeyHint => 'Stored securely on this device';

  @override
  String get searchOptionalToken => 'Bearer token (optional)';

  @override
  String get searchSerperHelp =>
      'Search Google through Serper. Enter your Serper API key; the default endpoint is ready to use.';

  @override
  String get searchDdgsHelp =>
      'Enter the URL of your DDGS API server (ddgs api). A key is not required unless your server or reverse proxy uses Bearer authentication.';

  @override
  String get searchSearxngHelp =>
      'Enter your SearXNG instance URL. JSON results must be enabled on the server.';

  @override
  String get files => 'Files';

  @override
  String get attach => 'Attach images or files';

  @override
  String get camera => 'Camera';

  @override
  String get photos => 'Photos';

  @override
  String get attachmentBusy =>
      'Wait for the current action to finish before adding an image.';

  @override
  String get attachmentLimit =>
      'You can attach up to 8 images or files per message.';

  @override
  String get imageUnavailable =>
      'Could not read this image. Try choosing it from Photos or Files.';

  @override
  String get unsupportedImage =>
      'This image format is not supported. Choose a PNG, JPEG, GIF, or WebP image.';

  @override
  String get importFiles => 'Import files';

  @override
  String get emptyFiles => 'The workspace is empty.';

  @override
  String get filePreview => 'File preview';

  @override
  String get deleteFileBody =>
      'Delete this workspace file? A backup will be kept.';

  @override
  String get workspace => 'Workspace';

  @override
  String get restoreFiles => 'Restore workspace files';

  @override
  String get sideEffectsTitle => 'Actions have already happened';

  @override
  String get sideEffectsBody =>
      'Rewinding the chat does not undo these actions. Available workspace backups and newly saved memories can be restored before rewinding.';

  @override
  String get restoreAndRewind => 'Restore and rewind';

  @override
  String get rewindOnly => 'Rewind chat only';

  @override
  String get visionRequired =>
      'Choose a model that supports vision or reference images to send images.';

  @override
  String get toolStepLimit =>
      'Tool-call limit reached. Review the results, then press Continue if needed.';

  @override
  String get toolRunning => 'Running';

  @override
  String get toolWaiting => 'Waiting';

  @override
  String get toolCompleted => 'Completed';

  @override
  String get toolFailed => 'Failed';

  @override
  String get toolsUnavailable =>
      'Enable tool calling in this model’s capabilities to let it use tools.';

  @override
  String get deviceStatusTool => 'Read device status';

  @override
  String get locationTool => 'Read location';

  @override
  String get clipboardReadTool => 'Read clipboard';

  @override
  String get clipboardWriteTool => 'Write clipboard';

  @override
  String get calendarListTool => 'Read calendar';

  @override
  String get calendarAddTool => 'Add calendar event';

  @override
  String get alarmTool => 'Set alarm';

  @override
  String get timerTool => 'Set timer';

  @override
  String get openUrlTool => 'Open URL';

  @override
  String get openAppTool => 'Open app';

  @override
  String get searchTool => 'Search web';

  @override
  String get fetchTool => 'Read web page';

  @override
  String get fileListTool => 'List files';

  @override
  String get fileReadTool => 'Read file';

  @override
  String get fileWriteTool => 'Write file';

  @override
  String get fileDeleteTool => 'Delete file';

  @override
  String get toolDisabled => 'Unavailable';

  @override
  String get highRiskKeywords => 'High-risk keywords (one per line)';

  @override
  String get importFailed => 'Could not import the selected file.';

  @override
  String get restoreFailed =>
      'A backup could not be restored. The conversation was not rewound.';

  @override
  String get toolResultAttachment => 'Tool attachment';

  @override
  String get noBackup => 'No workspace backup';

  @override
  String get systemPermissionHint =>
      'Android may ask for permission after you allow this tool.';

  @override
  String get newChat => 'New chat';

  @override
  String get chats => 'Chats';

  @override
  String get settings => 'Settings';

  @override
  String get providers => 'Providers';

  @override
  String get addProvider => 'Add provider';

  @override
  String get editProvider => 'Edit provider';

  @override
  String get noProviders => 'Connect your model';

  @override
  String get welcome => 'A little space to think.';

  @override
  String get welcomeBody =>
      'Ask, explore, or work something out. Your conversations stay on this device.';

  @override
  String get setupBody =>
      'Add a cloud provider, a local server, or an on-device model to start chatting. You choose where your messages go.';

  @override
  String get messageHint => 'Ask anything';

  @override
  String get send => 'Send';

  @override
  String get stop => 'Stop';

  @override
  String get retry => 'Retry';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get close => 'Close';

  @override
  String get copy => 'Copy';

  @override
  String get copyMarkdown => 'Copy as Markdown';

  @override
  String get selectText => 'Select text';

  @override
  String get copied => 'Copied';

  @override
  String get share => 'Share';

  @override
  String get edit => 'Edit';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get rewind => 'Rewind to here';

  @override
  String get rewindDelete => 'Rewind and delete after';

  @override
  String get rewindDeleteBody =>
      'Delete all later branches after this message? This cannot be undone.';

  @override
  String get deleteChatBody =>
      'Delete this conversation and all of its branches?';

  @override
  String get thinking => 'Thinking';

  @override
  String get you => 'You';

  @override
  String get image => 'Image';

  @override
  String get file => 'File';

  @override
  String get stopped => 'Stopped';

  @override
  String get streaming => 'Writing…';

  @override
  String get providerName => 'Display name';

  @override
  String get apiType => 'API format';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get apiKey => 'API key';

  @override
  String get keyHint => 'Optional for local servers';

  @override
  String get keyStored => 'Key saved securely · leave blank to keep';

  @override
  String get removeKey => 'Remove saved key';

  @override
  String get model => 'Model';

  @override
  String get modelHint => 'Enter a model ID or load the list';

  @override
  String get loadModels => 'Load models';

  @override
  String get testConnection => 'Test connection';

  @override
  String get connectionOk => 'Connected. Model list is available.';

  @override
  String get connectionHelp =>
      'Tests the models endpoint. You can still enter a model manually if this endpoint is unavailable.';

  @override
  String get extraHeaders => 'Extra headers (JSON object)';

  @override
  String get headersHint => 'Stored securely with your key';

  @override
  String get headersStored => 'Headers saved securely · leave blank to keep';

  @override
  String get removeHeaders => 'Remove saved headers';

  @override
  String get localProvider => 'Local provider';

  @override
  String get localDescription =>
      'Auto-detected for loopback and private LAN addresses. You can override it.';

  @override
  String get toolsCapability => 'Tool calling';

  @override
  String get visionCapability => 'Vision';

  @override
  String get visionCapabilityHelp =>
      'Allows the model to understand images in chat. Image generation is configured separately.';

  @override
  String get imageGeneration => 'Image generation';

  @override
  String get imageGenerationNone => 'Off';

  @override
  String get imageGenerationImagesApi => 'Images API';

  @override
  String get imageGenerationChatOutput => 'Image output in chat';

  @override
  String get imageGenerationResponsesTool => 'Responses image tool';

  @override
  String get imageGenerationOnDevice => 'On this device';

  @override
  String get imageGenerationHelp =>
      'Choose the image format supported by this model. You can select it for image generation or let a chat model call it through the image generation tool.';

  @override
  String get imageGenerationProtocolHelp =>
      'Image generation requires an OpenAI-compatible Chat Completions or Responses provider.';

  @override
  String get imageReferenceInput => 'Reference images';

  @override
  String get imageReferenceInputHelp =>
      'Allow attached images as references for generation or editing. Enable only when this model supports image input for generation.';

  @override
  String get imageGenerationTool => 'Generate image';

  @override
  String get reasoningCapability => 'Reasoning';

  @override
  String get capabilities => 'Model capabilities';

  @override
  String get contextWindow => 'Context window (tokens)';

  @override
  String get maxOutput => 'Maximum output tokens';

  @override
  String get reasoningMode => 'Reasoning mode';

  @override
  String get reasoningOff => 'Provider default';

  @override
  String get reasoningEnabled => 'Enabled (budget)';

  @override
  String get reasoningAdaptive => 'Adaptive';

  @override
  String get thinkingBudget => 'Thinking budget (tokens)';

  @override
  String get reasoningEffort => 'Reasoning effort';

  @override
  String get requiredField => 'Required';

  @override
  String get invalidUrl =>
      'Use an http(s) URL without credentials, query, or fragment.';

  @override
  String get invalidJson => 'Enter a JSON object with string header values.';

  @override
  String get invalidNumber => 'Enter a positive whole number.';

  @override
  String get invalidBudget =>
      'Output tokens must be smaller than the context window. Thinking budget must be at least 1024 and smaller than output tokens.';

  @override
  String get operationFailed => 'Something went wrong. Please try again.';

  @override
  String get fileUnavailable => 'This workspace file is unavailable.';

  @override
  String get contextTrimmed => 'Older context trimmed for this model';

  @override
  String get contextTooLarge =>
      'This message exceeds the model’s context window. Shorten it or increase the context window in provider settings.';

  @override
  String get noProviderSelected => 'Select a provider in settings to continue.';

  @override
  String get providerRemoved =>
      'The provider for this conversation is unavailable. Choose another provider.';

  @override
  String get changeProvider => 'Change provider';

  @override
  String get changeProviderBody =>
      'The conversation will continue with this provider. Its visible history will be sent there and the system prompt will be refreshed.';

  @override
  String get continueAction => 'Continue';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get systemTheme => 'System';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get textSize => 'Text size';

  @override
  String get language => 'Language';

  @override
  String get privacy => 'Local first';

  @override
  String get privacyBody =>
      'Chats and memories are saved on this device. When you chat, your messages and what tools read, such as the screen or notifications, are sent to your selected model provider; with an on-device model they never leave this phone. API keys and extra headers are stored in secure storage. No accounts, analytics, or telemetry.';

  @override
  String get about => 'About';

  @override
  String get developerContext => 'Stored context';

  @override
  String get noChats => 'Your conversations will appear here.';

  @override
  String get chooseProvider => 'Choose a provider';

  @override
  String get previousBranch => 'Previous branch';

  @override
  String get nextBranch => 'Next branch';

  @override
  String get providerDeleteBody =>
      'Remove this provider and its saved credentials? Conversations are kept.';

  @override
  String get emptyResponse =>
      'The provider returned no answer. Try again or check the model settings.';

  @override
  String get toolsLater =>
      'Tools are not enabled or available for this request.';

  @override
  String get builtInSearch => 'Provider-managed web search';

  @override
  String get builtInSearchHelp =>
      'Use the model provider\'s native search. Turn off to use the provider in Search settings. Tool permission rules still apply.';

  @override
  String get allowCustomSearchEndpoint => 'Allow compatible proxies (CPA)';

  @override
  String get allowCustomSearchEndpointHelp =>
      'Send native search tools to this custom endpoint. The proxy must preserve the Responses or Messages search format; automatic detection otherwise allows official endpoints only.';

  @override
  String get testNativeSearch => 'Test native search';

  @override
  String get nativeSearchTesting => 'Testing native search…';

  @override
  String get nativeSearchTestHelp =>
      'Runs one public search for the official Flutter website using this model and endpoint. May incur API charges. Does not send chat history, enable search, or save settings.';

  @override
  String get nativeSearchSupported =>
      'Verified: the provider completed a native search.';

  @override
  String get nativeSearchNotObserved =>
      'The endpoint responded, but no completed native search was observed. The proxy may have removed the tool or the route may not support it.';

  @override
  String get nativeSearchProtocolHelp =>
      'Native search here requires OpenAI Responses or Anthropic Messages. For Chat Completions, use the provider in Search settings.';

  @override
  String get nativeSearchDisabled =>
      'Enable tools and web search in Tools and permissions before testing.';

  @override
  String get nativeSearchDenied =>
      'The web search permission policy denied this test.';

  @override
  String get nativeSearchFailed =>
      'Native search test failed. Check that the model and proxy route support native search.';

  @override
  String get nativeSearchCancelled => 'Native search test cancelled.';

  @override
  String get nativeSearchTimeout =>
      'Native search test timed out. Its request was cancelled.';

  @override
  String get nativeSearchBusy =>
      'Wait for the current operation to finish before testing.';

  @override
  String get localLabel => 'Local';

  @override
  String get cloudLabel => 'Cloud';

  @override
  String get connectionFailed => 'Connection failed';

  @override
  String get noModels => 'No models returned. Enter a model ID manually.';

  @override
  String get viewImage => 'View image';

  @override
  String get openImageLink => 'Open image in browser';

  @override
  String get renameChat => 'Rename chat';

  @override
  String get chatTitle => 'Conversation title';

  @override
  String get messageActions => 'Message actions';

  @override
  String get models => 'Models';

  @override
  String get addModel => 'Add model';

  @override
  String get addModels => 'Add selected';

  @override
  String get newModel => 'New model';

  @override
  String get duplicateModel => 'This model is already added.';

  @override
  String get autoModelSpecs => 'Detect model specifications';

  @override
  String get knownModelSpecs =>
      'Known specifications applied. Turn off to customize limits and capabilities.';

  @override
  String get unknownModelSpecs =>
      'Unknown model: using fallback settings. Set the limits supported by your server.';

  @override
  String get officialModelId => 'Official API model ID';

  @override
  String get chooseModel => 'Choose a model';

  @override
  String get memory => 'Memory';

  @override
  String get memoryEnabled => 'Use memory';

  @override
  String memoryEnabledHelp(String app) {
    return '$app can save and look up lasting facts you share. Pinned profile and preference entries are added to new chats.';
  }

  @override
  String get memoryOff =>
      'Memory is off. Saved memories are kept but are not used in chats.';

  @override
  String get memorySearchHint => 'Search memories';

  @override
  String memoryEmpty(String app) {
    return 'No memories yet. Ask $app to remember something, or add one here.';
  }

  @override
  String get memoryNoMatches => 'No matching memories.';

  @override
  String get addMemory => 'Add memory';

  @override
  String get editMemory => 'Edit memory';

  @override
  String get memoryText => 'Text';

  @override
  String get memoryKind => 'Type';

  @override
  String get memoryKindProfile => 'Profile';

  @override
  String get memoryKindPreference => 'Preference';

  @override
  String get memoryKindFact => 'Fact';

  @override
  String get memoryPinned => 'Pinned';

  @override
  String get memoryPin => 'Pin';

  @override
  String get memoryUnpin => 'Unpin';

  @override
  String get memoryPinHelp =>
      'Pinned profile and preference entries are included in new chats.';

  @override
  String memoryProfileUsage(int words, int limit) {
    return 'Pinned profile: $words/$limit words';
  }

  @override
  String get memoryProfileTruncated =>
      'Some pinned entries do not fit and are left out of new chats.';

  @override
  String get memoryFromChat => 'Saved from a chat';

  @override
  String get deleteMemoryBody => 'Delete this memory?';

  @override
  String get deleteAllMemories => 'Delete all memories';

  @override
  String get deleteAllMemoriesBody =>
      'Delete every saved memory? This cannot be undone.';

  @override
  String get exportMemories => 'Export JSON';

  @override
  String get importMemories => 'Import JSON';

  @override
  String memoriesImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count memories',
      one: 'Imported 1 memory',
      zero: 'No new memories imported',
    );
    return '$_temp0';
  }

  @override
  String memoryImportFailed(String app) {
    return 'This file is not a valid $app memory export.';
  }

  @override
  String get memorySaved => 'Saved to memory';

  @override
  String get memoryUndone => 'Removed from memory';

  @override
  String get memoryChanged => 'Changed or removed since it was saved';

  @override
  String get personalization => 'Personalization';

  @override
  String displayName(String app) {
    return 'What should $app call you?';
  }

  @override
  String get customInstructions => 'Custom instructions';

  @override
  String customInstructionsHint(String app) {
    return 'Anything $app should know or follow in every new chat';
  }

  @override
  String get replyStyle => 'Reply style';

  @override
  String get replyConcise => 'Concise';

  @override
  String get replyNormal => 'Normal';

  @override
  String get replyDetailed => 'Detailed';

  @override
  String get personalizationHelp =>
      'Changes apply to new chats. Existing chats keep the settings they started with.';

  @override
  String get incognitoChat => 'Incognito chat';

  @override
  String get newIncognitoChat => 'New incognito chat';

  @override
  String get incognitoBody =>
      'Memory is off, and this chat is deleted when you leave it.';

  @override
  String get browser => 'Browser';

  @override
  String get openBrowser => 'Open browser';

  @override
  String get browserAddressHint => 'Enter a web address';

  @override
  String get browserInvalidAddress =>
      'Enter a web address such as example.com.';

  @override
  String browserEmpty(String app) {
    return 'Enter an address, or ask $app to open a page.';
  }

  @override
  String browserModelActive(String app) {
    return '$app is using the browser';
  }

  @override
  String get takeOver => 'Take over';

  @override
  String get browserBack => 'Back';

  @override
  String get browserForward => 'Forward';

  @override
  String get browserReload => 'Reload';

  @override
  String get openExternally => 'Open in another app';

  @override
  String get clearBrowsingData => 'Clear browsing data';

  @override
  String get clearBrowsingDataBody =>
      'Delete cookies, site storage, cache and history of the in-app browser? You will be signed out of sites.';

  @override
  String get browsingDataCleared => 'Browsing data cleared';

  @override
  String get openLinksInApp => 'Open links in the in-app browser';

  @override
  String get openLinksInAppHelp =>
      'When off, links open in your default browser. The in-app browser keeps its own cookies, separate from other browsers.';

  @override
  String get browserUnavailable =>
      'The in-app browser is not available on this device.';

  @override
  String get downloadTitle => 'Download file?';

  @override
  String downloadBody(String name, String host) {
    return 'Save $name from $host to Files?';
  }

  @override
  String get download => 'Download';

  @override
  String get downloadSaved => 'Saved to Files';

  @override
  String get downloadFailed => 'The download failed.';

  @override
  String get downloadTooLarge => 'Files over 20 MB cannot be downloaded.';

  @override
  String get approvalElement => 'Element';

  @override
  String get approvalPage => 'Page';

  @override
  String get approvalSubmit => 'Submits with';

  @override
  String get memorySearchTool => 'Search memory';

  @override
  String get memorySaveTool => 'Save to memory';

  @override
  String get memoryUpdateTool => 'Update memory';

  @override
  String get memoryDeleteTool => 'Delete memory';

  @override
  String get browserOpenTool => 'Open web page';

  @override
  String get browserReadTool => 'Read browser page';

  @override
  String get browserClickTool => 'Click in browser';

  @override
  String get browserTypeTool => 'Type in browser';

  @override
  String get browserScrollTool => 'Scroll browser page';

  @override
  String get browserBackTool => 'Browser back';

  @override
  String get readScreenTool => 'Read screen';

  @override
  String get tapTool => 'Tap on screen';

  @override
  String get longPressTool => 'Long-press on screen';

  @override
  String get swipeTool => 'Swipe on screen';

  @override
  String get scrollTool => 'Scroll on screen';

  @override
  String get typeTextTool => 'Type on screen';

  @override
  String get pressKeyTool => 'Press key';

  @override
  String get runShellTool => 'Run shell command';

  @override
  String get notificationsListTool => 'Read notifications';

  @override
  String get approvalApp => 'App';

  @override
  String get approvalPoint => 'Position';

  @override
  String screenSessionTitle(String app) {
    return '$app is using your phone';
  }

  @override
  String get screenSessionThinking => 'Thinking about the next step…';

  @override
  String get screenSessionWaiting => 'Waiting for your approval…';

  @override
  String get screenSessionBody => 'Tap Stop to take over.';

  @override
  String get screenChannel => 'Screen control';

  @override
  String get alertChannel => 'Approvals and replies';

  @override
  String approvalNeededTitle(String app) {
    return '$app needs your approval';
  }

  @override
  String get approvalNeededBody => 'Open the app to review the request.';

  @override
  String replyReadyTitle(String app) {
    return '$app replied';
  }

  @override
  String get replyReadyBody => 'Tap to read the reply.';

  @override
  String get deviceControl => 'Device control';

  @override
  String deviceControlHelp(String app) {
    return 'Let $app use other apps, your notifications and Termux. Each is turned on in Android settings, and every action still goes through tool permissions.';
  }

  @override
  String get screenControl => 'Screen control';

  @override
  String get statusOn => 'On';

  @override
  String get statusOff => 'Off';

  @override
  String get screenControlUnsupported =>
      'This version does not include screen control.';

  @override
  String screenControlHelp(String app) {
    return '$app reads the screen and taps, types and scrolls in other apps only when you ask, through approved tools. Send, pay, delete and similar buttons always ask first, and password fields are never filled.';
  }

  @override
  String get screenControlDisclosureTitle => 'Turn on screen control?';

  @override
  String screenControlDisclosure(String app) {
    return '$app uses Android\'s accessibility service to read what is on the screen and to tap, type and scroll for you. The screen is read only while a screen tool runs. What it reads is sent to the model provider you chose, kept in that chat, and used for nothing else. On the next screen, find $app and turn it on.';
  }

  @override
  String get openAccessibilitySettings => 'Open accessibility settings';

  @override
  String get restrictedSettingsHelp =>
      'If Android says the setting is restricted, open App info, tap the ⋮ menu, choose Allow restricted settings, and try again.';

  @override
  String get openAppInfo => 'Open app info';

  @override
  String get screenshotsSetting => 'Send screenshots to vision models';

  @override
  String get screenshotsHelp =>
      'read_screen also attaches a screenshot when the model accepts images. Screenshots show everything on screen and use more tokens.';

  @override
  String get screenshotsUnsupported => 'Screenshots need Android 11 or later.';

  @override
  String get sessionNotification => 'Notification while controlling the screen';

  @override
  String get sessionNotificationHelp =>
      'Shows that the screen is being controlled, with a Stop button.';

  @override
  String get allowNotifications => 'Allow notifications';

  @override
  String get allowed => 'Allowed';

  @override
  String get notificationAccess => 'Notification access';

  @override
  String notificationAccessHelp(String app) {
    return 'Lets $app read your current notifications when you ask. Nothing is read or kept in the background.';
  }

  @override
  String get openNotificationAccess => 'Open notification access settings';

  @override
  String get termux => 'Termux (run_shell)';

  @override
  String get termuxHelp =>
      'run_shell runs commands in Termux. Read-only commands such as ls or cat count as reading private data; anything else asks every time.';

  @override
  String get termuxNotInstalled =>
      'Termux is not installed. Install it from F-Droid or its GitHub releases.';

  @override
  String get termuxStepOpen =>
      'Open Termux once and wait for its setup to finish.';

  @override
  String get termuxStepProperty =>
      'In Termux, run this command so other apps can send commands:';

  @override
  String termuxStepPermission(String app) {
    return 'Allow $app to run commands in Termux.';
  }

  @override
  String get termuxSecurityNote =>
      'This setting lets any app holding the Termux permission run commands.';

  @override
  String get openTermux => 'Open Termux';

  @override
  String get testShell => 'Test';

  @override
  String shellTestPassed(String output) {
    return 'Termux replied: $output';
  }

  @override
  String shellTestFailed(String error) {
    return 'The test failed ($error).';
  }

  @override
  String get shellTimeout => 'Command timeout (seconds)';

  @override
  String get appTagline => 'A local-first AI assistant';

  @override
  String get grantPermission => 'Allow';

  @override
  String get tabs => 'Tabs';

  @override
  String get newTab => 'New tab';

  @override
  String get closeTab => 'Close tab';

  @override
  String get blankTab => 'Blank page';

  @override
  String openedByAssistant(String app) {
    return 'Opened by $app';
  }

  @override
  String get deleteScreenshots => 'Delete screenshots with their chat';

  @override
  String get deleteScreenshotsHelp =>
      'Also when a rewind deletes later messages. Incognito chats always remove theirs.';

  @override
  String get onDeviceModels => 'On-device models';

  @override
  String get onDeviceModelsHelp => 'Run local models on this phone';

  @override
  String get onDeviceApi =>
      'On-device (llama.cpp / AICore / Apple Intelligence)';

  @override
  String get aicoreHelp =>
      'Chat with the model managed by Android AICore. Setup may need an internet connection. Compatible models can use Tako\'s tools with the usual permission checks.';

  @override
  String get aicorePreviewHelp =>
      'Preview models require enrollment in Google\'s AICore Developer Preview. Availability depends on this device and may change.';

  @override
  String get aicoreToolsUnavailable =>
      'This AICore model doesn\'t provide the structured responses Tako needs for tools. Choose a compatible preview model or turn off tools for this model.';

  @override
  String get aicoreInvalidTools =>
      'The model returned an incomplete or invalid tool request. This reply did not execute any tools. Try again.';

  @override
  String get aicoreBackground =>
      'Keep Tako in the foreground while AICore generates a reply.';

  @override
  String get aicorePrepare => 'Set up Gemini Nano';

  @override
  String get aicorePreparing =>
      'AICore is downloading or preparing Gemini Nano…';

  @override
  String get aicoreManaged => 'Model managed by Android AICore';

  @override
  String get aicoreUnavailable =>
      'This model isn\'t available through this device\'s AICore service. Update Android AICore and check device support. Preview models also require AICore Developer Preview enrollment.';

  @override
  String get aicoreUpdate =>
      'Update Android and the Android AICore app, then try again.';

  @override
  String get aicoreRequestTooLarge =>
      'This conversation is too long for Gemini Nano. Start a new chat or shorten the system prompt.';

  @override
  String get aicoreBusy => 'AICore is busy. Wait a moment and try again.';

  @override
  String get aicoreFailed =>
      'AICore couldn\'t prepare or run this model. Update Android AICore, check device support, then try again.';

  @override
  String get appleHelp =>
      'Chat with Apple\'s on-device model through Apple Intelligence, without a network connection. Needs an Apple Intelligence device with iOS 26 or later. It can use Tako\'s tools with the usual permission checks.';

  @override
  String get appleImageHelp =>
      'Create images on this device with Image Playground. Select it to generate images directly, or let a chat model call it through the image generation tool. It takes one reference image. Needs iOS 18.4 or later with Apple Intelligence turned on.';

  @override
  String get appleManaged => 'Managed by Apple Intelligence';

  @override
  String get appleCheckAgain => 'Check again';

  @override
  String get appleChecking => 'Checking Apple Intelligence…';

  @override
  String get appleUnavailable =>
      'This device doesn\'t support Apple Intelligence. It needs an iPhone 15 Pro or later, or an iPad or Mac with an M-series or A17 Pro chip.';

  @override
  String get appleUpdate =>
      'Update iOS to use this model. Apple\'s on-device model needs iOS 26 or later; Image Playground needs iOS 18.4 or later.';

  @override
  String get appleDisabled =>
      'Turn on Apple Intelligence in Settings > Apple Intelligence & Siri, wait for its models to download, then check again.';

  @override
  String get appleNotReady =>
      'Apple Intelligence is still downloading or preparing its models. Stay on Wi-Fi with the device charging, then check again.';

  @override
  String get appleRequestTooLarge =>
      'This conversation is too long for Apple\'s on-device model. Start a new chat or shorten the system prompt.';

  @override
  String get appleBusy =>
      'Apple Intelligence can\'t take more requests right now. Keep Tako open, wait a moment and try again.';

  @override
  String get appleBackground =>
      'Keep Tako in the foreground while Apple Intelligence generates.';

  @override
  String get appleGuardrail =>
      'Apple Intelligence\'s safety checks declined this request. Rephrase it, or use another model.';

  @override
  String get appleLanguage =>
      'Apple Intelligence doesn\'t support the language of this request yet. Use a supported language, or another model.';

  @override
  String get appleImageInput =>
      'Image Playground couldn\'t use this prompt or reference image. Attach at most one clear photo, or describe the image differently.';

  @override
  String get appleFailed =>
      'Apple Intelligence couldn\'t complete this request. Try again later.';

  @override
  String get onDeviceProviderHelp =>
      'Uses models stored on this phone. No URL or key needed.';

  @override
  String get manageOnDeviceModels => 'Manage on-device models';

  @override
  String get onDeviceUnavailable =>
      'This device can\'t run on-device models. They need a 64-bit Android or iOS device.';

  @override
  String get onDeviceIntro =>
      'Models run entirely on this phone; your chats aren\'t sent anywhere. Larger models answer better but need more memory and run slower.';

  @override
  String onDeviceStorage(String size) {
    return 'Models use $size';
  }

  @override
  String get installedModels => 'Installed';

  @override
  String get noLocalModels =>
      'No models yet. Download a recommended model or import a GGUF file.';

  @override
  String get modelDownloads => 'Downloading';

  @override
  String get recommendedModels => 'Recommended models';

  @override
  String get recommendedModelsHelp =>
      'Downloaded from Hugging Face and checked against their SHA-256. Tako connects only when you start a download.';

  @override
  String get otherModels => 'Other models';

  @override
  String get otherModelsHelp =>
      'Any GGUF model that llama.cpp supports works. Small models may not use tools correctly.';

  @override
  String get importModel => 'Import GGUF file';

  @override
  String get importingModel => 'Importing…';

  @override
  String get downloadFromUrl => 'Download from URL';

  @override
  String modelAdded(String name) {
    return 'Added $name';
  }

  @override
  String get modelDownloadStarted => 'Download started';

  @override
  String modelSelected(String name) {
    return 'Switched to $name';
  }

  @override
  String deleteModelBody(String name) {
    return 'Delete $name? You can download or import it again later.';
  }

  @override
  String get inMemory => 'Loaded';

  @override
  String get useInChat => 'Use in chat';

  @override
  String get addProjector => 'Add vision projector';

  @override
  String get removeProjector => 'Remove vision projector';

  @override
  String get unloadModel => 'Unload from memory';

  @override
  String get verifyingDownload => 'Checking the file…';

  @override
  String get downloadPaused => 'Paused';

  @override
  String get pauseDownload => 'Pause';

  @override
  String get resumeDownload => 'Resume download';

  @override
  String get recommendedFast => 'Fastest; runs on most phones';

  @override
  String get recommendedBalanced => 'Balances speed and quality';

  @override
  String get recommendedBest => 'Best answers; needs a recent phone';

  @override
  String get recommendedVision =>
      'Sees images when downloaded with image input';

  @override
  String memoryNeeded(int gb) {
    return '$gb GB+ memory recommended';
  }

  @override
  String downloadWithVision(String size) {
    return 'Download with image input ($size)';
  }

  @override
  String get modelUrl => 'URL';

  @override
  String get modelUrlHelp =>
      'A direct link to a GGUF file, such as a Hugging Face \"resolve\" link. Tako connects only to this address, and only over HTTPS outside your local network.';

  @override
  String get modelErrorNotGguf => 'This is not a GGUF model file.';

  @override
  String get modelErrorIsProjector =>
      'This is a vision projector. Add it from a model\'s menu with \"Add vision projector\".';

  @override
  String get modelErrorNotProjector => 'This is not a vision projector.';

  @override
  String get modelErrorExists => 'A model with this name already exists.';

  @override
  String get modelErrorUrl =>
      'Only HTTPS URLs, or HTTP inside your local network.';

  @override
  String get modelErrorChecksum =>
      'The file doesn\'t match what was expected and was deleted.';

  @override
  String get modelErrorSize =>
      'The file size doesn\'t match what was expected.';

  @override
  String get modelErrorNoSpace => 'Not enough storage.';

  @override
  String get modelErrorNetwork =>
      'The connection was interrupted. You can resume the download.';

  @override
  String modelErrorHttp(String status) {
    return 'The server answered HTTP $status.';
  }

  @override
  String get loadingModel => 'Loading the model…';

  @override
  String get localModelMissing =>
      'This model file is no longer on the phone. Download or import it again under On-device models.';

  @override
  String get localModelLoad =>
      'Couldn\'t load the model. The phone may be out of memory, or this llama.cpp version may not support it. Try a smaller model or a shorter context.';

  @override
  String get shortcuts => 'Shortcuts';

  @override
  String get shortcutsHelp => 'Let Tako run Shortcuts you choose';

  @override
  String get shortcutsIntro =>
      'iOS doesn\'t let apps list your Shortcuts. Enter the names of the ones Tako may use, exactly as they appear in the Shortcuts app. Tako asks before every run.';

  @override
  String get addShortcut => 'Add Shortcut';

  @override
  String get shortcutName => 'Shortcut name';

  @override
  String get noShortcuts => 'No Shortcuts yet.';

  @override
  String get listShortcutsTool => 'List Shortcuts';

  @override
  String get runShortcutTool => 'Run Shortcut';

  @override
  String get useOnDeviceModel => 'Run a model on this phone';

  @override
  String get preferSpeed => 'Prefer speed';

  @override
  String get preferSpeedHelp =>
      'Uses more processor cores: faster answers, but the phone may stutter. When off, one core is left for the system so the phone stays smooth.';

  @override
  String get visualDrawing => 'Drawing…';

  @override
  String get visualFailed => 'Couldn\'t draw this. Showing the source.';

  @override
  String get visualShowTable => 'Show as table';

  @override
  String get visualShowChart => 'Show chart';

  @override
  String get visualShowCode => 'Show code';

  @override
  String get visualShowDiagram => 'Show diagram';

  @override
  String get visualFullScreen => 'Full screen';

  @override
  String get visualShareImage => 'Share image';

  @override
  String get visualShareFailed => 'Couldn\'t share the image.';

  @override
  String get visualOther => 'Other';

  @override
  String get visualTotal => 'Total';

  @override
  String get visualSourcePrefix => 'Source: ';

  @override
  String get visualChart => 'Chart';

  @override
  String get visualFlowchart => 'Flowchart';

  @override
  String get visualSequence => 'Sequence diagram';

  @override
  String get visualMindmap => 'Mind map';

  @override
  String get calloutNote => 'Note';

  @override
  String get calloutTip => 'Tip';

  @override
  String get calloutImportant => 'Important';

  @override
  String get calloutWarning => 'Warning';

  @override
  String get calloutCaution => 'Caution';
}
