// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get controlToolMode => '瀏覽器與手機操控';

  @override
  String get controlToolModeAuto => '自動';

  @override
  String get controlToolModeBasic => '基礎工具';

  @override
  String get controlToolModeRepl => 'JavaScript REPL';

  @override
  String get controlToolModeHelp =>
      '自動模式讓遠端 API 模型使用 REPL，裝置端與本機伺服器模型使用基礎工具。REPL 可用 JavaScript 組合操作，每個動作仍需經過工具權限。';

  @override
  String get readSkillTool => '載入操作指引';

  @override
  String get jsReplTool => '執行 JavaScript';

  @override
  String get toolLoopDetected => '已阻止重复的工具循环。请查看模型说明，需要尝试其他方式时按「继续」。';

  @override
  String get appUpdates => '应用更新';

  @override
  String get appUpdatesHelp => '从 GitHub nightly 检查并安装 Android full 版本更新。';

  @override
  String get installedVersion => '已安装版本';

  @override
  String get checkUpdates => '检查更新';

  @override
  String get downloadUpdate => '下载并安装';

  @override
  String get updateAvailable => '有可用更新。';

  @override
  String get updateCurrent => '目前已是最新 nightly 版本。';

  @override
  String get updateCheckFailed => '无法检查更新，请稍后再试。';

  @override
  String get updateInstallPermission =>
      '请在 Android 设置中允许 Tako 安装应用，返回后再次点击下载并安装。';

  @override
  String get updateInstallerOpened => 'Android 已开启安装确认画面。';

  @override
  String get updateInstallFailed => '无法下载或安装更新，请检查网络，并确认已安装的应用使用正式版本签章。';

  @override
  String get generateChatTitle => '生成对话标题';

  @override
  String get titleGenerationFailed => '标题生成失败，已保留原本的标题。';

  @override
  String toolRunSummary(String tool, int count) {
    return '$tool · $count 個步驟';
  }

  @override
  String get toolRunTitle => '工具執行過程';

  @override
  String get toolRunIncomplete => '未完成';

  @override
  String get toolRunUnavailable => '目前的對話分支已不包含這段工具執行過程。';

  @override
  String get undo => '復原';

  @override
  String get deleteAttachmentBody =>
      '此附件可能仍被較早的對話使用。刪除後，相關圖片／檔案將無法讀取；操作後會提供備份與復原。';

  @override
  String get toolsSettings => '工具與權限';

  @override
  String get toolsEnabled => '啟用工具';

  @override
  String get maxToolSteps => '达到此工具调用次数后开始检测循环';

  @override
  String get maxScreenToolSteps => '操控屏幕达到此调用次数后开始检测循环';

  @override
  String get toolOutputLimit => '工具結果長度上限（字元）';

  @override
  String get permissions => '權限';

  @override
  String get fullPermissions => '完整權限';

  @override
  String get fullPermissionsWarning => '讀取私人資料及可復原的操作將不再詢問。高風險操作仍需逐次確認。';

  @override
  String get skipHighRisk => '也略過高風險確認';

  @override
  String get skipHighRiskWarning => '工具將能傳送資料、刪除檔案或進行變更，而不再逐次確認。僅在你接受這些操作時啟用。';

  @override
  String get toolOverrides => '個別工具';

  @override
  String get defaultPolicy => '預設規則';

  @override
  String get alwaysAllow => '永遠允許此工具';

  @override
  String get alwaysAsk => '每次詢問';

  @override
  String get deny => '拒絕';

  @override
  String get allowOnce => '允許這一次';

  @override
  String get allowChat => '此對話允許';

  @override
  String get approvalTitle => '工具操作確認';

  @override
  String get approvalBody => '請確認操作內容與完整參數，再決定是否允許。';

  @override
  String get riskSafe => '安全';

  @override
  String get riskSensitive => '讀取私人資料';

  @override
  String get riskAction => '進行變更';

  @override
  String get riskHigh => '高風險操作';

  @override
  String get auditLog => '工具活動紀錄';

  @override
  String get clearAudit => '清除紀錄';

  @override
  String get clearAuditBody => '刪除本機的工具活動紀錄？';

  @override
  String get noAudit => '尚無工具活動。';

  @override
  String get arguments => '參數';

  @override
  String get result => '結果';

  @override
  String get search => '網路搜尋';

  @override
  String get searchProvider => '搜尋供應商';

  @override
  String get searchUrl => '搜尋端點';

  @override
  String get searchKey => '搜尋 API 金鑰';

  @override
  String get searchResults => '結果筆數';

  @override
  String get searchHelp => '搜尋金鑰保存在安全儲存空間，各供應商分開保存。';

  @override
  String get searchKeyHint => '安全儲存在此裝置上';

  @override
  String get searchOptionalToken => 'Bearer 權杖（選填）';

  @override
  String get searchSerperHelp =>
      '透過 Serper 搜尋 Google。填入 Serper API 金鑰即可使用預設端點。';

  @override
  String get searchDdgsHelp =>
      '填入你的 DDGS API 服務網址（ddgs api）。一般不需金鑰；若服務或反向代理採用 Bearer 驗證，可填入權杖。';

  @override
  String get searchSearxngHelp => '填入你的 SearXNG 服務網址，伺服器必須啟用 JSON 搜尋結果。';

  @override
  String get files => '檔案';

  @override
  String get attach => '附加圖片或文件';

  @override
  String get camera => '相機';

  @override
  String get photos => '相片';

  @override
  String get attachmentBusy => '請等目前的操作完成後，再加入圖片。';

  @override
  String get attachmentLimit => '每則訊息最多可附加 8 個圖片或檔案。';

  @override
  String get imageUnavailable => '無法讀取這張圖片，請改由「相片」或「檔案」選取。';

  @override
  String get unsupportedImage => '不支援此圖片格式，請選取 PNG、JPEG、GIF 或 WebP 圖片。';

  @override
  String get importFiles => '匯入檔案';

  @override
  String get emptyFiles => '工作區目前沒有檔案。';

  @override
  String get filePreview => '檔案預覽';

  @override
  String get deleteFileBody => '刪除此工作區檔案？會保留一份備份。';

  @override
  String get workspace => '工作區';

  @override
  String get restoreFiles => '還原工作區檔案';

  @override
  String get sideEffectsTitle => '這些操作已經發生';

  @override
  String get sideEffectsBody => '回溯對話不會撤銷以下操作。你可以先還原可用的工作區備份，以及移除之後新存入的記憶。';

  @override
  String get restoreAndRewind => '還原並回溯';

  @override
  String get rewindOnly => '只回溯對話';

  @override
  String get visionRequired => '请选择支持视觉或参考图的模型，再发送图片。';

  @override
  String get toolStepLimit => '已達工具呼叫上限。請檢查目前結果，需要時按「繼續」。';

  @override
  String get toolRunning => '執行中';

  @override
  String get toolWaiting => '等待中';

  @override
  String get toolCompleted => '已完成';

  @override
  String get toolFailed => '失敗';

  @override
  String get toolsUnavailable => '請在此模型的能力設定中啟用工具呼叫，才能使用工具。';

  @override
  String get deviceStatusTool => '讀取裝置狀態';

  @override
  String get locationTool => '讀取位置';

  @override
  String get clipboardReadTool => '讀取剪貼簿';

  @override
  String get clipboardWriteTool => '寫入剪貼簿';

  @override
  String get calendarListTool => '讀取行事曆';

  @override
  String get calendarAddTool => '新增行事曆活動';

  @override
  String get alarmTool => '設定鬧鐘';

  @override
  String get timerTool => '設定計時器';

  @override
  String get openUrlTool => '開啟網址';

  @override
  String get openAppTool => '開啟 App';

  @override
  String get searchTool => '搜尋網路';

  @override
  String get fetchTool => '讀取網頁';

  @override
  String get fileListTool => '列出檔案';

  @override
  String get fileReadTool => '讀取檔案';

  @override
  String get fileWriteTool => '寫入檔案';

  @override
  String get fileDeleteTool => '刪除檔案';

  @override
  String get toolDisabled => '無法使用';

  @override
  String get highRiskKeywords => '高風險關鍵字（每行一個）';

  @override
  String get importFailed => '無法匯入所選檔案。';

  @override
  String get restoreFailed => '有備份無法還原，對話尚未回溯。';

  @override
  String get toolResultAttachment => '工具附件';

  @override
  String get noBackup => '沒有工作區備份';

  @override
  String get systemPermissionHint => '允許後，Android 可能會再詢問系統權限。';

  @override
  String get newChat => '新對話';

  @override
  String get chats => '對話';

  @override
  String get settings => '設定';

  @override
  String get providers => '模型供應商';

  @override
  String get addProvider => '新增供應商';

  @override
  String get editProvider => '編輯供應商';

  @override
  String get noProviders => '連接你的模型';

  @override
  String get welcome => '留一點空間，好好想想。';

  @override
  String get welcomeBody => '提問、探索，或一起理清思緒。對話保存在這台裝置上。';

  @override
  String get setupBody => '新增雲端供應商、本機伺服器或裝置上模型，即可開始聊天。由你決定訊息送往哪裡。';

  @override
  String get messageHint => '想問什麼？';

  @override
  String get send => '傳送';

  @override
  String get stop => '停止';

  @override
  String get retry => '重試';

  @override
  String get save => '儲存';

  @override
  String get cancel => '取消';

  @override
  String get delete => '刪除';

  @override
  String get close => '關閉';

  @override
  String get copy => '複製';

  @override
  String get copyMarkdown => '複製 Markdown';

  @override
  String get selectText => '選取文字';

  @override
  String get copied => '已複製';

  @override
  String get share => '分享';

  @override
  String get edit => '編輯';

  @override
  String get regenerate => '重新生成';

  @override
  String get rewind => '回到這裡';

  @override
  String get rewindDelete => '回到這裡並刪除後續';

  @override
  String get rewindDeleteBody => '刪除此訊息之後的所有分支？此操作無法復原。';

  @override
  String get deleteChatBody => '刪除此對話及所有分支？';

  @override
  String get thinking => '思考過程';

  @override
  String get you => '你';

  @override
  String get image => '圖片';

  @override
  String get file => '檔案';

  @override
  String get stopped => '已停止';

  @override
  String get streaming => '正在撰寫⋯';

  @override
  String get providerName => '顯示名稱';

  @override
  String get apiType => 'API 格式';

  @override
  String get baseUrl => '基底網址';

  @override
  String get apiKey => 'API 金鑰';

  @override
  String get keyHint => '本機伺服器可留空';

  @override
  String get keyStored => '金鑰已安全儲存 · 留空以保留';

  @override
  String get removeKey => '移除已儲存的金鑰';

  @override
  String get model => '模型';

  @override
  String get modelHint => '輸入模型 ID 或載入清單';

  @override
  String get loadModels => '載入模型';

  @override
  String get testConnection => '測試連線';

  @override
  String get connectionOk => '連線成功，模型清單可用。';

  @override
  String get connectionHelp => '測試模型清單端點。若供應商不支援此端點，仍可手動輸入模型。';

  @override
  String get extraHeaders => '額外標頭（JSON 物件）';

  @override
  String get headersHint => '與金鑰一起安全儲存';

  @override
  String get headersStored => '標頭已安全儲存 · 留空以保留';

  @override
  String get removeHeaders => '移除已儲存的標頭';

  @override
  String get localProvider => '本機供應商';

  @override
  String get localDescription => '自動辨識回環與區域網路位址，也可以手動設定。';

  @override
  String get toolsCapability => '工具呼叫';

  @override
  String get visionCapability => '視覺';

  @override
  String get visionCapabilityHelp => '让模型理解聊天中的图片。图片生成需要单独设置。';

  @override
  String get imageGeneration => '图片生成';

  @override
  String get imageGenerationNone => '关闭';

  @override
  String get imageGenerationImagesApi => 'Images API';

  @override
  String get imageGenerationChatOutput => '聊天中输出图片';

  @override
  String get imageGenerationResponsesTool => 'Responses 生图工具';

  @override
  String get imageGenerationOnDevice => '在这台设备上';

  @override
  String get imageGenerationHelp =>
      '选择此模型支持的生图格式。你可以直接选择它生成图片，也可以让聊天模型通过生图工具调用它。';

  @override
  String get imageGenerationProtocolHelp =>
      '图片生成需要兼容 OpenAI Chat Completions 或 Responses 的供应商。';

  @override
  String get imageReferenceInput => '参考图';

  @override
  String get imageReferenceInputHelp => '允许将附件图片用于参考生图或编辑。仅在此模型支持生图图片输入时开启。';

  @override
  String get imageGenerationTool => '生成图片';

  @override
  String get reasoningCapability => '推理';

  @override
  String get capabilities => '模型能力';

  @override
  String get contextWindow => '上下文長度（token）';

  @override
  String get maxOutput => '輸出上限（token）';

  @override
  String get reasoningMode => '推理模式';

  @override
  String get reasoningOff => '供應商預設';

  @override
  String get reasoningEnabled => '啟用（預算）';

  @override
  String get reasoningAdaptive => '自適應';

  @override
  String get thinkingBudget => '思考預算（token）';

  @override
  String get reasoningEffort => '推理強度';

  @override
  String get requiredField => '必填';

  @override
  String get invalidUrl => '請輸入 http(s) 網址，不含帳密、查詢參數或片段。';

  @override
  String get invalidJson => '請輸入標頭值為字串的 JSON 物件。';

  @override
  String get invalidNumber => '請輸入正整數。';

  @override
  String get invalidBudget => '輸出上限須小於上下文長度。思考預算須至少為 1024，且小於輸出上限。';

  @override
  String get operationFailed => '操作失敗，請再試一次。';

  @override
  String get fileUnavailable => '此工作區檔案目前無法使用。';

  @override
  String get contextTrimmed => '已裁剪較舊的上下文以符合模型限制';

  @override
  String get contextTooLarge => '此訊息超過模型上下文長度，請縮短訊息或在供應商設定中調整長度。';

  @override
  String get noProviderSelected => '請先在設定中選擇供應商。';

  @override
  String get providerRemoved => '此對話的供應商已無法使用，請選擇其他供應商。';

  @override
  String get changeProvider => '更換供應商';

  @override
  String get changeProviderBody => '對話將由此供應商繼續。可見的對話歷史會傳送給它，系統提示詞也會重新產生。';

  @override
  String get continueAction => '繼續';

  @override
  String get appearance => '外觀';

  @override
  String get theme => '主題';

  @override
  String get systemTheme => '跟隨系統';

  @override
  String get lightTheme => '淺色';

  @override
  String get darkTheme => '深色';

  @override
  String get textSize => '文字大小';

  @override
  String get language => '語言';

  @override
  String get privacy => '以本機為本';

  @override
  String get privacyBody =>
      '對話與記憶保存在此裝置。聊天時，你的訊息以及工具讀到的內容（例如畫面或通知）會傳送給你選擇的模型供應商；使用裝置上模型時，這些內容不會離開這支手機。API 金鑰與額外標頭保存在安全儲存空間。沒有帳號、分析或遙測。';

  @override
  String get about => '關於';

  @override
  String get developerContext => '已儲存的上下文';

  @override
  String get noChats => '你的對話會顯示在這裡。';

  @override
  String get chooseProvider => '選擇供應商';

  @override
  String get previousBranch => '上一個分支';

  @override
  String get nextBranch => '下一個分支';

  @override
  String get providerDeleteBody => '移除此供應商及其憑證？對話將予以保留。';

  @override
  String get emptyResponse => '供應商未回傳回覆，請重試或檢查模型設定。';

  @override
  String get toolsLater => '此請求尚未啟用工具，或工具目前無法使用。';

  @override
  String get builtInSearch => '供應商內建網路搜尋';

  @override
  String get builtInSearchHelp => '使用模型供應商的原生搜尋；關閉時使用「搜尋」設定中的供應商。仍受工具權限規則控制。';

  @override
  String get allowCustomSearchEndpoint => '允許相容代理（CPA）';

  @override
  String get allowCustomSearchEndpointHelp =>
      '向此自訂端點送出原生搜尋工具。代理必須保留 Responses 或 Messages 搜尋格式；未開啟時只自動允許官方端點。';

  @override
  String get testNativeSearch => '測試原生搜尋';

  @override
  String get nativeSearchTesting => '正在測試原生搜尋⋯';

  @override
  String get nativeSearchTestHelp =>
      '使用目前模型與端點搜尋一次 Flutter 官方網站，可能產生 API 費用。不會傳送對話紀錄、自動啟用搜尋或儲存設定。';

  @override
  String get nativeSearchSupported => '測試成功：供應商確實完成了原生搜尋。';

  @override
  String get nativeSearchNotObserved =>
      '端點有回應，但未收到原生搜尋完成紀錄。可能是代理移除了搜尋工具，或此轉送路徑不支援。';

  @override
  String get nativeSearchProtocolHelp =>
      '此處的原生搜尋需使用 OpenAI Responses 或 Anthropic Messages。Chat Completions 請搭配「搜尋」設定中的供應商。';

  @override
  String get nativeSearchDisabled => '請先在「工具與權限」啟用工具與網路搜尋。';

  @override
  String get nativeSearchDenied => '這次測試已被網路搜尋權限規則拒絕。';

  @override
  String get nativeSearchFailed => '原生搜尋測試失敗，請確認模型與代理轉送路徑支援原生搜尋。';

  @override
  String get nativeSearchCancelled => '已取消原生搜尋測試。';

  @override
  String get nativeSearchTimeout => '原生搜尋測試逾時，已取消請求。';

  @override
  String get nativeSearchBusy => '請等待目前工作結束後再測試。';

  @override
  String get localLabel => '本機';

  @override
  String get cloudLabel => '雲端';

  @override
  String get connectionFailed => '連線失敗';

  @override
  String get noModels => '未取得模型，請手動輸入模型 ID。';

  @override
  String get viewImage => '檢視圖片';

  @override
  String get openImageLink => '在瀏覽器開啟圖片';

  @override
  String get renameChat => '重新命名對話';

  @override
  String get chatTitle => '對話標題';

  @override
  String get messageActions => '訊息選項';

  @override
  String get models => '模型';

  @override
  String get addModel => '新增模型';

  @override
  String get addModels => '加入所選模型';

  @override
  String get newModel => '新模型';

  @override
  String get duplicateModel => '此模型已經加入。';

  @override
  String get autoModelSpecs => '自動辨識模型規格';

  @override
  String get knownModelSpecs => '已套用已知規格，可自行調整限制與能力。';

  @override
  String get unknownModelSpecs => '未知模型：目前使用預設值，請依伺服器支援的規格調整。';

  @override
  String get officialModelId => '官方 API 模型 ID';

  @override
  String get chooseModel => '選擇模型';

  @override
  String get memory => '記憶';

  @override
  String get memoryEnabled => '使用記憶';

  @override
  String memoryEnabledHelp(String app) {
    return '$app 可以儲存並查詢你提供的長期資訊。釘選的個人檔案與偏好會加入新的對話。';
  }

  @override
  String get memoryOff => '記憶已關閉。已儲存的記憶會保留，但不會在對話中使用。';

  @override
  String get memorySearchHint => '搜尋記憶';

  @override
  String memoryEmpty(String app) {
    return '還沒有記憶。可以請 $app 記住某件事，或在這裡新增。';
  }

  @override
  String get memoryNoMatches => '沒有符合的記憶。';

  @override
  String get addMemory => '新增記憶';

  @override
  String get editMemory => '編輯記憶';

  @override
  String get memoryText => '內容';

  @override
  String get memoryKind => '類型';

  @override
  String get memoryKindProfile => '個人檔案';

  @override
  String get memoryKindPreference => '偏好';

  @override
  String get memoryKindFact => '事實';

  @override
  String get memoryPinned => '已釘選';

  @override
  String get memoryPin => '釘選';

  @override
  String get memoryUnpin => '取消釘選';

  @override
  String get memoryPinHelp => '釘選的個人檔案與偏好會加入新的對話。';

  @override
  String memoryProfileUsage(int words, int limit) {
    return '釘選的個人檔案：$words/$limit 字';
  }

  @override
  String get memoryProfileTruncated => '部分釘選內容超出上限，不會加入新的對話。';

  @override
  String get memoryFromChat => '從對話中儲存';

  @override
  String get deleteMemoryBody => '要刪除這則記憶嗎？';

  @override
  String get deleteAllMemories => '刪除所有記憶';

  @override
  String get deleteAllMemoriesBody => '要刪除所有已儲存的記憶嗎？此操作無法復原。';

  @override
  String get exportMemories => '匯出 JSON';

  @override
  String get importMemories => '匯入 JSON';

  @override
  String memoriesImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已匯入 $count 則記憶',
      zero: '沒有匯入新的記憶',
    );
    return '$_temp0';
  }

  @override
  String memoryImportFailed(String app) {
    return '這不是有效的 $app 記憶匯出檔。';
  }

  @override
  String get memorySaved => '已存入記憶';

  @override
  String get memoryUndone => '已從記憶移除';

  @override
  String get memoryChanged => '儲存後已被修改或移除';

  @override
  String get personalization => '個人化';

  @override
  String displayName(String app) {
    return '$app 該怎麼稱呼你？';
  }

  @override
  String get customInstructions => '自訂指示';

  @override
  String customInstructionsHint(String app) {
    return '希望 $app 在每個新對話中都知道或遵守的事';
  }

  @override
  String get replyStyle => '回覆風格';

  @override
  String get replyConcise => '簡潔';

  @override
  String get replyNormal => '一般';

  @override
  String get replyDetailed => '詳細';

  @override
  String get personalizationHelp => '變更會套用到新的對話；既有對話維持開始時的設定。';

  @override
  String get incognitoChat => '無痕聊天';

  @override
  String get newIncognitoChat => '新增無痕聊天';

  @override
  String get incognitoBody => '不使用記憶，離開後這段對話會被刪除。';

  @override
  String get browser => '瀏覽器';

  @override
  String get openBrowser => '開啟瀏覽器';

  @override
  String get browserAddressHint => '輸入網址';

  @override
  String get browserInvalidAddress => '請輸入網址，例如 example.com。';

  @override
  String browserEmpty(String app) {
    return '輸入網址，或請 $app 開啟網頁。';
  }

  @override
  String browserModelActive(String app) {
    return '$app 正在使用瀏覽器';
  }

  @override
  String get takeOver => '接手操作';

  @override
  String get browserBack => '上一頁';

  @override
  String get browserForward => '下一頁';

  @override
  String get browserReload => '重新載入';

  @override
  String get openExternally => '在其他應用程式開啟';

  @override
  String get clearBrowsingData => '清除瀏覽資料';

  @override
  String get clearBrowsingDataBody =>
      '要刪除內建瀏覽器的 Cookie、網站儲存資料、快取與瀏覽紀錄嗎？你將會登出各個網站。';

  @override
  String get browsingDataCleared => '已清除瀏覽資料';

  @override
  String get openLinksInApp => '在內建瀏覽器開啟連結';

  @override
  String get openLinksInAppHelp => '關閉時，連結會以預設瀏覽器開啟。內建瀏覽器的 Cookie 與其他瀏覽器分開保存。';

  @override
  String get browserUnavailable => '此裝置無法使用內建瀏覽器。';

  @override
  String get downloadTitle => '要下載檔案嗎？';

  @override
  String downloadBody(String name, String host) {
    return '要將來自 $host 的「$name」儲存到檔案嗎？';
  }

  @override
  String get download => '下載';

  @override
  String get downloadSaved => '已儲存到檔案';

  @override
  String get downloadFailed => '下載失敗。';

  @override
  String get downloadTooLarge => '無法下載超過 20 MB 的檔案。';

  @override
  String get approvalElement => '元素';

  @override
  String get approvalPage => '網頁';

  @override
  String get approvalSubmit => '送出按鈕';

  @override
  String get memorySearchTool => '搜尋記憶';

  @override
  String get memorySaveTool => '存入記憶';

  @override
  String get memoryUpdateTool => '更新記憶';

  @override
  String get memoryDeleteTool => '刪除記憶';

  @override
  String get browserStartSessionTool => '開啟瀏覽器工作階段';

  @override
  String get browserOpenTool => '開啟網頁';

  @override
  String get browserReadTool => '讀取瀏覽器頁面';

  @override
  String get browserClickTool => '在瀏覽器中點擊';

  @override
  String get browserTypeTool => '在瀏覽器中輸入';

  @override
  String get browserScrollTool => '捲動瀏覽器頁面';

  @override
  String get browserBackTool => '瀏覽器上一頁';

  @override
  String get readScreenTool => '讀取螢幕';

  @override
  String get tapTool => '點按螢幕';

  @override
  String get longPressTool => '長按螢幕';

  @override
  String get swipeTool => '在螢幕上滑動';

  @override
  String get scrollTool => '捲動螢幕';

  @override
  String get typeTextTool => '在螢幕上輸入';

  @override
  String get pressKeyTool => '按系統鍵';

  @override
  String get runShellTool => '執行 Shell 指令';

  @override
  String get notificationsListTool => '讀取通知';

  @override
  String get approvalApp => 'App';

  @override
  String get approvalPoint => '位置';

  @override
  String screenSessionTitle(String app) {
    return '$app 正在使用你的手機';
  }

  @override
  String get screenSessionThinking => '正在思考下一步…';

  @override
  String get screenSessionWaiting => '等待你的核准…';

  @override
  String get screenSessionBody => '點「停止」即可接手。';

  @override
  String get screenChannel => '螢幕控制';

  @override
  String get alertChannel => '核准與回覆';

  @override
  String approvalNeededTitle(String app) {
    return '$app 需要你的核准';
  }

  @override
  String get approvalNeededBody => '開啟 App 查看這項要求。';

  @override
  String replyReadyTitle(String app) {
    return '$app 已回覆';
  }

  @override
  String get replyReadyBody => '點一下查看回覆。';

  @override
  String get deviceControl => '裝置控制';

  @override
  String deviceControlHelp(String app) {
    return '讓 $app 使用其他 App、你的通知與 Termux。每一項都要在 Android 設定中開啟，所有操作仍需經過工具權限。';
  }

  @override
  String get screenControl => '螢幕控制';

  @override
  String get statusOn => '已開啟';

  @override
  String get statusOff => '未開啟';

  @override
  String get screenControlUnsupported => '這個版本不含螢幕控制功能。';

  @override
  String screenControlHelp(String app) {
    return '$app 只會在你要求時，透過已核准的工具讀取畫面，並在其他 App 中點按、輸入和捲動。「傳送」、「付款」、「刪除」等按鈕一定會先詢問，也永遠不會填入密碼欄位。';
  }

  @override
  String get screenControlDisclosureTitle => '要開啟螢幕控制嗎？';

  @override
  String screenControlDisclosure(String app) {
    return '$app 會使用 Android 的無障礙服務讀取畫面內容，並替你點按、輸入和捲動。只有螢幕工具執行時才會讀取畫面；讀到的內容會傳送給你選擇的模型供應商並保留在該對話中，不會用於其他用途。請在下一個畫面中找到 $app 並開啟。';
  }

  @override
  String get openAccessibilitySettings => '開啟無障礙設定';

  @override
  String get restrictedSettingsHelp =>
      '如果 Android 顯示這是「受限制的設定」，請開啟應用程式資訊，點右上角的 ⋮ 選單並選擇「允許受限制的設定」，再試一次。';

  @override
  String get openAppInfo => '開啟應用程式資訊';

  @override
  String get screenshotsSetting => '傳送截圖給視覺模型';

  @override
  String get screenshotsHelp =>
      '模型支援圖片時，read_screen 也會附上截圖。截圖包含畫面上的所有內容，也會使用較多 token。';

  @override
  String get screenshotsUnsupported => '截圖需要 Android 11 以上版本。';

  @override
  String get sessionNotification => '操作螢幕時的通知';

  @override
  String get sessionNotificationHelp => '顯示目前正在操作螢幕，並提供「停止」按鈕。';

  @override
  String get allowNotifications => '允許通知';

  @override
  String get allowed => '已允許';

  @override
  String get notificationAccess => '通知存取';

  @override
  String notificationAccessHelp(String app) {
    return '讓 $app 在你要求時讀取目前的通知。不會在背景讀取或保存。';
  }

  @override
  String get openNotificationAccess => '開啟通知存取設定';

  @override
  String get termux => 'Termux（run_shell）';

  @override
  String get termuxHelp =>
      'run_shell 會在 Termux 中執行指令。ls、cat 等唯讀指令視為讀取私人資料；其他指令每次都會詢問。';

  @override
  String get termuxNotInstalled =>
      '尚未安裝 Termux。請從 F-Droid 或 Termux 的 GitHub Releases 安裝。';

  @override
  String get termuxStepOpen => '開啟 Termux 一次，等待初始設定完成。';

  @override
  String get termuxStepProperty => '在 Termux 執行以下指令，讓其他 App 可以傳送指令：';

  @override
  String termuxStepPermission(String app) {
    return '允許 $app 在 Termux 中執行指令。';
  }

  @override
  String get termuxSecurityNote => '這項設定會讓任何取得 Termux 權限的 App 都能執行指令。';

  @override
  String get openTermux => '開啟 Termux';

  @override
  String get testShell => '測試';

  @override
  String shellTestPassed(String output) {
    return 'Termux 回應：$output';
  }

  @override
  String shellTestFailed(String error) {
    return '測試失敗（$error）。';
  }

  @override
  String get shellTimeout => '指令逾時（秒）';

  @override
  String get appTagline => '本機優先的 AI 助理';

  @override
  String get grantPermission => '允許';

  @override
  String get tabs => '分頁';

  @override
  String get newTab => '新增分頁';

  @override
  String get closeTab => '關閉分頁';

  @override
  String get blankTab => '空白頁';

  @override
  String openedByAssistant(String app) {
    return '由 $app 開啟';
  }

  @override
  String get deleteScreenshots => '刪除對話時一併刪除截圖';

  @override
  String get deleteScreenshotsHelp => '回溯並刪除之後的訊息時也一樣。無痕聊天一律刪除。';

  @override
  String get onDeviceModels => '裝置上模型';

  @override
  String get onDeviceModelsHelp => '在這支手機上直接執行本地模型';

  @override
  String get onDeviceApi => '裝置上（llama.cpp / AICore / Apple Intelligence）';

  @override
  String get aicoreHelp =>
      '與 Android AICore 管理的模型聊天，首次設定可能需要網路連線。相容模型可使用 Tako 的工具，並沿用原有的權限檢查。';

  @override
  String get aicorePreviewHelp =>
      '預覽版模型需要加入 Google 的 AICore Developer Preview，能否使用取決於裝置，且可能隨版本變動。';

  @override
  String get aicoreToolsUnavailable =>
      '這個 AICore 模型無法提供 Tako 工具所需的結構化回覆。請選用相容的預覽版模型，或關閉這個模型的工具能力。';

  @override
  String get aicoreInvalidTools => '模型回傳了不完整或無效的工具請求，這次回覆未執行任何工具。請再試一次。';

  @override
  String get aicoreBackground => '請讓 Tako 保持在前景，讓 AICore 繼續生成回覆。';

  @override
  String get aicorePrepare => '設定 Gemini Nano';

  @override
  String get aicorePreparing => 'AICore 正在下載或準備 Gemini Nano…';

  @override
  String get aicoreManaged => '模型由 Android AICore 管理';

  @override
  String get aicoreUnavailable =>
      '這台裝置的 AICore 服務無法提供這個模型。請更新 Android AICore 並確認裝置支援；預覽版模型還需要加入 AICore Developer Preview。';

  @override
  String get aicoreUpdate => '請更新 Android 系統及 Android AICore 應用程式後再試。';

  @override
  String get aicoreRequestTooLarge =>
      '這段對話超過 Gemini Nano 可處理的長度。請開啟新對話或縮短系統提示詞。';

  @override
  String get aicoreBusy => 'AICore 正忙碌，請稍候再試。';

  @override
  String get aicoreFailed => 'AICore 無法準備或執行這個模型。請更新 Android AICore、確認裝置支援後再試。';

  @override
  String get appleHelp =>
      '透過 Apple Intelligence 與 Apple 的裝置端模型聊天，不需要網路連線。需要支援 Apple Intelligence 的裝置與 iOS 26 以上版本。可使用 Tako 的工具，並沿用原有的權限檢查。';

  @override
  String get appleImageHelp =>
      '用 Image Playground 在這台裝置上生成圖片。可以直接選它來生圖，也可以讓聊天模型透過生圖工具呼叫它，並可附上一張參考圖片。需要 iOS 18.4 以上版本，並開啟 Apple Intelligence。';

  @override
  String get appleManaged => '由 Apple Intelligence 管理';

  @override
  String get appleCheckAgain => '重新檢查';

  @override
  String get appleChecking => '正在檢查 Apple Intelligence…';

  @override
  String get appleUnavailable =>
      '這台裝置不支援 Apple Intelligence。需要 iPhone 15 Pro 或更新的機型，或搭載 M 系列、A17 Pro 晶片的 iPad 或 Mac。';

  @override
  String get appleUpdate =>
      '請更新 iOS 才能使用這個模型。Apple 裝置端模型需要 iOS 26 以上，Image Playground 需要 iOS 18.4 以上。';

  @override
  String get appleDisabled =>
      '請到「設定」>「Apple Intelligence 與 Siri」開啟 Apple Intelligence，等模型下載完成後再重新檢查。';

  @override
  String get appleNotReady =>
      'Apple Intelligence 仍在下載或準備模型。請保持 Wi-Fi 連線並接上電源，稍後再重新檢查。';

  @override
  String get appleRequestTooLarge => '這段對話超過 Apple 裝置端模型可處理的長度。請開啟新對話或縮短系統提示詞。';

  @override
  String get appleBusy => 'Apple Intelligence 暫時無法處理更多請求。請讓 Tako 保持開啟，稍候再試。';

  @override
  String get appleBackground => '請讓 Tako 保持在前景，Apple Intelligence 才能繼續生成。';

  @override
  String get appleGuardrail => 'Apple Intelligence 的安全檢查拒絕了這個請求。請換個說法，或改用其他模型。';

  @override
  String get appleLanguage =>
      'Apple Intelligence 目前不支援這個請求的語言。請改用支援的語言，或改用其他模型。';

  @override
  String get appleImageInput =>
      'Image Playground 無法使用這個提示或參考圖片。請最多附上一張清楚的照片，或換個方式描述。';

  @override
  String get appleFailed => 'Apple Intelligence 無法完成這個請求，請稍後再試。';

  @override
  String get onDeviceProviderHelp => '使用已放在這支手機上的模型。不需要網址或金鑰。';

  @override
  String get manageOnDeviceModels => '管理裝置上模型';

  @override
  String get onDeviceUnavailable => '這台裝置無法執行裝置上模型。需要 64 位元的 Android 或 iOS 裝置。';

  @override
  String get onDeviceIntro =>
      '模型完全在這支手機上執行，對話不會傳到任何地方。模型越大，回答越好，但需要更多記憶體，速度也較慢。';

  @override
  String onDeviceStorage(String size) {
    return '模型占用 $size';
  }

  @override
  String get installedModels => '已安裝';

  @override
  String get noLocalModels => '還沒有模型。下載推薦模型，或匯入 GGUF 檔案。';

  @override
  String get modelDownloads => '下載中';

  @override
  String get recommendedModels => '推薦模型';

  @override
  String get recommendedModelsHelp =>
      '從 Hugging Face 下載，完成後會核對檔案的 SHA-256。只有在你按下下載時才會連線。';

  @override
  String get otherModels => '其他模型';

  @override
  String get otherModelsHelp => 'llama.cpp 支援的 GGUF 模型都可以使用。小模型可能無法正確使用工具。';

  @override
  String get importModel => '匯入 GGUF 檔案';

  @override
  String get importingModel => '正在匯入⋯';

  @override
  String get downloadFromUrl => '從網址下載';

  @override
  String modelAdded(String name) {
    return '已加入 $name';
  }

  @override
  String get modelDownloadStarted => '已開始下載';

  @override
  String modelSelected(String name) {
    return '已切換到 $name';
  }

  @override
  String deleteModelBody(String name) {
    return '要刪除 $name 嗎？之後可以再下載或匯入。';
  }

  @override
  String get inMemory => '已載入';

  @override
  String get useInChat => '在聊天中使用';

  @override
  String get addProjector => '加入視覺投影檔';

  @override
  String get removeProjector => '移除視覺投影檔';

  @override
  String get unloadModel => '從記憶體卸載';

  @override
  String get verifyingDownload => '正在核對檔案⋯';

  @override
  String get downloadPaused => '已暫停';

  @override
  String get pauseDownload => '暫停';

  @override
  String get resumeDownload => '繼續下載';

  @override
  String get recommendedFast => '最快，大多數手機都能執行';

  @override
  String get recommendedBalanced => '速度與品質兼顧';

  @override
  String get recommendedBest => '回答最好，需要較新的手機';

  @override
  String get recommendedVision => '可以看圖片，下載時選擇加入看圖功能';

  @override
  String memoryNeeded(int gb) {
    return '建議 $gb GB 以上記憶體';
  }

  @override
  String downloadWithVision(String size) {
    return '下載並加入看圖功能（$size）';
  }

  @override
  String get modelUrl => '網址';

  @override
  String get modelUrlHelp =>
      'GGUF 檔案的直接連結，例如 Hugging Face 上的「resolve」連結。Tako 只會連線到這個網址；區域網路以外只接受 HTTPS。';

  @override
  String get modelErrorNotGguf => '這不是 GGUF 模型檔。';

  @override
  String get modelErrorIsProjector => '這是視覺投影檔。請在模型的選單中選「加入視覺投影檔」。';

  @override
  String get modelErrorNotProjector => '這不是視覺投影檔。';

  @override
  String get modelErrorExists => '已經有同名的模型。';

  @override
  String get modelErrorUrl => '只接受 HTTPS 網址；區域網路內可以用 HTTP。';

  @override
  String get modelErrorChecksum => '檔案內容和預期不符，已刪除。';

  @override
  String get modelErrorSize => '檔案大小和預期不符。';

  @override
  String get modelErrorNoSpace => '儲存空間不足。';

  @override
  String get modelErrorNetwork => '連線中斷。可以繼續下載。';

  @override
  String modelErrorHttp(String status) {
    return '伺服器回應 HTTP $status。';
  }

  @override
  String get loadingModel => '正在載入模型⋯';

  @override
  String get localModelMissing => '這個模型檔案已不在手機上。請到「裝置上模型」重新下載或匯入。';

  @override
  String get localModelLoad =>
      '無法載入模型。可能是記憶體不足，或這個版本的 llama.cpp 不支援它。請試試較小的模型或較短的上下文。';

  @override
  String get shortcuts => '捷徑';

  @override
  String get shortcutsHelp => '讓 Tako 執行你指定的捷徑';

  @override
  String get shortcutsIntro =>
      'iOS 不允許 App 讀取你的捷徑清單。請輸入要讓 Tako 使用的捷徑名稱，需與「捷徑」App 中的名稱完全相同。每次執行前都會先詢問你。';

  @override
  String get addShortcut => '新增捷徑';

  @override
  String get shortcutName => '捷徑名稱';

  @override
  String get noShortcuts => '還沒有新增捷徑。';

  @override
  String get listShortcutsTool => '列出捷徑';

  @override
  String get runShortcutTool => '執行捷徑';

  @override
  String get useOnDeviceModel => '在手機上執行模型';

  @override
  String get preferSpeed => '優先速度';

  @override
  String get preferSpeedHelp => '使用更多處理器核心，回答較快，但手機可能會卡頓。關閉時會留一個核心給系統，讓手機保持流暢。';

  @override
  String get visualDrawing => '正在繪製⋯';

  @override
  String get visualFailed => '無法繪製，以下是原始內容。';

  @override
  String get visualShowTable => '以表格顯示';

  @override
  String get visualShowChart => '以圖表顯示';

  @override
  String get visualShowCode => '顯示原始碼';

  @override
  String get visualShowDiagram => '顯示圖形';

  @override
  String get visualFullScreen => '全螢幕';

  @override
  String get visualShareImage => '分享圖片';

  @override
  String get visualShareFailed => '無法分享圖片。';

  @override
  String get visualOther => '其他';

  @override
  String get visualTotal => '總計';

  @override
  String get visualSourcePrefix => '資料來源：';

  @override
  String get visualChart => '圖表';

  @override
  String get visualFlowchart => '流程圖';

  @override
  String get visualSequence => '循序圖';

  @override
  String get visualMindmap => '心智圖';

  @override
  String get calloutNote => '備註';

  @override
  String get calloutTip => '提示';

  @override
  String get calloutImportant => '重要';

  @override
  String get calloutWarning => '警告';

  @override
  String get calloutCaution => '注意';

  @override
  String get automations => '自動化';

  @override
  String get automationHelp => '設定排程、通知觸發器與 AI 任務。';

  @override
  String get automationName => '名稱';

  @override
  String get automationPrompt => '任務提示詞';

  @override
  String get automationPromptHelp => 'AI 可依既有權限選用工具。不需要通知時，讓最終回答只有 [SILENT]。';

  @override
  String get automationTrigger => '觸發來源';

  @override
  String get automationSchedule => '排程';

  @override
  String get automationNotification => '收到通知';

  @override
  String get automationShortcut => 'iOS 捷徑';

  @override
  String get automationEnabled => '啟用';

  @override
  String get automationContinue => '延續這條規則的對話';

  @override
  String get automationIndependent => '關閉時，每次執行使用獨立對話。';

  @override
  String get automationTimeout => '等待逾時（分鐘，可留白）';

  @override
  String get automationNoTimeout => '留白表示等待你處理時不設逾時。只計算等待使用者的時間。';

  @override
  String get automationBatch => '通知累積方式';

  @override
  String get automationImmediate => '立即處理';

  @override
  String get automationWindow => '時間窗內合併';

  @override
  String get automationDigest => '累積到指定排程';

  @override
  String get automationWindowSeconds => '累積時間窗（秒）';

  @override
  String get automationCondition => '條件式';

  @override
  String get automationAdvanced => '進階條件式';

  @override
  String get automationPackage => 'App 套件名稱（可留白）';

  @override
  String get automationTitleContains => '標題包含';

  @override
  String get automationTextContains => '內文包含';

  @override
  String get automationConditionHelp =>
      '範例：package == \"jp.naver.line\" and \"班群\" in title\n欄位：package、appLabel、title、text、lines、category、ongoing。支援 ==、!=、in、not in、and、or、not 與括號，不執行程式碼。';

  @override
  String get automationTest => '測試條件';

  @override
  String get automationTestHelp => '輸入 JSON 格式的範例通知欄位。只判斷條件，不呼叫 AI。';

  @override
  String get automationTestMatches => '符合：這個條件式的判斷結果為真。';

  @override
  String get automationTestNoMatch => '不符合：這個條件式的判斷結果為假。';

  @override
  String get automationOnce => '單次';

  @override
  String get automationDaily => '每日';

  @override
  String get automationWeekly => '每週';

  @override
  String get automationInterval => '固定間隔';

  @override
  String get automationEveryMinutes => '重複間隔（至少 15 分鐘）';

  @override
  String get automationDate => '日期與時間';

  @override
  String get automationTime => '時間';

  @override
  String get automationExact => '準時觸發';

  @override
  String get automationExactHelp => '需要「鬧鐘與提醒」權限。此設定控制觸發時間，完成時間仍受模型與工具影響。';

  @override
  String get automationExactRequired => '允許設定鬧鐘與提醒';

  @override
  String get automationNotificationAccess => '設定通知存取權';

  @override
  String get automationAllowNotifications => '允許 Tako 發送通知';

  @override
  String get automationIosHelp =>
      'iOS 會決定背景工作的執行時機，AI 排程可能延後；開啟 Tako 後會處理待執行任務。無法讀取其他 App 的通知。';

  @override
  String get automationShortcutGuide => '設定捷徑自動化';

  @override
  String get automationShortcutsHelp =>
      '1. 建立並啟用觸發來源為「iOS 捷徑」的規則。\n2. 在「捷徑 → 自動化」選擇「特定時間」等個人觸發來源。\n3. 加入「加入 Tako 自動化任務」，選擇規則，可傳入文字。\n4. 若 iOS 提供選項，選擇自動執行。\n此動作只加入任務佇列，iOS 可能延後執行；需要確認時，點開任務通知繼續。';

  @override
  String get automationInput => '觸發資料';

  @override
  String get automationRuns => '執行紀錄';

  @override
  String get automationRecentRuns => '顯示進行中的任務與最近 100 筆已結束紀錄。';

  @override
  String get automationClearHistory => '清除已結束紀錄';

  @override
  String get automationClearHistoryConfirm =>
      '刪除已結束的執行紀錄，以及未使用的自動化對話與附件？進行中的任務、目前開啟的對話，以及持續對話規則使用的對話會保留。';

  @override
  String get automationNoRules => '尚無自動化規則，按「＋」開始新增。';

  @override
  String get automationNoRuns => '尚無執行紀錄。';

  @override
  String get automationRunNow => '立即執行';

  @override
  String get automationResume => '檢視並繼續';

  @override
  String get automationCancel => '取消任務';

  @override
  String get automationResult => '執行結果';

  @override
  String get automationDetails => '任務詳情';

  @override
  String get automationQueued => '待執行';

  @override
  String get automationRunning => '執行中';

  @override
  String get automationWaiting => '等待你處理';

  @override
  String get automationCompleted => '已完成';

  @override
  String get automationSilent => '靜默完成';

  @override
  String get automationFailed => '執行失敗';

  @override
  String get automationCancelled => '已取消';

  @override
  String get automationTimedOut => '已逾時';

  @override
  String get automationReasonApproval => '請檢視並確認工具操作後繼續。';

  @override
  String get automationReasonForeground => '請開啟 Tako 並解鎖裝置後繼續。';

  @override
  String get automationReasonInterrupted =>
      '執行曾被中斷，請先檢視已保存的操作紀錄。沒有收據的操作可能已完成，確認後再繼續。';

  @override
  String get automationReasonPaused => '任務已暫停，完成的操作已保存。';

  @override
  String get automationReasonFailed => '任務未能完成，請檢查模型與權限設定。';

  @override
  String get automationInvalid => '請檢查規則、條件式、排程及文字模型設定。';

  @override
  String get automationDeleteConfirm => '刪除此規則並取消待處理任務？執行紀錄會保留。';

  @override
  String get automationFormNotRepresentable => '這個條件式包含進階條件，請繼續使用條件式編輯器以保留內容。';

  @override
  String get automationModel => '模型';

  @override
  String get automationRefresh => '重新整理';

  @override
  String get automationViewConversation => '檢視對話與產物';

  @override
  String get automationListTool => '查看自動化規則';

  @override
  String get automationGetTool => '讀取自動化規則';

  @override
  String get automationSaveTool => '儲存自動化規則';

  @override
  String get automationDeleteTool => '刪除自動化規則';

  @override
  String get automationRunTool => '啟動自動化任務';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get controlToolMode => '瀏覽器與手機操控';

  @override
  String get controlToolModeAuto => '自動';

  @override
  String get controlToolModeBasic => '基礎工具';

  @override
  String get controlToolModeRepl => 'JavaScript REPL';

  @override
  String get controlToolModeHelp =>
      '自動模式讓遠端 API 模型使用 REPL，裝置端與本機伺服器模型使用基礎工具。REPL 可用 JavaScript 組合操作，每個動作仍需經過工具權限。';

  @override
  String get readSkillTool => '載入操作指引';

  @override
  String get jsReplTool => '執行 JavaScript';

  @override
  String get toolLoopDetected => '已阻止重複的工具循環。請查看模型說明，需要嘗試其他方式時按「繼續」。';

  @override
  String get appUpdates => '應用程式更新';

  @override
  String get appUpdatesHelp => '從 GitHub nightly 檢查並安裝 Android full 版本更新。';

  @override
  String get installedVersion => '已安裝版本';

  @override
  String get checkUpdates => '檢查更新';

  @override
  String get downloadUpdate => '下載並安裝';

  @override
  String get updateAvailable => '有可用更新。';

  @override
  String get updateCurrent => '目前已是最新 nightly 版本。';

  @override
  String get updateCheckFailed => '無法檢查更新，請稍後再試。';

  @override
  String get updateInstallPermission =>
      '請在 Android 設定中允許 Tako 安裝應用程式，返回後再次點選下載並安裝。';

  @override
  String get updateInstallerOpened => 'Android 已開啟安裝確認畫面。';

  @override
  String get updateInstallFailed => '無法下載或安裝更新，請檢查網路，並確認已安裝的應用程式使用正式版本簽章。';

  @override
  String get generateChatTitle => '生成對話標題';

  @override
  String get titleGenerationFailed => '標題生成失敗，已保留原本的標題。';

  @override
  String toolRunSummary(String tool, int count) {
    return '$tool · $count 個步驟';
  }

  @override
  String get toolRunTitle => '工具執行過程';

  @override
  String get toolRunIncomplete => '未完成';

  @override
  String get toolRunUnavailable => '目前的對話分支已不包含這段工具執行過程。';

  @override
  String get undo => '復原';

  @override
  String get deleteAttachmentBody =>
      '此附件可能仍被較早的對話使用。刪除後，相關圖片／檔案將無法讀取；操作後會提供備份與復原。';

  @override
  String get toolsSettings => '工具與權限';

  @override
  String get toolsEnabled => '啟用工具';

  @override
  String get maxToolSteps => '達到此工具呼叫次數後開始偵測循環';

  @override
  String get maxScreenToolSteps => '操控螢幕達到此呼叫次數後開始偵測循環';

  @override
  String get toolOutputLimit => '工具結果長度上限（字元）';

  @override
  String get permissions => '權限';

  @override
  String get fullPermissions => '完整權限';

  @override
  String get fullPermissionsWarning => '讀取私人資料及可復原的操作將不再詢問。高風險操作仍需逐次確認。';

  @override
  String get skipHighRisk => '也略過高風險確認';

  @override
  String get skipHighRiskWarning => '工具將能傳送資料、刪除檔案或進行變更，而不再逐次確認。僅在你接受這些操作時啟用。';

  @override
  String get toolOverrides => '個別工具';

  @override
  String get defaultPolicy => '預設規則';

  @override
  String get alwaysAllow => '永遠允許此工具';

  @override
  String get alwaysAsk => '每次詢問';

  @override
  String get deny => '拒絕';

  @override
  String get allowOnce => '允許這一次';

  @override
  String get allowChat => '此對話允許';

  @override
  String get approvalTitle => '工具操作確認';

  @override
  String get approvalBody => '請確認操作內容與完整參數，再決定是否允許。';

  @override
  String get riskSafe => '安全';

  @override
  String get riskSensitive => '讀取私人資料';

  @override
  String get riskAction => '進行變更';

  @override
  String get riskHigh => '高風險操作';

  @override
  String get auditLog => '工具活動紀錄';

  @override
  String get clearAudit => '清除紀錄';

  @override
  String get clearAuditBody => '刪除本機的工具活動紀錄？';

  @override
  String get noAudit => '尚無工具活動。';

  @override
  String get arguments => '參數';

  @override
  String get result => '結果';

  @override
  String get search => '網路搜尋';

  @override
  String get searchProvider => '搜尋供應商';

  @override
  String get searchUrl => '搜尋端點';

  @override
  String get searchKey => '搜尋 API 金鑰';

  @override
  String get searchResults => '結果筆數';

  @override
  String get searchHelp => '搜尋金鑰保存在安全儲存空間，各供應商分開保存。';

  @override
  String get searchKeyHint => '安全儲存在此裝置上';

  @override
  String get searchOptionalToken => 'Bearer 權杖（選填）';

  @override
  String get searchSerperHelp =>
      '透過 Serper 搜尋 Google。填入 Serper API 金鑰即可使用預設端點。';

  @override
  String get searchDdgsHelp =>
      '填入你的 DDGS API 服務網址（ddgs api）。一般不需金鑰；若服務或反向代理採用 Bearer 驗證，可填入權杖。';

  @override
  String get searchSearxngHelp => '填入你的 SearXNG 服務網址，伺服器必須啟用 JSON 搜尋結果。';

  @override
  String get files => '檔案';

  @override
  String get attach => '附加圖片或文件';

  @override
  String get camera => '相機';

  @override
  String get photos => '相片';

  @override
  String get attachmentBusy => '請等目前的操作完成後，再加入圖片。';

  @override
  String get attachmentLimit => '每則訊息最多可附加 8 個圖片或檔案。';

  @override
  String get imageUnavailable => '無法讀取這張圖片，請改由「相片」或「檔案」選取。';

  @override
  String get unsupportedImage => '不支援此圖片格式，請選取 PNG、JPEG、GIF 或 WebP 圖片。';

  @override
  String get importFiles => '匯入檔案';

  @override
  String get emptyFiles => '工作區目前沒有檔案。';

  @override
  String get filePreview => '檔案預覽';

  @override
  String get deleteFileBody => '刪除此工作區檔案？會保留一份備份。';

  @override
  String get workspace => '工作區';

  @override
  String get restoreFiles => '還原工作區檔案';

  @override
  String get sideEffectsTitle => '這些操作已經發生';

  @override
  String get sideEffectsBody => '回溯對話不會撤銷以下操作。你可以先還原可用的工作區備份，以及移除之後新存入的記憶。';

  @override
  String get restoreAndRewind => '還原並回溯';

  @override
  String get rewindOnly => '只回溯對話';

  @override
  String get visionRequired => '請選擇支援視覺或參考圖的模型，再傳送圖片。';

  @override
  String get toolStepLimit => '已達工具呼叫上限。請檢查目前結果，需要時按「繼續」。';

  @override
  String get toolRunning => '執行中';

  @override
  String get toolWaiting => '等待中';

  @override
  String get toolCompleted => '已完成';

  @override
  String get toolFailed => '失敗';

  @override
  String get toolsUnavailable => '請在此模型的能力設定中啟用工具呼叫，才能使用工具。';

  @override
  String get deviceStatusTool => '讀取裝置狀態';

  @override
  String get locationTool => '讀取位置';

  @override
  String get clipboardReadTool => '讀取剪貼簿';

  @override
  String get clipboardWriteTool => '寫入剪貼簿';

  @override
  String get calendarListTool => '讀取行事曆';

  @override
  String get calendarAddTool => '新增行事曆活動';

  @override
  String get alarmTool => '設定鬧鐘';

  @override
  String get timerTool => '設定計時器';

  @override
  String get openUrlTool => '開啟網址';

  @override
  String get openAppTool => '開啟 App';

  @override
  String get searchTool => '搜尋網路';

  @override
  String get fetchTool => '讀取網頁';

  @override
  String get fileListTool => '列出檔案';

  @override
  String get fileReadTool => '讀取檔案';

  @override
  String get fileWriteTool => '寫入檔案';

  @override
  String get fileDeleteTool => '刪除檔案';

  @override
  String get toolDisabled => '無法使用';

  @override
  String get highRiskKeywords => '高風險關鍵字（每行一個）';

  @override
  String get importFailed => '無法匯入所選檔案。';

  @override
  String get restoreFailed => '有備份無法還原，對話尚未回溯。';

  @override
  String get toolResultAttachment => '工具附件';

  @override
  String get noBackup => '沒有工作區備份';

  @override
  String get systemPermissionHint => '允許後，Android 可能會再詢問系統權限。';

  @override
  String get newChat => '新對話';

  @override
  String get chats => '對話';

  @override
  String get settings => '設定';

  @override
  String get providers => '模型供應商';

  @override
  String get addProvider => '新增供應商';

  @override
  String get editProvider => '編輯供應商';

  @override
  String get noProviders => '連接你的模型';

  @override
  String get welcome => '留一點空間，好好想想。';

  @override
  String get welcomeBody => '提問、探索，或一起理清思緒。對話保存在這台裝置上。';

  @override
  String get setupBody => '新增雲端供應商、本機伺服器或裝置上模型，即可開始聊天。由你決定訊息送往哪裡。';

  @override
  String get messageHint => '想問什麼？';

  @override
  String get send => '傳送';

  @override
  String get stop => '停止';

  @override
  String get retry => '重試';

  @override
  String get save => '儲存';

  @override
  String get cancel => '取消';

  @override
  String get delete => '刪除';

  @override
  String get close => '關閉';

  @override
  String get copy => '複製';

  @override
  String get copyMarkdown => '複製 Markdown';

  @override
  String get selectText => '選取文字';

  @override
  String get copied => '已複製';

  @override
  String get share => '分享';

  @override
  String get edit => '編輯';

  @override
  String get regenerate => '重新生成';

  @override
  String get rewind => '回到這裡';

  @override
  String get rewindDelete => '回到這裡並刪除後續';

  @override
  String get rewindDeleteBody => '刪除此訊息之後的所有分支？此操作無法復原。';

  @override
  String get deleteChatBody => '刪除此對話及所有分支？';

  @override
  String get thinking => '思考過程';

  @override
  String get you => '你';

  @override
  String get image => '圖片';

  @override
  String get file => '檔案';

  @override
  String get stopped => '已停止';

  @override
  String get streaming => '正在撰寫⋯';

  @override
  String get providerName => '顯示名稱';

  @override
  String get apiType => 'API 格式';

  @override
  String get baseUrl => '基底網址';

  @override
  String get apiKey => 'API 金鑰';

  @override
  String get keyHint => '本機伺服器可留空';

  @override
  String get keyStored => '金鑰已安全儲存 · 留空以保留';

  @override
  String get removeKey => '移除已儲存的金鑰';

  @override
  String get model => '模型';

  @override
  String get modelHint => '輸入模型 ID 或載入清單';

  @override
  String get loadModels => '載入模型';

  @override
  String get testConnection => '測試連線';

  @override
  String get connectionOk => '連線成功，模型清單可用。';

  @override
  String get connectionHelp => '測試模型清單端點。若供應商不支援此端點，仍可手動輸入模型。';

  @override
  String get extraHeaders => '額外標頭（JSON 物件）';

  @override
  String get headersHint => '與金鑰一起安全儲存';

  @override
  String get headersStored => '標頭已安全儲存 · 留空以保留';

  @override
  String get removeHeaders => '移除已儲存的標頭';

  @override
  String get localProvider => '本機供應商';

  @override
  String get localDescription => '自動辨識回環與區域網路位址，也可以手動設定。';

  @override
  String get toolsCapability => '工具呼叫';

  @override
  String get visionCapability => '視覺';

  @override
  String get visionCapabilityHelp => '讓模型理解聊天中的圖片。圖片生成需要另外設定。';

  @override
  String get imageGeneration => '圖片生成';

  @override
  String get imageGenerationNone => '關閉';

  @override
  String get imageGenerationImagesApi => 'Images API';

  @override
  String get imageGenerationChatOutput => '聊天中輸出圖片';

  @override
  String get imageGenerationResponsesTool => 'Responses 生圖工具';

  @override
  String get imageGenerationOnDevice => '在這台裝置上';

  @override
  String get imageGenerationHelp =>
      '選擇此模型支援的生圖格式。你可以直接選擇它生成圖片，也可以讓聊天模型透過生圖工具呼叫它。';

  @override
  String get imageGenerationProtocolHelp =>
      '圖片生成需要相容 OpenAI Chat Completions 或 Responses 的供應商。';

  @override
  String get imageReferenceInput => '參考圖';

  @override
  String get imageReferenceInputHelp => '允許將附件圖片用於參考生圖或編輯。僅在此模型支援生圖圖片輸入時開啟。';

  @override
  String get imageGenerationTool => '生成圖片';

  @override
  String get reasoningCapability => '推理';

  @override
  String get capabilities => '模型能力';

  @override
  String get contextWindow => '上下文長度（token）';

  @override
  String get maxOutput => '輸出上限（token）';

  @override
  String get reasoningMode => '推理模式';

  @override
  String get reasoningOff => '供應商預設';

  @override
  String get reasoningEnabled => '啟用（預算）';

  @override
  String get reasoningAdaptive => '自適應';

  @override
  String get thinkingBudget => '思考預算（token）';

  @override
  String get reasoningEffort => '推理強度';

  @override
  String get requiredField => '必填';

  @override
  String get invalidUrl => '請輸入 http(s) 網址，不含帳密、查詢參數或片段。';

  @override
  String get invalidJson => '請輸入標頭值為字串的 JSON 物件。';

  @override
  String get invalidNumber => '請輸入正整數。';

  @override
  String get invalidBudget => '輸出上限須小於上下文長度。思考預算須至少為 1024，且小於輸出上限。';

  @override
  String get operationFailed => '操作失敗，請再試一次。';

  @override
  String get fileUnavailable => '此工作區檔案目前無法使用。';

  @override
  String get contextTrimmed => '已裁剪較舊的上下文以符合模型限制';

  @override
  String get contextTooLarge => '此訊息超過模型上下文長度，請縮短訊息或在供應商設定中調整長度。';

  @override
  String get noProviderSelected => '請先在設定中選擇供應商。';

  @override
  String get providerRemoved => '此對話的供應商已無法使用，請選擇其他供應商。';

  @override
  String get changeProvider => '更換供應商';

  @override
  String get changeProviderBody => '對話將由此供應商繼續。可見的對話歷史會傳送給它，系統提示詞也會重新產生。';

  @override
  String get continueAction => '繼續';

  @override
  String get appearance => '外觀';

  @override
  String get theme => '主題';

  @override
  String get systemTheme => '跟隨系統';

  @override
  String get lightTheme => '淺色';

  @override
  String get darkTheme => '深色';

  @override
  String get textSize => '文字大小';

  @override
  String get language => '語言';

  @override
  String get privacy => '以本機為本';

  @override
  String get privacyBody =>
      '對話與記憶保存在此裝置。聊天時，你的訊息以及工具讀到的內容（例如畫面或通知）會傳送給你選擇的模型供應商；使用裝置上模型時，這些內容不會離開這支手機。API 金鑰與額外標頭保存在安全儲存空間。沒有帳號、分析或遙測。';

  @override
  String get about => '關於';

  @override
  String get developerContext => '已儲存的上下文';

  @override
  String get noChats => '你的對話會顯示在這裡。';

  @override
  String get chooseProvider => '選擇供應商';

  @override
  String get previousBranch => '上一個分支';

  @override
  String get nextBranch => '下一個分支';

  @override
  String get providerDeleteBody => '移除此供應商及其憑證？對話將予以保留。';

  @override
  String get emptyResponse => '供應商未回傳回覆，請重試或檢查模型設定。';

  @override
  String get toolsLater => '此請求尚未啟用工具，或工具目前無法使用。';

  @override
  String get builtInSearch => '供應商內建網路搜尋';

  @override
  String get builtInSearchHelp => '使用模型供應商的原生搜尋；關閉時使用「搜尋」設定中的供應商。仍受工具權限規則控制。';

  @override
  String get allowCustomSearchEndpoint => '允許相容代理（CPA）';

  @override
  String get allowCustomSearchEndpointHelp =>
      '向此自訂端點送出原生搜尋工具。代理必須保留 Responses 或 Messages 搜尋格式；未開啟時只自動允許官方端點。';

  @override
  String get testNativeSearch => '測試原生搜尋';

  @override
  String get nativeSearchTesting => '正在測試原生搜尋⋯';

  @override
  String get nativeSearchTestHelp =>
      '使用目前模型與端點搜尋一次 Flutter 官方網站，可能產生 API 費用。不會傳送對話紀錄、自動啟用搜尋或儲存設定。';

  @override
  String get nativeSearchSupported => '測試成功：供應商確實完成了原生搜尋。';

  @override
  String get nativeSearchNotObserved =>
      '端點有回應，但未收到原生搜尋完成紀錄。可能是代理移除了搜尋工具，或此轉送路徑不支援。';

  @override
  String get nativeSearchProtocolHelp =>
      '此處的原生搜尋需使用 OpenAI Responses 或 Anthropic Messages。Chat Completions 請搭配「搜尋」設定中的供應商。';

  @override
  String get nativeSearchDisabled => '請先在「工具與權限」啟用工具與網路搜尋。';

  @override
  String get nativeSearchDenied => '這次測試已被網路搜尋權限規則拒絕。';

  @override
  String get nativeSearchFailed => '原生搜尋測試失敗，請確認模型與代理轉送路徑支援原生搜尋。';

  @override
  String get nativeSearchCancelled => '已取消原生搜尋測試。';

  @override
  String get nativeSearchTimeout => '原生搜尋測試逾時，已取消請求。';

  @override
  String get nativeSearchBusy => '請等待目前工作結束後再測試。';

  @override
  String get localLabel => '本機';

  @override
  String get cloudLabel => '雲端';

  @override
  String get connectionFailed => '連線失敗';

  @override
  String get noModels => '未取得模型，請手動輸入模型 ID。';

  @override
  String get viewImage => '檢視圖片';

  @override
  String get openImageLink => '在瀏覽器開啟圖片';

  @override
  String get renameChat => '重新命名對話';

  @override
  String get chatTitle => '對話標題';

  @override
  String get messageActions => '訊息選項';

  @override
  String get models => '模型';

  @override
  String get addModel => '新增模型';

  @override
  String get addModels => '加入所選模型';

  @override
  String get newModel => '新模型';

  @override
  String get duplicateModel => '此模型已經加入。';

  @override
  String get autoModelSpecs => '自動辨識模型規格';

  @override
  String get knownModelSpecs => '已套用已知規格，可自行調整限制與能力。';

  @override
  String get unknownModelSpecs => '未知模型：目前使用預設值，請依伺服器支援的規格調整。';

  @override
  String get officialModelId => '官方 API 模型 ID';

  @override
  String get chooseModel => '選擇模型';

  @override
  String get memory => '記憶';

  @override
  String get memoryEnabled => '使用記憶';

  @override
  String memoryEnabledHelp(String app) {
    return '$app 可以儲存並查詢你提供的長期資訊。釘選的個人檔案與偏好會加入新的對話。';
  }

  @override
  String get memoryOff => '記憶已關閉。已儲存的記憶會保留，但不會在對話中使用。';

  @override
  String get memorySearchHint => '搜尋記憶';

  @override
  String memoryEmpty(String app) {
    return '還沒有記憶。可以請 $app 記住某件事，或在這裡新增。';
  }

  @override
  String get memoryNoMatches => '沒有符合的記憶。';

  @override
  String get addMemory => '新增記憶';

  @override
  String get editMemory => '編輯記憶';

  @override
  String get memoryText => '內容';

  @override
  String get memoryKind => '類型';

  @override
  String get memoryKindProfile => '個人檔案';

  @override
  String get memoryKindPreference => '偏好';

  @override
  String get memoryKindFact => '事實';

  @override
  String get memoryPinned => '已釘選';

  @override
  String get memoryPin => '釘選';

  @override
  String get memoryUnpin => '取消釘選';

  @override
  String get memoryPinHelp => '釘選的個人檔案與偏好會加入新的對話。';

  @override
  String memoryProfileUsage(int words, int limit) {
    return '釘選的個人檔案：$words/$limit 字';
  }

  @override
  String get memoryProfileTruncated => '部分釘選內容超出上限，不會加入新的對話。';

  @override
  String get memoryFromChat => '從對話中儲存';

  @override
  String get deleteMemoryBody => '要刪除這則記憶嗎？';

  @override
  String get deleteAllMemories => '刪除所有記憶';

  @override
  String get deleteAllMemoriesBody => '要刪除所有已儲存的記憶嗎？此操作無法復原。';

  @override
  String get exportMemories => '匯出 JSON';

  @override
  String get importMemories => '匯入 JSON';

  @override
  String memoriesImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已匯入 $count 則記憶',
      zero: '沒有匯入新的記憶',
    );
    return '$_temp0';
  }

  @override
  String memoryImportFailed(String app) {
    return '這不是有效的 $app 記憶匯出檔。';
  }

  @override
  String get memorySaved => '已存入記憶';

  @override
  String get memoryUndone => '已從記憶移除';

  @override
  String get memoryChanged => '儲存後已被修改或移除';

  @override
  String get personalization => '個人化';

  @override
  String displayName(String app) {
    return '$app 該怎麼稱呼你？';
  }

  @override
  String get customInstructions => '自訂指示';

  @override
  String customInstructionsHint(String app) {
    return '希望 $app 在每個新對話中都知道或遵守的事';
  }

  @override
  String get replyStyle => '回覆風格';

  @override
  String get replyConcise => '簡潔';

  @override
  String get replyNormal => '一般';

  @override
  String get replyDetailed => '詳細';

  @override
  String get personalizationHelp => '變更會套用到新的對話；既有對話維持開始時的設定。';

  @override
  String get incognitoChat => '無痕聊天';

  @override
  String get newIncognitoChat => '新增無痕聊天';

  @override
  String get incognitoBody => '不使用記憶，離開後這段對話會被刪除。';

  @override
  String get browser => '瀏覽器';

  @override
  String get openBrowser => '開啟瀏覽器';

  @override
  String get browserAddressHint => '輸入網址';

  @override
  String get browserInvalidAddress => '請輸入網址，例如 example.com。';

  @override
  String browserEmpty(String app) {
    return '輸入網址，或請 $app 開啟網頁。';
  }

  @override
  String browserModelActive(String app) {
    return '$app 正在使用瀏覽器';
  }

  @override
  String get takeOver => '接手操作';

  @override
  String get browserBack => '上一頁';

  @override
  String get browserForward => '下一頁';

  @override
  String get browserReload => '重新載入';

  @override
  String get openExternally => '在其他應用程式開啟';

  @override
  String get clearBrowsingData => '清除瀏覽資料';

  @override
  String get clearBrowsingDataBody =>
      '要刪除內建瀏覽器的 Cookie、網站儲存資料、快取與瀏覽紀錄嗎？你將會登出各個網站。';

  @override
  String get browsingDataCleared => '已清除瀏覽資料';

  @override
  String get openLinksInApp => '在內建瀏覽器開啟連結';

  @override
  String get openLinksInAppHelp => '關閉時，連結會以預設瀏覽器開啟。內建瀏覽器的 Cookie 與其他瀏覽器分開保存。';

  @override
  String get browserUnavailable => '此裝置無法使用內建瀏覽器。';

  @override
  String get downloadTitle => '要下載檔案嗎？';

  @override
  String downloadBody(String name, String host) {
    return '要將來自 $host 的「$name」儲存到檔案嗎？';
  }

  @override
  String get download => '下載';

  @override
  String get downloadSaved => '已儲存到檔案';

  @override
  String get downloadFailed => '下載失敗。';

  @override
  String get downloadTooLarge => '無法下載超過 20 MB 的檔案。';

  @override
  String get approvalElement => '元素';

  @override
  String get approvalPage => '網頁';

  @override
  String get approvalSubmit => '送出按鈕';

  @override
  String get memorySearchTool => '搜尋記憶';

  @override
  String get memorySaveTool => '存入記憶';

  @override
  String get memoryUpdateTool => '更新記憶';

  @override
  String get memoryDeleteTool => '刪除記憶';

  @override
  String get browserStartSessionTool => '開啟瀏覽器工作階段';

  @override
  String get browserOpenTool => '開啟網頁';

  @override
  String get browserReadTool => '讀取瀏覽器頁面';

  @override
  String get browserClickTool => '在瀏覽器中點擊';

  @override
  String get browserTypeTool => '在瀏覽器中輸入';

  @override
  String get browserScrollTool => '捲動瀏覽器頁面';

  @override
  String get browserBackTool => '瀏覽器上一頁';

  @override
  String get readScreenTool => '讀取螢幕';

  @override
  String get tapTool => '點按螢幕';

  @override
  String get longPressTool => '長按螢幕';

  @override
  String get swipeTool => '在螢幕上滑動';

  @override
  String get scrollTool => '捲動螢幕';

  @override
  String get typeTextTool => '在螢幕上輸入';

  @override
  String get pressKeyTool => '按系統鍵';

  @override
  String get runShellTool => '執行 Shell 指令';

  @override
  String get notificationsListTool => '讀取通知';

  @override
  String get approvalApp => 'App';

  @override
  String get approvalPoint => '位置';

  @override
  String screenSessionTitle(String app) {
    return '$app 正在使用你的手機';
  }

  @override
  String get screenSessionThinking => '正在思考下一步…';

  @override
  String get screenSessionWaiting => '等待你的核准…';

  @override
  String get screenSessionBody => '點「停止」即可接手。';

  @override
  String get screenChannel => '螢幕控制';

  @override
  String get alertChannel => '核准與回覆';

  @override
  String approvalNeededTitle(String app) {
    return '$app 需要你的核准';
  }

  @override
  String get approvalNeededBody => '開啟 App 查看這項要求。';

  @override
  String replyReadyTitle(String app) {
    return '$app 已回覆';
  }

  @override
  String get replyReadyBody => '點一下查看回覆。';

  @override
  String get deviceControl => '裝置控制';

  @override
  String deviceControlHelp(String app) {
    return '讓 $app 使用其他 App、你的通知與 Termux。每一項都要在 Android 設定中開啟，所有操作仍需經過工具權限。';
  }

  @override
  String get screenControl => '螢幕控制';

  @override
  String get statusOn => '已開啟';

  @override
  String get statusOff => '未開啟';

  @override
  String get screenControlUnsupported => '這個版本不含螢幕控制功能。';

  @override
  String screenControlHelp(String app) {
    return '$app 只會在你要求時，透過已核准的工具讀取畫面，並在其他 App 中點按、輸入和捲動。「傳送」、「付款」、「刪除」等按鈕一定會先詢問，也永遠不會填入密碼欄位。';
  }

  @override
  String get screenControlDisclosureTitle => '要開啟螢幕控制嗎？';

  @override
  String screenControlDisclosure(String app) {
    return '$app 會使用 Android 的無障礙服務讀取畫面內容，並替你點按、輸入和捲動。只有螢幕工具執行時才會讀取畫面；讀到的內容會傳送給你選擇的模型供應商並保留在該對話中，不會用於其他用途。請在下一個畫面中找到 $app 並開啟。';
  }

  @override
  String get openAccessibilitySettings => '開啟無障礙設定';

  @override
  String get restrictedSettingsHelp =>
      '如果 Android 顯示這是「受限制的設定」，請開啟應用程式資訊，點右上角的 ⋮ 選單並選擇「允許受限制的設定」，再試一次。';

  @override
  String get openAppInfo => '開啟應用程式資訊';

  @override
  String get screenshotsSetting => '傳送截圖給視覺模型';

  @override
  String get screenshotsHelp =>
      '模型支援圖片時，read_screen 也會附上截圖。截圖包含畫面上的所有內容，也會使用較多 token。';

  @override
  String get screenshotsUnsupported => '截圖需要 Android 11 以上版本。';

  @override
  String get sessionNotification => '操作螢幕時的通知';

  @override
  String get sessionNotificationHelp => '顯示目前正在操作螢幕，並提供「停止」按鈕。';

  @override
  String get allowNotifications => '允許通知';

  @override
  String get allowed => '已允許';

  @override
  String get notificationAccess => '通知存取';

  @override
  String notificationAccessHelp(String app) {
    return '讓 $app 在你要求時讀取目前的通知。不會在背景讀取或保存。';
  }

  @override
  String get openNotificationAccess => '開啟通知存取設定';

  @override
  String get termux => 'Termux（run_shell）';

  @override
  String get termuxHelp =>
      'run_shell 會在 Termux 中執行指令。ls、cat 等唯讀指令視為讀取私人資料；其他指令每次都會詢問。';

  @override
  String get termuxNotInstalled =>
      '尚未安裝 Termux。請從 F-Droid 或 Termux 的 GitHub Releases 安裝。';

  @override
  String get termuxStepOpen => '開啟 Termux 一次，等待初始設定完成。';

  @override
  String get termuxStepProperty => '在 Termux 執行以下指令，讓其他 App 可以傳送指令：';

  @override
  String termuxStepPermission(String app) {
    return '允許 $app 在 Termux 中執行指令。';
  }

  @override
  String get termuxSecurityNote => '這項設定會讓任何取得 Termux 權限的 App 都能執行指令。';

  @override
  String get openTermux => '開啟 Termux';

  @override
  String get testShell => '測試';

  @override
  String shellTestPassed(String output) {
    return 'Termux 回應：$output';
  }

  @override
  String shellTestFailed(String error) {
    return '測試失敗（$error）。';
  }

  @override
  String get shellTimeout => '指令逾時（秒）';

  @override
  String get appTagline => '本機優先的 AI 助理';

  @override
  String get grantPermission => '允許';

  @override
  String get tabs => '分頁';

  @override
  String get newTab => '新增分頁';

  @override
  String get closeTab => '關閉分頁';

  @override
  String get blankTab => '空白頁';

  @override
  String openedByAssistant(String app) {
    return '由 $app 開啟';
  }

  @override
  String get deleteScreenshots => '刪除對話時一併刪除截圖';

  @override
  String get deleteScreenshotsHelp => '回溯並刪除之後的訊息時也一樣。無痕聊天一律刪除。';

  @override
  String get onDeviceModels => '裝置上模型';

  @override
  String get onDeviceModelsHelp => '在這支手機上直接執行本地模型';

  @override
  String get onDeviceApi => '裝置上（llama.cpp / AICore / Apple Intelligence）';

  @override
  String get aicoreHelp =>
      '與 Android AICore 管理的模型聊天，首次設定可能需要網路連線。相容模型可使用 Tako 的工具，並沿用原有的權限檢查。';

  @override
  String get aicorePreviewHelp =>
      '預覽版模型需要加入 Google 的 AICore Developer Preview，能否使用取決於裝置，且可能隨版本變動。';

  @override
  String get aicoreToolsUnavailable =>
      '這個 AICore 模型無法提供 Tako 工具所需的結構化回覆。請選用相容的預覽版模型，或關閉這個模型的工具能力。';

  @override
  String get aicoreInvalidTools => '模型回傳了不完整或無效的工具請求，這次回覆未執行任何工具。請再試一次。';

  @override
  String get aicoreBackground => '請讓 Tako 保持在前景，讓 AICore 繼續生成回覆。';

  @override
  String get aicorePrepare => '設定 Gemini Nano';

  @override
  String get aicorePreparing => 'AICore 正在下載或準備 Gemini Nano…';

  @override
  String get aicoreManaged => '模型由 Android AICore 管理';

  @override
  String get aicoreUnavailable =>
      '這台裝置的 AICore 服務無法提供這個模型。請更新 Android AICore 並確認裝置支援；預覽版模型還需要加入 AICore Developer Preview。';

  @override
  String get aicoreUpdate => '請更新 Android 系統及 Android AICore 應用程式後再試。';

  @override
  String get aicoreRequestTooLarge =>
      '這段對話超過 Gemini Nano 可處理的長度。請開啟新對話或縮短系統提示詞。';

  @override
  String get aicoreBusy => 'AICore 正忙碌，請稍候再試。';

  @override
  String get aicoreFailed => 'AICore 無法準備或執行這個模型。請更新 Android AICore、確認裝置支援後再試。';

  @override
  String get appleHelp =>
      '透過 Apple Intelligence 與 Apple 的裝置端模型聊天，不需要網路連線。需要支援 Apple Intelligence 的裝置與 iOS 26 以上版本。可使用 Tako 的工具，並沿用原有的權限檢查。';

  @override
  String get appleImageHelp =>
      '用 Image Playground 在這台裝置上生成圖片。可以直接選它來生圖，也可以讓聊天模型透過生圖工具呼叫它，並可附上一張參考圖片。需要 iOS 18.4 以上版本，並開啟 Apple Intelligence。';

  @override
  String get appleManaged => '由 Apple Intelligence 管理';

  @override
  String get appleCheckAgain => '重新檢查';

  @override
  String get appleChecking => '正在檢查 Apple Intelligence…';

  @override
  String get appleUnavailable =>
      '這台裝置不支援 Apple Intelligence。需要 iPhone 15 Pro 或更新的機型，或搭載 M 系列、A17 Pro 晶片的 iPad 或 Mac。';

  @override
  String get appleUpdate =>
      '請更新 iOS 才能使用這個模型。Apple 裝置端模型需要 iOS 26 以上，Image Playground 需要 iOS 18.4 以上。';

  @override
  String get appleDisabled =>
      '請到「設定」>「Apple Intelligence 與 Siri」開啟 Apple Intelligence，等模型下載完成後再重新檢查。';

  @override
  String get appleNotReady =>
      'Apple Intelligence 仍在下載或準備模型。請保持 Wi-Fi 連線並接上電源，稍後再重新檢查。';

  @override
  String get appleRequestTooLarge => '這段對話超過 Apple 裝置端模型可處理的長度。請開啟新對話或縮短系統提示詞。';

  @override
  String get appleBusy => 'Apple Intelligence 暫時無法處理更多請求。請讓 Tako 保持開啟，稍候再試。';

  @override
  String get appleBackground => '請讓 Tako 保持在前景，Apple Intelligence 才能繼續生成。';

  @override
  String get appleGuardrail => 'Apple Intelligence 的安全檢查拒絕了這個請求。請換個說法，或改用其他模型。';

  @override
  String get appleLanguage =>
      'Apple Intelligence 目前不支援這個請求的語言。請改用支援的語言，或改用其他模型。';

  @override
  String get appleImageInput =>
      'Image Playground 無法使用這個提示或參考圖片。請最多附上一張清楚的照片，或換個方式描述。';

  @override
  String get appleFailed => 'Apple Intelligence 無法完成這個請求，請稍後再試。';

  @override
  String get onDeviceProviderHelp => '使用已放在這支手機上的模型。不需要網址或金鑰。';

  @override
  String get manageOnDeviceModels => '管理裝置上模型';

  @override
  String get onDeviceUnavailable => '這台裝置無法執行裝置上模型。需要 64 位元的 Android 或 iOS 裝置。';

  @override
  String get onDeviceIntro =>
      '模型完全在這支手機上執行，對話不會傳到任何地方。模型越大，回答越好，但需要更多記憶體，速度也較慢。';

  @override
  String onDeviceStorage(String size) {
    return '模型占用 $size';
  }

  @override
  String get installedModels => '已安裝';

  @override
  String get noLocalModels => '還沒有模型。下載推薦模型，或匯入 GGUF 檔案。';

  @override
  String get modelDownloads => '下載中';

  @override
  String get recommendedModels => '推薦模型';

  @override
  String get recommendedModelsHelp =>
      '從 Hugging Face 下載，完成後會核對檔案的 SHA-256。只有在你按下下載時才會連線。';

  @override
  String get otherModels => '其他模型';

  @override
  String get otherModelsHelp => 'llama.cpp 支援的 GGUF 模型都可以使用。小模型可能無法正確使用工具。';

  @override
  String get importModel => '匯入 GGUF 檔案';

  @override
  String get importingModel => '正在匯入⋯';

  @override
  String get downloadFromUrl => '從網址下載';

  @override
  String modelAdded(String name) {
    return '已加入 $name';
  }

  @override
  String get modelDownloadStarted => '已開始下載';

  @override
  String modelSelected(String name) {
    return '已切換到 $name';
  }

  @override
  String deleteModelBody(String name) {
    return '要刪除 $name 嗎？之後可以再下載或匯入。';
  }

  @override
  String get inMemory => '已載入';

  @override
  String get useInChat => '在聊天中使用';

  @override
  String get addProjector => '加入視覺投影檔';

  @override
  String get removeProjector => '移除視覺投影檔';

  @override
  String get unloadModel => '從記憶體卸載';

  @override
  String get verifyingDownload => '正在核對檔案⋯';

  @override
  String get downloadPaused => '已暫停';

  @override
  String get pauseDownload => '暫停';

  @override
  String get resumeDownload => '繼續下載';

  @override
  String get recommendedFast => '最快，大多數手機都能執行';

  @override
  String get recommendedBalanced => '速度與品質兼顧';

  @override
  String get recommendedBest => '回答最好，需要較新的手機';

  @override
  String get recommendedVision => '可以看圖片，下載時選擇加入看圖功能';

  @override
  String memoryNeeded(int gb) {
    return '建議 $gb GB 以上記憶體';
  }

  @override
  String downloadWithVision(String size) {
    return '下載並加入看圖功能（$size）';
  }

  @override
  String get modelUrl => '網址';

  @override
  String get modelUrlHelp =>
      'GGUF 檔案的直接連結，例如 Hugging Face 上的「resolve」連結。Tako 只會連線到這個網址；區域網路以外只接受 HTTPS。';

  @override
  String get modelErrorNotGguf => '這不是 GGUF 模型檔。';

  @override
  String get modelErrorIsProjector => '這是視覺投影檔。請在模型的選單中選「加入視覺投影檔」。';

  @override
  String get modelErrorNotProjector => '這不是視覺投影檔。';

  @override
  String get modelErrorExists => '已經有同名的模型。';

  @override
  String get modelErrorUrl => '只接受 HTTPS 網址；區域網路內可以用 HTTP。';

  @override
  String get modelErrorChecksum => '檔案內容和預期不符，已刪除。';

  @override
  String get modelErrorSize => '檔案大小和預期不符。';

  @override
  String get modelErrorNoSpace => '儲存空間不足。';

  @override
  String get modelErrorNetwork => '連線中斷。可以繼續下載。';

  @override
  String modelErrorHttp(String status) {
    return '伺服器回應 HTTP $status。';
  }

  @override
  String get loadingModel => '正在載入模型⋯';

  @override
  String get localModelMissing => '這個模型檔案已不在手機上。請到「裝置上模型」重新下載或匯入。';

  @override
  String get localModelLoad =>
      '無法載入模型。可能是記憶體不足，或這個版本的 llama.cpp 不支援它。請試試較小的模型或較短的上下文。';

  @override
  String get shortcuts => '捷徑';

  @override
  String get shortcutsHelp => '讓 Tako 執行你指定的捷徑';

  @override
  String get shortcutsIntro =>
      'iOS 不允許 App 讀取你的捷徑清單。請輸入要讓 Tako 使用的捷徑名稱，需與「捷徑」App 中的名稱完全相同。每次執行前都會先詢問你。';

  @override
  String get addShortcut => '新增捷徑';

  @override
  String get shortcutName => '捷徑名稱';

  @override
  String get noShortcuts => '還沒有新增捷徑。';

  @override
  String get listShortcutsTool => '列出捷徑';

  @override
  String get runShortcutTool => '執行捷徑';

  @override
  String get useOnDeviceModel => '在手機上執行模型';

  @override
  String get preferSpeed => '優先速度';

  @override
  String get preferSpeedHelp => '使用更多處理器核心，回答較快，但手機可能會卡頓。關閉時會留一個核心給系統，讓手機保持流暢。';

  @override
  String get visualDrawing => '正在繪製⋯';

  @override
  String get visualFailed => '無法繪製，以下是原始內容。';

  @override
  String get visualShowTable => '以表格顯示';

  @override
  String get visualShowChart => '以圖表顯示';

  @override
  String get visualShowCode => '顯示原始碼';

  @override
  String get visualShowDiagram => '顯示圖形';

  @override
  String get visualFullScreen => '全螢幕';

  @override
  String get visualShareImage => '分享圖片';

  @override
  String get visualShareFailed => '無法分享圖片。';

  @override
  String get visualOther => '其他';

  @override
  String get visualTotal => '總計';

  @override
  String get visualSourcePrefix => '資料來源：';

  @override
  String get visualChart => '圖表';

  @override
  String get visualFlowchart => '流程圖';

  @override
  String get visualSequence => '循序圖';

  @override
  String get visualMindmap => '心智圖';

  @override
  String get calloutNote => '備註';

  @override
  String get calloutTip => '提示';

  @override
  String get calloutImportant => '重要';

  @override
  String get calloutWarning => '警告';

  @override
  String get calloutCaution => '注意';

  @override
  String get automations => '自動化';

  @override
  String get automationHelp => '設定排程、通知觸發器與 AI 任務。';

  @override
  String get automationName => '名稱';

  @override
  String get automationPrompt => '任務提示詞';

  @override
  String get automationPromptHelp => 'AI 可依既有權限選用工具。不需要通知時，讓最終回答只有 [SILENT]。';

  @override
  String get automationTrigger => '觸發來源';

  @override
  String get automationSchedule => '排程';

  @override
  String get automationNotification => '收到通知';

  @override
  String get automationShortcut => 'iOS 捷徑';

  @override
  String get automationEnabled => '啟用';

  @override
  String get automationContinue => '延續這條規則的對話';

  @override
  String get automationIndependent => '關閉時，每次執行使用獨立對話。';

  @override
  String get automationTimeout => '等待逾時（分鐘，可留白）';

  @override
  String get automationNoTimeout => '留白表示等待你處理時不設逾時。只計算等待使用者的時間。';

  @override
  String get automationBatch => '通知累積方式';

  @override
  String get automationImmediate => '立即處理';

  @override
  String get automationWindow => '時間窗內合併';

  @override
  String get automationDigest => '累積到指定排程';

  @override
  String get automationWindowSeconds => '累積時間窗（秒）';

  @override
  String get automationCondition => '條件式';

  @override
  String get automationAdvanced => '進階條件式';

  @override
  String get automationPackage => 'App 套件名稱（可留白）';

  @override
  String get automationTitleContains => '標題包含';

  @override
  String get automationTextContains => '內文包含';

  @override
  String get automationConditionHelp =>
      '範例：package == \"jp.naver.line\" and \"班群\" in title\n欄位：package、appLabel、title、text、lines、category、ongoing。支援 ==、!=、in、not in、and、or、not 與括號，不執行程式碼。';

  @override
  String get automationTest => '測試條件';

  @override
  String get automationTestHelp => '輸入 JSON 格式的範例通知欄位。只判斷條件，不呼叫 AI。';

  @override
  String get automationTestMatches => '符合：這個條件式的判斷結果為真。';

  @override
  String get automationTestNoMatch => '不符合：這個條件式的判斷結果為假。';

  @override
  String get automationOnce => '單次';

  @override
  String get automationDaily => '每日';

  @override
  String get automationWeekly => '每週';

  @override
  String get automationInterval => '固定間隔';

  @override
  String get automationEveryMinutes => '重複間隔（至少 15 分鐘）';

  @override
  String get automationDate => '日期與時間';

  @override
  String get automationTime => '時間';

  @override
  String get automationExact => '準時觸發';

  @override
  String get automationExactHelp => '需要「鬧鐘與提醒」權限。此設定控制觸發時間，完成時間仍受模型與工具影響。';

  @override
  String get automationExactRequired => '允許設定鬧鐘與提醒';

  @override
  String get automationNotificationAccess => '設定通知存取權';

  @override
  String get automationAllowNotifications => '允許 Tako 發送通知';

  @override
  String get automationIosHelp =>
      'iOS 會決定背景工作的執行時機，AI 排程可能延後；開啟 Tako 後會處理待執行任務。無法讀取其他 App 的通知。';

  @override
  String get automationShortcutGuide => '設定捷徑自動化';

  @override
  String get automationShortcutsHelp =>
      '1. 建立並啟用觸發來源為「iOS 捷徑」的規則。\n2. 在「捷徑 → 自動化」選擇「特定時間」等個人觸發來源。\n3. 加入「加入 Tako 自動化任務」，選擇規則，可傳入文字。\n4. 若 iOS 提供選項，選擇自動執行。\n此動作只加入任務佇列，iOS 可能延後執行；需要確認時，點開任務通知繼續。';

  @override
  String get automationInput => '觸發資料';

  @override
  String get automationRuns => '執行紀錄';

  @override
  String get automationRecentRuns => '顯示進行中的任務與最近 100 筆已結束紀錄。';

  @override
  String get automationClearHistory => '清除已結束紀錄';

  @override
  String get automationClearHistoryConfirm =>
      '刪除已結束的執行紀錄，以及未使用的自動化對話與附件？進行中的任務、目前開啟的對話，以及持續對話規則使用的對話會保留。';

  @override
  String get automationNoRules => '尚無自動化規則，按「＋」開始新增。';

  @override
  String get automationNoRuns => '尚無執行紀錄。';

  @override
  String get automationRunNow => '立即執行';

  @override
  String get automationResume => '檢視並繼續';

  @override
  String get automationCancel => '取消任務';

  @override
  String get automationResult => '執行結果';

  @override
  String get automationDetails => '任務詳情';

  @override
  String get automationQueued => '待執行';

  @override
  String get automationRunning => '執行中';

  @override
  String get automationWaiting => '等待你處理';

  @override
  String get automationCompleted => '已完成';

  @override
  String get automationSilent => '靜默完成';

  @override
  String get automationFailed => '執行失敗';

  @override
  String get automationCancelled => '已取消';

  @override
  String get automationTimedOut => '已逾時';

  @override
  String get automationReasonApproval => '請檢視並確認工具操作後繼續。';

  @override
  String get automationReasonForeground => '請開啟 Tako 並解鎖裝置後繼續。';

  @override
  String get automationReasonInterrupted =>
      '執行曾被中斷，請先檢視已保存的操作紀錄。沒有收據的操作可能已完成，確認後再繼續。';

  @override
  String get automationReasonPaused => '任務已暫停，完成的操作已保存。';

  @override
  String get automationReasonFailed => '任務未能完成，請檢查模型與權限設定。';

  @override
  String get automationInvalid => '請檢查規則、條件式、排程及文字模型設定。';

  @override
  String get automationDeleteConfirm => '刪除此規則並取消待處理任務？執行紀錄會保留。';

  @override
  String get automationFormNotRepresentable => '這個條件式包含進階條件，請繼續使用條件式編輯器以保留內容。';

  @override
  String get automationModel => '模型';

  @override
  String get automationRefresh => '重新整理';

  @override
  String get automationViewConversation => '檢視對話與產物';

  @override
  String get automationListTool => '查看自動化規則';

  @override
  String get automationGetTool => '讀取自動化規則';

  @override
  String get automationSaveTool => '儲存自動化規則';

  @override
  String get automationDeleteTool => '刪除自動化規則';

  @override
  String get automationRunTool => '啟動自動化任務';
}
