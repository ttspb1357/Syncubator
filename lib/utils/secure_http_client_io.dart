import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;

Future<http.Client> createSecureClient() async {
  final certData = await rootBundle.load('assets/certs/syncubator.crt');
  final context = SecurityContext(withTrustedRoots: false);
  context.setTrustedCertificatesBytes(certData.buffer.asUint8List());

  final rawClient = HttpClient(context: context);
  return io_client.IOClient(rawClient);
}

Future<void> initializePlatformClient(
  Completer<http.Client> completer,
) async {
  try {
    completer.complete(await createSecureClient());
  } catch (error, stackTrace) {
    completer.completeError(error, stackTrace);
    rethrow;
  }
}
