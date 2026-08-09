/// Pluggable authentication provider for the robotsix-chat backend.
///
/// The chat backend is fronted by an SSO/OIDC gateway in production;
/// the mobile app uses a pluggable [AuthProvider] so the concrete
/// token-acquisition flow can be swapped in later without touching
/// the API service.
///
/// TODO: replace with real OIDC / mobile token-exchange flow once the
/// backend endpoint is built.
abstract class AuthProvider {
  /// Return headers to attach to every outgoing HTTP request.
  ///
  /// Called before each request, so implementations can return
  /// fresh tokens (e.g. with a short-lived OAuth2 access token
  /// that is refreshed on-demand).
  Future<Map<String, String>> requestHeaders();
}

/// [AuthProvider] that attaches a Bearer token when one is available.
///
/// Used for v1 where the token is supplied manually via the Settings
/// screen and persisted in secure storage.
class TokenAuthProvider implements AuthProvider {
  final String? token;

  const TokenAuthProvider({this.token});

  @override
  Future<Map<String, String>> requestHeaders() async {
    if (token != null && token!.isNotEmpty) {
      return {'Authorization': 'Bearer $token'};
    }
    return {};
  }
}
