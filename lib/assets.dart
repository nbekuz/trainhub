/// Typed asset path accessors.
///
/// Add new assets under `assets/` and expose them here so call sites stay
/// refactor-safe: `Assets.images.logo`, `Assets.icons.home`, etc.
///
/// Tip: for large projects consider `flutter_gen` to auto-generate this file.
class Assets {
  Assets._();

  static const images = _Images();
  static const icons = _Icons();
  static const animations = _Animations();
  static const translations = _Translations();
}

class _Images {
  const _Images();

  /// Example logo path — drop your file at `assets/images/logo.png`.
  final String logo = 'assets/images/logo.png';

  /// Example placeholder illustration.
  final String placeholder = 'assets/images/placeholder.png';
}

class _Icons {
  const _Icons();

  /// Example home icon — drop an SVG/PNG at `assets/icons/home.svg`.
  final String home = 'assets/icons/home.svg';

  /// Example settings icon.
  final String settings = 'assets/icons/settings.svg';
}

class _Animations {
  const _Animations();

  /// Example Lottie / Rive path.
  final String loading = 'assets/animations/loading.json';
}

class _Translations {
  const _Translations();

  /// Example ARB / JSON locale file.
  final String en = 'assets/translations/en.json';
}
