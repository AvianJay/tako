# Tako

A local-first AI assistant for Android, built with Flutter. Bring your own model: a local server such as llama-server in Termux, or any OpenAI-compatible, OpenAI Responses or Anthropic Messages endpoint.

Conversations stay on the device in SQLite. API keys and headers are kept in secure storage, never in the database or logs.

## Features

- **Chat**
  - Streaming replies with branches, edit and regenerate, and rewind.
  - Markdown and LaTeX rendering.
  - Image, PDF and text attachments.
  - Several models per provider, switched from the chat title.
- **Tools**, with a permission gate and an audit log:
  - **Web:** search through SearXNG, Tavily, Brave, Serper or DDGS, or the provider's built-in search, plus page fetching.
  - **Files:** a workspace whose earlier versions are kept when a file is replaced.
  - **Device:** status, location, clipboard, calendar, alarms and timers, opening links and apps by name.
  - **Memory:** long-term memory with a pinned profile, a memory screen, personalization and incognito chats.
  - **In-app browser:** the model works in its own tab while you watch, and you can take over at any time.
- **Device control** (Android, `full` build):
  - **Screen control** through an accessibility service you turn on yourself:
    - The model reads the screen as `[id] type "text"` elements, with an optional screenshot for vision models.
    - It can tap, type, scroll, swipe and press system keys.
    - Each action returns the screen after it, so a task takes fewer tool calls.
  - **`run_shell`** through Termux.
  - **`notifications_list`** to read current notifications.

## Safety

The app enforces safety; the model only proposes actions.

- **Risk levels.** Every tool call is classified as safe, sensitive, action or high risk. Sensitive and action calls ask once, for one call or for the whole chat.
- **High risk** always asks, even with **Full permissions** on, unless you separately opt in. This covers:
  - sending, paying and deleting;
  - installing;
  - changing settings;
  - shell commands that change things.

  For screen control, the label is read from the live screen, not taken from the model. A tap on a "Send"-like button, a confirmation in a delete dialog, or a Settings switch is therefore always high risk.
- **Passwords and one-time codes** are never typed.
- **Tako's own screens** are never read or acted on.
- **While Tako is in the background,** approvals are drawn over the app being controlled. A notification offers **Stop** throughout.
- **Untrusted content.** Web pages, screen contents, notifications and command output are passed to the model as untrusted data.

## Requirements

- Flutter 3.41.6 (Dart 3.11.4), Java 17 and the Android SDK.
- An Android device, Android 7.0 (API 24) or later. Screen control needs Android 11 or later for screenshots and the Enter key.
- Optional: [Termux](https://termux.dev) from F-Droid or GitHub, for `run_shell` and for running a local model.

## Build

```powershell
flutter pub get
flutter gen-l10n
dart run pigeon --input pigeons/device_api.dart
dart run pigeon --input pigeons/control_api.dart
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release                  # full flavor
flutter build apk --release --flavor play    # play flavor
```

The APKs are written to `build/app/outputs/flutter-apk/`.

There are two build flavors:

| Flavor | Output | Contents |
| --- | --- | --- |
| `full` (default) | `app-full-release.apk` | Everything, including screen control. |
| `play` | `app-play-release.apk` | No accessibility service, for distribution on Google Play. |

## Getting started

1. Install the APK and open **Settings → Providers** to add a provider:
   - **llama-server in Termux:** Chat Completions, `http://127.0.0.1:8080`. The server must already be running.
   - **OpenAI:** Responses, `https://api.openai.com`.
   - **Anthropic:** Messages, `https://api.anthropic.com`.
   - **Other compatible endpoints:** Chat Completions and the endpoint's base URL.

   Load the model list or enter the exact model ID. Enter keys only in the app.
2. Optional: set up device control under **Settings → Device control**:
   - turn on screen control (Tako explains it first, then opens Android's accessibility settings);
   - allow notifications and grant notification access;
   - copy the Termux setup command.
3. Optional: under **Settings → Tools and permissions**, adjust tool limits, per-tool permissions and high-risk keywords.

## Development

```powershell
dart format lib test integration_test pigeons tool
flutter analyze
flutter test
flutter run -d <android-device-id>
```

The app name is in `lib/app/app_info.dart`. The Android launcher label and application ID (`tw.avianjay.tako`) are in `android/gradle.properties`.

### On-device tests

`integration_test/device_control_test.dart` drives the real app with a scripted model, with no provider and no network. `flutter test` on a device uninstalls the app first, which turns screen control off again. So build the test entry point, install it over the app, enable the services, and launch it:

```powershell
flutter build apk --debug -t integration_test/device_control_test.dart
adb install -r build/app/outputs/flutter-apk/app-full-debug.apk
adb shell settings put secure enabled_accessibility_services tw.avianjay.tako/tw.avianjay.tako.TakoAccessibilityService
adb shell settings put secure accessibility_enabled 1
adb shell cmd notification allow_listener tw.avianjay.tako/tw.avianjay.tako.TakoNotificationListener
adb shell pm grant tw.avianjay.tako com.termux.permission.RUN_COMMAND
adb shell "cmd notification post -S bigtext -t 'Tako fixture notification' fixture 'Hello'"
adb shell am start -n tw.avianjay.tako/.MainActivity
adb logcat -s flutter
```

Before running:

- **Termux** must be installed, opened once, and have `allow-external-apps = true`.
- **Settings labels.** The script looks for Traditional Chinese labels (`設定`, `系統`, `日期和時間`). Pass `--dart-define=SETTINGS_APP=<name>` for another label of the Settings app.
- **Manual steps.** Two steps need a person:
  - press **Stop** in the "Tako is controlling the screen" notification;
  - press **Deny** in the prompt drawn over Settings for **Uninstall**.

## Project structure

| Path | Contents |
| --- | --- |
| `lib/app` | Bootstrap, theme and the chat controller with the agent loop. |
| `lib/core` | Messages, the conversation tree, prompt assembly, provider adapters, tools, permissions, memory, and the browser, screen, shell and notification contracts. |
| `lib/data` | The drift schema and repositories, including the memory store and its FTS5 index. |
| `lib/platform` | Native and plugin implementations, including the WebView browser and the Pigeon-backed device control. |
| `lib/ui` | Chat, browser, memory, files and settings screens, the renderer, and the Tako mark. |
| `lib/l10n` | Localizations: Traditional Chinese and English. |
| `pigeons` | Typed definitions of the native APIs. |
| `assets/prompts/system_prompt.md` | The system prompt template (Mustache). |
| `assets/branding` | The app icon. The launcher, status bar and launch screen drawables, and `lib/ui/brand/tako_mark.dart`, use the same geometry; change them together. |
| `android/app/src/full` | The accessibility service and the approval prompt drawn over other apps. The `play` flavor leaves these out. |
| `test` | Unit, agent-loop and widget tests. |
| `integration_test` | On-device checks of screen control, Termux, notifications and the browser. |
| `tool/browser_runtime_check` | A jsdom check of the browser's injected page script. It needs Node.js and runs in CI. |
