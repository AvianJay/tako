import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh', 'TW'),
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @toolLoopDetected.
  ///
  /// In zh, this message translates to:
  /// **'??????????????????????????????????'**
  String get toolLoopDetected;

  /// No description provided for @appUpdates.
  ///
  /// In zh, this message translates to:
  /// **'????'**
  String get appUpdates;

  /// No description provided for @appUpdatesHelp.
  ///
  /// In zh, this message translates to:
  /// **'? GitHub nightly ????? Android full ?????'**
  String get appUpdatesHelp;

  /// No description provided for @installedVersion.
  ///
  /// In zh, this message translates to:
  /// **'?????'**
  String get installedVersion;

  /// No description provided for @checkUpdates.
  ///
  /// In zh, this message translates to:
  /// **'????'**
  String get checkUpdates;

  /// No description provided for @downloadUpdate.
  ///
  /// In zh, this message translates to:
  /// **'?????'**
  String get downloadUpdate;

  /// No description provided for @updateAvailable.
  ///
  /// In zh, this message translates to:
  /// **'??????'**
  String get updateAvailable;

  /// No description provided for @updateCurrent.
  ///
  /// In zh, this message translates to:
  /// **'?????? nightly ???'**
  String get updateCurrent;

  /// No description provided for @updateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'?????????????'**
  String get updateCheckFailed;

  /// No description provided for @updateInstallPermission.
  ///
  /// In zh, this message translates to:
  /// **'?? Android ????? Tako ??????????????????'**
  String get updateInstallPermission;

  /// No description provided for @updateInstallerOpened.
  ///
  /// In zh, this message translates to:
  /// **'Android ??????????'**
  String get updateInstallerOpened;

  /// No description provided for @updateInstallFailed.
  ///
  /// In zh, this message translates to:
  /// **'??????????????????????????????????'**
  String get updateInstallFailed;

  /// No description provided for @generateChatTitle.
  ///
  /// In zh, this message translates to:
  /// **'??????'**
  String get generateChatTitle;

  /// No description provided for @titleGenerationFailed.
  ///
  /// In zh, this message translates to:
  /// **'????????????????'**
  String get titleGenerationFailed;

  /// No description provided for @toolRunSummary.
  ///
  /// In zh, this message translates to:
  /// **'{tool} · {count} 個步驟'**
  String toolRunSummary(String tool, int count);

  /// No description provided for @toolRunTitle.
  ///
  /// In zh, this message translates to:
  /// **'工具執行過程'**
  String get toolRunTitle;

  /// No description provided for @toolRunIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'未記錄結果'**
  String get toolRunIncomplete;

  /// No description provided for @toolRunUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'目前的對話分支已不包含這段工具執行過程。'**
  String get toolRunUnavailable;

  /// No description provided for @undo.
  ///
  /// In zh, this message translates to:
  /// **'復原'**
  String get undo;

  /// No description provided for @deleteAttachmentBody.
  ///
  /// In zh, this message translates to:
  /// **'此附件可能仍被較早的對話使用。刪除後，相關圖片／檔案將無法讀取；操作後會提供備份與復原。'**
  String get deleteAttachmentBody;

  /// No description provided for @toolsSettings.
  ///
  /// In zh, this message translates to:
  /// **'工具與權限'**
  String get toolsSettings;

  /// No description provided for @toolsEnabled.
  ///
  /// In zh, this message translates to:
  /// **'啟用工具'**
  String get toolsEnabled;

  /// No description provided for @maxToolSteps.
  ///
  /// In zh, this message translates to:
  /// **'????????????????'**
  String get maxToolSteps;

  /// No description provided for @maxScreenToolSteps.
  ///
  /// In zh, this message translates to:
  /// **'??????????????????'**
  String get maxScreenToolSteps;

  /// No description provided for @toolOutputLimit.
  ///
  /// In zh, this message translates to:
  /// **'工具結果長度上限（字元）'**
  String get toolOutputLimit;

  /// No description provided for @permissions.
  ///
  /// In zh, this message translates to:
  /// **'權限'**
  String get permissions;

  /// No description provided for @fullPermissions.
  ///
  /// In zh, this message translates to:
  /// **'完整權限'**
  String get fullPermissions;

  /// No description provided for @fullPermissionsWarning.
  ///
  /// In zh, this message translates to:
  /// **'讀取私人資料及可復原的操作將不再詢問。高風險操作仍需逐次確認。'**
  String get fullPermissionsWarning;

  /// No description provided for @skipHighRisk.
  ///
  /// In zh, this message translates to:
  /// **'也略過高風險確認'**
  String get skipHighRisk;

  /// No description provided for @skipHighRiskWarning.
  ///
  /// In zh, this message translates to:
  /// **'工具將能傳送資料、刪除檔案或進行變更，而不再逐次確認。僅在你接受這些操作時啟用。'**
  String get skipHighRiskWarning;

  /// No description provided for @toolOverrides.
  ///
  /// In zh, this message translates to:
  /// **'個別工具'**
  String get toolOverrides;

  /// No description provided for @defaultPolicy.
  ///
  /// In zh, this message translates to:
  /// **'預設規則'**
  String get defaultPolicy;

  /// No description provided for @alwaysAllow.
  ///
  /// In zh, this message translates to:
  /// **'永遠允許此工具'**
  String get alwaysAllow;

  /// No description provided for @alwaysAsk.
  ///
  /// In zh, this message translates to:
  /// **'每次詢問'**
  String get alwaysAsk;

  /// No description provided for @deny.
  ///
  /// In zh, this message translates to:
  /// **'拒絕'**
  String get deny;

  /// No description provided for @allowOnce.
  ///
  /// In zh, this message translates to:
  /// **'允許這一次'**
  String get allowOnce;

  /// No description provided for @allowChat.
  ///
  /// In zh, this message translates to:
  /// **'此對話允許'**
  String get allowChat;

  /// No description provided for @approvalTitle.
  ///
  /// In zh, this message translates to:
  /// **'工具操作確認'**
  String get approvalTitle;

  /// No description provided for @approvalBody.
  ///
  /// In zh, this message translates to:
  /// **'請確認操作內容與完整參數，再決定是否允許。'**
  String get approvalBody;

  /// No description provided for @riskSafe.
  ///
  /// In zh, this message translates to:
  /// **'安全'**
  String get riskSafe;

  /// No description provided for @riskSensitive.
  ///
  /// In zh, this message translates to:
  /// **'讀取私人資料'**
  String get riskSensitive;

  /// No description provided for @riskAction.
  ///
  /// In zh, this message translates to:
  /// **'進行變更'**
  String get riskAction;

  /// No description provided for @riskHigh.
  ///
  /// In zh, this message translates to:
  /// **'高風險操作'**
  String get riskHigh;

  /// No description provided for @auditLog.
  ///
  /// In zh, this message translates to:
  /// **'工具活動紀錄'**
  String get auditLog;

  /// No description provided for @clearAudit.
  ///
  /// In zh, this message translates to:
  /// **'清除紀錄'**
  String get clearAudit;

  /// No description provided for @clearAuditBody.
  ///
  /// In zh, this message translates to:
  /// **'刪除本機的工具活動紀錄？'**
  String get clearAuditBody;

  /// No description provided for @noAudit.
  ///
  /// In zh, this message translates to:
  /// **'尚無工具活動。'**
  String get noAudit;

  /// No description provided for @arguments.
  ///
  /// In zh, this message translates to:
  /// **'參數'**
  String get arguments;

  /// No description provided for @result.
  ///
  /// In zh, this message translates to:
  /// **'結果'**
  String get result;

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'網路搜尋'**
  String get search;

  /// No description provided for @searchProvider.
  ///
  /// In zh, this message translates to:
  /// **'搜尋供應商'**
  String get searchProvider;

  /// No description provided for @searchUrl.
  ///
  /// In zh, this message translates to:
  /// **'搜尋端點'**
  String get searchUrl;

  /// No description provided for @searchKey.
  ///
  /// In zh, this message translates to:
  /// **'搜尋 API 金鑰'**
  String get searchKey;

  /// No description provided for @searchResults.
  ///
  /// In zh, this message translates to:
  /// **'結果筆數'**
  String get searchResults;

  /// No description provided for @searchHelp.
  ///
  /// In zh, this message translates to:
  /// **'搜尋金鑰保存在安全儲存空間，各供應商分開保存。'**
  String get searchHelp;

  /// No description provided for @searchKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'安全儲存在此裝置上'**
  String get searchKeyHint;

  /// No description provided for @searchOptionalToken.
  ///
  /// In zh, this message translates to:
  /// **'Bearer 權杖（選填）'**
  String get searchOptionalToken;

  /// No description provided for @searchSerperHelp.
  ///
  /// In zh, this message translates to:
  /// **'透過 Serper 搜尋 Google。填入 Serper API 金鑰即可使用預設端點。'**
  String get searchSerperHelp;

  /// No description provided for @searchDdgsHelp.
  ///
  /// In zh, this message translates to:
  /// **'填入你的 DDGS API 服務網址（ddgs api）。一般不需金鑰；若服務或反向代理採用 Bearer 驗證，可填入權杖。'**
  String get searchDdgsHelp;

  /// No description provided for @searchSearxngHelp.
  ///
  /// In zh, this message translates to:
  /// **'填入你的 SearXNG 服務網址，伺服器必須啟用 JSON 搜尋結果。'**
  String get searchSearxngHelp;

  /// No description provided for @files.
  ///
  /// In zh, this message translates to:
  /// **'檔案'**
  String get files;

  /// No description provided for @attach.
  ///
  /// In zh, this message translates to:
  /// **'附加圖片或文件'**
  String get attach;

  /// No description provided for @camera.
  ///
  /// In zh, this message translates to:
  /// **'相機'**
  String get camera;

  /// No description provided for @photos.
  ///
  /// In zh, this message translates to:
  /// **'相片'**
  String get photos;

  /// No description provided for @attachmentBusy.
  ///
  /// In zh, this message translates to:
  /// **'請等目前的操作完成後，再加入圖片。'**
  String get attachmentBusy;

  /// No description provided for @attachmentLimit.
  ///
  /// In zh, this message translates to:
  /// **'每則訊息最多可附加 8 個圖片或檔案。'**
  String get attachmentLimit;

  /// No description provided for @imageUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'無法讀取這張圖片，請改由「相片」或「檔案」選取。'**
  String get imageUnavailable;

  /// No description provided for @unsupportedImage.
  ///
  /// In zh, this message translates to:
  /// **'不支援此圖片格式，請選取 PNG、JPEG、GIF 或 WebP 圖片。'**
  String get unsupportedImage;

  /// No description provided for @importFiles.
  ///
  /// In zh, this message translates to:
  /// **'匯入檔案'**
  String get importFiles;

  /// No description provided for @emptyFiles.
  ///
  /// In zh, this message translates to:
  /// **'工作區目前沒有檔案。'**
  String get emptyFiles;

  /// No description provided for @filePreview.
  ///
  /// In zh, this message translates to:
  /// **'檔案預覽'**
  String get filePreview;

  /// No description provided for @deleteFileBody.
  ///
  /// In zh, this message translates to:
  /// **'刪除此工作區檔案？會保留一份備份。'**
  String get deleteFileBody;

  /// No description provided for @workspace.
  ///
  /// In zh, this message translates to:
  /// **'工作區'**
  String get workspace;

  /// No description provided for @restoreFiles.
  ///
  /// In zh, this message translates to:
  /// **'還原工作區檔案'**
  String get restoreFiles;

  /// No description provided for @sideEffectsTitle.
  ///
  /// In zh, this message translates to:
  /// **'這些操作已經發生'**
  String get sideEffectsTitle;

  /// No description provided for @sideEffectsBody.
  ///
  /// In zh, this message translates to:
  /// **'回溯對話不會撤銷以下操作。你可以先還原可用的工作區備份，以及移除之後新存入的記憶。'**
  String get sideEffectsBody;

  /// No description provided for @restoreAndRewind.
  ///
  /// In zh, this message translates to:
  /// **'還原並回溯'**
  String get restoreAndRewind;

  /// No description provided for @rewindOnly.
  ///
  /// In zh, this message translates to:
  /// **'只回溯對話'**
  String get rewindOnly;

  /// No description provided for @visionRequired.
  ///
  /// In zh, this message translates to:
  /// **'请选择支持视觉或参考图的模型，再发送图片。'**
  String get visionRequired;

  /// No description provided for @toolStepLimit.
  ///
  /// In zh, this message translates to:
  /// **'已達工具呼叫上限。請檢查目前結果，需要時按「繼續」。'**
  String get toolStepLimit;

  /// No description provided for @toolRunning.
  ///
  /// In zh, this message translates to:
  /// **'執行中'**
  String get toolRunning;

  /// No description provided for @toolWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get toolWaiting;

  /// No description provided for @toolCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get toolCompleted;

  /// No description provided for @toolFailed.
  ///
  /// In zh, this message translates to:
  /// **'失敗'**
  String get toolFailed;

  /// No description provided for @toolsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'請在此模型的能力設定中啟用工具呼叫，才能使用工具。'**
  String get toolsUnavailable;

  /// No description provided for @deviceStatusTool.
  ///
  /// In zh, this message translates to:
  /// **'讀取裝置狀態'**
  String get deviceStatusTool;

  /// No description provided for @locationTool.
  ///
  /// In zh, this message translates to:
  /// **'讀取位置'**
  String get locationTool;

  /// No description provided for @clipboardReadTool.
  ///
  /// In zh, this message translates to:
  /// **'讀取剪貼簿'**
  String get clipboardReadTool;

  /// No description provided for @clipboardWriteTool.
  ///
  /// In zh, this message translates to:
  /// **'寫入剪貼簿'**
  String get clipboardWriteTool;

  /// No description provided for @calendarListTool.
  ///
  /// In zh, this message translates to:
  /// **'讀取行事曆'**
  String get calendarListTool;

  /// No description provided for @calendarAddTool.
  ///
  /// In zh, this message translates to:
  /// **'新增行事曆活動'**
  String get calendarAddTool;

  /// No description provided for @alarmTool.
  ///
  /// In zh, this message translates to:
  /// **'設定鬧鐘'**
  String get alarmTool;

  /// No description provided for @timerTool.
  ///
  /// In zh, this message translates to:
  /// **'設定計時器'**
  String get timerTool;

  /// No description provided for @openUrlTool.
  ///
  /// In zh, this message translates to:
  /// **'開啟網址'**
  String get openUrlTool;

  /// No description provided for @openAppTool.
  ///
  /// In zh, this message translates to:
  /// **'開啟 App'**
  String get openAppTool;

  /// No description provided for @searchTool.
  ///
  /// In zh, this message translates to:
  /// **'搜尋網路'**
  String get searchTool;

  /// No description provided for @fetchTool.
  ///
  /// In zh, this message translates to:
  /// **'讀取網頁'**
  String get fetchTool;

  /// No description provided for @fileListTool.
  ///
  /// In zh, this message translates to:
  /// **'列出檔案'**
  String get fileListTool;

  /// No description provided for @fileReadTool.
  ///
  /// In zh, this message translates to:
  /// **'讀取檔案'**
  String get fileReadTool;

  /// No description provided for @fileWriteTool.
  ///
  /// In zh, this message translates to:
  /// **'寫入檔案'**
  String get fileWriteTool;

  /// No description provided for @fileDeleteTool.
  ///
  /// In zh, this message translates to:
  /// **'刪除檔案'**
  String get fileDeleteTool;

  /// No description provided for @toolDisabled.
  ///
  /// In zh, this message translates to:
  /// **'無法使用'**
  String get toolDisabled;

  /// No description provided for @highRiskKeywords.
  ///
  /// In zh, this message translates to:
  /// **'高風險關鍵字（每行一個）'**
  String get highRiskKeywords;

  /// No description provided for @importFailed.
  ///
  /// In zh, this message translates to:
  /// **'無法匯入所選檔案。'**
  String get importFailed;

  /// No description provided for @restoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'有備份無法還原，對話尚未回溯。'**
  String get restoreFailed;

  /// No description provided for @toolResultAttachment.
  ///
  /// In zh, this message translates to:
  /// **'工具附件'**
  String get toolResultAttachment;

  /// No description provided for @noBackup.
  ///
  /// In zh, this message translates to:
  /// **'沒有工作區備份'**
  String get noBackup;

  /// No description provided for @systemPermissionHint.
  ///
  /// In zh, this message translates to:
  /// **'允許後，Android 可能會再詢問系統權限。'**
  String get systemPermissionHint;

  /// No description provided for @newChat.
  ///
  /// In zh, this message translates to:
  /// **'新對話'**
  String get newChat;

  /// No description provided for @chats.
  ///
  /// In zh, this message translates to:
  /// **'對話'**
  String get chats;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'設定'**
  String get settings;

  /// No description provided for @providers.
  ///
  /// In zh, this message translates to:
  /// **'模型供應商'**
  String get providers;

  /// No description provided for @addProvider.
  ///
  /// In zh, this message translates to:
  /// **'新增供應商'**
  String get addProvider;

  /// No description provided for @editProvider.
  ///
  /// In zh, this message translates to:
  /// **'編輯供應商'**
  String get editProvider;

  /// No description provided for @noProviders.
  ///
  /// In zh, this message translates to:
  /// **'連接你的模型'**
  String get noProviders;

  /// No description provided for @welcome.
  ///
  /// In zh, this message translates to:
  /// **'留一點空間，好好想想。'**
  String get welcome;

  /// No description provided for @welcomeBody.
  ///
  /// In zh, this message translates to:
  /// **'提問、探索，或一起理清思緒。對話保存在這台裝置上。'**
  String get welcomeBody;

  /// No description provided for @setupBody.
  ///
  /// In zh, this message translates to:
  /// **'新增雲端供應商、本機伺服器或裝置上模型，即可開始聊天。由你決定訊息送往哪裡。'**
  String get setupBody;

  /// No description provided for @messageHint.
  ///
  /// In zh, this message translates to:
  /// **'想問什麼？'**
  String get messageHint;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'傳送'**
  String get send;

  /// No description provided for @stop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get stop;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重試'**
  String get retry;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'儲存'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'刪除'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'關閉'**
  String get close;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'複製'**
  String get copy;

  /// No description provided for @copyMarkdown.
  ///
  /// In zh, this message translates to:
  /// **'複製 Markdown'**
  String get copyMarkdown;

  /// No description provided for @selectText.
  ///
  /// In zh, this message translates to:
  /// **'選取文字'**
  String get selectText;

  /// No description provided for @copied.
  ///
  /// In zh, this message translates to:
  /// **'已複製'**
  String get copied;

  /// No description provided for @share.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get share;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'編輯'**
  String get edit;

  /// No description provided for @regenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get regenerate;

  /// No description provided for @rewind.
  ///
  /// In zh, this message translates to:
  /// **'回到這裡'**
  String get rewind;

  /// No description provided for @rewindDelete.
  ///
  /// In zh, this message translates to:
  /// **'回到這裡並刪除後續'**
  String get rewindDelete;

  /// No description provided for @rewindDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'刪除此訊息之後的所有分支？此操作無法復原。'**
  String get rewindDeleteBody;

  /// No description provided for @deleteChatBody.
  ///
  /// In zh, this message translates to:
  /// **'刪除此對話及所有分支？'**
  String get deleteChatBody;

  /// No description provided for @thinking.
  ///
  /// In zh, this message translates to:
  /// **'思考過程'**
  String get thinking;

  /// No description provided for @you.
  ///
  /// In zh, this message translates to:
  /// **'你'**
  String get you;

  /// No description provided for @image.
  ///
  /// In zh, this message translates to:
  /// **'圖片'**
  String get image;

  /// No description provided for @file.
  ///
  /// In zh, this message translates to:
  /// **'檔案'**
  String get file;

  /// No description provided for @stopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get stopped;

  /// No description provided for @streaming.
  ///
  /// In zh, this message translates to:
  /// **'正在撰寫⋯'**
  String get streaming;

  /// No description provided for @providerName.
  ///
  /// In zh, this message translates to:
  /// **'顯示名稱'**
  String get providerName;

  /// No description provided for @apiType.
  ///
  /// In zh, this message translates to:
  /// **'API 格式'**
  String get apiType;

  /// No description provided for @baseUrl.
  ///
  /// In zh, this message translates to:
  /// **'基底網址'**
  String get baseUrl;

  /// No description provided for @apiKey.
  ///
  /// In zh, this message translates to:
  /// **'API 金鑰'**
  String get apiKey;

  /// No description provided for @keyHint.
  ///
  /// In zh, this message translates to:
  /// **'本機伺服器可留空'**
  String get keyHint;

  /// No description provided for @keyStored.
  ///
  /// In zh, this message translates to:
  /// **'金鑰已安全儲存 · 留空以保留'**
  String get keyStored;

  /// No description provided for @removeKey.
  ///
  /// In zh, this message translates to:
  /// **'移除已儲存的金鑰'**
  String get removeKey;

  /// No description provided for @model.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get model;

  /// No description provided for @modelHint.
  ///
  /// In zh, this message translates to:
  /// **'輸入模型 ID 或載入清單'**
  String get modelHint;

  /// No description provided for @loadModels.
  ///
  /// In zh, this message translates to:
  /// **'載入模型'**
  String get loadModels;

  /// No description provided for @testConnection.
  ///
  /// In zh, this message translates to:
  /// **'測試連線'**
  String get testConnection;

  /// No description provided for @connectionOk.
  ///
  /// In zh, this message translates to:
  /// **'連線成功，模型清單可用。'**
  String get connectionOk;

  /// No description provided for @connectionHelp.
  ///
  /// In zh, this message translates to:
  /// **'測試模型清單端點。若供應商不支援此端點，仍可手動輸入模型。'**
  String get connectionHelp;

  /// No description provided for @extraHeaders.
  ///
  /// In zh, this message translates to:
  /// **'額外標頭（JSON 物件）'**
  String get extraHeaders;

  /// No description provided for @headersHint.
  ///
  /// In zh, this message translates to:
  /// **'與金鑰一起安全儲存'**
  String get headersHint;

  /// No description provided for @headersStored.
  ///
  /// In zh, this message translates to:
  /// **'標頭已安全儲存 · 留空以保留'**
  String get headersStored;

  /// No description provided for @removeHeaders.
  ///
  /// In zh, this message translates to:
  /// **'移除已儲存的標頭'**
  String get removeHeaders;

  /// No description provided for @localProvider.
  ///
  /// In zh, this message translates to:
  /// **'本機供應商'**
  String get localProvider;

  /// No description provided for @localDescription.
  ///
  /// In zh, this message translates to:
  /// **'自動辨識回環與區域網路位址，也可以手動設定。'**
  String get localDescription;

  /// No description provided for @toolsCapability.
  ///
  /// In zh, this message translates to:
  /// **'工具呼叫'**
  String get toolsCapability;

  /// No description provided for @visionCapability.
  ///
  /// In zh, this message translates to:
  /// **'視覺'**
  String get visionCapability;

  /// No description provided for @visionCapabilityHelp.
  ///
  /// In zh, this message translates to:
  /// **'让模型理解聊天中的图片。图片生成需要单独设置。'**
  String get visionCapabilityHelp;

  /// No description provided for @imageGeneration.
  ///
  /// In zh, this message translates to:
  /// **'图片生成'**
  String get imageGeneration;

  /// No description provided for @imageGenerationNone.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get imageGenerationNone;

  /// No description provided for @imageGenerationImagesApi.
  ///
  /// In zh, this message translates to:
  /// **'Images API'**
  String get imageGenerationImagesApi;

  /// No description provided for @imageGenerationChatOutput.
  ///
  /// In zh, this message translates to:
  /// **'聊天中输出图片'**
  String get imageGenerationChatOutput;

  /// No description provided for @imageGenerationResponsesTool.
  ///
  /// In zh, this message translates to:
  /// **'Responses 生图工具'**
  String get imageGenerationResponsesTool;

  /// No description provided for @imageGenerationHelp.
  ///
  /// In zh, this message translates to:
  /// **'选择此模型支持的生图格式。你可以直接选择它生成图片，也可以让聊天模型通过生图工具调用它。'**
  String get imageGenerationHelp;

  /// No description provided for @imageGenerationProtocolHelp.
  ///
  /// In zh, this message translates to:
  /// **'图片生成需要兼容 OpenAI Chat Completions 或 Responses 的供应商。'**
  String get imageGenerationProtocolHelp;

  /// No description provided for @imageReferenceInput.
  ///
  /// In zh, this message translates to:
  /// **'参考图'**
  String get imageReferenceInput;

  /// No description provided for @imageReferenceInputHelp.
  ///
  /// In zh, this message translates to:
  /// **'允许将附件图片用于参考生图或编辑。仅在此模型支持生图图片输入时开启。'**
  String get imageReferenceInputHelp;

  /// No description provided for @imageGenerationTool.
  ///
  /// In zh, this message translates to:
  /// **'生成图片'**
  String get imageGenerationTool;

  /// No description provided for @reasoningCapability.
  ///
  /// In zh, this message translates to:
  /// **'推理'**
  String get reasoningCapability;

  /// No description provided for @capabilities.
  ///
  /// In zh, this message translates to:
  /// **'模型能力'**
  String get capabilities;

  /// No description provided for @contextWindow.
  ///
  /// In zh, this message translates to:
  /// **'上下文長度（token）'**
  String get contextWindow;

  /// No description provided for @maxOutput.
  ///
  /// In zh, this message translates to:
  /// **'輸出上限（token）'**
  String get maxOutput;

  /// No description provided for @reasoningMode.
  ///
  /// In zh, this message translates to:
  /// **'推理模式'**
  String get reasoningMode;

  /// No description provided for @reasoningOff.
  ///
  /// In zh, this message translates to:
  /// **'供應商預設'**
  String get reasoningOff;

  /// No description provided for @reasoningEnabled.
  ///
  /// In zh, this message translates to:
  /// **'啟用（預算）'**
  String get reasoningEnabled;

  /// No description provided for @reasoningAdaptive.
  ///
  /// In zh, this message translates to:
  /// **'自適應'**
  String get reasoningAdaptive;

  /// No description provided for @thinkingBudget.
  ///
  /// In zh, this message translates to:
  /// **'思考預算（token）'**
  String get thinkingBudget;

  /// No description provided for @reasoningEffort.
  ///
  /// In zh, this message translates to:
  /// **'推理強度'**
  String get reasoningEffort;

  /// No description provided for @requiredField.
  ///
  /// In zh, this message translates to:
  /// **'必填'**
  String get requiredField;

  /// No description provided for @invalidUrl.
  ///
  /// In zh, this message translates to:
  /// **'請輸入 http(s) 網址，不含帳密、查詢參數或片段。'**
  String get invalidUrl;

  /// No description provided for @invalidJson.
  ///
  /// In zh, this message translates to:
  /// **'請輸入標頭值為字串的 JSON 物件。'**
  String get invalidJson;

  /// No description provided for @invalidNumber.
  ///
  /// In zh, this message translates to:
  /// **'請輸入正整數。'**
  String get invalidNumber;

  /// No description provided for @invalidBudget.
  ///
  /// In zh, this message translates to:
  /// **'輸出上限須小於上下文長度。思考預算須至少為 1024，且小於輸出上限。'**
  String get invalidBudget;

  /// No description provided for @operationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失敗，請再試一次。'**
  String get operationFailed;

  /// No description provided for @fileUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'此工作區檔案目前無法使用。'**
  String get fileUnavailable;

  /// No description provided for @contextTrimmed.
  ///
  /// In zh, this message translates to:
  /// **'已裁剪較舊的上下文以符合模型限制'**
  String get contextTrimmed;

  /// No description provided for @contextTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'此訊息超過模型上下文長度，請縮短訊息或在供應商設定中調整長度。'**
  String get contextTooLarge;

  /// No description provided for @noProviderSelected.
  ///
  /// In zh, this message translates to:
  /// **'請先在設定中選擇供應商。'**
  String get noProviderSelected;

  /// No description provided for @providerRemoved.
  ///
  /// In zh, this message translates to:
  /// **'此對話的供應商已無法使用，請選擇其他供應商。'**
  String get providerRemoved;

  /// No description provided for @changeProvider.
  ///
  /// In zh, this message translates to:
  /// **'更換供應商'**
  String get changeProvider;

  /// No description provided for @changeProviderBody.
  ///
  /// In zh, this message translates to:
  /// **'對話將由此供應商繼續。可見的對話歷史會傳送給它，系統提示詞也會重新產生。'**
  String get changeProviderBody;

  /// No description provided for @continueAction.
  ///
  /// In zh, this message translates to:
  /// **'繼續'**
  String get continueAction;

  /// No description provided for @appearance.
  ///
  /// In zh, this message translates to:
  /// **'外觀'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In zh, this message translates to:
  /// **'主題'**
  String get theme;

  /// No description provided for @systemTheme.
  ///
  /// In zh, this message translates to:
  /// **'跟隨系統'**
  String get systemTheme;

  /// No description provided for @lightTheme.
  ///
  /// In zh, this message translates to:
  /// **'淺色'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get darkTheme;

  /// No description provided for @textSize.
  ///
  /// In zh, this message translates to:
  /// **'文字大小'**
  String get textSize;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'語言'**
  String get language;

  /// No description provided for @privacy.
  ///
  /// In zh, this message translates to:
  /// **'以本機為本'**
  String get privacy;

  /// No description provided for @privacyBody.
  ///
  /// In zh, this message translates to:
  /// **'對話與記憶保存在此裝置。聊天時，你的訊息以及工具讀到的內容（例如畫面或通知）會傳送給你選擇的模型供應商；使用裝置上模型時，這些內容不會離開這支手機。API 金鑰與額外標頭保存在安全儲存空間。沒有帳號、分析或遙測。'**
  String get privacyBody;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'關於'**
  String get about;

  /// No description provided for @developerContext.
  ///
  /// In zh, this message translates to:
  /// **'已儲存的上下文'**
  String get developerContext;

  /// No description provided for @noChats.
  ///
  /// In zh, this message translates to:
  /// **'你的對話會顯示在這裡。'**
  String get noChats;

  /// No description provided for @chooseProvider.
  ///
  /// In zh, this message translates to:
  /// **'選擇供應商'**
  String get chooseProvider;

  /// No description provided for @previousBranch.
  ///
  /// In zh, this message translates to:
  /// **'上一個分支'**
  String get previousBranch;

  /// No description provided for @nextBranch.
  ///
  /// In zh, this message translates to:
  /// **'下一個分支'**
  String get nextBranch;

  /// No description provided for @providerDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'移除此供應商及其憑證？對話將予以保留。'**
  String get providerDeleteBody;

  /// No description provided for @emptyResponse.
  ///
  /// In zh, this message translates to:
  /// **'供應商未回傳回覆，請重試或檢查模型設定。'**
  String get emptyResponse;

  /// No description provided for @toolsLater.
  ///
  /// In zh, this message translates to:
  /// **'此請求尚未啟用工具，或工具目前無法使用。'**
  String get toolsLater;

  /// No description provided for @builtInSearch.
  ///
  /// In zh, this message translates to:
  /// **'供應商內建網路搜尋'**
  String get builtInSearch;

  /// No description provided for @builtInSearchHelp.
  ///
  /// In zh, this message translates to:
  /// **'使用模型供應商的原生搜尋；關閉時使用「搜尋」設定中的供應商。仍受工具權限規則控制。'**
  String get builtInSearchHelp;

  /// No description provided for @allowCustomSearchEndpoint.
  ///
  /// In zh, this message translates to:
  /// **'允許相容代理（CPA）'**
  String get allowCustomSearchEndpoint;

  /// No description provided for @allowCustomSearchEndpointHelp.
  ///
  /// In zh, this message translates to:
  /// **'向此自訂端點送出原生搜尋工具。代理必須保留 Responses 或 Messages 搜尋格式；未開啟時只自動允許官方端點。'**
  String get allowCustomSearchEndpointHelp;

  /// No description provided for @testNativeSearch.
  ///
  /// In zh, this message translates to:
  /// **'測試原生搜尋'**
  String get testNativeSearch;

  /// No description provided for @nativeSearchTesting.
  ///
  /// In zh, this message translates to:
  /// **'正在測試原生搜尋⋯'**
  String get nativeSearchTesting;

  /// No description provided for @nativeSearchTestHelp.
  ///
  /// In zh, this message translates to:
  /// **'使用目前模型與端點搜尋一次 Flutter 官方網站，可能產生 API 費用。不會傳送對話紀錄、自動啟用搜尋或儲存設定。'**
  String get nativeSearchTestHelp;

  /// No description provided for @nativeSearchSupported.
  ///
  /// In zh, this message translates to:
  /// **'測試成功：供應商確實完成了原生搜尋。'**
  String get nativeSearchSupported;

  /// No description provided for @nativeSearchNotObserved.
  ///
  /// In zh, this message translates to:
  /// **'端點有回應，但未收到原生搜尋完成紀錄。可能是代理移除了搜尋工具，或此轉送路徑不支援。'**
  String get nativeSearchNotObserved;

  /// No description provided for @nativeSearchProtocolHelp.
  ///
  /// In zh, this message translates to:
  /// **'此處的原生搜尋需使用 OpenAI Responses 或 Anthropic Messages。Chat Completions 請搭配「搜尋」設定中的供應商。'**
  String get nativeSearchProtocolHelp;

  /// No description provided for @nativeSearchDisabled.
  ///
  /// In zh, this message translates to:
  /// **'請先在「工具與權限」啟用工具與網路搜尋。'**
  String get nativeSearchDisabled;

  /// No description provided for @nativeSearchDenied.
  ///
  /// In zh, this message translates to:
  /// **'這次測試已被網路搜尋權限規則拒絕。'**
  String get nativeSearchDenied;

  /// No description provided for @nativeSearchFailed.
  ///
  /// In zh, this message translates to:
  /// **'原生搜尋測試失敗，請確認模型與代理轉送路徑支援原生搜尋。'**
  String get nativeSearchFailed;

  /// No description provided for @nativeSearchCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消原生搜尋測試。'**
  String get nativeSearchCancelled;

  /// No description provided for @nativeSearchTimeout.
  ///
  /// In zh, this message translates to:
  /// **'原生搜尋測試逾時，已取消請求。'**
  String get nativeSearchTimeout;

  /// No description provided for @nativeSearchBusy.
  ///
  /// In zh, this message translates to:
  /// **'請等待目前工作結束後再測試。'**
  String get nativeSearchBusy;

  /// No description provided for @localLabel.
  ///
  /// In zh, this message translates to:
  /// **'本機'**
  String get localLabel;

  /// No description provided for @cloudLabel.
  ///
  /// In zh, this message translates to:
  /// **'雲端'**
  String get cloudLabel;

  /// No description provided for @connectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'連線失敗'**
  String get connectionFailed;

  /// No description provided for @noModels.
  ///
  /// In zh, this message translates to:
  /// **'未取得模型，請手動輸入模型 ID。'**
  String get noModels;

  /// No description provided for @viewImage.
  ///
  /// In zh, this message translates to:
  /// **'檢視圖片'**
  String get viewImage;

  /// No description provided for @openImageLink.
  ///
  /// In zh, this message translates to:
  /// **'在瀏覽器開啟圖片'**
  String get openImageLink;

  /// No description provided for @renameChat.
  ///
  /// In zh, this message translates to:
  /// **'重新命名對話'**
  String get renameChat;

  /// No description provided for @chatTitle.
  ///
  /// In zh, this message translates to:
  /// **'對話標題'**
  String get chatTitle;

  /// No description provided for @messageActions.
  ///
  /// In zh, this message translates to:
  /// **'訊息選項'**
  String get messageActions;

  /// No description provided for @models.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get models;

  /// No description provided for @addModel.
  ///
  /// In zh, this message translates to:
  /// **'新增模型'**
  String get addModel;

  /// No description provided for @addModels.
  ///
  /// In zh, this message translates to:
  /// **'加入所選模型'**
  String get addModels;

  /// No description provided for @newModel.
  ///
  /// In zh, this message translates to:
  /// **'新模型'**
  String get newModel;

  /// No description provided for @duplicateModel.
  ///
  /// In zh, this message translates to:
  /// **'此模型已經加入。'**
  String get duplicateModel;

  /// No description provided for @autoModelSpecs.
  ///
  /// In zh, this message translates to:
  /// **'自動辨識模型規格'**
  String get autoModelSpecs;

  /// No description provided for @knownModelSpecs.
  ///
  /// In zh, this message translates to:
  /// **'已套用已知規格，可自行調整限制與能力。'**
  String get knownModelSpecs;

  /// No description provided for @unknownModelSpecs.
  ///
  /// In zh, this message translates to:
  /// **'未知模型：目前使用預設值，請依伺服器支援的規格調整。'**
  String get unknownModelSpecs;

  /// No description provided for @officialModelId.
  ///
  /// In zh, this message translates to:
  /// **'官方 API 模型 ID'**
  String get officialModelId;

  /// No description provided for @chooseModel.
  ///
  /// In zh, this message translates to:
  /// **'選擇模型'**
  String get chooseModel;

  /// No description provided for @memory.
  ///
  /// In zh, this message translates to:
  /// **'記憶'**
  String get memory;

  /// No description provided for @memoryEnabled.
  ///
  /// In zh, this message translates to:
  /// **'使用記憶'**
  String get memoryEnabled;

  /// No description provided for @memoryEnabledHelp.
  ///
  /// In zh, this message translates to:
  /// **'{app} 可以儲存並查詢你提供的長期資訊。釘選的個人檔案與偏好會加入新的對話。'**
  String memoryEnabledHelp(String app);

  /// No description provided for @memoryOff.
  ///
  /// In zh, this message translates to:
  /// **'記憶已關閉。已儲存的記憶會保留，但不會在對話中使用。'**
  String get memoryOff;

  /// No description provided for @memorySearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜尋記憶'**
  String get memorySearchHint;

  /// No description provided for @memoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'還沒有記憶。可以請 {app} 記住某件事，或在這裡新增。'**
  String memoryEmpty(String app);

  /// No description provided for @memoryNoMatches.
  ///
  /// In zh, this message translates to:
  /// **'沒有符合的記憶。'**
  String get memoryNoMatches;

  /// No description provided for @addMemory.
  ///
  /// In zh, this message translates to:
  /// **'新增記憶'**
  String get addMemory;

  /// No description provided for @editMemory.
  ///
  /// In zh, this message translates to:
  /// **'編輯記憶'**
  String get editMemory;

  /// No description provided for @memoryText.
  ///
  /// In zh, this message translates to:
  /// **'內容'**
  String get memoryText;

  /// No description provided for @memoryKind.
  ///
  /// In zh, this message translates to:
  /// **'類型'**
  String get memoryKind;

  /// No description provided for @memoryKindProfile.
  ///
  /// In zh, this message translates to:
  /// **'個人檔案'**
  String get memoryKindProfile;

  /// No description provided for @memoryKindPreference.
  ///
  /// In zh, this message translates to:
  /// **'偏好'**
  String get memoryKindPreference;

  /// No description provided for @memoryKindFact.
  ///
  /// In zh, this message translates to:
  /// **'事實'**
  String get memoryKindFact;

  /// No description provided for @memoryPinned.
  ///
  /// In zh, this message translates to:
  /// **'已釘選'**
  String get memoryPinned;

  /// No description provided for @memoryPin.
  ///
  /// In zh, this message translates to:
  /// **'釘選'**
  String get memoryPin;

  /// No description provided for @memoryUnpin.
  ///
  /// In zh, this message translates to:
  /// **'取消釘選'**
  String get memoryUnpin;

  /// No description provided for @memoryPinHelp.
  ///
  /// In zh, this message translates to:
  /// **'釘選的個人檔案與偏好會加入新的對話。'**
  String get memoryPinHelp;

  /// No description provided for @memoryProfileUsage.
  ///
  /// In zh, this message translates to:
  /// **'釘選的個人檔案：{words}/{limit} 字'**
  String memoryProfileUsage(int words, int limit);

  /// No description provided for @memoryProfileTruncated.
  ///
  /// In zh, this message translates to:
  /// **'部分釘選內容超出上限，不會加入新的對話。'**
  String get memoryProfileTruncated;

  /// No description provided for @memoryFromChat.
  ///
  /// In zh, this message translates to:
  /// **'從對話中儲存'**
  String get memoryFromChat;

  /// No description provided for @deleteMemoryBody.
  ///
  /// In zh, this message translates to:
  /// **'要刪除這則記憶嗎？'**
  String get deleteMemoryBody;

  /// No description provided for @deleteAllMemories.
  ///
  /// In zh, this message translates to:
  /// **'刪除所有記憶'**
  String get deleteAllMemories;

  /// No description provided for @deleteAllMemoriesBody.
  ///
  /// In zh, this message translates to:
  /// **'要刪除所有已儲存的記憶嗎？此操作無法復原。'**
  String get deleteAllMemoriesBody;

  /// No description provided for @exportMemories.
  ///
  /// In zh, this message translates to:
  /// **'匯出 JSON'**
  String get exportMemories;

  /// No description provided for @importMemories.
  ///
  /// In zh, this message translates to:
  /// **'匯入 JSON'**
  String get importMemories;

  /// No description provided for @memoriesImported.
  ///
  /// In zh, this message translates to:
  /// **'{count, plural, =0{沒有匯入新的記憶} other{已匯入 {count} 則記憶}}'**
  String memoriesImported(int count);

  /// No description provided for @memoryImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'這不是有效的 {app} 記憶匯出檔。'**
  String memoryImportFailed(String app);

  /// No description provided for @memorySaved.
  ///
  /// In zh, this message translates to:
  /// **'已存入記憶'**
  String get memorySaved;

  /// No description provided for @memoryUndone.
  ///
  /// In zh, this message translates to:
  /// **'已從記憶移除'**
  String get memoryUndone;

  /// No description provided for @memoryChanged.
  ///
  /// In zh, this message translates to:
  /// **'儲存後已被修改或移除'**
  String get memoryChanged;

  /// No description provided for @personalization.
  ///
  /// In zh, this message translates to:
  /// **'個人化'**
  String get personalization;

  /// No description provided for @displayName.
  ///
  /// In zh, this message translates to:
  /// **'{app} 該怎麼稱呼你？'**
  String displayName(String app);

  /// No description provided for @customInstructions.
  ///
  /// In zh, this message translates to:
  /// **'自訂指示'**
  String get customInstructions;

  /// No description provided for @customInstructionsHint.
  ///
  /// In zh, this message translates to:
  /// **'希望 {app} 在每個新對話中都知道或遵守的事'**
  String customInstructionsHint(String app);

  /// No description provided for @replyStyle.
  ///
  /// In zh, this message translates to:
  /// **'回覆風格'**
  String get replyStyle;

  /// No description provided for @replyConcise.
  ///
  /// In zh, this message translates to:
  /// **'簡潔'**
  String get replyConcise;

  /// No description provided for @replyNormal.
  ///
  /// In zh, this message translates to:
  /// **'一般'**
  String get replyNormal;

  /// No description provided for @replyDetailed.
  ///
  /// In zh, this message translates to:
  /// **'詳細'**
  String get replyDetailed;

  /// No description provided for @personalizationHelp.
  ///
  /// In zh, this message translates to:
  /// **'變更會套用到新的對話；既有對話維持開始時的設定。'**
  String get personalizationHelp;

  /// No description provided for @incognitoChat.
  ///
  /// In zh, this message translates to:
  /// **'無痕聊天'**
  String get incognitoChat;

  /// No description provided for @newIncognitoChat.
  ///
  /// In zh, this message translates to:
  /// **'新增無痕聊天'**
  String get newIncognitoChat;

  /// No description provided for @incognitoBody.
  ///
  /// In zh, this message translates to:
  /// **'不使用記憶，離開後這段對話會被刪除。'**
  String get incognitoBody;

  /// No description provided for @browser.
  ///
  /// In zh, this message translates to:
  /// **'瀏覽器'**
  String get browser;

  /// No description provided for @openBrowser.
  ///
  /// In zh, this message translates to:
  /// **'開啟瀏覽器'**
  String get openBrowser;

  /// No description provided for @browserAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'輸入網址'**
  String get browserAddressHint;

  /// No description provided for @browserInvalidAddress.
  ///
  /// In zh, this message translates to:
  /// **'請輸入網址，例如 example.com。'**
  String get browserInvalidAddress;

  /// No description provided for @browserEmpty.
  ///
  /// In zh, this message translates to:
  /// **'輸入網址，或請 {app} 開啟網頁。'**
  String browserEmpty(String app);

  /// No description provided for @browserModelActive.
  ///
  /// In zh, this message translates to:
  /// **'{app} 正在使用瀏覽器'**
  String browserModelActive(String app);

  /// No description provided for @takeOver.
  ///
  /// In zh, this message translates to:
  /// **'接手操作'**
  String get takeOver;

  /// No description provided for @browserBack.
  ///
  /// In zh, this message translates to:
  /// **'上一頁'**
  String get browserBack;

  /// No description provided for @browserForward.
  ///
  /// In zh, this message translates to:
  /// **'下一頁'**
  String get browserForward;

  /// No description provided for @browserReload.
  ///
  /// In zh, this message translates to:
  /// **'重新載入'**
  String get browserReload;

  /// No description provided for @openExternally.
  ///
  /// In zh, this message translates to:
  /// **'在其他應用程式開啟'**
  String get openExternally;

  /// No description provided for @clearBrowsingData.
  ///
  /// In zh, this message translates to:
  /// **'清除瀏覽資料'**
  String get clearBrowsingData;

  /// No description provided for @clearBrowsingDataBody.
  ///
  /// In zh, this message translates to:
  /// **'要刪除內建瀏覽器的 Cookie、網站儲存資料、快取與瀏覽紀錄嗎？你將會登出各個網站。'**
  String get clearBrowsingDataBody;

  /// No description provided for @browsingDataCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除瀏覽資料'**
  String get browsingDataCleared;

  /// No description provided for @openLinksInApp.
  ///
  /// In zh, this message translates to:
  /// **'在內建瀏覽器開啟連結'**
  String get openLinksInApp;

  /// No description provided for @openLinksInAppHelp.
  ///
  /// In zh, this message translates to:
  /// **'關閉時，連結會以預設瀏覽器開啟。內建瀏覽器的 Cookie 與其他瀏覽器分開保存。'**
  String get openLinksInAppHelp;

  /// No description provided for @browserUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'此裝置無法使用內建瀏覽器。'**
  String get browserUnavailable;

  /// No description provided for @downloadTitle.
  ///
  /// In zh, this message translates to:
  /// **'要下載檔案嗎？'**
  String get downloadTitle;

  /// No description provided for @downloadBody.
  ///
  /// In zh, this message translates to:
  /// **'要將來自 {host} 的「{name}」儲存到檔案嗎？'**
  String downloadBody(String name, String host);

  /// No description provided for @download.
  ///
  /// In zh, this message translates to:
  /// **'下載'**
  String get download;

  /// No description provided for @downloadSaved.
  ///
  /// In zh, this message translates to:
  /// **'已儲存到檔案'**
  String get downloadSaved;

  /// No description provided for @downloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'下載失敗。'**
  String get downloadFailed;

  /// No description provided for @downloadTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'無法下載超過 20 MB 的檔案。'**
  String get downloadTooLarge;

  /// No description provided for @approvalElement.
  ///
  /// In zh, this message translates to:
  /// **'元素'**
  String get approvalElement;

  /// No description provided for @approvalPage.
  ///
  /// In zh, this message translates to:
  /// **'網頁'**
  String get approvalPage;

  /// No description provided for @approvalSubmit.
  ///
  /// In zh, this message translates to:
  /// **'送出按鈕'**
  String get approvalSubmit;

  /// No description provided for @memorySearchTool.
  ///
  /// In zh, this message translates to:
  /// **'搜尋記憶'**
  String get memorySearchTool;

  /// No description provided for @memorySaveTool.
  ///
  /// In zh, this message translates to:
  /// **'存入記憶'**
  String get memorySaveTool;

  /// No description provided for @memoryUpdateTool.
  ///
  /// In zh, this message translates to:
  /// **'更新記憶'**
  String get memoryUpdateTool;

  /// No description provided for @memoryDeleteTool.
  ///
  /// In zh, this message translates to:
  /// **'刪除記憶'**
  String get memoryDeleteTool;

  /// No description provided for @browserOpenTool.
  ///
  /// In zh, this message translates to:
  /// **'開啟網頁'**
  String get browserOpenTool;

  /// No description provided for @browserReadTool.
  ///
  /// In zh, this message translates to:
  /// **'讀取瀏覽器頁面'**
  String get browserReadTool;

  /// No description provided for @browserClickTool.
  ///
  /// In zh, this message translates to:
  /// **'在瀏覽器中點擊'**
  String get browserClickTool;

  /// No description provided for @browserTypeTool.
  ///
  /// In zh, this message translates to:
  /// **'在瀏覽器中輸入'**
  String get browserTypeTool;

  /// No description provided for @browserScrollTool.
  ///
  /// In zh, this message translates to:
  /// **'捲動瀏覽器頁面'**
  String get browserScrollTool;

  /// No description provided for @browserBackTool.
  ///
  /// In zh, this message translates to:
  /// **'瀏覽器上一頁'**
  String get browserBackTool;

  /// No description provided for @readScreenTool.
  ///
  /// In zh, this message translates to:
  /// **'讀取螢幕'**
  String get readScreenTool;

  /// No description provided for @tapTool.
  ///
  /// In zh, this message translates to:
  /// **'點按螢幕'**
  String get tapTool;

  /// No description provided for @longPressTool.
  ///
  /// In zh, this message translates to:
  /// **'長按螢幕'**
  String get longPressTool;

  /// No description provided for @swipeTool.
  ///
  /// In zh, this message translates to:
  /// **'在螢幕上滑動'**
  String get swipeTool;

  /// No description provided for @scrollTool.
  ///
  /// In zh, this message translates to:
  /// **'捲動螢幕'**
  String get scrollTool;

  /// No description provided for @typeTextTool.
  ///
  /// In zh, this message translates to:
  /// **'在螢幕上輸入'**
  String get typeTextTool;

  /// No description provided for @pressKeyTool.
  ///
  /// In zh, this message translates to:
  /// **'按系統鍵'**
  String get pressKeyTool;

  /// No description provided for @runShellTool.
  ///
  /// In zh, this message translates to:
  /// **'執行 Shell 指令'**
  String get runShellTool;

  /// No description provided for @notificationsListTool.
  ///
  /// In zh, this message translates to:
  /// **'讀取通知'**
  String get notificationsListTool;

  /// No description provided for @approvalApp.
  ///
  /// In zh, this message translates to:
  /// **'App'**
  String get approvalApp;

  /// No description provided for @approvalPoint.
  ///
  /// In zh, this message translates to:
  /// **'位置'**
  String get approvalPoint;

  /// No description provided for @screenSessionTitle.
  ///
  /// In zh, this message translates to:
  /// **'{app} 正在使用你的手機'**
  String screenSessionTitle(String app);

  /// No description provided for @screenSessionThinking.
  ///
  /// In zh, this message translates to:
  /// **'正在思考下一步…'**
  String get screenSessionThinking;

  /// No description provided for @screenSessionWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待你的核准…'**
  String get screenSessionWaiting;

  /// No description provided for @screenSessionBody.
  ///
  /// In zh, this message translates to:
  /// **'點「停止」即可接手。'**
  String get screenSessionBody;

  /// No description provided for @screenChannel.
  ///
  /// In zh, this message translates to:
  /// **'螢幕控制'**
  String get screenChannel;

  /// No description provided for @alertChannel.
  ///
  /// In zh, this message translates to:
  /// **'核准與回覆'**
  String get alertChannel;

  /// No description provided for @approvalNeededTitle.
  ///
  /// In zh, this message translates to:
  /// **'{app} 需要你的核准'**
  String approvalNeededTitle(String app);

  /// No description provided for @approvalNeededBody.
  ///
  /// In zh, this message translates to:
  /// **'開啟 App 查看這項要求。'**
  String get approvalNeededBody;

  /// No description provided for @replyReadyTitle.
  ///
  /// In zh, this message translates to:
  /// **'{app} 已回覆'**
  String replyReadyTitle(String app);

  /// No description provided for @replyReadyBody.
  ///
  /// In zh, this message translates to:
  /// **'點一下查看回覆。'**
  String get replyReadyBody;

  /// No description provided for @deviceControl.
  ///
  /// In zh, this message translates to:
  /// **'裝置控制'**
  String get deviceControl;

  /// No description provided for @deviceControlHelp.
  ///
  /// In zh, this message translates to:
  /// **'讓 {app} 使用其他 App、你的通知與 Termux。每一項都要在 Android 設定中開啟，所有操作仍需經過工具權限。'**
  String deviceControlHelp(String app);

  /// No description provided for @screenControl.
  ///
  /// In zh, this message translates to:
  /// **'螢幕控制'**
  String get screenControl;

  /// No description provided for @statusOn.
  ///
  /// In zh, this message translates to:
  /// **'已開啟'**
  String get statusOn;

  /// No description provided for @statusOff.
  ///
  /// In zh, this message translates to:
  /// **'未開啟'**
  String get statusOff;

  /// No description provided for @screenControlUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'這個版本不含螢幕控制功能。'**
  String get screenControlUnsupported;

  /// No description provided for @screenControlHelp.
  ///
  /// In zh, this message translates to:
  /// **'{app} 只會在你要求時，透過已核准的工具讀取畫面，並在其他 App 中點按、輸入和捲動。「傳送」、「付款」、「刪除」等按鈕一定會先詢問，也永遠不會填入密碼欄位。'**
  String screenControlHelp(String app);

  /// No description provided for @screenControlDisclosureTitle.
  ///
  /// In zh, this message translates to:
  /// **'要開啟螢幕控制嗎？'**
  String get screenControlDisclosureTitle;

  /// No description provided for @screenControlDisclosure.
  ///
  /// In zh, this message translates to:
  /// **'{app} 會使用 Android 的無障礙服務讀取畫面內容，並替你點按、輸入和捲動。只有螢幕工具執行時才會讀取畫面；讀到的內容會傳送給你選擇的模型供應商並保留在該對話中，不會用於其他用途。請在下一個畫面中找到 {app} 並開啟。'**
  String screenControlDisclosure(String app);

  /// No description provided for @openAccessibilitySettings.
  ///
  /// In zh, this message translates to:
  /// **'開啟無障礙設定'**
  String get openAccessibilitySettings;

  /// No description provided for @restrictedSettingsHelp.
  ///
  /// In zh, this message translates to:
  /// **'如果 Android 顯示這是「受限制的設定」，請開啟應用程式資訊，點右上角的 ⋮ 選單並選擇「允許受限制的設定」，再試一次。'**
  String get restrictedSettingsHelp;

  /// No description provided for @openAppInfo.
  ///
  /// In zh, this message translates to:
  /// **'開啟應用程式資訊'**
  String get openAppInfo;

  /// No description provided for @screenshotsSetting.
  ///
  /// In zh, this message translates to:
  /// **'傳送截圖給視覺模型'**
  String get screenshotsSetting;

  /// No description provided for @screenshotsHelp.
  ///
  /// In zh, this message translates to:
  /// **'模型支援圖片時，read_screen 也會附上截圖。截圖包含畫面上的所有內容，也會使用較多 token。'**
  String get screenshotsHelp;

  /// No description provided for @screenshotsUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'截圖需要 Android 11 以上版本。'**
  String get screenshotsUnsupported;

  /// No description provided for @sessionNotification.
  ///
  /// In zh, this message translates to:
  /// **'操作螢幕時的通知'**
  String get sessionNotification;

  /// No description provided for @sessionNotificationHelp.
  ///
  /// In zh, this message translates to:
  /// **'顯示目前正在操作螢幕，並提供「停止」按鈕。'**
  String get sessionNotificationHelp;

  /// No description provided for @allowNotifications.
  ///
  /// In zh, this message translates to:
  /// **'允許通知'**
  String get allowNotifications;

  /// No description provided for @allowed.
  ///
  /// In zh, this message translates to:
  /// **'已允許'**
  String get allowed;

  /// No description provided for @notificationAccess.
  ///
  /// In zh, this message translates to:
  /// **'通知存取'**
  String get notificationAccess;

  /// No description provided for @notificationAccessHelp.
  ///
  /// In zh, this message translates to:
  /// **'讓 {app} 在你要求時讀取目前的通知。不會在背景讀取或保存。'**
  String notificationAccessHelp(String app);

  /// No description provided for @openNotificationAccess.
  ///
  /// In zh, this message translates to:
  /// **'開啟通知存取設定'**
  String get openNotificationAccess;

  /// No description provided for @termux.
  ///
  /// In zh, this message translates to:
  /// **'Termux（run_shell）'**
  String get termux;

  /// No description provided for @termuxHelp.
  ///
  /// In zh, this message translates to:
  /// **'run_shell 會在 Termux 中執行指令。ls、cat 等唯讀指令視為讀取私人資料；其他指令每次都會詢問。'**
  String get termuxHelp;

  /// No description provided for @termuxNotInstalled.
  ///
  /// In zh, this message translates to:
  /// **'尚未安裝 Termux。請從 F-Droid 或 Termux 的 GitHub Releases 安裝。'**
  String get termuxNotInstalled;

  /// No description provided for @termuxStepOpen.
  ///
  /// In zh, this message translates to:
  /// **'開啟 Termux 一次，等待初始設定完成。'**
  String get termuxStepOpen;

  /// No description provided for @termuxStepProperty.
  ///
  /// In zh, this message translates to:
  /// **'在 Termux 執行以下指令，讓其他 App 可以傳送指令：'**
  String get termuxStepProperty;

  /// No description provided for @termuxStepPermission.
  ///
  /// In zh, this message translates to:
  /// **'允許 {app} 在 Termux 中執行指令。'**
  String termuxStepPermission(String app);

  /// No description provided for @termuxSecurityNote.
  ///
  /// In zh, this message translates to:
  /// **'這項設定會讓任何取得 Termux 權限的 App 都能執行指令。'**
  String get termuxSecurityNote;

  /// No description provided for @openTermux.
  ///
  /// In zh, this message translates to:
  /// **'開啟 Termux'**
  String get openTermux;

  /// No description provided for @testShell.
  ///
  /// In zh, this message translates to:
  /// **'測試'**
  String get testShell;

  /// No description provided for @shellTestPassed.
  ///
  /// In zh, this message translates to:
  /// **'Termux 回應：{output}'**
  String shellTestPassed(String output);

  /// No description provided for @shellTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'測試失敗（{error}）。'**
  String shellTestFailed(String error);

  /// No description provided for @shellTimeout.
  ///
  /// In zh, this message translates to:
  /// **'指令逾時（秒）'**
  String get shellTimeout;

  /// No description provided for @appTagline.
  ///
  /// In zh, this message translates to:
  /// **'本機優先的 AI 助理'**
  String get appTagline;

  /// No description provided for @grantPermission.
  ///
  /// In zh, this message translates to:
  /// **'允許'**
  String get grantPermission;

  /// No description provided for @tabs.
  ///
  /// In zh, this message translates to:
  /// **'分頁'**
  String get tabs;

  /// No description provided for @newTab.
  ///
  /// In zh, this message translates to:
  /// **'新增分頁'**
  String get newTab;

  /// No description provided for @closeTab.
  ///
  /// In zh, this message translates to:
  /// **'關閉分頁'**
  String get closeTab;

  /// No description provided for @blankTab.
  ///
  /// In zh, this message translates to:
  /// **'空白頁'**
  String get blankTab;

  /// No description provided for @openedByAssistant.
  ///
  /// In zh, this message translates to:
  /// **'由 {app} 開啟'**
  String openedByAssistant(String app);

  /// No description provided for @deleteScreenshots.
  ///
  /// In zh, this message translates to:
  /// **'刪除對話時一併刪除截圖'**
  String get deleteScreenshots;

  /// No description provided for @deleteScreenshotsHelp.
  ///
  /// In zh, this message translates to:
  /// **'回溯並刪除之後的訊息時也一樣。無痕聊天一律刪除。'**
  String get deleteScreenshotsHelp;

  /// No description provided for @onDeviceModels.
  ///
  /// In zh, this message translates to:
  /// **'裝置上模型'**
  String get onDeviceModels;

  /// No description provided for @onDeviceModelsHelp.
  ///
  /// In zh, this message translates to:
  /// **'在這支手機上直接執行本地模型'**
  String get onDeviceModelsHelp;

  /// No description provided for @onDeviceApi.
  ///
  /// In zh, this message translates to:
  /// **'裝置上（llama.cpp / AICore）'**
  String get onDeviceApi;

  /// No description provided for @aicoreHelp.
  ///
  /// In zh, this message translates to:
  /// **'與 Android AICore 管理的模型聊天，首次設定可能需要網路連線。相容模型可使用 Tako 的工具，並沿用原有的權限檢查。'**
  String get aicoreHelp;

  /// No description provided for @aicorePreviewHelp.
  ///
  /// In zh, this message translates to:
  /// **'預覽版模型需要加入 Google 的 AICore Developer Preview，能否使用取決於裝置，且可能隨版本變動。'**
  String get aicorePreviewHelp;

  /// No description provided for @aicoreToolsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'這個 AICore 模型無法提供 Tako 工具所需的結構化回覆。請選用相容的預覽版模型，或關閉這個模型的工具能力。'**
  String get aicoreToolsUnavailable;

  /// No description provided for @aicoreInvalidTools.
  ///
  /// In zh, this message translates to:
  /// **'模型回傳了不完整或無效的工具請求，這次回覆未執行任何工具。請再試一次。'**
  String get aicoreInvalidTools;

  /// No description provided for @aicoreBackground.
  ///
  /// In zh, this message translates to:
  /// **'請讓 Tako 保持在前景，讓 AICore 繼續生成回覆。'**
  String get aicoreBackground;

  /// No description provided for @aicorePrepare.
  ///
  /// In zh, this message translates to:
  /// **'設定 Gemini Nano'**
  String get aicorePrepare;

  /// No description provided for @aicorePreparing.
  ///
  /// In zh, this message translates to:
  /// **'AICore 正在下載或準備 Gemini Nano…'**
  String get aicorePreparing;

  /// No description provided for @aicoreManaged.
  ///
  /// In zh, this message translates to:
  /// **'模型由 Android AICore 管理'**
  String get aicoreManaged;

  /// No description provided for @aicoreUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'這台裝置的 AICore 服務無法提供這個模型。請更新 Android AICore 並確認裝置支援；預覽版模型還需要加入 AICore Developer Preview。'**
  String get aicoreUnavailable;

  /// No description provided for @aicoreUpdate.
  ///
  /// In zh, this message translates to:
  /// **'請更新 Android 系統及 Android AICore 應用程式後再試。'**
  String get aicoreUpdate;

  /// No description provided for @aicoreRequestTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'這段對話超過 Gemini Nano 可處理的長度。請開啟新對話或縮短系統提示詞。'**
  String get aicoreRequestTooLarge;

  /// No description provided for @aicoreBusy.
  ///
  /// In zh, this message translates to:
  /// **'AICore 正忙碌，請稍候再試。'**
  String get aicoreBusy;

  /// No description provided for @aicoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'AICore 無法準備或執行這個模型。請更新 Android AICore、確認裝置支援後再試。'**
  String get aicoreFailed;

  /// No description provided for @onDeviceProviderHelp.
  ///
  /// In zh, this message translates to:
  /// **'使用已放在這支手機上的模型。不需要網址或金鑰。'**
  String get onDeviceProviderHelp;

  /// No description provided for @manageOnDeviceModels.
  ///
  /// In zh, this message translates to:
  /// **'管理裝置上模型'**
  String get manageOnDeviceModels;

  /// No description provided for @onDeviceUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'這台裝置無法執行裝置上模型。需要 64 位元的 Android 或 iOS 裝置。'**
  String get onDeviceUnavailable;

  /// No description provided for @onDeviceIntro.
  ///
  /// In zh, this message translates to:
  /// **'模型完全在這支手機上執行，對話不會傳到任何地方。模型越大，回答越好，但需要更多記憶體，速度也較慢。'**
  String get onDeviceIntro;

  /// No description provided for @onDeviceStorage.
  ///
  /// In zh, this message translates to:
  /// **'模型占用 {size}'**
  String onDeviceStorage(String size);

  /// No description provided for @installedModels.
  ///
  /// In zh, this message translates to:
  /// **'已安裝'**
  String get installedModels;

  /// No description provided for @noLocalModels.
  ///
  /// In zh, this message translates to:
  /// **'還沒有模型。下載推薦模型，或匯入 GGUF 檔案。'**
  String get noLocalModels;

  /// No description provided for @modelDownloads.
  ///
  /// In zh, this message translates to:
  /// **'下載中'**
  String get modelDownloads;

  /// No description provided for @recommendedModels.
  ///
  /// In zh, this message translates to:
  /// **'推薦模型'**
  String get recommendedModels;

  /// No description provided for @recommendedModelsHelp.
  ///
  /// In zh, this message translates to:
  /// **'從 Hugging Face 下載，完成後會核對檔案的 SHA-256。只有在你按下下載時才會連線。'**
  String get recommendedModelsHelp;

  /// No description provided for @otherModels.
  ///
  /// In zh, this message translates to:
  /// **'其他模型'**
  String get otherModels;

  /// No description provided for @otherModelsHelp.
  ///
  /// In zh, this message translates to:
  /// **'llama.cpp 支援的 GGUF 模型都可以使用。小模型可能無法正確使用工具。'**
  String get otherModelsHelp;

  /// No description provided for @importModel.
  ///
  /// In zh, this message translates to:
  /// **'匯入 GGUF 檔案'**
  String get importModel;

  /// No description provided for @importingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在匯入⋯'**
  String get importingModel;

  /// No description provided for @downloadFromUrl.
  ///
  /// In zh, this message translates to:
  /// **'從網址下載'**
  String get downloadFromUrl;

  /// No description provided for @modelAdded.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {name}'**
  String modelAdded(String name);

  /// No description provided for @modelDownloadStarted.
  ///
  /// In zh, this message translates to:
  /// **'已開始下載'**
  String get modelDownloadStarted;

  /// No description provided for @modelSelected.
  ///
  /// In zh, this message translates to:
  /// **'已切換到 {name}'**
  String modelSelected(String name);

  /// No description provided for @deleteModelBody.
  ///
  /// In zh, this message translates to:
  /// **'要刪除 {name} 嗎？之後可以再下載或匯入。'**
  String deleteModelBody(String name);

  /// No description provided for @inMemory.
  ///
  /// In zh, this message translates to:
  /// **'已載入'**
  String get inMemory;

  /// No description provided for @useInChat.
  ///
  /// In zh, this message translates to:
  /// **'在聊天中使用'**
  String get useInChat;

  /// No description provided for @addProjector.
  ///
  /// In zh, this message translates to:
  /// **'加入視覺投影檔'**
  String get addProjector;

  /// No description provided for @removeProjector.
  ///
  /// In zh, this message translates to:
  /// **'移除視覺投影檔'**
  String get removeProjector;

  /// No description provided for @unloadModel.
  ///
  /// In zh, this message translates to:
  /// **'從記憶體卸載'**
  String get unloadModel;

  /// No description provided for @verifyingDownload.
  ///
  /// In zh, this message translates to:
  /// **'正在核對檔案⋯'**
  String get verifyingDownload;

  /// No description provided for @downloadPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暫停'**
  String get downloadPaused;

  /// No description provided for @pauseDownload.
  ///
  /// In zh, this message translates to:
  /// **'暫停'**
  String get pauseDownload;

  /// No description provided for @resumeDownload.
  ///
  /// In zh, this message translates to:
  /// **'繼續下載'**
  String get resumeDownload;

  /// No description provided for @recommendedFast.
  ///
  /// In zh, this message translates to:
  /// **'最快，大多數手機都能執行'**
  String get recommendedFast;

  /// No description provided for @recommendedBalanced.
  ///
  /// In zh, this message translates to:
  /// **'速度與品質兼顧'**
  String get recommendedBalanced;

  /// No description provided for @recommendedBest.
  ///
  /// In zh, this message translates to:
  /// **'回答最好，需要較新的手機'**
  String get recommendedBest;

  /// No description provided for @recommendedVision.
  ///
  /// In zh, this message translates to:
  /// **'可以看圖片，下載時選擇加入看圖功能'**
  String get recommendedVision;

  /// No description provided for @memoryNeeded.
  ///
  /// In zh, this message translates to:
  /// **'建議 {gb} GB 以上記憶體'**
  String memoryNeeded(int gb);

  /// No description provided for @downloadWithVision.
  ///
  /// In zh, this message translates to:
  /// **'下載並加入看圖功能（{size}）'**
  String downloadWithVision(String size);

  /// No description provided for @modelUrl.
  ///
  /// In zh, this message translates to:
  /// **'網址'**
  String get modelUrl;

  /// No description provided for @modelUrlHelp.
  ///
  /// In zh, this message translates to:
  /// **'GGUF 檔案的直接連結，例如 Hugging Face 上的「resolve」連結。Tako 只會連線到這個網址；區域網路以外只接受 HTTPS。'**
  String get modelUrlHelp;

  /// No description provided for @modelErrorNotGguf.
  ///
  /// In zh, this message translates to:
  /// **'這不是 GGUF 模型檔。'**
  String get modelErrorNotGguf;

  /// No description provided for @modelErrorIsProjector.
  ///
  /// In zh, this message translates to:
  /// **'這是視覺投影檔。請在模型的選單中選「加入視覺投影檔」。'**
  String get modelErrorIsProjector;

  /// No description provided for @modelErrorNotProjector.
  ///
  /// In zh, this message translates to:
  /// **'這不是視覺投影檔。'**
  String get modelErrorNotProjector;

  /// No description provided for @modelErrorExists.
  ///
  /// In zh, this message translates to:
  /// **'已經有同名的模型。'**
  String get modelErrorExists;

  /// No description provided for @modelErrorUrl.
  ///
  /// In zh, this message translates to:
  /// **'只接受 HTTPS 網址；區域網路內可以用 HTTP。'**
  String get modelErrorUrl;

  /// No description provided for @modelErrorChecksum.
  ///
  /// In zh, this message translates to:
  /// **'檔案內容和預期不符，已刪除。'**
  String get modelErrorChecksum;

  /// No description provided for @modelErrorSize.
  ///
  /// In zh, this message translates to:
  /// **'檔案大小和預期不符。'**
  String get modelErrorSize;

  /// No description provided for @modelErrorNoSpace.
  ///
  /// In zh, this message translates to:
  /// **'儲存空間不足。'**
  String get modelErrorNoSpace;

  /// No description provided for @modelErrorNetwork.
  ///
  /// In zh, this message translates to:
  /// **'連線中斷。可以繼續下載。'**
  String get modelErrorNetwork;

  /// No description provided for @modelErrorHttp.
  ///
  /// In zh, this message translates to:
  /// **'伺服器回應 HTTP {status}。'**
  String modelErrorHttp(String status);

  /// No description provided for @loadingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在載入模型⋯'**
  String get loadingModel;

  /// No description provided for @localModelMissing.
  ///
  /// In zh, this message translates to:
  /// **'這個模型檔案已不在手機上。請到「裝置上模型」重新下載或匯入。'**
  String get localModelMissing;

  /// No description provided for @localModelLoad.
  ///
  /// In zh, this message translates to:
  /// **'無法載入模型。可能是記憶體不足，或這個版本的 llama.cpp 不支援它。請試試較小的模型或較短的上下文。'**
  String get localModelLoad;

  /// No description provided for @shortcuts.
  ///
  /// In zh, this message translates to:
  /// **'捷徑'**
  String get shortcuts;

  /// No description provided for @shortcutsHelp.
  ///
  /// In zh, this message translates to:
  /// **'讓 Tako 執行你指定的捷徑'**
  String get shortcutsHelp;

  /// No description provided for @shortcutsIntro.
  ///
  /// In zh, this message translates to:
  /// **'iOS 不允許 App 讀取你的捷徑清單。請輸入要讓 Tako 使用的捷徑名稱，需與「捷徑」App 中的名稱完全相同。每次執行前都會先詢問你。'**
  String get shortcutsIntro;

  /// No description provided for @addShortcut.
  ///
  /// In zh, this message translates to:
  /// **'新增捷徑'**
  String get addShortcut;

  /// No description provided for @shortcutName.
  ///
  /// In zh, this message translates to:
  /// **'捷徑名稱'**
  String get shortcutName;

  /// No description provided for @noShortcuts.
  ///
  /// In zh, this message translates to:
  /// **'還沒有新增捷徑。'**
  String get noShortcuts;

  /// No description provided for @listShortcutsTool.
  ///
  /// In zh, this message translates to:
  /// **'列出捷徑'**
  String get listShortcutsTool;

  /// No description provided for @runShortcutTool.
  ///
  /// In zh, this message translates to:
  /// **'執行捷徑'**
  String get runShortcutTool;

  /// No description provided for @useOnDeviceModel.
  ///
  /// In zh, this message translates to:
  /// **'在手機上執行模型'**
  String get useOnDeviceModel;

  /// No description provided for @preferSpeed.
  ///
  /// In zh, this message translates to:
  /// **'優先速度'**
  String get preferSpeed;

  /// No description provided for @preferSpeedHelp.
  ///
  /// In zh, this message translates to:
  /// **'使用更多處理器核心，回答較快，但手機可能會卡頓。關閉時會留一個核心給系統，讓手機保持流暢。'**
  String get preferSpeedHelp;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
