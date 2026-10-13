# iCTRL validation and agent latency

The implementation uses iCTRL's v1 authenticated envelopes and loopback pairing, or X25519 pairing for a LAN/Tailscale endpoint. The runner remains a separately installed application. Pairing keys live in platform secure storage, never in a conversation or the repository.

## Read and action costs

- Reuse the HTTP client and approved key. Refreshes do not repeatedly fetch the schema or prompt for pairing.
- Read the visible accessibility hierarchy with 400 elements and 100 children per container. The scientific Calculator keypad silently lost its last controls at 50 children; the new bound exposes them without an unbounded fetch. Strip server diagnostics before sending the listing to the model.
- Recover sparse reads and server-recommended OCR views with OCR. Rich truncated trees avoid an extra OCR round; request a screenshot or scroll when the needed control is missing. Prefer AX labels over OCR duplicates.
- Resolve labeled controls with a fresh live ref. Reject changed labels/types, offscreen matches, ambiguous results, and stale listing IDs. Unnamed containers are checked against their descendants.
- Send mutations with `settle:false`; do not retry mutations automatically. Preserve warnings and page-change information in the tool receipt. A missing settling measurement is unknown, not evidence that the screen stayed unchanged.
- Return one text observation after the final action of a response. Batch stable controls with `observe:false` on intermediate calls. Navigation still needs a fresh observation.
- Request screenshots explicitly when the provider has vision and the listing cannot answer the task. JPEG quality defaults to 0.55. Phones up to 512 points wide use scale 1 so screenshot pixels and device points coincide; tablets use 0.75. Large authenticated responses decrypt off the UI isolate.
- Navigation actions accept `screenshot:true`, returning image and text in the same tool result instead of a second model/read round. Only two recent remote screen images are uploaded during an active turn; saved conversation images and text receipts remain intact.
- OCR target matching normalizes whitespace/full-width punctuation and checks source type plus nearby geometry. Repeated text elsewhere on the page cannot redirect a tap. These changes are shared by every app, not Shopee routes.
- Prefer typed live refs over same-label wrappers. Omit OCR fragments inside small named AX controls, while preserving OCR for custom controls elsewhere.
- Claude's native Messages stream preserves empty-object tool arguments, including empty JSON deltas. Adaptive thinking sends the selected reasoning effort. These fixes apply to all tools and conversations.

The referenced osu! report verified that one iCTRL 1.96 landscape screenshot was upright but stretched. This backend resizes that case rather than rotating, and applies the report's synthesized gesture mapping. Both endpoints of a drag use the same transform. Opposite landscape rotation has not been calibrated on this test phone.

## Live evidence

Tested on an iPhone with 440 × 956 point geometry, iCTRL 1.96.1, through Tailscale using the exact `deepseek-v4.1-flash` model. Calculator assertions read the real displayed result; successful RPC responses alone are insufficient.

| Task | Result | Tool calls | Model rounds | Elapsed, excluding final proof capture |
| --- | --- | ---: | ---: | ---: |
| 7 + 8 | Displayed 15 | 6 | 5 | 26.85 s |
| 123 + 456 | Displayed 579 | 10 | 4 | 22.29 s |
| Shopee daily check-in | Success popup +0.10; balance 0.05 → 0.15 | 10 | 11 | 98.39 s |
| Shopee treasure chest | History entry 蝦幣寶箱 +0.01; balance 0.15 → 0.16 | 18 | 19 | 164.00 s |

In the longer calculation, individual verified taps without observation took 0.65–0.84 s, and the final tap plus observation took 1.49 s. The first read took 0.44 s. Most elapsed time came from the model's response rounds. These are measured samples, not universal latency guarantees.

The initial Shopee daily-coin exploration reached its 24-round limit without completing the claim. It exposed raw-tree truncation and ambiguous unlabeled rows; those findings motivated the OCR/descendant changes above. Complex-task outcomes are recorded separately and must be verified from the final screen. Do not label an exhausted exploration as a successful claim.

