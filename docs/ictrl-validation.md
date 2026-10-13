# iCTRL validation and agent latency

The implementation uses iCTRL's v1 authenticated envelopes and loopback pairing, or X25519 pairing for a LAN/Tailscale endpoint. The runner remains a separately installed application. Pairing keys live in platform secure storage, never in a conversation or the repository.

## Read and action costs

- Reuse the HTTP client and approved key. Refreshes do not repeatedly fetch the schema or prompt for pairing.
- Read the visible accessibility hierarchy with 400 elements and 100 children per container. The scientific Calculator keypad silently lost its last controls at 50 children; the new bound exposes them without an unbounded fetch. Strip server diagnostics before sending the listing to the model.
- Recover sparse reads and server-recommended OCR views with OCR. Rich truncated trees avoid an extra OCR round; request a screenshot or scroll when the needed control is missing. Prefer AX labels over OCR duplicates.
- Resolve labeled controls with a fresh live ref. Reject changed labels/types, offscreen matches, ambiguous results, and stale listing IDs. Unnamed containers are checked against their descendants.
- Observed navigation requests native settling with a 1.2-second cap. Stable-key sequences and timed/game input keep `settle:false`. When the server has not confirmed stability, only the next observation makes bounded local reads for unchanged, loading or wrong-launch pages. Never retry committed mutations automatically. Preserve warnings and page-change information; missing settling evidence is unknown.
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


## Build 17 installed validation and native icon workflows

Build 17 (3968436, successful Actions run 38372521120) was signed with the
existing LCSign configuration, installed and launched. Device control shows
`build 17`, `registered=true`, `submitted=true`, `handler=true`, state `ended`,
local pairing ready at 127.0.0.1:8200 and Haiku Messages xhigh ready. The
installed Calculator task ran beyond the previous 32-second cancellation.
External Claude observations independently captured 7+8=15, 123+456=579 and
98-76=22; the Tako response reports the two intermediate answers 408 and134.
The main model split the prompt into separate remote_control calls. Those
observations prove continued execution on this phone, not indefinite uptime
or a measured speed improvement for the entire five-operation task.

The latest authorized Nicko message was sent once through the production
Haiku worker on the PC and independently verified in history. No further
Nicko messages were sent.

Shopee's cart now contains one environment-technology ESP32-S3 SuperMini
board, variant unsoldered pins, actual cart price TWD165. A native read and
independent screenshot confirm title, variant and quantity1. The badge
increased from4to5 during the external Claude attempt; its verbal report
incorrectly said nothing was added. The subsequent installed worker reached
the cart and reported165 but did not establish quantity itself. Preserve
existing items and never retry an add from an uncertain verbal report.
This is a failed cheapest-price selection:147 was previously inspected,
not relocated for the final addition, and the165item is not globally cheapest.

Build18 makes visible unnamed native image IDs discoverable in compact
screen reads across apps, allowing workflow view_id selection without a
screenshot/model round. Images inside a named tappable parent stay omitted.
The live PC-hosted production workflow opened Shopee's native cart icon
and independently verified the cart heading in3.031seconds,3steps,0worker
model rounds,0worker tokens and421characters returned to the main agent.
This timing starts on Shopee Home and excludes the main model and app launch.
It verifies navigation, not item price or quantity. The result drawer shows
results before long arguments so device verification does not require
scrolling past a full workflow JSON.


The subsequent external Claude stage relocated the mixed C3/S3/C6/H2 listing
using an exact-title search URL and rechecked its ESP32-S3-SuperMini board
variant at147(152struck), stock169, quantity1. It committed one add and
verified sellerwmx88's exact variant in the cart at152before discount;
badge5became6. Independent screenshots confirm both selector and cart.
This completes the lowest-among-four variant addition, not a worldwide
cheapest guarantee or an installed-worker add. The earlier165testboard
remains in the cart along with all original items. Claude unchecked only
the newly added item, leaving zero selected and no checkout. Final local
validation passed604tests with2opt-in tests skipped and cleananalysis,
formatting, and10browser checks.

## Automatic proxy discovery and worker reasoning (build 19)

The CPA proxy changes its model-ID format according to authentication. A live
Bearer request to `/v1/models` returns 57 mixed model IDs including
`gpt-6.1-sol` and `claude-haiku-5-5`. The same URL with Anthropic headers
returns Claude-formatted IDs and no GPT IDs. Multi-API mode therefore uses
Bearer authentication for discovery, Messages for Claude generation and
Responses for GPT generation. A live GPT 6.1 Sol Responses request successfully
returned the requested harmless `echo_test` function call.

