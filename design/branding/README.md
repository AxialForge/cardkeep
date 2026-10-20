# CardKeep app icon package

Built from your selected orange card-and-corner-clip design. The symbol has been
cleaned into solid-color vector paths, retaining its two parts and stepped gap.
The original approved icon is included for reference. No wordmark is placed in
the app icons. Brand colors: orange `#C4542D`, ivory `#F7F4ED`, charcoal `#24231F`.

## What to use

| Target | Files |
| --- | --- |
| Android / Flutter Android | `android/app/src/main/res/` |
| iPhone and iPad / Flutter iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` |
| Google Play listing | `android/store/google-play-512.png` |
| Apple App Store | `ios/store/app-store-1024.png` (also in the Xcode catalog) |
| Windows / Flutter Windows | `windows/CardKeep.ico` |
| Editable artwork | `source/CardKeep-mark.svg`, `source/CardKeep-app-icon.svg` |
| Review the result | `preview.png` |

ICO is for Windows and compatible desktop/web tooling. Android and iOS use the
native resources included alongside it. This is an icon asset package; it is
not an APK, AAB, IPA, or a complete application. Other store material, including
screenshots and Android feature graphics, is separate from the app icon.

## Android installation

1. Merge `android/app/src/main/res/` into the same folder in your Android or
   Flutter project. Preserve unrelated existing files. The filenames beginning
   `ic_launcher` replace that project's icons, so back up any existing icons.
2. In the existing `<application>` element of `AndroidManifest.xml`, set
   `android:icon="@mipmap/ic_launcher"`. If you use a round icon, also set
   `android:roundIcon="@mipmap/ic_launcher_round"`. An attribute snippet is
   provided; do not replace your manifest with the snippet.
3. Build normally. Use an Android SDK that can compile API 33+ resources for
   the included themed icon layer. Android selects the appropriate versioned
   resource at runtime.

The package supplies legacy launcher icons at 48/72/96/144/192 pixels, vector
adaptive layers on a 108 dp canvas, and a monochrome layer. The mark is centered
within a 66 dp diameter safe region; the system supplies the final adaptive
mask. Version 26 XML provides foreground/background; version 33 adds monochrome.
Transparent PNG layers at every standard density are in `android/layers/` for
tools that require images rather than vectors. Those PNGs already include
adaptive padding; avoid adding the same padding again in an icon generator.

Optional notification artwork is `@drawable/ic_stat_cardkeep`: a white symbol
with transparent surround, exported at 24/36/48/72/96 pixels. Use it when your
notification API asks for a small status-bar icon. In flutter_local_notifications,
the Android resource name is `ic_stat_cardkeep` without an extension.

If your project uses different icon resource names or additional generated icon
folders, update or remove only the old icon resources that would override these
names. Uninstall/reinstall a development build if the launcher caches its icon.

[Android adaptive-icon requirements](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)

## iPhone and iPad installation

1. Replace the existing `AppIcon.appiconset` in your target's `Assets.xcassets`
   with `ios/Runner/Assets.xcassets/AppIcon.appiconset/`. For a Flutter project,
   this is normally `ios/Runner/Assets.xcassets/AppIcon.appiconset/`.
2. In Xcode, confirm the target's App Icons source is `AppIcon` and the catalog
   is configured to use a single size. The supplied `Contents.json` maps all
   three 1024 x 1024 appearance images: default, dark, and grayscale tinted.
3. Build and inspect on an iPhone/iPad simulator or device. iOS applies the
   outer mask; do not pre-round the supplied square PNGs.

The default and store images are opaque RGB PNGs with no alpha channel. All
exports carry an sRGB profile. Xcode generates the required size variations
from the modern 1024 catalog.

For an older project that expects explicit image sizes, use
`optional/ios-legacy/AppIcon.appiconset/` INSTEAD of the modern catalog. It
includes iPhone, iPad, and App Store slots at 20, 29, 40, 58, 60, 76, 80, 87,
120, 152, 167, 180, and 1024 pixels. Install only one catalog named AppIcon.

The optional Icon Composer folder contains importable SVG/PNG foreground art.
It is not a finished `.icon` project. Apple's layered Icon Composer workflow
requires macOS/Xcode; the supplied PNG catalog is the flat asset-catalog path.
The catalog does not supply custom clear-appearance or layered glass designs.

[Apple asset-catalog configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
[Apple Icon Composer workflow](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)

## Store icons

`android/store/google-play-512.png` is a 512 x 512, 32-bit RGBA PNG with an opaque
full square background, an sRGB profile, and no outer mask or shadow. Its size
is below 1024 KB. `ios/store/app-store-1024.png` is opaque RGB, 1024 x 1024.

[Google Play icon specifications](https://developer.android.com/distribute/google-play/resources/icon-design-specifications)

## ICO and Windows

`windows/CardKeep.ico` contains 16, 20, 24, 32, 40, 48, 64, 96, 128, and 256
pixel images in one ICO. The mark is orange with transparent surround. Matching
PNG exports are in `windows/png/`. In a Flutter Windows project, copy the ICO
to `windows/runner/resources/app_icon.ico`, retaining that filename.

[Microsoft icon construction](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction)

## Validation and scope

`validation-report.json` records the generated-file checks: dimensions, image
modes, alpha handling, PNG profiles, ICO entries, JSON image references, native
resource references, adaptive safe-zone coverage, and shape similarity to the
approved icon. `asset-manifest.json` lists sizes and SHA-256 hashes.

Artwork was exported deterministically from the cleaned SVG, not regenerated
with imagegen. The SDK/Xcode build and device installation have not been run
because this handoff contains artwork rather than the application project.
Review the icon after integration on your target launchers and Apple devices.

Platform references checked 2026-10-19.
