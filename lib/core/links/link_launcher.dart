import 'package:url_launcher/url_launcher.dart';

import '../settings/settings_repository.dart';

/// Every outbound link goes through here (spec §5): web, tel, sms, mailto and
/// maps all open in the user's default app. There is no in-app web view.
class LinkLauncher {
  final Future<bool> Function(Uri uri) _open;

  LinkLauncher([Future<bool> Function(Uri uri)? open])
      : _open = open ?? ((u) => launchUrl(u, mode: LaunchMode.externalApplication));

  Future<bool> open(Uri uri) async {
    try {
      return await _open(uri);
    } catch (_) {
      return false;
    }
  }

  Future<bool> call(String phone) => open(Uri(scheme: 'tel', path: _dialable(phone)));

  Future<bool> text(String phone) => open(Uri(scheme: 'sms', path: _dialable(phone)));

  Future<bool> email(String address, {String? subject, String? body}) => open(Uri(
        scheme: 'mailto',
        path: address,
        // Uri's queryParameters encodes spaces as '+', which mail apps show literally.
        query: [
          if (subject != null) 'subject=${Uri.encodeComponent(subject)}',
          if (body != null) 'body=${Uri.encodeComponent(body)}',
        ].join('&').nullIfEmpty,
      ));

  Future<bool> web(String url) => open(webUri(url));

  Future<bool> map(String address) =>
      open(Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}'));

  /// "Check on web": "{first} {last} {company}" in the chosen search engine.
  Future<bool> webCheck(SearchEngine engine, List<String?> parts) =>
      open(engine.searchUri(parts.where((p) => p != null && p.trim().isNotEmpty).join(' ')));

  static Uri webUri(String url) {
    final u = url.trim();
    return Uri.parse(RegExp(r'^https?://', caseSensitive: false).hasMatch(u) ? u : 'https://$u');
  }

  static String _dialable(String phone) => phone.replaceAll(RegExp(r'[^\d+*#,;]'), '');
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
