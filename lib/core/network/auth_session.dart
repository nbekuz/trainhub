/// Notifies the UI layer when the network stack invalidates the auth session.
///
/// Bound once under [ProviderScope] so interceptors can clear Riverpod state
/// and route to login without depending on Flutter widgets.
class AuthSession {
  void Function()? _onInvalidated;

  /// Registers the UI handler. Replaces any previous handler.
  void bind(void Function() onInvalidated) {
    _onInvalidated = onInvalidated;
  }

  /// Clears the UI binding (e.g. on dispose).
  void unbind() {
    _onInvalidated = null;
  }

  /// Called when access/refresh tokens are wiped after a hard auth failure.
  void notifyInvalidated() {
    _onInvalidated?.call();
  }
}
