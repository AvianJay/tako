# Automations

Open **Settings → Automations** to create a schedule, an Android notification
trigger, or an iOS Shortcut entry. Select a saved text model and write the task
prompt. Rules start disabled until enabled explicitly.

Notification conditions have a basic form and a safe expression editor:

```text
package == "jp.naver.line" and "班群" in title
```

Use the package name installed on the device. Supported fields are `package`,
`appLabel`, `title`, `text`, `lines`, `category`, and `ongoing`. Expressions support
`==`, `!=`, `in`, `not in`, `and`, `or`, `not`, parentheses, and literal lists.
They cannot call functions or access properties. The condition tester evaluates
sample JSON locally and never contacts a model.

Notification rules can run immediately, combine notifications in a window
starting at the first matching event, or collect them until a schedule. A digest
with no new matching input is skipped. Tako's own notifications are excluded.
Duplicate notification updates and repeated MessagingStyle messages are filtered
before ingress. Group summaries are omitted to avoid duplicate child messages.
Large batches split at 50 events or approximately 24,000 characters; remaining
events are queued in additional runs rather than discarded.

Schedules support once, daily, selected weekdays, and intervals of at least 15
minutes. Daily/weekly schedules follow the device's local time. Missed occurrences
are caught up once. Android's optional precise mode requires **Alarms & reminders**
access; it controls the trigger time, while model/tool execution can take longer.
Normal background work follows Android's scheduling and battery restrictions.

Each execution has a saved rule/input snapshot and a separate run record. Runs
use independent conversations by default; a rule can continue its own conversation.
Automation conversations are accessible from run details without cluttering the
normal chat list. The history screen loads all active tasks and the 100 most
recent finished runs. **Clear finished history** removes finished records and
unused automation conversations and attachments; it preserves resumable tasks,
the open conversation, and conversations still used by continuing rules.

AI edits with `automation_save` preserve fields omitted from an existing rule,
including nested schedule fields. Renaming a rule keeps its existing schedule
deadline. Each resumed task starts a new user-wait period; execution time does
not consume that period. Permission changes are merged atomically per preference
and reloaded before authorization, including across foreground/background engines.

Android checks basic package/title/text filters before starting a worker. Advanced
expressions are evaluated in Dart. Unchanged rules are not repeatedly synchronized
on idle polls. Database upgrades commit their schema and version in one transaction
and recheck the current version after acquiring the native SQLite writer lock.

AI chooses from the normal enabled tools and uses the same
permission policy and audit log as chat.

If the entire final visible answer, after trimming whitespace, is `[SILENT]`, the
run completes silently. Other valid results post a notification linked to the run.
Intermediate reasoning and tool output do not control this decision.

## Waiting and recovery

Background requests needing approval or foreground access are saved and paused.
Open the task notification and choose **Review and continue**. Approval targets
are resolved again using the existing tool permission checks. A per-rule waiting
timeout is optional; blank means no timeout.

Native events are durable until a successful Drift transaction acknowledges them.
UI/background engines coordinate through a process broker, SQLite execution
leases, WAL, and native change signals. Interactive chat can interrupt background
work at safe boundaries. Ordinary workers are bounded to eight-minute execution
segments, with progress persisted for continuation.

Each tool operation, including inner REPL primitives, records its start and result.
Completed calls are not automatically replayed. If the process dies during an
operation, the task requires review; resuming produces an interruption receipt for
unconfirmed calls rather than replaying an old REPL program. A model may then plan
the next step from saved evidence under the normal permissions.

## iOS Shortcuts

iOS does not expose other apps' notifications. Background execution is best effort
through a separate `BGProcessingTask` identifier; it can be delayed or interrupted.
Opening Tako processes pending work. Keys or models unavailable in the background
leave the task waiting for foreground execution.

1. Create and enable a rule with the **iOS Shortcut** trigger.
2. In Shortcuts → Automation, select a personal trigger such as Time of Day.
3. Add **Queue Tako Automation**, select the rule, and optionally pass text.
4. Choose automatic execution where iOS offers it.

The intent saves input and schedules background work without opening Tako. Its
result confirms queueing, not task completion. Existing `run_shortcut` behavior
and iCTRL continued-processing identifiers are separate.

## Implementation and checks

Shared behavior is in `lib/core/automation`, `lib/app/automation_*`, and
`lib/data/automation_repository.dart`; the shared agent loop is in
`lib/core/chat/agent_runner.dart`. `pigeons/automation_api.dart` defines both
native implementations. Database schema 4 adds rules, inputs, runs, event dedup,
and execution leases. Provider credentials continue to use secure storage.

Android adds **Jetpack WorkManager 2.11.2**, a native dependency for persistent
work. No Flutter background plugin is needed. iOS uses system BackgroundTasks,
AppIntents, and UserNotifications.

```powershell
dart run pigeon --input pigeons/automation_api.dart
flutter gen-l10n
flutter analyze
flutter test test/automation
flutter test
flutter build apk --debug --flavor full
flutter build apk --debug --flavor play
```

`tool/automation_smoke.dart` and `tool/automation_fixture_server.py` provide an
isolated Android headless-worker probe. Build it with a **separate application ID**
and use only the fixture server; it is not a production app entry point. Actual
notification delivery, exact alarms, reboot recovery, lock-screen behavior, iOS
App Intents, and iOS expiration should also be checked on physical devices.

Validated on 2026-10-16: both Android debug flavors build for arm64 and x86-64.
An isolated Android 16 emulator completed a scheduled headless model/tool run,
merged two notifications while ignoring an identical update, and completed a
notification run after its app process restarted without an Activity. Native
screen status and user-stop/system-retry behavior are covered by tests. iOS
Swift syntax, resource references and localization data were checked locally;
Xcode compilation and physical iOS validation remain unverified.
