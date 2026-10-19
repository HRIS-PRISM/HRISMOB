/// Resolves only backend-owned, root-level raster images under `/uploads/`.
///
/// Protected API data is untrusted input. Full URLs, encoded paths and nested
/// paths are rejected so an event cannot make the app contact another host or
/// escape the intended static upload directory.
class UploadImageUrlResolver {
  UploadImageUrlResolver(Uri apiBaseUri)
    : _origin = _validatedOrigin(apiBaseUri);

  static const int _maxInputLength = 300;
  static final RegExp _pathPattern = RegExp(
    r'^/uploads/([A-Za-z0-9][A-Za-z0-9._-]{0,254})$',
  );
  static const Set<String> _extensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

  final Uri _origin;

  Uri? resolve(Object? value) {
    if (value is! String) return null;
    if (value.length > _maxInputLength ||
        value.codeUnits.any((code) => code < 0x20 || code == 0x7f)) {
      return null;
    }
    final raw = value.trim();
    if (raw != value ||
        raw.isEmpty ||
        raw.contains('%') ||
        raw.contains(r'\')) {
      return null;
    }

    final parsed = Uri.tryParse(raw);
    if (parsed == null ||
        parsed.hasScheme ||
        parsed.hasAuthority ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      return null;
    }

    final match = _pathPattern.firstMatch(raw);
    if (match == null) return null;
    final filename = match.group(1)!;
    if (filename.contains('..')) return null;
    final dot = filename.lastIndexOf('.');
    if (dot <= 0 || dot == filename.length - 1) return null;
    if (!_extensions.contains(filename.substring(dot + 1).toLowerCase())) {
      return null;
    }
    return _origin.resolve(raw);
  }

  static Uri _validatedOrigin(Uri base) {
    final scheme = base.scheme.toLowerCase();
    if (!base.isAbsolute ||
        !const {'http', 'https'}.contains(scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty) {
      throw ArgumentError.value(base, 'apiBaseUri', 'Invalid HTTP(S) origin');
    }
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    );
  }
}