Discovery runs on startup, provider save, foreground return and model selection,
with a 15-minute successful-fetch cache and coalesced requests. Refresh preserves
edited profiles, shared secure-storage references, the main selection and the
independent worker selection. Empty/offline replies retain the saved list. A
reply for a changed connection is discarded; updates wait for active generation
to finish. Friendly names affect presentation only; exact IDs remain on the wire.
Unknown model capabilities remain manual rather than inferred from `/models`.

Worker reasoning is independently selectable. Claude Off sends
`thinking.type=disabled`; Low/Medium/High/Extra use the selected supported effort.
GPT 6.1 offers Low through Maximum, without an unsupported Off choice. Haiku's
previous Extra default remains unless the user changes the worker setting.

The real production Dart Haiku worker on the PC controlled this iPhone's
Calculator and verified both results from fresh native screen data. No Codex
chose the key taps. Each cell is one live trial, not a statistical benchmark:

| Worker effort | 7 + 8 = 15 | 123 + 456 = 579 | Model rounds |
| --- | ---: | ---: | --- |
| Off | 7.542 s | 14.573 s | 1 / 3 |
| Low | 7.550 s | 9.672 s | 1 / 1 |
| Extra | 7.655 s | 10.383 s | 1 / 1 |

These timings exclude main-agent planning and app launch. Low used roughly
3.1 seconds of model time per expression; native checks and taps account for
the remaining time. Off did not improve the longer case because it needed
additional model rounds. The main agent received 428–430 result characters,
with no raw worker screen history. These figures do not establish identical
performance for arbitrary apps or games.

## General navigation, recovery and chat fixes (build 19)

App resolution reads the runner's opened-app history first and matches supplied
English/localized names without launching. Catalog suggestions retain their
source and never claim installation. On this phone `Shopee|蝦皮` resolves
`com.beeasy.shopee.tw`; `Settings|設定` resolves `com.apple.Preferences`.
The upstream name catalog returned unrelated candidates for English Shopee,
so treating every catalog result as installed would be incorrect. An empty
lookup does not prove that an app is absent. Android resolves actual installed
packages using its native listing.

Workflows prefer actionable controls over a matching page title, expose stable
native IDs for buttons, revalidate each step against a fresh observation and
return one final screen instead of every intermediate screen. A bounded
postcondition read can wait for a transition without replaying its gesture.
Read-only locator failures can fall back to an exact fresh-tree identity and
nearby geometry match; changed apps, moved controls and ambiguous matches
remain rejected. No uncertain mutation is automatically retried.

An unfinished worker gets one bounded recovery opportunity within the original
task. Password/login/CAPTCHA/denial blockers stop it. A constraint reminder such
as 'I did not enter passwords' does not incorrectly prevent navigation recovery.
Missing expected evidence prevents a worker's verbal completion from ending
the run as success. Remote results needing semantic review show Incomplete
rather than Completed. Tapping blank chat history or dragging it dismisses the
keyboard and preserves the draft.

Live Claude Low trials through the production Dart worker:

| Task | Elapsed | Worker rounds | Model time | Outcome |
| --- | ---: | ---: | ---: | --- |
| Storage from a wrong nested Settings page | 37.002 s | 9 | 24.289 s | Reached storage, read figures |
| Storage via root and General after workflow fixes | 18.817 s | 2 | 9.556 s | Read 178.49/256 GB and largest visible app 31.41 GB |
| Discord to Nicko DM, read only | 30.728 s | 4 | 22.168 s | DM reached; message author remained ambiguous |
| Calculator 7+8 | 11.048 s | 2 | 6.948 s | Native result 15 verified; first request had malformed tap_ids |
| Calculator 123+456 | 9.831 s | 1 | 3.140 s | Native result 579 verified |
| Settings storage heading, resumed page from Calculator | 4.551 s | 1 | 2.548 s | Exact heading verified; no full storage reading |
| Discord navigation to Nicko header | 12.761 s | 2 | 8.914 s | Exact DM header verified with workflow; no message sent |
| Shopee known URL search for ESP32-S3 | 6.460 s | 0 | 0 s | Native product title and price card verified with workflow |

