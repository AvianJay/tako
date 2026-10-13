# Tako

A local-first AI assistant for Android, built with Flutter. Bring your own model:

- run a GGUF model on the phone itself with llama.cpp;
- use Gemini Nano through Android AICore on compatible devices;
- use a local server such as llama-server in Termux;
- or use any OpenAI-compatible, OpenAI Responses or Anthropic Messages endpoint.

Conversations stay on the device in SQLite. API keys and headers are kept in secure storage, never in the database or logs.

An iOS build is included. It compiles in CI but has not yet been run on a device; see [iOS](#ios).

## Features

- **Chat**
  - Streaming replies with branches, edit and regenerate, and rewind.
  - Markdown and LaTeX rendering.
  - Image, PDF and text attachments.
  - Several models per provider, switched from the chat title.
  - Image generation through compatible Images APIs, chat image output, or the
    Responses image tool. Configure the output mode and reference-image support
    for each model in **Settings → Providers**. Switch to an image model for
    direct generation, or let a tool-capable chat model call `generate_image`
    using the configured image models. Reference images can come from message
    attachments or workspace files. Generated originals are saved locally and
    can be viewed, shared, or used as references in later requests.
- **On-device models** (64-bit Android and iOS), run by llama.cpp through [llamadart](https://pub.dev/packages/llamadart):
  - A recommended list of small Qwen3 models. They are downloaded from Hugging Face, pinned to a commit, and checked against their SHA-256.
  - You can also import a GGUF file or download one from a URL.
  - Optional vision projectors (mmproj) let a model see images.
  - Downloads can be paused and resumed. Model files live outside the workspace, so file tools never see them.
  - By default llama.cpp leaves a CPU core free so the phone stays smooth; **Prefer speed** uses more cores.
  - The chat with the model never leaves the phone.
  - **Gemini Nano (Android):** in **On-device models**, tap **Set up Gemini Nano**,
    then select it for chat. Uses `com.google.mlkit:genai-prompt:1.0.0-beta4`
    over the Android AICore system service. Tako queries the actual availability
    and token limit of the stable and preview models; installing AICore alone
    does not guarantee support. The preview model requires enrollment in
    [AICore Developer Preview](https://developers.google.com/ml-kit/genai/aicore-dev-preview).
    AICore manages downloads and updates; setup may need internet access.
    Requests without tool definitions stream normally. When the selected model supports structured
    output, Tako enables tools through an app-level protocol over ML Kit's
    `@Generable` responses. Requests with tools wait for a complete response, validate
    all requested names and JSON objects, then use the same argument checks,
    approvals, audit log and agent loop as other providers. Malformed or
    truncated requests never execute tools. This is not a native `tools=` SDK
    interface. Image input and thinking are not enabled by this integration.
    See [ML Kit Prompt API](https://developers.google.com/ml-kit/genai/prompt/android/get-started)
    and [structured output](https://developers.google.com/ml-kit/genai/prompt/android/structured-output).
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
    - A thin green-to-teal gradient frame and a status pill show when Tako is using your phone, with the current operation title and **Stop**. The indicator stays through model thinking and is cleared when the response ends or you take over.
    - Screen tools and `open_app` require a short `title`, also shown in the chat's tool history. The indicator is excluded from screenshots and cannot receive model gestures.
  - **`run_shell`** through Termux.
  - **`notifications_list`** to read current notifications.
- **iOS screen control** through [iCTRL](https://github.com/OpenMinis/iCTRL):
  - Start the iCTRL runner on the phone. Tako detects `127.0.0.1:8200`, requests pairing once, and stores the approved key in secure storage.
  - **Settings → Device control** also accepts LAN and Tailscale endpoints. Enable iCTRL Remote Access for another device.
  - Compact accessibility reads, live element references, OCR recovery, optional screenshots, and actions without settling keep agent calls short. Stable sequences can skip intermediate observations.
  - A Live Activity shows progress on the Lock Screen and Dynamic Island, with a link to stop. iOS grants finite background time; expiration stops the agent. Reopen Tako to continue.

## Safety

The app enforces safety; the model only proposes actions.

- **Risk levels.** Every tool call is classified as safe, sensitive, action or high risk. Sensitive and action calls ask once, for one call or for the whole chat.
- **High risk** always asks, even with **Full permissions** on, unless you separately opt in. This covers:
  - sending, paying and deleting;
  - installing;
  - changing settings;
  - shell commands that change things;
  - running a Shortcut (iOS).

  For screen control, the label is read from the live screen, not taken from the model. A tap on a "Send"-like button, a confirmation in a delete dialog, or a Settings switch is therefore always high risk.
- **Passwords and one-time codes** are never typed.
- **Tako's own screens** are never read or acted on.
- **While Tako is in the background,** Android draws approvals over the controlled app and offers **Stop** in a notification. iOS keeps approvals pending until you return to Tako; its Live Activity links back to the app and to Stop.
- **Untrusted content.** Web pages, screen contents, notifications, command output and Shortcut output are passed to the model as untrusted data.
- **Network.** Tako connects only to:
  - your model and search providers;
  - pages that `fetch_page` and the in-app browser load;
  - model downloads you start yourself: Hugging Face for recommended models, or the URL you enter. Plain HTTP is accepted only inside the local network.
  - your configured iCTRL runner, using authenticated encrypted RPC envelopes.

## Requirements

- Flutter 3.41.6 (Dart 3.11.4), Java 17 and the Android SDK.
- An Android device, Android 7.0 (API 24) or later. Screen control needs Android 11 or later for screenshots and the Enter key.
- On-device models need a 64-bit device (arm64-v8a or x86_64) and enough memory: about 3 GB for the smallest recommended model and 8 GB for the largest.
- Optional: [Termux](https://termux.dev) from F-Droid or GitHub, for `run_shell` and for running a local model.
- For iOS: macOS with Xcode and CocoaPods; iOS 16.4 or later.

## Build

```powershell
flutter pub get
flutter gen-l10n
dart run pigeon --input pigeons/device_api.dart
dart run pigeon --input pigeons/control_api.dart
dart run pigeon --input pigeons/ios_api.dart
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi                  # full flavor
flutter build apk --release --split-per-abi --flavor play    # play flavor
flutter build ios --release --no-codesign                    # on macOS
```

The APKs are written to `build/app/outputs/flutter-apk/`, one per ABI. Each ABI gets its own version code: 1000 + build number for armeabi-v7a, 2000 + build number for arm64-v8a, and 4000 + build number for x86_64.

| ABI | Size | For |
| --- | --- | --- |
| arm64-v8a | about 55 MB | Most phones. |
| armeabi-v7a | about 31 MB | Older 32-bit phones; no on-device models. |
| x86_64 | about 48 MB | Emulators and Chromebooks. |

The first build downloads the llama.cpp libraries through llamadart's build hook. `hooks: user_defines` in `pubspec.yaml` keeps only the llama.cpp runtime, and on Android only its CPU backend: Vulkan is experimental there and adds 26 MB per ABI. After changing that configuration, run `flutter clean`: Flutter does not remove native libraries that a hook stops producing.

There are two build flavors:

| Flavor | Contents |
| --- | --- |
| `full` (default) | Everything, including screen control. |
| `play` | No accessibility service, for distribution on Google Play. |

Every push to `main` updates the [nightly release](https://github.com/AvianJay/tako/releases/tag/nightly) with all six APKs, named `tako-<flavor>-<abi>.apk`, and the unsigned iOS build, `tako-ios-unsigned.ipa`, after both platform builds succeed.

CI signs the release APKs on pushes using the GitHub Actions secrets
`KEYSTORE_BASE64` (the base64-encoded keystore), `KEYSTORE_ALIAS`, and
`KEYSTORE_PASSWORD`. The password must match both the keystore password and the
key password. Push builds fail if any signing secret is missing. Pull-request
and local builds use the debug key when no signing environment is set. To sign
locally, set `KEYSTORE_PATH` to the keystore's absolute path, plus `KEYSTORE_ALIAS`
and `KEYSTORE_PASSWORD`, before running the build commands.

## Getting started

1. Choose where the model runs:
   - **On the phone:** open **Settings → On-device models**, download a recommended model, then tap it to chat with it. Tako creates the on-device provider for you.
   - **Elsewhere:** open **Settings → Providers** and add a provider:
     - **llama-server in Termux:** Chat Completions, `http://127.0.0.1:8080`. The server must already be running.
     - **OpenAI:** Responses, `https://api.openai.com`.
     - **Anthropic:** Messages, `https://api.anthropic.com`.
     - **Other compatible endpoints:** Chat Completions and the endpoint's base URL.

     Load the model list or enter the exact model ID. Enter keys only in the app.

   On-device models are slower than servers. Reading the system prompt and tool definitions takes the longest; later turns reuse it. Hybrid models such as Qwen3.5 cannot reuse it, so every tool round reads it again. The recommended models are plain transformers.
2. Optional: set up device control under **Settings → Device control**:
   - **Android:** enable accessibility, notification access, and the Termux integration as needed;
   - **iOS:** start iCTRL, open this screen, and approve Tako's pairing request. The default address is `http://127.0.0.1:8200`.
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

The opt-in `test/screen/ictrl_live_test.dart` exercises the real Dart iCTRL transport, tool executor, permission gate, audit database and streaming provider. It defaults to `deepseek-v4.1-flash`; `TAKO_ICTRL_MODEL` and `TAKO_ICTRL_EFFORT` select another model and reasoning effort. It requires a paired test device and local API credentials; CI skips it. See [the iCTRL validation notes](docs/ictrl-validation.md) for setup and measured results.

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

## iOS

The iOS app shares everything above except what iOS does not allow:

| Feature | On iOS |
| --- | --- |
| Chat, providers, on-device models, memory, files, browser | Same as Android. On-device models use Metal. |
| Device tools | Status, location, clipboard, calendar and opening links. Paired iCTRL also opens apps by name or bundle ID. No alarms or timers. |
| `run_shell` | A built-in mini shell over the workspace: `ls`, `cat`, `head`, `tail`, `wc`, `grep`, `find`, `echo`, `pwd`, `date`, `mkdir`, `touch`, `cp`, `mv`, `rm`, with pipes. |
| Shortcuts | `list_shortcuts` and `run_shortcut` run the Shortcuts you name under **Settings → Shortcuts**, through the Shortcuts app's x-callback-url. Every run asks first. |
| Screen control | iCTRL runner on the phone, automatically detected at `127.0.0.1:8200`, with one pairing approval. LAN/Tailscale endpoints can be configured in Device control settings. |
| Notifications | Notification access is unavailable. Live Activity progress appears on the Lock Screen and Dynamic Island, with a Stop link; background execution is limited by iOS. |

CI builds it with `flutter build ios --release --no-codesign` and packages `Tako.app` under `Payload/` as `tako-ios-unsigned.ipa`. The IPA is available as a workflow artifact and in the nightly release. It must be signed before installation on an iOS device. It has not been run on a device or simulator yet.

## Project structure

| Path | Contents |
| --- | --- |
| `lib/app` | Bootstrap, theme and the chat controller with the agent loop. |
| `lib/core` | Messages, the conversation tree, prompt assembly, provider adapters, tools, permissions, memory, on-device models, and the browser, screen, shell, notification and Shortcuts contracts. |
| `lib/data` | The drift schema and repositories, including the memory store and its FTS5 index. |
| `lib/platform` | Native and plugin implementations: the WebView browser, llama.cpp and model files (`on_device`), the device tools shared by Android and iOS (`native`), Android device control (`android`), iOS Shortcuts (`ios`), and the workspace with its built-in shell (`workspace`). |
| `lib/ui` | Chat, browser, memory, files and settings screens, the renderer, and the Tako mark. |
| `lib/l10n` | Localizations: Traditional Chinese and English. |
| `pigeons` | Typed definitions of the native APIs. |
| `assets/prompts/system_prompt.md` | The system prompt template (Mustache). |
| `assets/branding` | The app icon. The launcher, status bar and launch screen drawables, the iOS app icons (square, without transparency), and `lib/ui/brand/tako_mark.dart` use the same geometry; change them together. |
| `android/app/src/full` | The accessibility service and the approval prompt drawn over other apps. The `play` flavor leaves these out. |
| `ios/Runner` | The iOS host app: device tools, backup exclusion for model files and Shortcuts callbacks (`TakoNative.swift`, `IosDeviceApi.swift`). The `full` Xcode scheme matches the default flavor. |
| `test` | Unit, agent-loop and widget tests. |
| `integration_test` | On-device checks of screen control, Termux, notifications and the browser. |
| `tool/browser_runtime_check` | A jsdom check of the browser's injected page script. It needs Node.js and runs in CI. |
