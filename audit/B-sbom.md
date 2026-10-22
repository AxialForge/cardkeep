# Appendix B: Software bill of materials (CardKeep 0.6.0)

Source: pubspec.lock at cdcf49d (dev dependencies excluded), licences read from the local pub cache LICENSE files, native libs from audit/artifact/native-libs.txt. Generated 2026-10-21. Outdated status from `flutter pub outdated` 2026-10-21. No pub.dev security advisory was reported by pub tooling; an external OSV/GHSA lookup was not performed (MANUAL REVIEW in G1).

## Native and platform components in the APK

| Component | Version | Origin | Licence | Notes |
|---|---|---|---|---|
| Flutter engine (libflutter.so) | 3.47.0 | Flutter SDK | BSD-3-Clause | Pinned in CI |
| Dart AOT app (libapp.so) | 0.6.0 | this repo | project licence | - |
| OpenCV (libdartcv.so) | via opencv_dart 2.2.2 | opencv_dart | Apache-2.0 | Image parsing of untrusted photos |
| SQLite (libsqlite3.so) | via sqlite3 3.5.2 | sqlite3 build hook | Public domain | FTS5 used |
| ML Kit OCR (libmlkit_google_ocr_pipeline.so) | via google_mlkit_text_recognition 0.17.1 | Google | ML Kit Terms | Bundled model, offline |
| ML Kit barcode (libbarhopper_v3.so) | via google_mlkit_barcode_scanning 0.16.1 | Google | ML Kit Terms | Bundled model |
| CameraX JNI (libimage_processing_util_jni.so, libsurface_util_jni.so) | via camera_android_camerax 0.7.5+1 | AndroidX | Apache-2.0 | - |
| libdartjni.so | jni 1.1.0 | Dart team | BSD-3-Clause | - |
| desugar_jdk_libs | 2.1.4 | Google | GPL-2.0 with Classpath Exception | Core library desugaring |

## Dart / Flutter packages

