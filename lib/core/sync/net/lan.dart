import 'dart:io';

/// True for an address on a home or office network: 10.x, 172.16-31.x,
/// 192.168.x, link-local, loopback and the IPv6 equivalents. The sync server
/// answers nobody else (S16.3), so it can never be reached from the internet
/// even if a router forwards the port by mistake.
bool isPrivateAddress(InternetAddress a) {
  if (a.isLoopback || a.isLinkLocal) return true;
  final raw = a.rawAddress;
  if (a.type == InternetAddressType.IPv4 && raw.length == 4) {
    final b0 = raw[0], b1 = raw[1];
    if (b0 == 10) return true;
    if (b0 == 172 && b1 >= 16 && b1 <= 31) return true;
    if (b0 == 192 && b1 == 168) return true;
    return false;
  }
  if (a.type == InternetAddressType.IPv6 && raw.length == 16) {
    // fc00::/7 unique local; ::ffff:a.b.c.d is an IPv4 address in IPv6 clothes.
    if ((raw[0] & 0xfe) == 0xfc) return true;
    final mapped = raw.sublist(0, 10).every((x) => x == 0) && raw[10] == 0xff && raw[11] == 0xff;
    if (mapped) {
      return isPrivateAddress(InternetAddress.fromRawAddress(raw.sublist(12), type: InternetAddressType.IPv4));
    }
  }
  return false;
}

/// The address a PC on the same Wi-Fi can reach this device at, or null when the
/// device is on no private network. Wi-Fi style interface names win over others.
Future<InternetAddress?> bestLanAddress() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  InternetAddress? fallback;
  for (final i in interfaces) {
    for (final a in i.addresses) {
      if (a.isLoopback || a.isLinkLocal || !isPrivateAddress(a)) continue;
      final n = i.name.toLowerCase();
      if (n.contains('wlan') || n.contains('wi-fi') || n.contains('wifi') || n.startsWith('en')) return a;
      fallback ??= a;
    }
  }
  return fallback;
}
