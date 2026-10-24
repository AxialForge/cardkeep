import 'package:axial_app_kit/axial_app_kit.dart';

/// The looks CardKeep offers, in pill order: CardKeep (orange, the default), Navy and brass,
/// then the Pagemark looks. The palettes and the saved-id rules live in axial_app_kit.
const cardkeepThemes = ThemeCatalog([
  ThemeFamily('classic', 'CardKeep', AppPalette.light, AppPalette.dark),
  ThemeFamily.navyBrass,
  ThemeFamily.harbor,
  ThemeFamily.rosewater,
  ThemeFamily.sage,
  ThemeFamily.lamplight,
]);