| Name | Version | Direct/transitive | Licence | Notes on risk |
|---|---|---|---|---|
| archive | 4.5.2 | direct | MIT | Parses user-chosen .zip backups (zip-slip handling assessed in the security domain) |
| camera | 0.12.1 | direct | BSD-3-Clause | Pulls RECORD_AUDIO into manifest (MOB-BLD-0001) |
| crypto | 3.0.7 | direct | BSD-3-Clause | SHA-256 for update and image hashing |
| device_info_plus | 13.3.0 | direct | BSD-3-Clause | - |
| drift | 2.35.2 | direct | MIT | - |
| drift_flutter | 0.3.1 | direct | MIT | - |
| file_picker | 13.1.0 | direct | MIT | SAF imports |
| flutter | 0.0.0 | direct | BSD-3-Clause (Flutter SDK) | - |
| flutter_local_notifications | 22.3.2 | direct | BSD-3-Clause | Boot receiver (exported=false) |
| flutter_riverpod | 3.4.3 | direct | MIT | - |
| go_router | 18.1.0 | direct | BSD-3-Clause | 18.1.1 available |
| google_mlkit_barcode_scanning | 0.16.1 | direct | MIT | Bundles ML Kit barcode (libbarhopper_v3.so); ML Kit terms |
| google_mlkit_text_recognition | 0.17.1 | direct | MIT | Bundles Google ML Kit OCR (proprietary ML Kit terms), on-device |
| http | 1.6.0 | direct | BSD-3-Clause | Only used by updater to GitHub |
| image | 4.12.0 | direct | MIT | Decodes untrusted images in Dart |
| image_picker | 1.2.4 | direct | Apache-2.0 | - |
| intl | 0.20.3 | direct | BSD-3-Clause | - |
| ndef_record | 1.4.2 | direct | MIT | 1.5.0 exists, not resolvable with nfc_manager_ndef |
| nfc_manager | 4.2.1 | direct | MIT | Reads untrusted NDEF tags |
| nfc_manager_ndef | 1.1.0 | direct | MIT | - |
| open_filex | 5.0.0 | direct | BSD-3-Clause | - |
| opencv_dart | 2.2.2 | direct | Apache-2.0 | Bundles native OpenCV (libdartcv.so 10.9 MB); parses untrusted images |
| package_info_plus | 10.2.2 | direct | BSD-3-Clause | - |
| path | 1.9.1 | direct | BSD-3-Clause | - |
| path_provider | 2.1.6 | direct | BSD-3-Clause | - |
| permission_handler | 13.0.2 | direct | MIT | - |
| phone_numbers_parser | 9.0.28 | direct | MIT | - |
| qr_flutter | 4.1.0 | direct | BSD-3-Clause | - |
| screen_brightness | 2.1.11 | direct | MIT | - |
| share_plus | 13.3.1 | direct | BSD-3-Clause | - |
| timezone | 0.11.2 | direct | BSD-2-Clause | - |
| url_launcher | 6.3.3 | direct | BSD-3-Clause | Opens links only on tap |
| uuid | 4.6.0 | direct | MIT | - |
| _fe_analyzer_shared | 109.0.0 | transitive | BSD-3-Clause | - |
| analyzer | 14.5.0 | transitive | BSD-3-Clause | - |
| android_file_picker | 2.1.1 | transitive | MIT | - |
| args | 2.7.0 | transitive | BSD-3-Clause | - |
| async | 2.13.1 | transitive | BSD-3-Clause | - |
| boolean_selector | 2.1.2 | transitive | BSD-3-Clause | - |
| build | 4.0.11 | transitive | BSD-3-Clause | - |
| build_config | 1.3.3 | transitive | BSD-3-Clause | - |
| build_daemon | 4.1.7 | transitive | BSD-3-Clause | - |
| built_collection | 5.1.2 | transitive | BSD-3-Clause | - |
| built_value | 8.13.0 | transitive | BSD-3-Clause | - |
| camera_android_camerax | 0.7.5+1 | transitive | BSD-3-Clause | - |
| camera_avfoundation | 0.10.3+1 | transitive | BSD-3-Clause | - |
| camera_platform_interface | 2.15.0 | transitive | BSD-3-Clause | - |
| camera_web | 0.3.5+6 | transitive | BSD-3-Clause | - |
| change_case | 2.2.0 | transitive | MIT | - |
| characters | 1.4.1 | transitive | BSD-3-Clause | - |
| charcode | 1.4.0 | transitive | BSD-3-Clause | - |
| checked_yaml | 2.0.4 | transitive | BSD-3-Clause | - |
| cli_util | 0.6.0 | transitive | BSD-3-Clause | - |
| clock | 1.1.3 | transitive | Apache-2.0 | - |
| code_assets | 1.2.1 | transitive | BSD-3-Clause | - |
| collection | 1.19.1 | transitive | BSD-3-Clause | - |
| convert | 3.1.2 | transitive | BSD-3-Clause | - |
| cross_file | 0.3.5+5 | transitive | BSD-3-Clause | - |
| cupertino_ui | 1.1.3 | transitive | BSD-3-Clause | - |
| dart_style | 3.1.14 | transitive | BSD-3-Clause | - |
| dartcv4 | 2.2.2 | transitive | Apache-2.0 | OpenCV bindings; 2.3.1 available |
| dbus | 0.8.0 | transitive | MPL-2.0 | MPL-2.0, Linux-only, not in APK |
| device_info_plus_platform_interface | 8.1.0 | transitive | BSD-3-Clause | - |
| fake_async | 1.3.3 | transitive | Apache-2.0 | - |
| ffi | 2.2.0 | transitive | BSD-3-Clause | - |
| ffi_leak_tracker | 0.1.2 | transitive | BSD-3-Clause | - |
| file | 7.0.1 | transitive | BSD-3-Clause | - |
| file_picker_darwin | 2.3.2 | transitive | MIT | - |
| file_picker_linux | 2.0.2 | transitive | MIT | - |
| file_picker_platform_interface | 4.2.0 | transitive | MIT | - |
| file_picker_web | 4.2.0 | transitive | MIT | - |
| file_selector_linux | 0.9.4+1 | transitive | BSD-3-Clause | - |
| file_selector_macos | 0.9.5+2 | transitive | BSD-3-Clause | - |
| file_selector_platform_interface | 2.7.0 | transitive | BSD-3-Clause | - |
| file_selector_windows | 0.9.3+6 | transitive | BSD-3-Clause | - |
| fixnum | 1.1.1 | transitive | BSD-3-Clause | - |
| flutter_local_notifications_linux | 8.0.2 | transitive | BSD-3-Clause | - |
| flutter_local_notifications_platform_interface | 12.2.0 | transitive | BSD-3-Clause | - |
| flutter_local_notifications_web | 1.0.0 | transitive | BSD-3-Clause | - |
| flutter_local_notifications_windows | 3.1.1 | transitive | BSD-3-Clause | - |
| flutter_localizations | 0.0.0 | transitive | BSD-3-Clause (Flutter SDK) | - |
| flutter_plugin_android_lifecycle | 2.0.35 | transitive | BSD-3-Clause | - |
| flutter_web_plugins | 0.0.0 | transitive | BSD-3-Clause (Flutter SDK) | - |
| glob | 2.2.0 | transitive | BSD-3-Clause | - |
| google_mlkit_commons | 0.13.0 | transitive | MIT | - |
| graphs | 2.3.2 | transitive | BSD-3-Clause | - |
| hooks | 2.0.2 | transitive | BSD-3-Clause | - |
| http_multi_server | 3.2.2 | transitive | BSD-3-Clause | - |
| http_parser | 4.1.2 | transitive | BSD-3-Clause | - |
| image_picker_android | 0.8.13+25 | transitive | Apache-2.0 | - |
| image_picker_for_web | 3.1.1 | transitive | BSD-3-Clause | - |
| image_picker_ios | 0.8.13+12 | transitive | Apache-2.0 | - |
| image_picker_linux | 0.2.2 | transitive | BSD-3-Clause | - |
| image_picker_macos | 0.2.2+1 | transitive | BSD-3-Clause | - |
| image_picker_platform_interface | 2.11.2 | transitive | BSD-3-Clause | - |
| image_picker_windows | 0.2.2 | transitive | BSD-3-Clause | - |
| io | 1.1.0 | transitive | BSD-3-Clause | - |
| jni | 1.1.0 | transitive | BSD-3-Clause | - |
| jni_flutter | 1.0.4+1 | transitive | BSD-3-Clause | - |
| jni_util | 1.0.0 | transitive | BSD-3-Clause | - |
| json_annotation | 4.12.0 | transitive | BSD-3-Clause | - |
| leak_tracker | 11.0.2 | transitive | BSD-3-Clause | - |
| leak_tracker_flutter_testing | 3.0.10 | transitive | BSD-3-Clause | - |
| leak_tracker_testing | 3.0.2 | transitive | BSD-3-Clause | - |
| lints | 6.1.0 | transitive | BSD-3-Clause | - |
| listen | 1.0.1 | transitive | BSD-3-Clause | - |
| logging | 1.3.0 | transitive | BSD-3-Clause | - |
| matcher | 0.12.20 | transitive | BSD-3-Clause | - |
| material_color_utilities | 0.13.0 | transitive | Apache-2.0 | - |
| material_ui | 1.7.0 | transitive | BSD-3-Clause | - |
| meta | 1.18.3 | transitive | BSD-3-Clause | - |
| mime | 2.1.0 | transitive | BSD-3-Clause | - |
| native_toolchain_c | 0.19.2 | transitive | BSD-3-Clause | - |
| native_toolchain_cmake | 0.3.2 | transitive | Apache-2.0 | - |
| objective_c | 9.5.0 | transitive | BSD-3-Clause | - |
| package_config | 3.0.0 | transitive | BSD-3-Clause | - |
| package_info_plus_platform_interface | 4.1.0 | transitive | BSD-3-Clause | - |
| path_provider_android | 2.3.1 | transitive | BSD-3-Clause | - |
| path_provider_foundation | 2.6.0 | transitive | BSD-3-Clause | - |
| path_provider_linux | 2.2.2 | transitive | BSD-3-Clause | - |
| path_provider_platform_interface | 2.1.3 | transitive | BSD-3-Clause | - |
| path_provider_windows | 2.3.0 | transitive | BSD-3-Clause | - |
| permission_handler_android | 14.1.0 | transitive | MIT | - |
| permission_handler_apple | 9.6.2 | transitive | MIT | - |
| permission_handler_html | 0.1.4+1 | transitive | MIT | - |
| permission_handler_platform_interface | 4.4.1 | transitive | MIT | - |
| permission_handler_windows | 0.2.2 | transitive | MIT | - |
| petitparser | 7.0.2 | transitive | MIT | - |
| platform | 3.2.0 | transitive | BSD-3-Clause | - |
| plugin_platform_interface | 2.1.8 | transitive | BSD-3-Clause | - |
| pool | 1.5.3 | transitive | BSD-3-Clause | - |
| posix | 6.5.2 | transitive | MIT | - |
| pub_semver | 2.2.1 | transitive | BSD-3-Clause | - |
| pubspec_parse | 1.6.0 | transitive | BSD-3-Clause | - |
| qr | 3.0.2 | transitive | BSD-3-Clause | - |
| recase | 4.1.0 | transitive | BSD-2-Clause | - |
| record_use | 0.6.0 | transitive | BSD-3-Clause | - |
| riverpod | 3.4.3 | transitive | MIT | - |
| screen_brightness_android | 2.1.6 | transitive | MIT | - |
| screen_brightness_ios | 2.1.4 | transitive | MIT | - |
| screen_brightness_macos | 2.1.4 | transitive | MIT | - |
| screen_brightness_ohos | 2.1.4 | transitive | MIT | - |
| screen_brightness_platform_interface | 2.1.2 | transitive | MIT | - |
| screen_brightness_windows | 2.1.2 | transitive | MIT | - |
| share_plus_platform_interface | 7.2.0 | transitive | BSD-3-Clause | - |
| shelf | 1.4.3 | transitive | BSD-3-Clause | - |
| shelf_web_socket | 3.0.0 | transitive | BSD-3-Clause | - |
| sky_engine | 0.0.0 | transitive | BSD-3-Clause (Flutter SDK) | - |
| source_gen | 4.3.1 | transitive | BSD-3-Clause | - |
| source_span | 1.10.2 | transitive | BSD-3-Clause | - |
| sqlcipher_flutter_libs | 0.7.0+eol | transitive | Apache-2.0 | EOL stub package; SQLCipher not used |
| sqlite3 | 3.5.2 | transitive | MIT | Native SQLite via build hooks (libsqlite3.so); 3.7.1 available |
| sqlite3_flutter_libs | 0.6.0+eol | transitive | MIT | EOL stub package |
| sqlparser | 0.45.0 | transitive | MIT | - |
| stack_trace | 1.12.2 | transitive | BSD-3-Clause | - |
| state_notifier | 1.0.0 | transitive | MIT | - |
| stream_channel | 2.1.4 | transitive | BSD-3-Clause | - |
| stream_transform | 2.1.2 | transitive | BSD-3-Clause | - |
| string_scanner | 1.4.1 | transitive | BSD-3-Clause | - |
| term_glyph | 1.2.2 | transitive | BSD-3-Clause | - |
| test_api | 0.7.12 | transitive | BSD-3-Clause | - |
| typed_data | 1.4.0 | transitive | BSD-3-Clause | - |
| url_launcher_android | 6.3.33 | transitive | BSD-3-Clause | - |
| url_launcher_ios | 6.4.2 | transitive | BSD-3-Clause | - |
| url_launcher_linux | 3.2.3 | transitive | BSD-3-Clause | - |
| url_launcher_macos | 3.2.6 | transitive | BSD-3-Clause | - |
| url_launcher_platform_interface | 2.3.2 | transitive | BSD-3-Clause | - |
| url_launcher_web | 2.4.3 | transitive | BSD-3-Clause | - |
| url_launcher_windows | 3.1.6 | transitive | BSD-3-Clause | - |
| vector_math | 2.4.0 | transitive | BSD-3-Clause | - |
| vm_service | 15.4.0 | transitive | BSD-3-Clause | - |
| watcher | 1.2.1 | transitive | BSD-3-Clause | - |
| web | 1.1.1 | transitive | BSD-3-Clause | - |
| web_socket | 1.0.1 | transitive | BSD-3-Clause | - |
| web_socket_channel | 3.0.3 | transitive | BSD-3-Clause | - |
| win32 | 6.4.0 | transitive | BSD-3-Clause | - |
| win32_registry | 3.0.3 | transitive | BSD-3-Clause | - |
| windows_file_picker | 2.0.1 | transitive | MIT | - |
| xdg_directories | 1.1.0 | transitive | BSD-3-Clause | - |
| xml | 7.0.1 | transitive | MIT | - |
| yaml | 3.1.4 | transitive | MIT | - |
| yaml_edit | 2.2.4 | transitive | BSD-3-Clause | - |

Build-only transitive packages (analyzer, build*, source_gen, dart_style, native_toolchain_*, hooks, code_assets) run at build time and do not ship in the APK. Platform-specific implementations for iOS, macOS, Windows, Linux and web are resolved but not compiled into the Android APK.
