// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get toolRunIncomplete => 'No result recorded';

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
  String get maxToolSteps => 'Maximum tool calls per turn';

  @override
  String get maxScreenToolSteps =>
      'Maximum tool calls per turn when controlling the screen';

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
  String get visionRequired => 'Choose a vision-capable model to send images.';

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
      'Add a cloud provider or a local server to start chatting. You choose where your messages go.';

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
      'Chats and memories are saved on this device. When you chat, your messages and what tools read, such as the screen or notifications, are sent to your selected model provider. API keys and extra headers are stored in secure storage. No accounts, analytics, or telemetry.';

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
    return '$app is controlling the screen';
  }

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
}
