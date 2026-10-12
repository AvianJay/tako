/// Shared code discovers capabilities rather than making platform checks.
///
/// Capability contracts live with their subsystems: browser in
/// `core/browser`, screen control in `core/screen`, the shell in
/// `core/shell`, notifications in `core/notifications`, on-device models in
/// `core/on_device` and Shortcuts in `core/shortcuts`. Implementations are
/// in `platform/`: shared by Android and iOS in `native`, `on_device` and
/// `workspace`, or for one of them in `android` and `ios`. Each reports what
/// its platform cannot do as unavailable.
abstract interface class Capability {
  bool get isAvailable;
}
