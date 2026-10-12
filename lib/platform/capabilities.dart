/// Shared code discovers capabilities rather than making platform checks.
///
/// Capability contracts live with their subsystems: browser in
/// `core/browser`, screen control in `core/screen`, the shell in
/// `core/shell` and notifications in `core/notifications`. Android
/// implementations are in `platform/android`; iOS reports them unavailable.
abstract interface class Capability {
  bool get isAvailable;
}

// TODO(ios): shortcut capability (list_shortcuts, run_shortcut).
