# axial_app_kit

Shared theme, layout and guidance kit for AxialForge mobile apps. Planning docs: `docs/`.

Use from an app (local development):

```yaml
dependencies:
  axial_app_kit:
    path: ../Mobile Kit
```

Apps build their own `ThemeCatalog` from `ThemeFamily.standard` (re-label, reorder, trim) and pass it to
`ThemeChoice.parse(raw, catalog: ...)`. Saved ids never change meaning: `system` is the catalog's default family,
`system:<familyId>` another family, and a bare palette id (`light`, `dark`, `harborDark`, ...) is a pinned mode.

```bash
flutter pub get
flutter analyze
flutter test
```