The treasure run subsequently completed and was independently checked in coin history. Its 164 s consisted of 109.32 s of model responses and 54.30 s of tools. Nine explicit reads, repeated OCR label failures and screenshot-to-text coordinate switches motivated on-action screenshots, OCR normalization and limiting repeated image uploads. These later improvements require separate measurements; the table does not claim a measured speedup for them. Free daily claims cannot be replayed on the same day as if the reward were still available.

## Claude Haiku Extra and cross-app installation

At the user's request, subsequent tests used provider-listed `claude-haiku-5-5` with Extra effort (`xhigh`). The provider rejects literal `extra`. Its chat-completions compatibility route repeatedly exhausted 4096/8192 output tokens during vision navigation. The native Messages route passed the vision probe in 4.17 s and performed the installation task. This is evidence about this provider, not a universal model comparison.

Safari downloaded the exact 20,991,820-byte `ios-unsigned-ipa` artifact from successful YaBus Actions run [38287508676](https://github.com/YetAnotherBusDeveloper/yetanotherbusapp/actions/runs/38287508676), commit `abe26057763a70f5932575f98bf27a46d2d12058`. The artifact was privately served over Tailscale. After assisted navigation into Downloads, Haiku imported the IPA into LCSign, used the existing signer, accepted installation, and launched `tw.avianjay.taiwanbus.flutter`. The first successful launch was tool call 22 of that native run. An independent launch and home-screen screenshot verified YaBus works. The run was stopped after launch to prevent redundant installation work; it is not reported as a wholly autonomous timed end-to-end benchmark.

The same native Haiku configuration passed both Calculator assertions in scientific mode. Before the last keypad/target/batching changes, 7 + 8 took 30.02 s (7 tools / 6 rounds), and 123 + 456 took 47.26 s (11 tools / 9 rounds). Afterward, they took 41.50 s (12 tools / 11 rounds) and 31.71 s (12 tools / 7 rounds). Median successful tap cost in those samples fell from 748 to 626 ms. The first improved run had an RPC failure and extra model recovery; there is no consistent task-wide speedup across both examples. The longer calculation improved by about 33% in this single sample. Model round latency remained about 3.2 s, the main cost to reduce through batching.

After integrating the Android floating overlay and operation titles, normal verification passed 523 tests, with the opt-in live test skipped, plus all 10 browser runtime checks. Analysis and formatting passed. A remote-session regression check verifies that titles update without restarting the native activity and disconnect ends it once. An unrelated pre-existing memory test had nondeterministic ordering for simultaneous saves; explicit fixture timestamps now test its intended oldest-first budget deterministically.

## Isolated worker and generic local execution

The main chat and phone worker use independently selected saved providers/models. Device control settings select the worker connection, model and effort; automatic selection uses Haiku Messages with Extra (`xhigh`). Other providers retain their saved API, capabilities and limits. Credentials belong to the selected connection. Raw screenshots and worker history stay out of the parent response; `remote_control_check` uses a fresh native read without a verifier model.

`screen_workflow` runs known app/URL/tap/type steps locally, resolving exact labels or view IDs after each navigation, and stops on ambiguity, changed apps, diagnostics or failed postconditions. `screen_sequence` batches stable controls with one final observation. Every underlying action still uses the permission gate and audit log. Workflows are supplied plans, not automatically learned persistent macros. They contain no app-specific engine.

The worker preserves signed reasoning provenance and opts into Messages prompt-cache breakpoints. Cache savings depend on the provider; this proxy's token reports are inconsistent, so cache-hit savings are not claimed. Offscreen cells are rejected rather than tapping their clipped centers. Multiline TextView composers resolve without a textfield-only filter. Exact verification excludes input fields and their descendants. A partial title match or an exhausted task cannot become verified completion.

Measured delegated samples through the same Tailscale phone:

| Task | Time | Worker rounds | Parent result | Evidence |
| --- | ---: | ---: | ---: | --- |
| Calculator 7 + 8 | 8.719 s | 1 | 387 chars | Native result 15 |
| Calculator 123 + 456 | 11.747 s | 1 | 391 chars | Native result 579 |
| Known search URL workflow | 10.735 s | 0 | 660 chars | Correct ESP32-S3 query and title/price in same card |
| Settings → General → About | 29.955 s | 6 | 436 chars | Native About heading |
| Discord Messages navigation | 23.179 s | 3 | 1083 chars | Worker visual report; semantic review required |
| Discord final send and verify | 5.865 s | 1 | 478 chars | Sent history and empty composer independently checked |
| Discord read latest reply and respond | 37.141 s | 5 | 791 chars | Worker report plus independent screenshot |
| YouTube unsubscribe, resumed at channel feed | 44.867 s | 8 | 688 chars | Official @MrBeast header shows Subscribe; independently checked |

Times exclude the outer main model. Discord final send starts with a prepared composer: contact discovery and input debugging are excluded, so it is not a complete DM benchmark. Shopping comparison still needed multiple attempts and has not produced verified cart addition. Do not claim the cheapest product from an advertised minimum price.

`screen_replay` implements calibrated tap/hold/drag segments up to 30 seconds with no per-note model calls. It checks app and geometry before gestures, stops on lateness/Stop/errors and retains committed receipts. iCTRL 1.96.1 has no server-side replay queue; per-gesture root reads and network delay limit dense rhythm-game timing. The old report's A-grade was achieved by a separate calibrated Python controller on an iPad. It is not an in-app Tako game result.

Local validation passed 557 tests with two opt-in live tests skipped, plus 10 browser runtime checks and clean analysis. Narrow Traditional Chinese settings, independent worker selection, signed reasoning replay, multiline input, clipped cells, sparse OCR recovery and timed-input interruption have regression coverage.

The opt-in delegated test is `test/screen/remote_control_live_test.dart` with `TAKO_ICTRL_WORKER_LIVE=1`. Custom authorized tasks use `TAKO_ICTRL_WORKER_TASK`, `TAKO_ICTRL_WORKER_APP`, optional `TAKO_ICTRL_WORKER_TEXT` and `TAKO_ICTRL_WORKER_PREFIX`. Use `TAKO_ICTRL_WORKER_RESUME=1` to preserve the current app. `TAKO_ICTRL_WORKER_PLAN` supplies a JSON workflow. Keep account-specific evidence and credentials ignored.

## Reproduction commands

Use Flutter 3.41.6 / Dart 3.11.4. Run the normal suite first:

```powershell
flutter analyze
flutter test
```

Live tests deliberately read ignored local files: `.build/ictrl-pairing.json` in the upstream Python client's host-keyed format, and `cpa.env` containing `api_endpoint` and `api_key`. Keep these files private. Supply your own paired host:

```powershell
$env:TAKO_ICTRL_LIVE='1'
$env:TAKO_ICTRL_ENDPOINT='http://<your-tailnet-ip>:8200'
flutter test test/screen/ictrl_live_test.dart --reporter expanded
```

To reproduce Claude Extra using the native API:

```powershell
$env:TAKO_ICTRL_MODEL='claude-haiku-5-5'
$env:TAKO_ICTRL_API='messages'
$env:TAKO_ICTRL_EFFORT='xhigh'
$env:TAKO_ICTRL_RESULT_PREFIX='haiku-'
flutter test test/screen/ictrl_live_test.dart --reporter expanded
```

For a user-authorized IPA installation, also set `TAKO_ICTRL_INSTALL=1`, `TAKO_ICTRL_IPA_URL`, `TAKO_ICTRL_IPA_NAME` and `TAKO_ICTRL_APP_BUNDLE`. `TAKO_ICTRL_INSTALL_RESUME=1` resumes from a downloaded file. The live installation gate restricts app launches and URLs and rejects deletion, payment and message actions. Preserve existing signer settings and stop for passwords or missing credentials.

For an explicitly authorized free daily-coin task on an account you control, set `TAKO_ICTRL_SHOPEE=1`. This is a live account action, not a repeatable unit test. Private timing, tool results and proof images go under `.build/ictrl-smoke/` and are excluded from Git.

## Installed-app setup and multiline accessibility

The IPA from successful Actions run [38357906188](https://github.com/AvianJay/tako/actions/runs/38357906188), commit `4a3c951`, was installed through LCSign and launched as `tw.avianjay.tako`. Claude configured the private provider using the existing local environment credentials, verified its model-list connection, and confirmed local pairing at `http://127.0.0.1:8200`. Screenshots were enabled; the worker settings showed Haiku Messages with `xhigh`. Credentials and device/account evidence remain ignored.

At the user's explicit request, both full permissions and skipping high-risk confirmations were enabled and verified after reopening settings. A Calculator task submitted through the installed app delegated the actual phone actions and reached the native displayed result `15` for `7 + 8`. A later main response confirmed it. The independent test controller only entered prompts into Tako and observed the other apps.

Longer shopping tasks reached Shopee search results but did not verify a cart addition. Returning to Tako while a worker or its final check is active changes the observed app and invalidates verification. Do not equate a quiet screen with task completion, or report a result-page minimum as an inspected variant price.

Live settings and chat screens exposed literal newlines inside accessibility labels. Parsing each physical line discarded control types and the text before the newline. The parser now joins complete records through their final frame, retaining indentation, flags, values and labels. Regression tests cover multiline switches, buttons, displayed text, editable values and secure-value redaction. Normal validation passed 595 tests with two opt-in live tests skipped.

## Background execution and packaging

An installed-app Discord trial failed before execution because the main model
sent `expected_text` as a string instead of an array. Tool-schema rejection now
returns the exact trusted schema path and expected type, without echoing supplied
values or unknown property names. This lets any tool caller correct the rejected
field without guessing or replaying an action. The receipt explicitly states that
no action was executed. The `expected_text` description gives a one-item array
example. Required array minima are also enforced. Regression tests cover a
corrected delegated call, nested fields, empty workflows, and private values.

This change improves recovery feedback across all tools and apps; it is not a
measured end-to-end latency result or proof that the Discord send completed.

On iOS 26 and later, a foreground user-started remote session submits a
`BGContinuedProcessingTaskRequest` with immediate-or-fail strategy. Its handler
is registered for the concrete identifier immediately before submission.
Each submitted identifier uses a unique suffix under the permitted
`tw.avianjay.tako.remote.*` wildcard; stale task callbacks cannot attach to a
new remote session. The system progress reflects
completed device actions; expiration cancels the agent, and task completion ends
the request. A declined request and older systems retain the bounded
`UIApplication.beginBackgroundTask` fallback. No task is queued to restart later.
ActivityKit remains a status surface. Neither API guarantees indefinite
execution; system cancellation, resource pressure, and closing the app can end
the work. iOS approvals require returning to Tako. See Apple's
[continued processing documentation](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados).

The build 13 installed trial demonstrated a cancelled 29.327-second Discord
worker. Separately, the production Dart worker on the PC sent the newly
authorized exact Nicko test message and verified its noneditable history label
in 22.079 seconds, 4 model rounds, 6 steps. An independent screenshot showed the
message in the DM and an empty composer. This desktop-hosted measurement does
not prove the installed-app background fix; that requires the later IPA trial.

The unsigned IPA must contain `PlugIns/TakoRemoteActivity.appex`, with the same build/version as the app. GitHub Actions verifies that extension and `NSSupportsLiveActivities` after compiling. The signer must preserve and sign the extension for Lock Screen / Dynamic Island display. CI compilation does not establish on-device background behavior.

Protocol reference: [OpenMinis/iCTRL](https://github.com/OpenMinis/iCTRL), Apache-2.0. See [third-party notices](../THIRD_PARTY_NOTICES.md).


Build 16's installed Calculator trial still cancelled after 32.158 seconds,
23 steps and 5 model rounds. It did not verify the requested final result 408.
Build 17 registers the same concrete identifier for the handler and request,
following Apple's example, with weak capture and stale callback rejection.
The permitted Info.plist value remains a wildcard. Device control settings
retain build, registration, submission, handler-start and scheduler error
domain/code diagnostics after a session ends. These contain no credentials,
task text or screen content. Submission failure remains bounded; no phone
actions are queued for delayed replay. Local validation passed 602 tests
with two opt-in tests skipped, 10 browser checks and clean analysis/formatting.