These are single trials with different starting states and tasks, not an A/B
benchmark. Storage and Discord remain semantic-review results; their compact
native evidence does not prove the full meaning of the worker's claims. No
extra Discord message was sent. Calculator main results were 429/431 characters.
Schema guidance now explicitly requires tap_ids to be an integer JSON array.
No claim of universal best speed or installed Tako osu gameplay is made.
The last Shopee trial verifies a search result card at TWD2,568, not a cheapest
variant or another cart addition. Settings resumed its stored page, so its
4.551-second result cannot be compared to navigation from Settings root.

Local checks after integrating the concurrent upstream updates: 659 tests passed
with three opt-in tests skipped; clean Flutter
analysis and Dart formatting; browser runtime 10/10. These checks are distinct
from CI packaging and the later LCSign installed-app trial.

Build 19 commit `20218be` passed all check, iOS and release jobs in
[GitHub Actions run 38397126507](https://github.com/AvianJay/tako/actions/runs/38397126507).
The downloaded 21,022,784-byte IPA passed ZIP integrity and app/extension
build-number checks: both bundles report build 19, and the app enables
`NSSupportsLiveActivities`.

## Build 19 installed validation

External Claude imported the downloaded IPA into LCSign and used the existing
signer to sign and install it. The signing log records build 19 and source
`Tako-20218be`; iOS installation was confirmed once. A later installed task
populated Device control diagnostics with `build 19`, state `ended`,
`registered=true`, `submitted=true` and `handler=true`, with no error shown.
The app retained its existing chats, provider credentials and pairing at
`http://127.0.0.1:8200`.

Claude selected GPT 6.1 Sol in the main chat and CPA / Haiku 5.5 / Low in
Device control. The saved worker readiness reads
`Haiku 5.5 · messages · low`; the main header remains GPT 6.1 Sol. Automatic
fetch was already enabled. Enabling CPA multi-API mode added mixed-format
IDs while preserving the existing profiles, so the installed saved list
showed 92 entries after refresh. This is a merged list, not 92 unique models
reported by the Bearer endpoint, which returned 57 in the earlier live test.
Reopening the saved provider editor independently confirmed both automatic
fetch and CPA multi-API switches were on, with the stored-key retention note.

The installed GPT main model resolved Settings and delegated one storage read
to the production Haiku Low worker. Claude only submitted the task and later
inspected it; all Settings actions came from the installed worker. The
`remote_control` receipt reports 10.452 seconds, two model rounds, three steps,
6.356 seconds of model time and `workflow_used=true`. Independent native
observations matched the final answer: 178.43 GB used of 256 GB; the largest
visible app was 異環 at 31.41 GB, with the list sorted by size. The receipt
retained `status=reported_complete`, `verified=false` and
`semantic_review_needed=true`, so the UI accurately showed Incomplete. This
read task lacked exact completion assertions; independent inspection
confirmed its figures, without turning arbitrary semantic claims into
automatic verification. The 10.452-second worker measurement excludes main
planning, response synthesis, and the QA controller's later inspection.

On the installed app, tapping blank chat history changed native
`keyboard.visible` from true to false and retained the unsent
`keyboard dismiss smoke` draft. Refocusing reopened the keyboard. Dragging
the initial blank chat did not dismiss it because it had no scrollable
history. A separate trial in the populated storage chat confirmed a history
drag changed `keyboard.visible` from true to false while preserving the draft.
The phone was left on the GPT 6.1 Sol chat with the keyboard dismissed.

## Android-style execution and direct results (build 20)

The Android source uses native Pigeon/AccessibilityNodeInfo operations, a real
OS Back action, hides its own overlay around input/capture, and waits for
accessibility change/quiet before returning a screen. These are source
observations, not a paired Android hardware latency benchmark. iOS still uses
remote XCTest RPCs and visible navigation controls; the platforms do not have
identical transport or background presentation APIs.

The common executor now resolves app names inside an `open_app` workflow,
without a separate main-model lookup round. Known exact label/view-ID steps
run locally from fresh observations. A bounded `back` step resolves the live
BackButton after each page, stops on unchanged pages/app changes/ambiguity,
and can find an exact destination within at most six back steps. Nested Cell
and Button representations of one row resolve to the deepest control; sibling
duplicates remain ambiguous. These primitives contain no Shopee-specific
navigation rules and do not persist learned macros.

Observed iOS navigation asks for native settling, capped at 1.2 seconds. If
native stability is unconfirmed, the next read permits at most three extra
reads with cancellable 100/180/180-ms waits. Server `loading:true` metadata is
also honored. Keypad and timed actions skip native settling; repeated keys
reuse the exact live server selector only within the same observation. The
server re-resolves that selector on every tap, and a fresh snapshot invalidates
the local cache. Other controls still require fresh target validation. A UI
timeout that may remain queued stops the run before another action or proof
read; regression checks cover initial reads, supplied workflows and two
model-emitted calls in one response.

Worker prompts and retained generated screen history are smaller. At most two
worker observations/images are retained while task text, action receipts,
errors and decisions are preserved; main user attachments are untouched. A
partial launch workflow no longer makes three pointless completion polls
before worker navigation. A single standalone `remote_control` with
`reply_direct:true` returns its compact note/native evidence immediately,
without another main-model summary call. Unverified reports are labeled as
such; mixed tasks and missing proof/note retain the ordinary main-agent path.
Receipts include model/effort, worker timing and main time/rounds before
delegation. Unit tests check one main request for direct results versus two
for the ordinary summary, honest failure labels, and permission-mode prompt
cache invalidation. Main and worker selections remain independent.

Live Sonnet 5.5 Medium trials on this phone:

| Task/sample | Elapsed | Worker rounds | Model time | Outcome |
| --- | ---: | ---: | ---: | --- |
| Baseline Calculator 7+8 | 16.549 s | 2 | 8.843 s | Native 15 verified |
| Baseline Calculator 123+456 | 10.056 s | 1 | 3.320 s | Native 579 verified |
| Reduced polling Calculator 7+8 | 10.182 s | 1 | 4.981 s | Native 15 verified |
| Reduced polling Calculator 123+456 | 43.292 s | 1 | 35.003 s | Native 579 verified; slow provider response |
| Final build-20 Calculator 7+8 | 15.770 s | 1 | 10.061 s | Native 15 verified |
| Final build-20 Calculator 123+456 | 17.032 s | 1 | 9.725 s | Native 579 verified |
| Initial nested Settings recovery | 239.854 s | 12 | 127.771 s | Failed with repeated UI/provider timeouts; motivated bounded busy stop |
| Settings About after native settling | 58.128 s | 7 | 45.422 s | iOS 27.0/model reported; independent inspection matched |
| Supplied Settings root/General/About workflow | 8.681 s | 0 | 0 s | Exact iPhone 16 Pro Max/app verified |
| Shopee free-coin availability inspection | 78.786 s | 6 | 62.197 s | Today already claimed; balance 0.16; no new reward action |

These are individual trials with different starting screens and intermediate
code revisions, not a controlled speedup benchmark. The Calculator samples
precede the last key-ref/native-settle adjustments. The 8.681-second Settings
sample measures a supplied known local route, excluding main planning; it
does not measure autonomous discovery. Settings reading and coin inspection
remain semantic-review reports rather than exact automatic verification.
Coin inspection excluded the already-claimed treasure, wheel and unrelated
points tasks; it does not prove every possible free reward is unavailable.
One provider round took 35 seconds despite a small action plan. No universal
best-speed, measured Android parity, or installed rhythm-game result is
claimed. In an earlier Calculator RPC sample, average find/tap/page-source
costs were 187/430/265 ms respectively, separate from model latency. The final
two Calculator trials made seven page-source calls combined, versus fourteen
in the earlier Android-style sample; both final trials completed in one worker
round. These runtime results measure the production Dart worker on the phone
through Tailscale, before IPA installation.

On iOS 26+, successful continued-processing submission already supplies a
system Live Activity, so build 20 does not create a duplicate custom one. The
custom fallback status ends after three seconds and immediately on completion;
per-action system subtitle rewriting was removed. Background processing is
preserved. Apple's public API cannot hide an active system continued-processing
Live Activity while preserving its execution task; an expanded banner can
still be swiped upward when it obstructs navigation. See Apple's
[continued-processing documentation](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados/)
and [immediate ActivityKit dismissal](https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/immediate).

Local build-20 verification: **685 passed, three opt-in tests skipped**,
clean Flutter analysis, unchanged Dart formatting and browser runtime 10/10.
The latest requested installed configuration is main GPT 6.1 Sol and worker
Sonnet 5.5 / Medium / Messages. CI and installed validation follow separately.

## Build 20 release and installed validation

Implementation commit `23693c7e29f86bffccc7cf5fb64a7b57af7e34ac` passed
all check, iOS and release jobs in
[Actions run 38423659526](https://github.com/AvianJay/tako/actions/runs/38423659526).
The [nightly release](https://github.com/AvianJay/tako/releases/tag/nightly)
published version `0.5.0+20` at that commit. The exact 21,040,672-byte IPA
passed ZIP integrity checks. App and Live Activity extension both report
build 20; bundle ID is `tw.avianjay.tako`, with Live Activities enabled. Its
SHA-256 matches the GitHub release asset digest:
`80be0c2c188188ab5293c7a823b8ae2574c5d47027ddf5d40157bb51a798130c`.

External Claude downloaded the exact `Tako-23693c7.ipa` through Safari and
imported it into LCSign. The first Haiku QA controller wandered in the picker
and incorrectly inferred cancellation meant import had failed. A separate
Sonnet Medium QA inspection checked the existing newest project first, found
the new source, and completed signing without importing again. The signing
log identifies build 20 and source `Tako-23693c7`; the install manifest
identifies `bundleID=tw.avianjay.tako, version=20`. It used the unchanged
saved signer, selected immediate install and accepted iOS installation once.
Tako reopened with existing chats. A later native diagnostics read confirmed
the installed executable is build 20, not merely the signed package. No
additional messages, cart changes, coin claims or wheel spins occurred.

Claude submitted phone requests through the installed GPT 6.1 Sol main agent.
All target-app actions came from the installed Sonnet 5.5 Medium Messages
worker; QA only submitted requests and inspected results afterward. It
preserved local pairing at `http://127.0.0.1:8200`, model selections, credentials
and chats. Installed outcomes:

| Request | Main before worker | Worker elapsed/model time | Worker rounds/steps | Saved outcome |
| --- | ---: | ---: | ---: | --- |
| Settings iOS version/model | 10.470 s, 1 main round | 9.978 / 8.092 s | 1 / 2 | Reported iOS 27.0, iPhone 16 Pro Max; semantic review |
| Calculator clear then 7+8=15 | 11.957 s, 1 main round | 15.016 / 9.547 s | 2 / 7 | Native exact 15/app verified |

Settings was already on About after an earlier trial. Two worker steps
(launch and proof read) did not establish the requested path through Settings
home/General. Its final values matched native labels, but the receipt correctly
kept `status=reported_complete`, `verified=false`, and
`semantic_review_needed=true`. This is a read/report test, not a navigation
benchmark from the root. The final answer was labeled
`操作模型回報（尚未獨立驗證）`.

Calculator independently reported `status=verified`, `verified=true`,
`matched_text=["15"]`, `semantic_review_needed=false`,
`worker_model=claude-sonnet-5-5`, `worker_effort=medium`,
`workflow_used=true`, `recovery_attempts=0`. Its tool arguments contained
`reply_direct=true` and `reply_language=繁體中文`. The final assistant text was
`已由畫面核對。15`, with no additional main-model synthesis. The first QA
report confused the row timestamp with a duration and did not inspect all
JSON fields; retained screenshots and a separate OCR inspection established
the actual values above. The second controller initially failed to read the
top JSON fields, which are plainly present in its saved first screenshot;
direct visual review confirmed those fields rather than assuming they were
absent. These QA inspection delays are separate from the measured app task.

The installed Calculator path took at least **26.973 seconds** before the
small local save/display work: 11.957 seconds main plus 15.016 worker. Of that,
21.504 seconds was model response time. Direct reporting removes a third
summary request; it does not eliminate the initial main planner or guarantee
low provider latency. This is still slow for simple arithmetic and does not
demonstrate Android hardware parity. General workflows can bypass worker
model calls when their exact route and final proof are supplied.

Native Device control diagnostics show `build 20`, `processing_state=ended`,
`registered=true`, `submitted=true`, `handler=true`, and
`custom_status=false`, with no error displayed. This confirms background
execution ran and no duplicate custom activity was present; it does not
prove Apple automatically hides its active system status. Readiness remains
`Sonnet 5.5 · messages · medium`, delegation enabled, with GPT 6.1 Sol in
the main chat. The phone was left in the main chat with keyboard dismissed
and no unsent draft.
