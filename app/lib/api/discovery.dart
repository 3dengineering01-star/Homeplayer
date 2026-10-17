import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredServer {
  const DiscoveredServer({required this.name, required this.address, this.id});
  final String name;
  final String address;

  /// The server's id, which tells whether it is a server the app knows by another address.
  final String? id;
}

/// Jellyfin answers a UDP broadcast on port 7359 with its name and address.
Future<List<DiscoveredServer>> discoverJellyfin({Duration timeout = const Duration(seconds: 2)}) async {
  final found = <String, DiscoveredServer>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final s = socket;
    s.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = s.receive();
      if (d == null) return;
      try {
        final j = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
        final address = j['Address'] as String?;
        if (address == null) return;
        found[(j['Id'] as String?) ?? address] =
            DiscoveredServer(name: (j['Name'] as String?) ?? d.address.address, address: address, id: j['Id'] as String?);
      } catch (_) {}
    });
    s.send(utf8.encode('who is JellyfinServer?'), InternetAddress('255.255.255.255'), 7359);
    await Future.delayed(timeout);
  } catch (_) {
    // No network or broadcast not allowed: manual entry still works.
  } finally {
    socket?.close();
  }
  return found.values.toList();
}
