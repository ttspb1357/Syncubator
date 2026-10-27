import 'dart:async';

import 'package:http/http.dart' as http;

Future<http.Client> createSecureClient() async => http.Client();

Future<void> initializePlatformClient(
  Completer<http.Client> completer,
) async {
  completer.complete(await createSecureClient());
}
