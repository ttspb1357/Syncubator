import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/navigation_provider.dart';
import 'providers/weight_provider.dart';
import 'providers/bed_provider.dart';
import 'providers/climate_provider.dart';
import 'providers/oxygen_provider.dart';
import 'providers/spo2_provider.dart';
import 'providers/skin_provider.dart';
import 'providers/lid_provider.dart';
import 'providers/photo_provider.dart';
import 'providers/alarm_provider.dart';
import 'screens/splash_screen.dart';
import 'utils/app_colors.dart';
import 'utils/api_constants.dart';
import 'utils/secure_http_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Must be awaited before runApp(): every screen that talks to the Pi
  // (via SecureHttpClient.instance) assumes the self-signed certificate is
  // already loaded and the client is ready by the time it renders.
  // Demo mode must be fully offline. Loading the Pi certificate is only
  // necessary when the app is configured to contact the real device.
  if (!ApiConstants.useMockData) {
    await SecureHttpClient.init();
  }
  runApp(const SyncubatorApp());
}

class SyncubatorApp extends StatelessWidget {
  const SyncubatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => WeightProvider()),
        ChangeNotifierProvider(create: (_) => BedProvider()),
        ChangeNotifierProvider(create: (_) => ClimateProvider()),
        ChangeNotifierProvider(create: (_) => OxygenProvider()),
        ChangeNotifierProvider(create: (_) => Spo2Provider()),
        ChangeNotifierProvider(create: (_) => SkinProvider()),
        ChangeNotifierProvider(create: (_) => LidProvider()),
        ChangeNotifierProvider(create: (_) => PhotoProvider()),
        ChangeNotifierProvider(create: (_) => AlarmProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Syncubator',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
