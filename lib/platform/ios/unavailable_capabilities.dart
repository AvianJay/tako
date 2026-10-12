/// iOS capabilities are not implemented yet. The contracts
/// already cover iOS: screen control has a screenshot observation mode with
/// x/y actions, and run_shell is environment-neutral.
library;

export '../../core/notifications/notification_capability.dart'
    show UnavailableNotifications;
export '../../core/screen/screen_capability.dart' show UnavailableScreen;
export '../../core/shell/shell_capability.dart' show UnavailableShell;

// TODO(ios): screen control through an external automation service
// (screenshot mode), a-Shell or a built-in shell, and Shortcuts.
